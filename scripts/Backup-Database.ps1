<#
    Backs up the research database to the path in settings.json and prunes old backups.

    -RegisterScheduledTask registers a nightly run. That needs an elevated PowerShell.
    -TestRestore restores the newest backup into a scratch database and drops it, which is
    the only way to know the backup is actually a backup.

    Note: SQL Server writes the file, not PowerShell, so the backup path must be writable
    by the SQL Server service account, not by you. A local folder like C:\Backups works;
    a mapped network drive usually does not.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$RegisterScheduledTask,
    [switch]$TestRestore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sql.ps1')

$cfg = Get-ResearchConfig -Path $ConfigPath
$backupDir = $cfg.backup.path

if ($RegisterScheduledTask) {
    $taskName = $cfg.backup.scheduledTaskName
    $pwsh = (Get-Command powershell.exe).Source
    $argline = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $argline -WorkingDirectory (Get-RepoRoot)
    $trigger = New-ScheduledTaskTrigger -Daily -At $cfg.backup.scheduledTime
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -Description 'Nightly backup of the market research database' -Force | Out-Null
        Write-Host "Registered scheduled task '$taskName' for $($cfg.backup.scheduledTime) daily."
    }
    catch {
        Write-Host 'Could not register the scheduled task.' -ForegroundColor Red
        Write-Host $_.Exception.Message
        Write-Host 'This usually means PowerShell is not elevated. Re-run it as administrator.'
        throw
    }
    return
}

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Write-Host "Created $backupDir"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$file = Join-Path $backupDir "$($cfg.database)-$stamp.bak"

Write-Host "Backing up $($cfg.database) to $file ... " -NoNewline

$safeName = $cfg.database -replace '\]', ']]'

# Express does not support backup compression, so ask the server rather than assume.
$engineEdition = [int](Invoke-ResearchScalar -Config $cfg -Database 'master' `
    -Query "SELECT CAST(SERVERPROPERTY('EngineEdition') AS int)")
$withOptions = 'FORMAT, INIT, CHECKSUM, STATS = 25'
if ($engineEdition -ne 4) { $withOptions = 'FORMAT, INIT, COMPRESSION, CHECKSUM, STATS = 25' }

Invoke-ResearchNonQuery -Config $cfg -Database 'master' -TimeoutSeconds 3600 -Parameters @{ path = $file } -Query @"
BACKUP DATABASE [$safeName] TO DISK = @path
WITH $withOptions;
"@ | Out-Null

Write-Host 'ok'

$size = (Get-Item $file).Length / 1MB
Write-Host ("  {0:N1} MB" -f $size)

# Prune
$cutoff = (Get-Date).AddDays(-1 * [int]$cfg.backup.retentionDays)
$old = Get-ChildItem -Path $backupDir -Filter "$($cfg.database)-*.bak" |
       Where-Object { $_.LastWriteTime -lt $cutoff }
if ($old) {
    $old | Remove-Item -Force
    Write-Host "Pruned $($old.Count) backup(s) older than $($cfg.backup.retentionDays) days."
}

if ($TestRestore) {
    $scratch = "$($cfg.database)_RestoreTest"
    $safeScratch = $scratch -replace '\]', ']]'
    Write-Host ''
    Write-Host "Restore test into [$scratch] ... " -NoNewline

    $dataDir = Invoke-ResearchScalar -Config $cfg -Database 'master' `
        -Query "SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(500))"
    $logDir = Invoke-ResearchScalar -Config $cfg -Database 'master' `
        -Query "SELECT CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(500))"

    $fileList = Invoke-ResearchQuery -Config $cfg -Database 'master' -Parameters @{ path = $file } `
        -Query 'RESTORE FILELISTONLY FROM DISK = @path'

    $moves = @()
    foreach ($f in $fileList) {
        $ext = '.mdf'
        $target = $dataDir
        if ($f.Type -eq 'L') { $ext = '.ldf'; $target = $logDir }
        $newPath = Join-Path $target "$scratch`_$($f.LogicalName)$ext"
        $moves += "MOVE N'$($f.LogicalName)' TO N'$newPath'"
    }

    try {
        Invoke-ResearchNonQuery -Config $cfg -Database 'master' -TimeoutSeconds 3600 -Parameters @{ path = $file } -Query @"
RESTORE DATABASE [$safeScratch] FROM DISK = @path
WITH $($moves -join ', '), REPLACE, RECOVERY;
"@ | Out-Null

        $obs = Invoke-ResearchScalar -Config $cfg -Database $scratch `
            -Query 'SELECT COUNT(*) FROM research.Observation'
        Write-Host "ok, $obs observation(s) readable in the restored copy."
    }
    finally {
        Invoke-ResearchNonQuery -Config $cfg -Database 'master' -Query @"
IF DB_ID('$safeScratch') IS NOT NULL
BEGIN
    ALTER DATABASE [$safeScratch] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$safeScratch];
END
"@ | Out-Null
        Write-Host "Dropped [$scratch]."
    }
}

Write-Host ''
Write-Host 'Reminder: the archive/ folder holds local copies of sources and is not covered'
Write-Host 'by this backup. Make sure whatever backs up your machine includes it.'
