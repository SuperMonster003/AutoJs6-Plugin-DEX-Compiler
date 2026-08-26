#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $WorktreeA,

    [Parameter(Mandatory)]
    [string] $WorktreeB,

    [Parameter(Mandatory)]
    [string] $GatePathA,

    [Parameter(Mandatory)]
    [string] $GatePathB,

    [Parameter(Mandatory)]
    [string] $ReportDirectoryA,

    [Parameter(Mandatory)]
    [string] $ReportDirectoryB,

    [Parameter(Mandatory)]
    [string] $ExpectedCommit,

    [Parameter(Mandatory)]
    [string] $OutputPath,

    [string] $ExpectedCompilerVersion = '8.13.22',

    [string] $MatrixRelativePath = 'scripts\r4-d8-upgrade\r4-d8-upgrade-matrix.json',

    [string] $MatrixSchemaRelativePath = 'scripts\r4-d8-upgrade\r4-d8-upgrade-matrix.schema.json',

    [string] $ReportSchemaRelativePath = 'scripts\r4-d8-upgrade\r4-d8-upgrade-report.schema.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GateSchema = 'autojs6.dex.r4.d8-upgrade-gate/v3'
$ComparisonSchema = 'autojs6.dex.r5.clean-directory-determinism-comparison/v1'
$ModulePath = Join-Path $PSScriptRoot '..\r4-d8-upgrade\R4D8UpgradeGate.psm1'
$ExpectedCommit = $ExpectedCommit.ToLowerInvariant()
$resolvedOutputPath = $null

function Assert-True {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitText {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string[]] $Arguments
    )
    $result = (& git.exe -C $Repository @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git failed for clean-directory evidence: $result"
    }
    return $result
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)][string] $Child,
        [Parameter(Mandatory)][string] $Parent
    )
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $parentPrefix = [IO.Path]::GetFullPath($Parent).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    return [IO.Path]::GetFullPath($Child).StartsWith($parentPrefix, $comparison)
}

function Get-CellReportPaths {
    param([Parameter(Mandatory)][string] $Directory)
    Assert-True (Test-Path -LiteralPath $Directory -PathType Container) "Report directory is missing."
    $paths = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter '*.json' |
            Where-Object Name -cne 'gate.json' |
            Sort-Object Name |
            ForEach-Object FullName
    )
    Assert-True ($paths.Count -eq 60) "Expected exactly 60 cell reports; found $($paths.Count)."
    return $paths
}

function Read-Json {
    param([Parameter(Mandatory)][string] $Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Required JSON file is missing."
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Assert-GateMatches {
    param(
        [Parameter(Mandatory)] $Persisted,
        [Parameter(Mandatory)] $Recomputed,
        [Parameter(Mandatory)][string] $Label
    )
    Assert-True ($Persisted.schemaVersion -ceq $GateSchema) "$Label gate schema changed."
    Assert-True ([bool] $Persisted.passed) "$Label persisted gate is not PASS."
    Assert-True ([bool] $Recomputed.passed) "$Label recomputed gate is not PASS: $($Recomputed.reasons -join ' | ')"
    Assert-True ($Persisted.evaluationKind -ceq 'PINNED_DEFAULT') "$Label is not a pinned-default evaluation."
    Assert-True ($Persisted.determinismClaim -ceq 'NOT_CLAIMED') "$Label persisted gate makes an unsupported determinism claim."
    Assert-True ($Recomputed.determinismClaim -ceq 'NOT_CLAIMED') "$Label recomputed gate makes an unsupported determinism claim."
    Assert-True ([int] $Persisted.reportCount -eq 60) "$Label persisted gate report count changed."
    Assert-True ([int] $Recomputed.reportCount -eq 60) "$Label recomputed gate report count changed."
    Assert-True ($Persisted.producerInvocationId -ceq $Recomputed.producerInvocationId) "$Label producer invocation changed."
    Assert-True ($Persisted.matrixSha256 -ceq $Recomputed.matrixSha256) "$Label matrix digest changed."
    Assert-True ($Persisted.reportSchemaSha256 -ceq $Recomputed.reportSchemaSha256) "$Label report schema digest changed."
    Assert-True ($Persisted.reportSetSha256 -ceq $Recomputed.reportSetSha256) "$Label report-set digest changed."
    Assert-True ($Persisted.compiler.evaluatedVersion -ceq $ExpectedCompilerVersion) "$Label compiler version changed."
}

function Read-ReportMap {
    param(
        [Parameter(Mandatory)][string[]] $Paths,
        [Parameter(Mandatory)][string] $SchemaPath
    )
    $map = @{}
    foreach ($path in $Paths) {
        $report = Read-R4D8UpgradeReport -ReportPath $path -SchemaPath $SchemaPath
        $cellId = [string] $report.cellId
        Assert-True (-not $map.ContainsKey($cellId)) "Duplicate cellId '$cellId'."
        $map[$cellId] = $report
    }
    return $map
}

function Get-DexEntryNames {
    param([Parameter(Mandatory)] $Report)
    return @($Report.output.dexManifest | ForEach-Object { [string] $_.entryName }) -join '|'
}

function Get-DexByteManifest {
    param([Parameter(Mandatory)] $Report)
    $manifest = @(
        $Report.output.dexManifest | ForEach-Object {
            [pscustomobject][ordered]@{
                entryName = [string] $_.entryName
                sha256 = [string] $_.sha256
                byteLength = [long] $_.byteLength
            }
        }
    )
    return $manifest | ConvertTo-Json -Compress -Depth 5
}

try {
    Import-Module $ModulePath -Force -ErrorAction Stop

    $resolvedWorktreeA = (Resolve-Path -LiteralPath $WorktreeA).Path
    $resolvedWorktreeB = (Resolve-Path -LiteralPath $WorktreeB).Path
    Assert-True ($resolvedWorktreeA -cne $resolvedWorktreeB) 'The two clean directories must be distinct.'
    Assert-True (Test-PathWithin -Child $GatePathA -Parent $resolvedWorktreeA) 'Gate A is outside clean directory A.'
    Assert-True (Test-PathWithin -Child $GatePathB -Parent $resolvedWorktreeB) 'Gate B is outside clean directory B.'
    Assert-True (Test-PathWithin -Child $ReportDirectoryA -Parent $resolvedWorktreeA) 'Reports A are outside clean directory A.'
    Assert-True (Test-PathWithin -Child $ReportDirectoryB -Parent $resolvedWorktreeB) 'Reports B are outside clean directory B.'

    $matrixPathA = Join-Path $resolvedWorktreeA $MatrixRelativePath
    $matrixPathB = Join-Path $resolvedWorktreeB $MatrixRelativePath
    $matrixSchemaPathA = Join-Path $resolvedWorktreeA $MatrixSchemaRelativePath
    $matrixSchemaPathB = Join-Path $resolvedWorktreeB $MatrixSchemaRelativePath
    $reportSchemaPathA = Join-Path $resolvedWorktreeA $ReportSchemaRelativePath
    $reportSchemaPathB = Join-Path $resolvedWorktreeB $ReportSchemaRelativePath

    $commitA = Get-GitText -Repository $resolvedWorktreeA -Arguments @('rev-parse', 'HEAD')
    $commitB = Get-GitText -Repository $resolvedWorktreeB -Arguments @('rev-parse', 'HEAD')
    $statusA = Get-GitText -Repository $resolvedWorktreeA -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    $statusB = Get-GitText -Repository $resolvedWorktreeB -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    Assert-True ($commitA -ceq $ExpectedCommit) 'Clean directory A is not at the expected commit.'
    Assert-True ($commitB -ceq $ExpectedCommit) 'Clean directory B is not at the expected commit.'
    Assert-True ([string]::IsNullOrEmpty($statusA)) 'Clean directory A has tracked or untracked changes.'
    Assert-True ([string]::IsNullOrEmpty($statusB)) 'Clean directory B has tracked or untracked changes.'

    $persistedGateA = Read-Json -Path $GatePathA
    $persistedGateB = Read-Json -Path $GatePathB
    $reportPathsA = Get-CellReportPaths -Directory $ReportDirectoryA
    $reportPathsB = Get-CellReportPaths -Directory $ReportDirectoryB
    $gateA = Test-R4D8UpgradeGate `
        -MatrixPath $matrixPathA `
        -MatrixSchemaPath $matrixSchemaPathA `
        -ReportSchemaPath $reportSchemaPathA `
        -ReportPath $reportPathsA `
        -ExpectedCompilerVersion $ExpectedCompilerVersion `
        -ExpectedProducerInvocationId ([string] $persistedGateA.producerInvocationId)
    $gateB = Test-R4D8UpgradeGate `
        -MatrixPath $matrixPathB `
        -MatrixSchemaPath $matrixSchemaPathB `
        -ReportSchemaPath $reportSchemaPathB `
        -ReportPath $reportPathsB `
        -ExpectedCompilerVersion $ExpectedCompilerVersion `
        -ExpectedProducerInvocationId ([string] $persistedGateB.producerInvocationId)
    Assert-GateMatches -Persisted $persistedGateA -Recomputed $gateA -Label 'A'
    Assert-GateMatches -Persisted $persistedGateB -Recomputed $gateB -Label 'B'
    Assert-True ($gateA.matrixSha256 -ceq $gateB.matrixSha256) 'The clean directories used different matrices.'
    Assert-True ($gateA.reportSchemaSha256 -ceq $gateB.reportSchemaSha256) 'The clean directories used different report schemas.'

    $mapA = Read-ReportMap -Paths $reportPathsA -SchemaPath $reportSchemaPathA
    $mapB = Read-ReportMap -Paths $reportPathsB -SchemaPath $reportSchemaPathB
    $cellIds = @($mapA.Keys | Sort-Object -CaseSensitive)
    Assert-True ($cellIds.Count -eq 60) 'Clean directory A does not contain 60 unique cells.'
    Assert-True ($mapB.Count -eq 60) 'Clean directory B does not contain 60 unique cells.'
    Assert-True (@($mapB.Keys | Where-Object { $_ -cnotin $cellIds }).Count -eq 0) 'The clean directories contain different cellId sets.'

    $cells = foreach ($cellId in $cellIds) {
        $a = $mapA[$cellId]
        $b = $mapB[$cellId]
        $producedInA = ([string] $a.output.status) -ceq 'PRODUCED'
        $producedInB = ([string] $b.output.status) -ceq 'PRODUCED'
        $repeatDigestApplicable = $producedInA -and $producedInB
        [pscustomobject][ordered]@{
            cellId = $cellId
            inputDigestChanged = ([string] $a.input.sha256) -cne ([string] $b.input.sha256)
            runtimeFingerprintChanged = ([string] $a.runtimeFingerprint.sha256) -cne ([string] $b.runtimeFingerprint.sha256)
            compilerOutcomeChanged = ([string] $a.observedCompilerOutcome) -cne ([string] $b.observedCompilerOutcome)
            outputStatusChanged = ([string] $a.output.status) -cne ([string] $b.output.status)
            outputDigestChanged = ([string] $a.output.sha256) -cne ([string] $b.output.sha256)
            dexEntryNamesChanged = (Get-DexEntryNames $a) -cne (Get-DexEntryNames $b)
            dexByteManifestChanged = (Get-DexByteManifest $a) -cne (Get-DexByteManifest $b)
            repeatDigestApplicable = $repeatDigestApplicable
            cleanDirectoryARepeatDigestIdentical = if ($producedInA) {
                [bool] $a.repeatObservation.identicalOutputDigest
            } else { $null }
            cleanDirectoryBRepeatDigestIdentical = if ($producedInB) {
                [bool] $b.repeatObservation.identicalOutputDigest
            } else { $null }
        }
    }

    $inputDifferenceCount = @($cells | Where-Object inputDigestChanged).Count
    $runtimeDifferenceCount = @($cells | Where-Object runtimeFingerprintChanged).Count
    $outcomeDifferenceCount = @($cells | Where-Object compilerOutcomeChanged).Count
    $outputStatusDifferenceCount = @($cells | Where-Object outputStatusChanged).Count
    $outputDigestDifferenceCount = @($cells | Where-Object outputDigestChanged).Count
    $dexEntryNamesDifferenceCount = @($cells | Where-Object dexEntryNamesChanged).Count
    $dexByteManifestDifferenceCount = @($cells | Where-Object dexByteManifestChanged).Count
    $producedCellCount = @($cells | Where-Object repeatDigestApplicable).Count
    $repeatMismatchCount = @(
        $cells | Where-Object {
            $_.repeatDigestApplicable -and
                (-not $_.cleanDirectoryARepeatDigestIdentical -or -not $_.cleanDirectoryBRepeatDigestIdentical)
        }
    ).Count
    $comparisonPassed = $inputDifferenceCount -eq 0 -and
        $runtimeDifferenceCount -eq 0 -and
        $outcomeDifferenceCount -eq 0 -and
        $outputStatusDifferenceCount -eq 0 -and
        $dexEntryNamesDifferenceCount -eq 0 -and
        $repeatMismatchCount -eq 0

    $protectedInputs = @(
        @(
            $GatePathA,
            $GatePathB,
            $matrixPathA,
            $matrixPathB,
            $matrixSchemaPathA,
            $matrixSchemaPathB,
            $reportSchemaPathA,
            $reportSchemaPathB,
            $ModulePath
        ) +
            @($reportPathsA) + @($reportPathsB)
    )
    $resolvedOutputPath = Resolve-R4SafeOutputPath -OutputPath $OutputPath -InputPath $protectedInputs
    $result = [pscustomobject][ordered]@{
        schemaVersion = $ComparisonSchema
        comparisonStatus = 'COMPLETED'
        passed = $comparisonPassed
        evidenceBoundary = 'SINGLE_MACHINE_TWO_CLEAN_DIRECTORIES_JVM_COMPILER_ONLY'
        evaluatedUtc = [DateTime]::UtcNow.ToString('o')
        commit = $ExpectedCommit
        compilerVersion = $ExpectedCompilerVersion
        matrixId = [string] $gateA.matrixId
        matrixSha256 = [string] $gateA.matrixSha256
        reportSchemaSha256 = [string] $gateA.reportSchemaSha256
        cellCount = $cells.Count
        outputProducingCellCount = $producedCellCount
        expectedNoOutputCellCount = $cells.Count - $producedCellCount
        inputDigestDifferenceCount = $inputDifferenceCount
        runtimeFingerprintDifferenceCount = $runtimeDifferenceCount
        compilerOutcomeDifferenceCount = $outcomeDifferenceCount
        outputStatusDifferenceCount = $outputStatusDifferenceCount
        outputDigestDifferenceCount = $outputDigestDifferenceCount
        dexEntryNamesDifferenceCount = $dexEntryNamesDifferenceCount
        dexByteManifestDifferenceCount = $dexByteManifestDifferenceCount
        withinDirectoryRepeatDigestMismatchCount = $repeatMismatchCount
        exactCrossDirectoryOutputDigestMatch = $outputDigestDifferenceCount -eq 0
        determinismClaim = 'NOT_CLAIMED'
        cleanDirectories = @(
            [pscustomobject][ordered]@{
                label = 'A'
                commit = $commitA
                clean = $true
                producerInvocationId = [string] $gateA.producerInvocationId
                gateSha256 = Get-Sha256 -Path $GatePathA
                reportSetSha256 = [string] $gateA.reportSetSha256
            },
            [pscustomobject][ordered]@{
                label = 'B'
                commit = $commitB
                clean = $true
                producerInvocationId = [string] $gateB.producerInvocationId
                gateSha256 = Get-Sha256 -Path $GatePathB
                reportSetSha256 = [string] $gateB.reportSetSha256
            }
        )
        summary = if ($outputDigestDifferenceCount -eq 0) {
            "All $producedCellCount output-producing cells matched across clean directories and repeated with identical digests within each directory; the $($cells.Count - $producedCellCount) expected no-output cells matched in outcome and status. This is one-machine/two-clean-directory evidence; no general determinism claim is made."
        } else {
            "$outputDigestDifferenceCount of 60 cross-directory output digests differed. The byte differences are recorded, and no determinism claim is made."
        }
        cells = @($cells)
    }
    Write-R4AtomicJsonFile -Path $resolvedOutputPath -Json (($result | ConvertTo-Json -Depth 20) + "`n")
    $result
} catch {
    if ($null -ne $resolvedOutputPath) {
        $failure = [pscustomobject][ordered]@{
            schemaVersion = $ComparisonSchema
            comparisonStatus = 'FAILED'
            passed = $false
            evaluatedUtc = [DateTime]::UtcNow.ToString('o')
            determinismClaim = 'NOT_CLAIMED'
            reason = $_.Exception.Message
        }
        Write-R4AtomicJsonFile -Path $resolvedOutputPath -Json (($failure | ConvertTo-Json -Depth 5) + "`n")
    }
    throw
}
