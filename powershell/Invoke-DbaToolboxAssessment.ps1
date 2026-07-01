<#
.SYNOPSIS
    Runs DBA Toolbox assessment scripts against a SQL Server instance.
.DESCRIPTION
    Read-only wrapper that executes a curated script bundle and writes one CSV
    per result set. Requires the SqlServer PowerShell module.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [string]$Database = 'master',

    [string]$OutputPath = (Join-Path (Get-Location) ("reports/{0}-{1:yyyyMMdd-HHmmss}" -f $SqlInstance.Replace('\','_'), (Get-Date))),

    [string[]]$ScriptPath = @(
        'health-checks/server-health-check.sql',
        'health-checks/database-size-report.sql',
        'health-checks/tempdb-configuration-check.sql',
        'backup-restore/backup-status-report.sql',
        'monitoring/agent-job-status.sql',
        'performance/wait-stats-snapshot.sql'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    throw "SqlServer module is required. Install with: Install-Module SqlServer -Scope CurrentUser"
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$summary = foreach ($relativeScript in $ScriptPath) {
    $fullScript = Join-Path $RepoRoot $relativeScript
    if (-not (Test-Path $fullScript)) {
        [pscustomobject]@{ Script = $relativeScript; Status = 'Missing'; Output = $null }
        continue
    }

    $safeName = ($relativeScript -replace '[\\/]', '_') -replace '\.sql$', '.csv'
    $target = Join-Path $OutputPath $safeName

    if ($PSCmdlet.ShouldProcess($SqlInstance, "Run $relativeScript")) {
        $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $Database -InputFile $fullScript -TrustServerCertificate -ErrorAction Stop
        if ($null -ne $result) {
            $result | Export-Csv -NoTypeInformation -Path $target
        } else {
            New-Item -ItemType File -Force -Path $target | Out-Null
        }
        [pscustomobject]@{ Script = $relativeScript; Status = 'Completed'; Output = $target }
    }
}

$summaryPath = Join-Path $OutputPath 'assessment-summary.csv'
$summary | Export-Csv -NoTypeInformation -Path $summaryPath
$summary
Write-Host "Assessment output: $OutputPath"
