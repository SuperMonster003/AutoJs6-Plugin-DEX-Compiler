#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateCount(3, 3)]
    [string[]] $ReportPaths,

    [Parameter(Mandatory)]
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ExpectedSchema = 'autojs6.dex.r5.classpath-cell-evidence/v1'
$ExpectedSelector = 'org.autojs.autojs.core.plugin.dex.DexCompilerRealProviderAndroidTest#representativeRhinoClasspathEntryUsesRealProviderAndRetainsLegacyLoadJar'
$ExpectedRoles = @('host', 'plugin', 'test')
$ExpectedSigner = '31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213'

function Get-Sha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Json {
    param([Parameter(Mandatory)][string] $Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    return [pscustomobject]@{
        Path = $resolved
        Value = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json -Depth 100
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-ReceiptManifest {
    param([Parameter(Mandatory)][string] $ReportPath)

    $directory = Split-Path -Parent $ReportPath
    $manifestPath = Join-Path $directory 'files.sha256.json'
    $entries = @(Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 10)
    $expectedFiles = @(
        Get-ChildItem -LiteralPath $directory -Recurse -File |
            Where-Object { $_.FullName -cne $manifestPath } |
            Sort-Object FullName
    )
    Assert-True ($entries.Count -eq $expectedFiles.Count) "Manifest count mismatch for $ReportPath"
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        $relative = [string] $entry.path
        Assert-True ($relative -cmatch '^(?!/)(?!.*(?:^|/)\.\.(?:/|$))[A-Za-z0-9._/-]+$') "Unsafe manifest path '$relative'"
        Assert-True ($seen.Add($relative)) "Duplicate manifest path '$relative'"
        $candidate = [IO.Path]::GetFullPath((Join-Path $directory $relative.Replace('/', '\')))
        $prefix = [IO.Path]::GetFullPath($directory).TrimEnd('\') + '\'
        Assert-True ($candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Manifest path escapes receipt: '$relative'"
        Assert-True (Test-Path -LiteralPath $candidate -PathType Leaf) "Manifest file is missing: '$relative'"
        $file = Get-Item -LiteralPath $candidate
        Assert-True ($file.Length -eq [long] $entry.sizeBytes) "Manifest byte length mismatch: '$relative'"
        Assert-True ((Get-Sha256 $candidate) -ceq [string] $entry.sha256) "Manifest digest mismatch: '$relative'"
    }
}

$outputParent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $outputParent)
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath
}

try {
    $reads = @($ReportPaths | ForEach-Object { Read-Json $_ })
    $reports = @($reads.Value)
    Assert-True ($reports.Count -eq 3) 'Exactly three classpath cell reports are required.'

    foreach ($read in $reads) {
        $report = $read.Value
        Assert-True ($report.schemaVersion -ceq $ExpectedSchema) "Unexpected report schema: $($read.Path)"
        Assert-True ($report.outcome -ceq 'PASS') "Cell did not pass: $($report.matrixCellId)"
        Assert-True ([bool] $report.scope.representativeR5MatrixCell) "Cell lacks representative-matrix scope: $($report.matrixCellId)"
        Assert-True ([int] $report.scope.scenarioCount -eq 1) "Cell scenario count changed: $($report.matrixCellId)"
        Assert-True ($report.scope.selector -ceq $ExpectedSelector) "Cell selector changed: $($report.matrixCellId)"
        Assert-True ([bool] $report.scenario.passed) "Cell scenario is not PASS: $($report.matrixCellId)"
        Assert-True ([bool] $report.safety.preflightFourPackagesAbsent) "Cell preflight was not clean: $($report.matrixCellId)"
        Assert-True ([bool] $report.safety.postflightFourPackagesAbsent) "Cell postflight was not clean: $($report.matrixCellId)"
        Assert-True (@($report.safety.cleanupFailures).Count -eq 0) "Cell cleanup failed: $($report.matrixCellId)"
        Assert-True ($report.safety.allAdbCommandsPinnedTo -ceq $report.device.adbSerial) "ADB serial binding changed: $($report.matrixCellId)"
        Assert-True ([bool] $report.repositories.host.clean -and [bool] $report.repositories.plugin.clean) "Cell repository identity was dirty: $($report.matrixCellId)"

        $roles = @($report.apks.role | Sort-Object)
        Assert-True (($roles -join ',') -ceq ($ExpectedRoles -join ',')) "Cell APK roles changed: $($report.matrixCellId)"
        $signers = @($report.apks.signerCertificateSha256 | Sort-Object -Unique)
        Assert-True ($signers.Count -eq 1 -and $signers[0] -ceq $ExpectedSigner) "Cell APK signer changed: $($report.matrixCellId)"
        Assert-True (@($report.apks | Where-Object { -not [bool] $_.v2Verified }).Count -eq 0) "Cell contains an APK without v2 verification: $($report.matrixCellId)"

        $instrumentation = @($report.commands | Where-Object { $_.label -ceq 'r5-classpath-entry-instrumentation' })
        Assert-True ($instrumentation.Count -eq 1) "Cell must contain one instrumentation command: $($report.matrixCellId)"
        Assert-True (-not [bool] $instrumentation[0].timedOut -and [int] $instrumentation[0].exitCode -eq 0) "Cell instrumentation command failed: $($report.matrixCellId)"
        $stdoutPath = Join-Path (Split-Path -Parent $read.Path) ([string] $instrumentation[0].stdoutFile).Replace('/', '\')
        $stdout = Get-Content -Raw -LiteralPath $stdoutPath
        Assert-True (@([regex]::Matches($stdout, '(?m)^OK \(1 test\)\r?$')).Count -eq 1) "Cell lacks exact OK (1 test): $($report.matrixCellId)"
        Assert-True (@([regex]::Matches($stdout, '(?m)^INSTRUMENTATION_CODE: -1\r?$')).Count -eq 1) "Cell lacks exact successful terminal: $($report.matrixCellId)"
        Assert-True ($stdout -notmatch 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed|AssumptionViolated|INSTRUMENTATION_ABORTED') "Cell stdout contains a failure/skip marker: $($report.matrixCellId)"
        Assert-ReceiptManifest -ReportPath $read.Path
    }

    $campaigns = @($reports.campaignId | Sort-Object -Unique)
    Assert-True ($campaigns.Count -eq 1 -and $campaigns[0] -cmatch '^[0-9a-f-]{36}$') 'Reports do not share one canonical campaignId.'
    $cellIds = @($reports.matrixCellId | Sort-Object -Unique)
    Assert-True ($cellIds.Count -eq 3) 'Reports do not contain three unique matrixCellId values.'
    Assert-True (@($reports | Where-Object { $_.device.kind -ceq 'EMULATOR' -and [int] $_.device.apiLevel -in 24, 25 }).Count -ge 1) 'Matrix lacks an API 24/25 emulator CLI-compatible cell.'
    Assert-True (@($reports | Where-Object { $_.device.kind -ceq 'EMULATOR' -and [int] $_.device.apiLevel -ge 26 }).Count -ge 1) 'Matrix lacks an API 26+ emulator D8Command cell.'
    Assert-True (@($reports | Where-Object { $_.device.kind -ceq 'PHYSICAL' -and $_.device.abi -ceq 'arm64-v8a' }).Count -ge 1) 'Matrix lacks an authorized arm64 physical-device cell.'

    $hostCommits = @($reports.repositories.host.commit | Sort-Object -Unique)
    $pluginCommits = @($reports.repositories.plugin.commit | Sort-Object -Unique)
    Assert-True ($hostCommits.Count -eq 1) 'Matrix reports use different host commits.'
    Assert-True ($pluginCommits.Count -eq 1) 'Matrix reports use different plugin commits.'
    foreach ($role in $ExpectedRoles) {
        $digests = @($reports | ForEach-Object { @($_.apks | Where-Object role -CEQ $role)[0].sha256 } | Sort-Object -Unique)
        Assert-True ($digests.Count -eq 1) "Matrix reports use different $role APKs."
    }

    $result = [ordered]@{
        schemaVersion = 'autojs6.dex.r5.classpath-matrix-gate/v1'
        passed = $true
        campaignId = $campaigns[0]
        evaluatedUtc = [DateTime]::UtcNow.ToString('o')
        evidenceBoundary = 'THREE_REPRESENTATIVE_REAL_PROVIDER_DEVICE_CELLS'
        cellCount = 3
        matrixCellIds = $cellIds
        hostCommit = $hostCommits[0]
        pluginCommit = $pluginCommits[0]
        signerCertificateSha256 = $ExpectedSigner
        reports = @($reads | ForEach-Object {
            [ordered]@{
                matrixCellId = $_.Value.matrixCellId
                reportFileName = [IO.Path]::GetFileName($_.Path)
                reportSha256 = Get-Sha256 $_.Path
                device = $_.Value.device
            }
        })
        summary = 'Three representative V1.1 classpath cells passed real provider, Rhino, DexClassLoader, compile-only classpath, cache-hit, and V1.0 regression assertions with clean package restoration.'
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), (($result | ConvertTo-Json -Depth 20) + "`n"), $Utf8NoBom)
    $result
} catch {
    $failure = [ordered]@{
        schemaVersion = 'autojs6.dex.r5.classpath-matrix-gate/v1'
        passed = $false
        evaluatedUtc = [DateTime]::UtcNow.ToString('o')
        reason = $_.Exception.Message
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), (($failure | ConvertTo-Json -Depth 5) + "`n"), $Utf8NoBom)
    throw
}
