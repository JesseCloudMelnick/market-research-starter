<#
    Proves the environment actually works, end to end, and leaves nothing behind.

    Connects, checks the expected objects exist, inserts a full chain of test data
    (source, collection run, entity, metric, observation), reads it back through the
    views, confirms the immutability trigger really blocks updates and deletes, and rolls
    everything back.

    Run this whenever something looks wrong, before debugging anything else.
#>
[CmdletBinding()]
param([string]$ConfigPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sql.ps1')

$cfg = Get-ResearchConfig -Path $ConfigPath
$pass = 0
$fail = 0

function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        $script:pass++
        Write-Host ('  [ ok ] ' + $Name) -ForegroundColor Green
    }
    else {
        $script:fail++
        Write-Host ('  [FAIL] ' + $Name) -ForegroundColor Red
    }
    if ($Detail) { Write-Host ('         ' + $Detail) -ForegroundColor DarkGray }
}

function Exec-Scalar {
    param($Conn, $Tran, [string]$Sql, [hashtable]$Params)
    $cmd = $Conn.CreateCommand()
    $cmd.Transaction = $Tran
    $cmd.CommandText = $Sql
    if ($Params) {
        foreach ($k in $Params.Keys) {
            $v = $Params[$k]
            if ($null -eq $v) { $v = [System.DBNull]::Value }
            [void]$cmd.Parameters.AddWithValue("@$k", $v)
        }
    }
    return $cmd.ExecuteScalar()
}

Write-Host ''
Write-Host "Connection" -ForegroundColor Cyan

try {
    $version = Invoke-ResearchScalar -Config $cfg -Query 'SELECT @@VERSION'
    Report -Name "Connected to $($cfg.server), database $($cfg.database)" -Ok $true -Detail ($version -split "`n")[0].Trim()
}
catch {
    Report -Name 'Connect' -Ok $false -Detail $_.Exception.Message
    Write-Host ''
    Write-Host 'Nothing else can be tested without a connection. Check settings.json and that SQL Server is running.'
    exit 1
}

Write-Host ''
Write-Host "Schema" -ForegroundColor Cyan

$expectedTables = @('EntityType','SourceType','Source','CollectionRun','Entity','EntityAlias',
                    'EntityRelationship','Metric','Observation','Thesis','ThesisEvidence','SchemaMigration')
$actualTables = (Invoke-ResearchQuery -Config $cfg -Query @'
SELECT name FROM sys.tables WHERE SCHEMA_NAME(schema_id) = 'research'
'@) | ForEach-Object { $_.name }

$missingTables = $expectedTables | Where-Object { $actualTables -notcontains $_ }
Report -Name "Tables present ($($actualTables.Count))" -Ok ($missingTables.Count -eq 0) `
       -Detail $(if ($missingTables) { 'Missing: ' + ($missingTables -join ', ') } else { '' })

$expectedViews = @('vw_CurrentObservation','vw_EntityLatestMetric','vw_StaleFact','vw_SourceUsage',
                   'vw_ThesisScorecard','vw_CollectionCoverage','vw_ThinEntity','vw_SupersededObservation')
$actualViews = (Invoke-ResearchQuery -Config $cfg -Query @'
SELECT name FROM sys.views WHERE SCHEMA_NAME(schema_id) = 'research'
'@) | ForEach-Object { $_.name }

$missingViews = $expectedViews | Where-Object { $actualViews -notcontains $_ }
Report -Name "Views present ($($actualViews.Count))" -Ok ($missingViews.Count -eq 0) `
       -Detail $(if ($missingViews) { 'Missing: ' + ($missingViews -join ', ') } else { '' })

$migrations = Invoke-ResearchQuery -Config $cfg -Query 'SELECT MigrationName, AppliedAt FROM research.SchemaMigration ORDER BY MigrationName'
Report -Name "Migrations applied ($($migrations.Count))" -Ok ($migrations.Count -gt 0) `
       -Detail (($migrations | ForEach-Object { $_.MigrationName }) -join ', ')

Write-Host ''
Write-Host "Round trip" -ForegroundColor Cyan

$conn = New-ResearchConnection -Config $cfg
$tran = $conn.BeginTransaction()
try {
    $sourceId = Exec-Scalar -Conn $conn -Tran $tran -Params @{ t = 'TEST source, safe to ignore' } -Sql @'
INSERT INTO research.Source (SourceTypeCode, Title, Publisher, Url, PublishedOn, Reliability)
OUTPUT INSERTED.SourceId
VALUES ('company-site', @t, N'Test Publisher', N'https://example.invalid/pricing', '2026-01-15', 4);
'@
    Report -Name 'Insert source' -Ok ($null -ne $sourceId) -Detail "SourceId $sourceId"

    $runId = Exec-Scalar -Conn $conn -Tran $tran -Params @{ op = "$env:USERNAME" } -Sql @'
INSERT INTO research.CollectionRun (Purpose, Method, QueryText, Operator, ResultCount, WasFruitful)
OUTPUT INSERTED.RunId
VALUES (N'Environment self-test', N'manual read', N'n/a', @op, 1, 1);
'@
    Report -Name 'Insert collection run' -Ok ($null -ne $runId) -Detail "RunId $runId"

    $entityId = Exec-Scalar -Conn $conn -Tran $tran -Sql @'
INSERT INTO research.Entity (EntityTypeCode, CanonicalName, Slug, Summary)
OUTPUT INSERTED.EntityId
VALUES ('company', N'Test Company', 'test-company-selftest', N'Inserted by Test-Environment.ps1.');
'@
    Report -Name 'Insert entity' -Ok ($null -ne $entityId) -Detail "EntityId $entityId"

    [void](Exec-Scalar -Conn $conn -Tran $tran -Params @{ e = $entityId } -Sql @'
INSERT INTO research.EntityAlias (EntityId, Alias, AliasType)
OUTPUT INSERTED.EntityAliasId
VALUES (@e, N'TestCo', 'abbreviation');
'@)
    Report -Name 'Insert entity alias' -Ok $true

    $metricId = Exec-Scalar -Conn $conn -Tran $tran -Sql @'
INSERT INTO research.Metric (Code, Name, Unit, ValueKind, Definition, AppliesToEntityType)
OUTPUT INSERTED.MetricId
VALUES ('selftest_price_per_seat_month', N'Self-test price per seat per month', N'USD/seat/month',
        'numeric', N'List price of the entry tier, per seat, per month, billed annually.', 'company');
'@
    Report -Name 'Insert metric' -Ok ($null -ne $metricId) -Detail "MetricId $metricId"

    $obsId = Exec-Scalar -Conn $conn -Tran $tran -Params @{
        e = $entityId; m = $metricId; s = $sourceId; r = $runId; by = "$env:USERNAME"
    } -Sql @'
INSERT INTO research.Observation (EntityId, MetricId, AsOfDate, NumericValue, Unit, SourceId, RunId, Confidence, RecordedBy)
OUTPUT INSERTED.ObservationId
VALUES (@e, @m, '2026-01-15', 42.00, N'USD/seat/month', @s, @r, 4, @by);
'@
    Report -Name 'Insert observation' -Ok ($null -ne $obsId) -Detail "ObservationId $obsId"

    $readBack = Exec-Scalar -Conn $conn -Tran $tran -Params @{ o = $obsId } -Sql @'
SELECT NumericValue FROM research.vw_CurrentObservation WHERE ObservationId = @o;
'@
    Report -Name 'Read back through vw_CurrentObservation' -Ok ($readBack -eq 42.00) -Detail "NumericValue $readBack"

    # Supersede it, and confirm the old row drops out of the current view.
    $newObsId = Exec-Scalar -Conn $conn -Tran $tran -Params @{
        e = $entityId; m = $metricId; s = $sourceId; r = $runId; by = "$env:USERNAME"; sup = $obsId
    } -Sql @'
INSERT INTO research.Observation (EntityId, MetricId, AsOfDate, NumericValue, Unit, SourceId, RunId,
                                  Confidence, RecordedBy, SupersedesObservationId, Notes)
OUTPUT INSERTED.ObservationId
VALUES (@e, @m, '2026-01-15', 44.00, N'USD/seat/month', @s, @r, 5, @by, @sup,
        N'Corrected: the earlier figure was the monthly-billed price.');
'@

    $stillCurrent = Exec-Scalar -Conn $conn -Tran $tran -Params @{ o = $obsId } -Sql @'
SELECT COUNT(*) FROM research.vw_CurrentObservation WHERE ObservationId = @o;
'@
    Report -Name 'Superseded observation leaves the current view' -Ok ([int]$stillCurrent -eq 0)

    $latest = Exec-Scalar -Conn $conn -Tran $tran -Params @{ o = $newObsId } -Sql @'
SELECT NumericValue FROM research.vw_EntityLatestMetric WHERE ObservationId = @o;
'@
    Report -Name 'Correction is what vw_EntityLatestMetric returns' -Ok ($latest -eq 44.00) -Detail "NumericValue $latest"

    $hist = Exec-Scalar -Conn $conn -Tran $tran -Params @{ o = $obsId } -Sql @'
SELECT COUNT(*) FROM research.vw_SupersededObservation WHERE OldObservationId = @o;
'@
    Report -Name 'Correction history is visible' -Ok ([int]$hist -eq 1)

    $thesisId = Exec-Scalar -Conn $conn -Tran $tran -Sql @'
INSERT INTO research.Thesis (Slug, Statement, DecidesWhat, Confidence, Status, FalsifiedBy)
OUTPUT INSERTED.ThesisId
VALUES ('selftest-thesis', N'A self-test thesis.', N'Nothing, this is a test.', 2, 'open',
        N'Any evidence at all, since this row is about to be rolled back.');
'@
    [void](Exec-Scalar -Conn $conn -Tran $tran -Params @{ t = $thesisId; o = $newObsId } -Sql @'
INSERT INTO research.ThesisEvidence (ThesisId, ObservationId, Stance, Weight)
OUTPUT INSERTED.ThesisEvidenceId
VALUES (@t, @o, 'supports', 3);
'@)

    $score = Exec-Scalar -Conn $conn -Tran $tran -Params @{ t = $thesisId } -Sql @'
SELECT SupportingWeight FROM research.vw_ThesisScorecard WHERE ThesisId = @t;
'@
    Report -Name 'Thesis evidence links and scores' -Ok ([int]$score -eq 3) -Detail "SupportingWeight $score"
}
catch {
    Report -Name 'Round trip' -Ok $false -Detail $_.Exception.Message
}
finally {
    try { $tran.Rollback() } catch { }
    $conn.Dispose()
    Write-Host '  (all test data rolled back)' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host "Immutability" -ForegroundColor Cyan

function Test-BlockedOperation {
    param([string]$Name, [string]$OperationSql, [string]$ExpectedText)

    $c = New-ResearchConnection -Config $cfg
    $t = $c.BeginTransaction()
    try {
        $sid = Exec-Scalar -Conn $c -Tran $t -Sql @'
INSERT INTO research.Source (SourceTypeCode, Title, Reliability)
OUTPUT INSERTED.SourceId VALUES ('company-site', N'TEST trigger source', 4);
'@
        $eid = Exec-Scalar -Conn $c -Tran $t -Sql @'
INSERT INTO research.Entity (EntityTypeCode, CanonicalName, Slug)
OUTPUT INSERTED.EntityId VALUES ('company', N'Trigger Test Co', 'trigger-test-co-selftest');
'@
        $mid = Exec-Scalar -Conn $c -Tran $t -Sql @'
INSERT INTO research.Metric (Code, Name, ValueKind, Definition)
OUTPUT INSERTED.MetricId VALUES ('selftest_trigger_metric', N'Trigger test', 'numeric', N'Test only.');
'@
        $oid = Exec-Scalar -Conn $c -Tran $t -Params @{ e = $eid; m = $mid; s = $sid; by = 'selftest' } -Sql @'
INSERT INTO research.Observation (EntityId, MetricId, AsOfDate, NumericValue, SourceId, Confidence, RecordedBy)
OUTPUT INSERTED.ObservationId VALUES (@e, @m, '2026-01-01', 1, @s, 3, @by);
'@
        try {
            [void](Exec-Scalar -Conn $c -Tran $t -Params @{ o = $oid } -Sql $OperationSql)
            Report -Name $Name -Ok $false -Detail 'The operation succeeded. It should have been blocked.'
        }
        catch {
            $blocked = $_.Exception.Message -like "*$ExpectedText*"
            Report -Name $Name -Ok $blocked -Detail $_.Exception.Message.Split([Environment]::NewLine)[0]
        }
    }
    catch {
        Report -Name $Name -Ok $false -Detail $_.Exception.Message
    }
    finally {
        # Disposing an open connection rolls back any transaction still in flight, which
        # is what we want here because the trigger itself may already have rolled back.
        $c.Dispose()
    }
}

Test-BlockedOperation -Name 'UPDATE of an observation value is blocked' -ExpectedText 'immutable' -OperationSql @'
UPDATE research.Observation SET NumericValue = 999 WHERE ObservationId = @o;
SELECT 1;
'@

Test-BlockedOperation -Name 'DELETE of an observation is blocked' -ExpectedText 'never deleted' -OperationSql @'
DELETE FROM research.Observation WHERE ObservationId = @o;
SELECT 1;
'@

Write-Host ''
Write-Host "Current contents" -ForegroundColor Cyan
$counts = Invoke-ResearchQuery -Config $cfg -Query @'
SELECT 'entities' AS Thing, COUNT(*) AS N FROM research.Entity
UNION ALL SELECT 'sources',      COUNT(*) FROM research.Source
UNION ALL SELECT 'metrics',      COUNT(*) FROM research.Metric
UNION ALL SELECT 'observations', COUNT(*) FROM research.Observation
UNION ALL SELECT 'theses',       COUNT(*) FROM research.Thesis
UNION ALL SELECT 'runs',         COUNT(*) FROM research.CollectionRun;
'@
foreach ($row in $counts) { Write-Host ("  {0,-14} {1}" -f $row.Thing, $row.N) }

Write-Host ''
if ($fail -eq 0) {
    Write-Host "$pass checks passed, nothing failed." -ForegroundColor Green
}
else {
    Write-Host "$pass passed, $fail FAILED. Fix these before doing any research." -ForegroundColor Red
    exit 1
}
