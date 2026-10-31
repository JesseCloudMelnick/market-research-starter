<#
    Shared database helpers.

    Uses System.Data.SqlClient directly so the only requirement is Windows PowerShell and
    a reachable SQL Server instance. No sqlcmd, no SqlServer module, nothing to install.

    Dot-source it:
        . .\scripts\lib\Sql.ps1
        $cfg = Get-ResearchConfig
        Invoke-ResearchQuery -Config $cfg -Query 'SELECT TOP 5 * FROM research.vw_CurrentObservation'
#>

Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Get-RepoRoot { $script:RepoRoot }

function Get-ResearchConfig {
    <#  Reads settings.json from the repo root. settings.local.json, if present, overrides
        it key by key and is gitignored, which is where a machine-specific instance name
        belongs. #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { $Path = Join-Path $script:RepoRoot 'settings.json' }
    if (-not (Test-Path $Path)) { throw "Config not found at $Path" }

    $cfg = Get-Content $Path -Raw | ConvertFrom-Json

    $localPath = Join-Path $script:RepoRoot 'settings.local.json'
    if (Test-Path $localPath) {
        $local = Get-Content $localPath -Raw | ConvertFrom-Json
        foreach ($p in $local.PSObject.Properties) {
            $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
    }

    return $cfg
}

function Get-ResearchConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [string]$Database
    )

    if (-not $Database) { $Database = $Config.database }

    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source']      = $Config.server
    $b['Initial Catalog']  = $Database
    $b['Connect Timeout']  = $Config.connectTimeoutSeconds
    $b['Application Name'] = 'MarketResearch Scripts'

    if ($Config.integratedSecurity) {
        $b['Integrated Security'] = $true
    }
    else {
        # Only reachable if the researcher deliberately opted out of Windows auth. The
        # credential must come from settings.local.json, which is gitignored.
        if (-not $Config.PSObject.Properties.Name.Contains('username')) {
            throw 'integratedSecurity is false but no username is configured. Put credentials in settings.local.json, never in settings.json.'
        }
        $b['User ID']  = $Config.username
        $b['Password'] = $Config.password
    }

    return $b.ConnectionString
}

function New-ResearchConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [string]$Database
    )
    $conn = New-Object System.Data.SqlClient.SqlConnection (Get-ResearchConnectionString -Config $Config -Database $Database)
    $conn.Open()
    return $conn
}

function Add-SqlParameters {
    param($Command, [hashtable]$Parameters)
    if (-not $Parameters) { return }
    foreach ($k in $Parameters.Keys) {
        $v = $Parameters[$k]
        if ($null -eq $v) { $v = [System.DBNull]::Value }
        [void]$Command.Parameters.AddWithValue("@$k", $v)
    }
}

function Invoke-ResearchQuery {
    <# Returns rows. Always parameterize; never build SQL by string concatenation. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Query,
        [hashtable]$Parameters,
        [string]$Database,
        [int]$TimeoutSeconds = 120
    )

    $conn = New-ResearchConnection -Config $Config -Database $Database
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSeconds
        Add-SqlParameters -Command $cmd -Parameters $Parameters

        $table = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        [void]$adapter.Fill($table)
        return $table.Rows
    }
    finally { $conn.Dispose() }
}

function Invoke-ResearchNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Query,
        [hashtable]$Parameters,
        [string]$Database,
        [int]$TimeoutSeconds = 300
    )

    $conn = New-ResearchConnection -Config $Config -Database $Database
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSeconds
        Add-SqlParameters -Command $cmd -Parameters $Parameters
        return $cmd.ExecuteNonQuery()
    }
    finally { $conn.Dispose() }
}

function Invoke-ResearchScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Query,
        [hashtable]$Parameters,
        [string]$Database
    )
    $conn = New-ResearchConnection -Config $Config -Database $Database
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        Add-SqlParameters -Command $cmd -Parameters $Parameters
        $result = $cmd.ExecuteScalar()
        if ($result -is [System.DBNull]) { return $null }
        return $result
    }
    finally { $conn.Dispose() }
}

function Split-SqlBatches {
    <# Splits on GO, which is a client directive the server does not understand. #>
    param([Parameter(Mandatory)][string]$Script)
    $parts = [regex]::Split($Script, '(?im)^[ \t]*GO[ \t]*(?:--.*)?$')
    return $parts | Where-Object { $_ -and $_.Trim().Length -gt 0 }
}

function Invoke-ResearchScriptFile {
    <# Runs a .sql file batch by batch inside a single transaction, so a migration either
       lands completely or not at all. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Database,
        [int]$TimeoutSeconds = 600
    )

    if (-not (Test-Path $Path)) { throw "Script not found: $Path" }
    $batches = Split-SqlBatches -Script (Get-Content $Path -Raw)

    $conn = New-ResearchConnection -Config $Config -Database $Database
    $tran = $conn.BeginTransaction()
    try {
        foreach ($batch in $batches) {
            $cmd = $conn.CreateCommand()
            $cmd.Transaction = $tran
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = $TimeoutSeconds
            [void]$cmd.ExecuteNonQuery()
        }
        $tran.Commit()
    }
    catch {
        try { $tran.Rollback() } catch { }
        throw "Failed applying $(Split-Path -Leaf $Path): $($_.Exception.Message)"
    }
    finally { $conn.Dispose() }
}

function Test-ResearchDatabaseExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)
    $count = Invoke-ResearchScalar -Config $Config -Database 'master' `
        -Query 'SELECT COUNT(*) FROM sys.databases WHERE name = @name' `
        -Parameters @{ name = $Config.database }
    return ([int]$count -gt 0)
}
