<#
    Reports conformance of the knowledge base to the conventions in AGENTS.md, and checks
    that every database citation in markdown still resolves.

    This is a REPORT, not a gate. A new repository will show gaps and that is expected.
    What matters is that the numbers move the right way over time.

    -Detailed lists every offending file rather than the first few.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Detailed,
    [switch]$SkipDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sql.ps1')

$repoRoot = Get-RepoRoot
$knowledgeDir = Join-Path $repoRoot 'knowledge'
$cfg = Get-ResearchConfig -Path $ConfigPath
$staleDays = [int]$cfg.staleAfterDays
$showLimit = 5
if ($Detailed) { $showLimit = [int]::MaxValue }

function Show-Files {
    param([string[]]$Files, [string]$Indent = '    ')
    $shown = $Files | Select-Object -First $showLimit
    foreach ($f in $shown) { Write-Host "$Indent$f" -ForegroundColor DarkGray }
    if ($Files.Count -gt $shown.Count) {
        Write-Host "$Indent... and $($Files.Count - $shown.Count) more (-Detailed to list)" -ForegroundColor DarkGray
    }
}

function Get-Frontmatter {
    param([string]$Text)
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')
    if (-not $m.Success) { return $null }
    $fm = @{}
    foreach ($line in ($m.Groups[1].Value -split "`r?`n")) {
        $kv = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$')
        if ($kv.Success) { $fm[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim() }
    }
    return $fm
}

Write-Host ''
Write-Host 'Knowledge base' -ForegroundColor Cyan

$entries = Get-ChildItem -Path $knowledgeDir -Filter '*.md' -Recurse |
           Where-Object { $_.Directory.Name -ne 'templates' }

$entityRefs = @{}

if ($entries.Count -eq 0) {
    Write-Host '  No entries yet. Nothing to check.' -ForegroundColor DarkGray
}
else {
    $required = @('title','type','status','created','last_reviewed','tags')
    $noFrontmatter = @()
    $missingFields = @()
    $stale = @()
    $badDates = @()

    foreach ($e in $entries) {
        $rel = $e.FullName.Substring($repoRoot.Length + 1)
        $text = Get-Content $e.FullName -Raw
        $fm = Get-Frontmatter -Text $text

        if (-not $fm) { $noFrontmatter += $rel; continue }

        $missing = $required | Where-Object { -not $fm.ContainsKey($_) -or -not $fm[$_] }
        if ($missing) { $missingFields += "$rel (missing: $($missing -join ', '))" }

        if ($fm.ContainsKey('last_reviewed') -and $fm['last_reviewed']) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($fm['last_reviewed'], [ref]$parsed)) {
                $age = (Get-Date) - $parsed
                if ($age.TotalDays -gt $staleDays) {
                    $stale += "$rel ($([int]$age.TotalDays) days)"
                }
            }
            else { $badDates += "$rel (last_reviewed: $($fm['last_reviewed']))" }
        }

        if ($fm.ContainsKey('entities') -and $fm['entities']) {
            $list = $fm['entities'].Trim('[',']') -split ','
            foreach ($slug in $list) {
                $s = $slug.Trim().Trim("'",'"')
                if ($s) {
                    if (-not $entityRefs.ContainsKey($s)) { $entityRefs[$s] = @() }
                    $entityRefs[$s] += $rel
                }
            }
        }
    }

    $withFm = $entries.Count - $noFrontmatter.Count
    $pct = 0
    if ($entries.Count -gt 0) { $pct = [int](($withFm / $entries.Count) * 100) }

    Write-Host ("  {0,-26} {1}" -f 'entries', $entries.Count)
    Write-Host ("  {0,-26} {1}/{2} ({3}%)" -f 'frontmatter', $withFm, $entries.Count, $pct)
    if ($noFrontmatter) { Show-Files -Files $noFrontmatter }

    Write-Host ("  {0,-26} {1}" -f 'incomplete frontmatter', $missingFields.Count)
    if ($missingFields) { Show-Files -Files $missingFields }

    Write-Host ("  {0,-26} {1} (over {2} days)" -f 'stale', $stale.Count, $staleDays)
    if ($stale) { Show-Files -Files $stale }

    if ($badDates) {
        Write-Host ("  {0,-26} {1}" -f 'unparseable dates', $badDates.Count)
        Show-Files -Files $badDates
    }

    # Companies must be named for their entity slug. That is what lines the stores up.
    $companyDir = Join-Path $knowledgeDir 'companies'
    if (Test-Path $companyDir) {
        $mismatch = @()
        foreach ($c in (Get-ChildItem -Path $companyDir -Filter '*.md')) {
            $fm = Get-Frontmatter -Text (Get-Content $c.FullName -Raw)
            if ($fm -and $fm.ContainsKey('entity_slug') -and $fm['entity_slug']) {
                if ($fm['entity_slug'] -ne $c.BaseName) {
                    $mismatch += "$($c.Name) (entity_slug: $($fm['entity_slug']))"
                }
            }
        }
        if ($mismatch) {
            Write-Host ("  {0,-26} {1}" -f 'slug/filename mismatch', $mismatch.Count)
            Show-Files -Files $mismatch
        }
    }
}

Write-Host ''
Write-Host 'Citations' -ForegroundColor Cyan

# Scan only real content. The convention docs and templates contain illustrative
# citations that are not meant to resolve.
$scanFiles = @()
$scanFiles += $entries
$sessionDir = Join-Path $repoRoot 'docs\sessions'
if (Test-Path $sessionDir) {
    $scanFiles += Get-ChildItem -Path $sessionDir -Filter '*.md' |
                  Where-Object { $_.Name -ne 'README.md' }
}

$citations = @()
foreach ($f in $scanFiles) {
    $rel = $f.FullName.Substring($repoRoot.Length + 1)
    $text = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($text, '\b(OBS|SRC|ENT|THESIS):([A-Za-z0-9][A-Za-z0-9\-_]*)')) {
        $citations += [pscustomobject]@{
            File = $rel; Kind = $m.Groups[1].Value; Ref = $m.Groups[2].Value
        }
    }
}

Write-Host ("  {0,-26} {1} in {2} file(s)" -f 'found', $citations.Count, ($citations.File | Select-Object -Unique).Count)

if ($SkipDatabase) {
    Write-Host '  (database check skipped)' -ForegroundColor DarkGray
}
elseif ($citations.Count -gt 0) {
    try {
        $obsIds    = @((Invoke-ResearchQuery -Config $cfg -Query 'SELECT ObservationId FROM research.Observation') | ForEach-Object { [string]$_.ObservationId })
        $srcIds    = @((Invoke-ResearchQuery -Config $cfg -Query 'SELECT SourceId FROM research.Source') | ForEach-Object { [string]$_.SourceId })
        $entSlugs  = @((Invoke-ResearchQuery -Config $cfg -Query 'SELECT Slug FROM research.Entity') | ForEach-Object { [string]$_.Slug })
        $thesSlugs = @((Invoke-ResearchQuery -Config $cfg -Query 'SELECT Slug FROM research.Thesis') | ForEach-Object { [string]$_.Slug })

        $broken = @()
        foreach ($c in $citations) {
            $ok = $false
            switch ($c.Kind) {
                'OBS'    { $ok = $obsIds -contains $c.Ref }
                'SRC'    { $ok = $srcIds -contains $c.Ref }
                'ENT'    { $ok = $entSlugs -contains $c.Ref }
                'THESIS' { $ok = $thesSlugs -contains $c.Ref }
            }
            if (-not $ok) { $broken += "$($c.File): $($c.Kind):$($c.Ref)" }
        }

        Write-Host ("  {0,-26} {1}" -f 'broken', $broken.Count)
        if ($broken) { Show-Files -Files $broken }

        # Entity slugs named in frontmatter should exist too.
        if ($entries.Count -gt 0 -and $entityRefs.Count -gt 0) {
            $badSlugs = @()
            foreach ($slug in $entityRefs.Keys) {
                if ($entSlugs -notcontains $slug) {
                    $badSlugs += "$slug (in $($entityRefs[$slug] -join ', '))"
                }
            }
            Write-Host ("  {0,-26} {1}" -f 'unknown entity slugs', $badSlugs.Count)
            if ($badSlugs) { Show-Files -Files $badSlugs }
        }
    }
    catch {
        Write-Host "  Could not reach the database: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '  Re-run with -SkipDatabase to check markdown only.' -ForegroundColor DarkGray
    }
}

if (-not $SkipDatabase) {
    Write-Host ''
    Write-Host 'Database health' -ForegroundColor Cyan
    try {
        $health = Invoke-ResearchQuery -Config $cfg -Query @'
SELECT 'stale facts (over 180d)'       AS Check_, COUNT(*) AS N FROM research.vw_StaleFact
UNION ALL SELECT 'thin entities (<3 observations)', COUNT(*) FROM research.vw_ThinEntity
UNION ALL SELECT 'open theses',                     COUNT(*) FROM research.Thesis WHERE Status = 'open'
UNION ALL SELECT 'theses unreviewed over 90d',      COUNT(*) FROM research.vw_ThesisScorecard WHERE DaysSinceReview > 90
UNION ALL SELECT 'theses with no evidence',         COUNT(*) FROM research.vw_ThesisScorecard WHERE SupportingCount = 0 AND ContradictingCount = 0
UNION ALL SELECT 'observations from reliability<=2',COUNT(*) FROM research.vw_CurrentObservation WHERE SourceReliability <= 2
UNION ALL SELECT 'unexplained estimates',           COUNT(*) FROM research.Observation WHERE IsEstimate = 1 AND EstimateMethod IS NULL
UNION ALL SELECT 'fruitless runs logged',           COUNT(*) FROM research.CollectionRun WHERE WasFruitful = 0;
'@
        foreach ($row in $health) { Write-Host ("  {0,-36} {1}" -f $row.Check_, $row.N) }
    }
    catch {
        Write-Host "  Could not reach the database: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'This is a report, not a gate. Retrofit frontmatter when you next edit a file for' -ForegroundColor DarkGray
Write-Host 'another reason. Do not bulk-stamp dates to make the numbers look better.' -ForegroundColor DarkGray
Write-Host ''
