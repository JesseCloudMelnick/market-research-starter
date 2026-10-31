<#
    Creates the research database if it does not exist, then applies all migrations.
    Safe to re-run. Does not touch an existing database beyond applying pending migrations.
#>
[CmdletBinding()]
param([string]$ConfigPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sql.ps1')

$cfg = Get-ResearchConfig -Path $ConfigPath

Write-Host "Server:   $($cfg.server)"
Write-Host "Database: $($cfg.database)"
Write-Host ''

try {
    $version = Invoke-ResearchScalar -Config $cfg -Database 'master' -Query 'SELECT @@VERSION'
}
catch {
    Write-Host 'Could not connect to the instance.' -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ''
    Write-Host 'Check that:'
    Write-Host "  - SQL Server is running:  Get-Service | Where-Object { `$_.Name -like 'MSSQL*' }"
    Write-Host "  - The instance name in settings.json is right. A named instance looks like '.\SQLEXPRESS'."
    Write-Host '  - Your Windows account can reach it.'
    throw
}

Write-Host ($version -split "`n")[0].Trim()
Write-Host ''

if (Test-ResearchDatabaseExists -Config $cfg) {
    Write-Host "Database '$($cfg.database)' already exists."
}
else {
    Write-Host "Creating database '$($cfg.database)' ... " -NoNewline
    # Database name cannot be parameterized, so quote it rather than interpolating raw.
    $safeName = $cfg.database -replace '\]', ']]'
    if ($cfg.database -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,120}$') {
        throw "Refusing to create a database named '$($cfg.database)'. Use letters, digits, and underscores."
    }
    Invoke-ResearchNonQuery -Config $cfg -Database 'master' -Query "CREATE DATABASE [$safeName];" | Out-Null
    Write-Host 'ok'
}

Write-Host ''
& (Join-Path $PSScriptRoot 'Apply-Migrations.ps1') -ConfigPath $ConfigPath

Write-Host ''
Write-Host 'Next: .\scripts\Test-Environment.ps1'
