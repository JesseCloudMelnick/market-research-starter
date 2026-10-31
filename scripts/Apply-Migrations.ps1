<#
    Applies every migration in sql/migrations that has not been applied yet, in filename
    order, recording each in research.SchemaMigration.

    Safe to re-run. Never edit a migration that has already been applied; write a new one.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$WhatIfOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sql.ps1')

$cfg = Get-ResearchConfig -Path $ConfigPath
$repoRoot = Get-RepoRoot
$migrationDir = Join-Path $repoRoot 'sql\migrations'

Write-Host "Server:   $($cfg.server)"
Write-Host "Database: $($cfg.database)"
Write-Host ''

if (-not (Test-ResearchDatabaseExists -Config $cfg)) {
    throw "Database '$($cfg.database)' does not exist. Run Initialize-Database.ps1 first."
}

# Bootstrap the tracking table. This one piece of DDL cannot live in a migration.
Invoke-ResearchNonQuery -Config $cfg -Query @'
IF SCHEMA_ID('research') IS NULL EXEC('CREATE SCHEMA research');
'@ | Out-Null

Invoke-ResearchNonQuery -Config $cfg -Query @'
IF OBJECT_ID('research.SchemaMigration') IS NULL
CREATE TABLE research.SchemaMigration (
    MigrationName  nvarchar(260) NOT NULL CONSTRAINT PK_SchemaMigration PRIMARY KEY,
    AppliedAt      datetime2(0)  NOT NULL CONSTRAINT DF_SchemaMigration_AppliedAt DEFAULT SYSUTCDATETIME(),
    AppliedBy      nvarchar(200) NOT NULL,
    ChecksumSha256 char(64)      NULL,
    DurationMs     int           NULL
);
'@ | Out-Null

$applied = @{}
foreach ($row in (Invoke-ResearchQuery -Config $cfg -Query 'SELECT MigrationName, ChecksumSha256 FROM research.SchemaMigration')) {
    $applied[$row.MigrationName] = $row.ChecksumSha256
}

$files = Get-ChildItem -Path $migrationDir -Filter '*.sql' | Sort-Object Name
if (-not $files) { Write-Host 'No migrations found.'; return }

function Get-FileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

$pending = @()
$changed = @()

foreach ($f in $files) {
    $hash = Get-FileSha256 -Path $f.FullName
    if ($applied.ContainsKey($f.Name)) {
        $recorded = $applied[$f.Name]
        if ($recorded -and $recorded -ne $hash) { $changed += $f.Name }
    }
    else {
        $pending += [pscustomobject]@{ File = $f; Hash = $hash }
    }
}

if ($changed.Count -gt 0) {
    Write-Warning 'These migrations have changed since they were applied. The database does not match the files.'
    $changed | ForEach-Object { Write-Warning "  $_" }
    Write-Warning 'Do not edit applied migrations. Write a new one that corrects the difference.'
}

if ($pending.Count -eq 0) {
    Write-Host "Up to date. $($applied.Count) migration(s) already applied."
    return
}

Write-Host "Pending:"
$pending | ForEach-Object { Write-Host "  $($_.File.Name)" }
Write-Host ''

if ($WhatIfOnly) { Write-Host 'WhatIfOnly specified, nothing applied.'; return }

$who = "$env:USERDOMAIN\$env:USERNAME"

foreach ($p in $pending) {
    Write-Host "Applying $($p.File.Name) ... " -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-ResearchScriptFile -Config $cfg -Path $p.File.FullName
    $sw.Stop()

    Invoke-ResearchNonQuery -Config $cfg -Parameters @{
        name = $p.File.Name; who = $who; hash = $p.Hash; ms = [int]$sw.ElapsedMilliseconds
    } -Query @'
INSERT INTO research.SchemaMigration (MigrationName, AppliedBy, ChecksumSha256, DurationMs)
VALUES (@name, @who, @hash, @ms);
'@ | Out-Null

    Write-Host "ok ($([int]$sw.ElapsedMilliseconds) ms)"
}

Write-Host ''
Write-Host "Applied $($pending.Count) migration(s)."
