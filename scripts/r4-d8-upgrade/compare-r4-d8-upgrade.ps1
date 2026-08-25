[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $BaselineReportDirectory,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $CandidateReportDirectory,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $BaselineVersion,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $CandidateVersion,

    [string] $MatrixPath = (Join-Path $PSScriptRoot 'r4-d8-upgrade-matrix.json'),

    [string] $MatrixSchemaPath = (Join-Path $PSScriptRoot 'r4-d8-upgrade-matrix.schema.json'),

    [string] $ReportSchemaPath = (Join-Path $PSScriptRoot 'r4-d8-upgrade-report.schema.json'),

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This bootstrap deliberately has no module dependency. It establishes the only safe failure-output
# path before the gate module is loaded, so a missing or broken module cannot leave stale PASS.
function Get-R4D8BootstrapCanonicalPath {
    param([Parameter(Mandatory)] [string] $Path)

    $pathToResolve = [IO.Path]::GetFullPath($Path)
    for ($pass = 0; $pass -lt 64; $pass++) {
        $root = [IO.Path]::GetPathRoot($pathToResolve)
        if ([string]::IsNullOrWhiteSpace($root)) { throw 'Path has no filesystem root.' }
        [char[]] $separators = @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $segments = @($pathToResolve.Substring($root.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries))
        $current = $root
        $linkResolved = $false
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $candidate = [IO.Path]::Combine($current, $segments[$index])
            if (Test-Path -LiteralPath $candidate) {
                $item = Get-Item -LiteralPath $candidate -Force
                $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                if ($null -ne $item.LinkType -or $isReparsePoint) {
                    $target = $item.ResolveLinkTarget($true)
                    if ($null -eq $target) { throw 'Unable to resolve a reparse point in path.' }
                    $remaining = if ($index + 1 -lt $segments.Count) {
                        [IO.Path]::Combine([string[]] $segments[($index + 1)..($segments.Count - 1)])
                    } else { '' }
                    $pathToResolve = if ([string]::IsNullOrEmpty($remaining)) {
                        [IO.Path]::GetFullPath($target.FullName)
                    } else {
                        [IO.Path]::GetFullPath([IO.Path]::Combine($target.FullName, $remaining))
                    }
                    $linkResolved = $true
                    break
                }
            }
            $current = $candidate
        }
        if (-not $linkResolved) { return [IO.Path]::GetFullPath($current) }
    }
    throw 'Path contains too many reparse-point resolutions.'
}

function Resolve-R4D8BootstrapSafeOutputPath {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string[]] $ProtectedPath
    )

    $resolvedOutput = Get-R4D8BootstrapCanonicalPath -Path $Candidate
    if (Test-Path -LiteralPath $resolvedOutput -PathType Container) {
        throw 'OutputPath must be a file path, not a directory.'
    }
    $parent = [IO.Path]::GetDirectoryName($resolvedOutput)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    foreach ($inputPath in $ProtectedPath) {
        if ([string]::IsNullOrWhiteSpace($inputPath)) { continue }
        $resolvedInput = Get-R4D8BootstrapCanonicalPath -Path $inputPath
        if ([string]::Equals($resolvedOutput, $resolvedInput, $comparison)) {
            throw 'OutputPath aliases protected input path.'
        }
        if (
            (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -and
            (Test-Path -LiteralPath $resolvedInput -PathType Leaf)
        ) {
            $outputItem = Get-Item -LiteralPath $resolvedOutput
            $inputItem = Get-Item -LiteralPath $resolvedInput
            if (
                $outputItem.Length -eq $inputItem.Length -and
                (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash -ceq
                    (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash
            ) {
                throw 'OutputPath may alias protected input content.'
            }
        }
    }
    return $resolvedOutput
}

function Write-R4D8BootstrapAtomicJson {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Json
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolvedPath)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
    $temporary = [IO.Path]::Combine(
        $parent,
        ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($resolvedPath), [guid]::NewGuid().ToString('N'))
    )
    try {
        [IO.File]::WriteAllText($temporary, $Json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $resolvedPath, $true)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function ConvertTo-R4D8SafeFailureMessage {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string[]] $PrivatePath
    )

    $safe = $Message
    $orderedPaths = @(
        $PrivatePath |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                try { [IO.Path]::GetFullPath($_) } catch { $null }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object Length -Descending -Unique
    )
    foreach ($privatePathValue in $orderedPaths) {
        $safe = [regex]::Replace(
            $safe,
            [regex]::Escape($privatePathValue),
            '<private-path>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    return $safe
}

function Get-CellReportPaths {
    param([Parameter(Mandatory)][string] $Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "Report directory does not exist: $Directory"
    }
    $paths = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter '*.json' |
            Where-Object Name -cne 'gate.json' |
            Sort-Object Name |
            ForEach-Object FullName
    )
    if ($paths.Count -eq 0) {
        throw "Report directory contains no cell reports: $Directory"
    }
    return $paths
}

function Read-ReportMap {
    param([Parameter(Mandatory)][string[]] $Paths)

    $map = @{}
    foreach ($path in $Paths) {
        $report = Read-R4D8UpgradeReport -ReportPath $path -SchemaPath $ReportSchemaPath
        $cellId = [string] $report.cellId
        if ($map.ContainsKey($cellId)) {
            throw "Duplicate cellId '$cellId' in comparison input."
        }
        $map[$cellId] = $report
    }
    return $map
}

$modulePath = Join-Path $PSScriptRoot 'R4D8UpgradeGate.psm1'
$resolvedOutputPath = $null
$safeOutputEstablished = $false
$privatePaths = @(
    $PSScriptRoot
    [IO.Path]::GetTempPath()
    $modulePath
    $PSCommandPath
    $MatrixPath
    $MatrixSchemaPath
    $ReportSchemaPath
    $BaselineReportDirectory
    $CandidateReportDirectory
)
try {
    $baselinePaths = if (Test-Path -LiteralPath $BaselineReportDirectory -PathType Container) {
        @(
            Get-ChildItem -LiteralPath $BaselineReportDirectory -File -Filter '*.json' |
                Where-Object Name -cne 'gate.json' |
                Sort-Object Name |
                ForEach-Object FullName
        )
    } else { @() }
    $candidatePaths = if (Test-Path -LiteralPath $CandidateReportDirectory -PathType Container) {
        @(
            Get-ChildItem -LiteralPath $CandidateReportDirectory -File -Filter '*.json' |
                Where-Object Name -cne 'gate.json' |
                Sort-Object Name |
                ForEach-Object FullName
        )
    } else { @() }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $protectedInputPaths = @(
            @($MatrixPath, $MatrixSchemaPath, $ReportSchemaPath, $modulePath, $PSCommandPath) +
                @($baselinePaths) + @($candidatePaths) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }
        )
        $resolvedOutputPath = Resolve-R4D8BootstrapSafeOutputPath `
            -Candidate $OutputPath `
            -ProtectedPath $protectedInputPaths
        $safeOutputEstablished = $true
    }
    Import-Module $modulePath -Force -ErrorAction Stop
    if ($safeOutputEstablished) {
        $resolvedOutputPath = Resolve-R4SafeOutputPath `
            -OutputPath $resolvedOutputPath `
            -InputPath $protectedInputPaths
    }
    if (-not (Test-Path -LiteralPath $BaselineReportDirectory -PathType Container)) {
        throw "Report directory does not exist: $BaselineReportDirectory"
    }
    if (-not (Test-Path -LiteralPath $CandidateReportDirectory -PathType Container)) {
        throw "Report directory does not exist: $CandidateReportDirectory"
    }
    if ($baselinePaths.Count -eq 0) {
        throw "Report directory contains no cell reports: $BaselineReportDirectory"
    }
    if ($candidatePaths.Count -eq 0) {
        throw "Report directory contains no cell reports: $CandidateReportDirectory"
    }
    $matrixRead = Read-R4D8UpgradeMatrix -MatrixPath $MatrixPath -SchemaPath $MatrixSchemaPath
    $pinnedVersion = [string] $matrixRead.Manifest.compiler.pinnedVersion
    if ($BaselineVersion -cne $pinnedVersion) {
        throw "BaselineVersion must equal pinned compiler version '$pinnedVersion'."
    }
    if ($BaselineVersion -ceq $CandidateVersion) {
        throw 'BaselineVersion and CandidateVersion must differ.'
    }
    $baselineGate = Test-R4D8UpgradeGate `
        -MatrixPath $MatrixPath `
        -MatrixSchemaPath $MatrixSchemaPath `
        -ReportSchemaPath $ReportSchemaPath `
        -ReportPath $baselinePaths `
        -ExpectedCompilerVersion $BaselineVersion
    $candidateGate = Test-R4D8UpgradeGate `
        -MatrixPath $MatrixPath `
        -MatrixSchemaPath $MatrixSchemaPath `
        -ReportSchemaPath $ReportSchemaPath `
        -ReportPath $candidatePaths `
        -ExpectedCompilerVersion $CandidateVersion `
        -CandidateEvaluation
    if (-not $baselineGate.passed) {
        throw "Baseline gate failed: $($baselineGate.reasons -join ' | ')"
    }
    if (-not $candidateGate.passed) {
        throw "Candidate gate failed: $($candidateGate.reasons -join ' | ')"
    }

    $baseline = Read-ReportMap -Paths $baselinePaths
    $candidate = Read-ReportMap -Paths $candidatePaths
    $cellIds = @($baseline.Keys | Sort-Object -CaseSensitive)
    if ($cellIds.Count -ne $candidate.Count -or
        @($candidate.Keys | Where-Object { $_ -cnotin $cellIds }).Count -gt 0) {
        throw 'Baseline and candidate cell sets differ.'
    }

    $cells = foreach ($cellId in $cellIds) {
        $before = $baseline[$cellId]
        $after = $candidate[$cellId]
        $baselineEntryNames = @($before.output.dexManifest | ForEach-Object { [string] $_.entryName })
        $candidateEntryNames = @($after.output.dexManifest | ForEach-Object { [string] $_.entryName })
        [pscustomobject][ordered]@{
            cellId = $cellId
            inputDigestChanged = $before.input.sha256 -cne $after.input.sha256
            runtimeFingerprintChanged = $before.runtimeFingerprint.sha256 -cne $after.runtimeFingerprint.sha256
            compilerOutcomeChanged = $before.observedCompilerOutcome -cne $after.observedCompilerOutcome
            outputDigestChanged = $before.output.sha256 -cne $after.output.sha256
            dexEntryNamesChanged = ($baselineEntryNames -join '|') -cne ($candidateEntryNames -join '|')
        }
    }

    $inputDifferenceCount = @($cells | Where-Object inputDigestChanged).Count
    $runtimeDifferenceCount = @($cells | Where-Object runtimeFingerprintChanged).Count
    $outcomeDifferenceCount = @($cells | Where-Object compilerOutcomeChanged).Count
    $outputDigestDifferenceCount = @($cells | Where-Object outputDigestChanged).Count
    $dexEntryNamesDifferenceCount = @($cells | Where-Object dexEntryNamesChanged).Count
    $passed = $inputDifferenceCount -eq 0 -and
        $runtimeDifferenceCount -eq 0 -and
        $outcomeDifferenceCount -eq 0 -and
        $dexEntryNamesDifferenceCount -eq 0

    $result = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-upgrade-comparison/v1'
        matrixId = [string] $baselineGate.matrixId
        evidenceBoundary = 'JVM_COMPILER_ONLY'
        baselineVersion = $BaselineVersion
        candidateVersion = $CandidateVersion
        baselineReportSetSha256 = [string] $baselineGate.reportSetSha256
        candidateReportSetSha256 = [string] $candidateGate.reportSetSha256
        passed = $passed
        cellCount = $cells.Count
        inputDigestDifferenceCount = $inputDifferenceCount
        runtimeFingerprintDifferenceCount = $runtimeDifferenceCount
        compilerOutcomeDifferenceCount = $outcomeDifferenceCount
        outputDigestDifferenceCount = $outputDigestDifferenceCount
        dexEntryNamesDifferenceCount = $dexEntryNamesDifferenceCount
        determinismClaim = 'NOT_CLAIMED'
        summary = if ($passed) {
            'Inputs, runtime fingerprints, compiler outcomes, and DEX entry topology match; byte-output differences are recorded without a determinism claim.'
        } else {
            'The candidate differs in input identity, runtime identity, compiler outcome, or DEX entry topology and is not eligible for promotion.'
        }
        cells = @($cells)
    }
    $json = $result | ConvertTo-Json -Depth 20
    if ($null -ne $resolvedOutputPath) {
        Write-R4AtomicJsonFile -Path $resolvedOutputPath -Json $json
    }
    $json
    if (-not $passed) {
        exit 1
    }
} catch {
    $failureMessage = ConvertTo-R4D8SafeFailureMessage `
        -Message $_.Exception.Message `
        -PrivatePath ($privatePaths + @($resolvedOutputPath))
    $errorResult = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-upgrade-comparison-error/v1'
        passed = $false
        determinismClaim = 'NOT_CLAIMED'
        error = $failureMessage
    }
    $errorJson = $errorResult | ConvertTo-Json -Depth 10
    if ($safeOutputEstablished -and $null -ne $resolvedOutputPath) {
        try {
            Write-R4D8BootstrapAtomicJson -Path $resolvedOutputPath -Json $errorJson
        } catch {
            $errorResult | Add-Member -NotePropertyName persistenceError -NotePropertyValue 'Atomic failure report persistence failed.'
            $errorJson = $errorResult | ConvertTo-Json -Depth 10
        }
    }
    $errorJson
    exit 1
}
