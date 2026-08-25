Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MatrixSchemaVersion = 'autojs6.dex.r4.d8-upgrade-matrix/v2'
$script:ReportSchemaVersion = 'autojs6.dex.r4.d8-upgrade-report/v2'
$script:GateSchemaVersion = 'autojs6.dex.r4.d8-upgrade-gate/v3'
$script:EvidenceBoundary = 'JVM_COMPILER_ONLY'
$script:CompilerCoordinate = 'com.android.tools:r8'
$script:PinnedCompilerVersion = '8.13.22'
$script:RollbackCompilerVersion = '8.13.17'
$script:CandidateVersionProperty = 'd8CandidateVersion'
$script:RollbackEvaluationProperty = 'd8RollbackEvaluation'
$script:AcceptanceKeyTemplate = '{caseId}|minApi={minApi}|mode={mode}|compiler={compilerVersion}'

function Read-R4JsonWithSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $SchemaPath,

        [Parameter(Mandatory)]
        [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "$Label schema does not exist: $SchemaPath"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "$Label is empty: $Path"
    }

    $schemaErrors = @()
    $valid = $raw | Test-Json `
        -SchemaFile $SchemaPath `
        -ErrorAction SilentlyContinue `
        -ErrorVariable +schemaErrors `
        -WarningAction SilentlyContinue
    if (-not $valid) {
        $detail = if ($schemaErrors.Count -gt 0) {
            ' ' + (($schemaErrors | ForEach-Object { $_.Exception.Message }) -join ' | ')
        } else {
            ''
        }
        throw "$Label does not conform to schema '$SchemaPath': $Path.$detail"
    }

    try {
        return $raw | ConvertFrom-Json -Depth 100 -NoEnumerate
    } catch {
        throw "$Label is not valid JSON: $Path. $($_.Exception.Message)"
    }
}

function Get-R4CanonicalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $pathToResolve = [IO.Path]::GetFullPath($Path)
    for ($resolutionPass = 0; $resolutionPass -lt 64; $resolutionPass++) {
        $root = [IO.Path]::GetPathRoot($pathToResolve)
        if ([string]::IsNullOrWhiteSpace($root)) {
            throw "Path has no filesystem root: $pathToResolve"
        }
        $relative = $pathToResolve.Substring($root.Length)
        [char[]] $pathSeparators = @(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $segments = @(
            $relative.Split($pathSeparators, [StringSplitOptions]::RemoveEmptyEntries)
        )
        $current = $root
        $ancestorLinkResolved = $false
        for ($segmentIndex = 0; $segmentIndex -lt $segments.Count; $segmentIndex++) {
            $candidate = [IO.Path]::Combine($current, $segments[$segmentIndex])
            if (Test-Path -LiteralPath $candidate) {
                $item = Get-Item -LiteralPath $candidate -Force
                $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                if ($null -ne $item.LinkType -or $isReparsePoint) {
                    $resolvedTarget = $item.ResolveLinkTarget($true)
                    if ($null -eq $resolvedTarget) {
                        throw "Unable to resolve reparse point in path: $candidate"
                    }
                    $remaining = if ($segmentIndex + 1 -lt $segments.Count) {
                        [IO.Path]::Combine([string[]] $segments[($segmentIndex + 1)..($segments.Count - 1)])
                    } else {
                        ''
                    }
                    $pathToResolve = if ([string]::IsNullOrEmpty($remaining)) {
                        [IO.Path]::GetFullPath($resolvedTarget.FullName)
                    } else {
                        [IO.Path]::GetFullPath([IO.Path]::Combine($resolvedTarget.FullName, $remaining))
                    }
                    $ancestorLinkResolved = $true
                    break
                }
            }
            $current = $candidate
        }
        if (-not $ancestorLinkResolved) {
            return [IO.Path]::GetFullPath($current)
        }
    }
    throw "Path contains too many symbolic-link or junction resolutions: $Path"
}

function Resolve-R4SafeOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $InputPath
    )

    $resolvedOutputPath = Get-R4CanonicalPath -Path $OutputPath
    if (Test-Path -LiteralPath $resolvedOutputPath -PathType Container) {
        throw "OutputPath must be a file path, not a directory: $resolvedOutputPath"
    }
    $parent = [IO.Path]::GetDirectoryName($resolvedOutputPath)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw "Output directory does not exist: $parent"
    }

    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    foreach ($input in $InputPath) {
        $resolvedInputPath = Get-R4CanonicalPath -Path $input
        if ([string]::Equals($resolvedOutputPath, $resolvedInputPath, $comparison)) {
            throw "OutputPath aliases protected input path '$resolvedInputPath'."
        }
    }
    return $resolvedOutputPath
}

function Write-R4AtomicJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Json
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolvedPath)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw "Output directory does not exist: $parent"
    }
    $temporaryPath = [IO.Path]::Combine(
        $parent,
        ('.{0}.{1}.tmp' -f ([IO.Path]::GetFileName($resolvedPath)), ([guid]::NewGuid().ToString('N')))
    )
    try {
        [IO.File]::WriteAllText($temporaryPath, $Json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $resolvedPath, $true)
    } finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

function Get-R4Sha256File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-R4Sha256Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Assert-R4ExactSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Actual,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Expected,

        [Parameter(Mandatory)]
        [string] $Label
    )

    if ($Actual.Count -ne $Expected.Count) {
        throw "$Label must contain exactly [$($Expected -join ', ')]; found [$($Actual -join ', ')]."
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string] $Actual[$index] -cne [string] $Expected[$index]) {
            throw "$Label must contain exactly [$($Expected -join ', ')] in canonical order; found [$($Actual -join ', ')]."
        }
    }
}

function Get-R4CellId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CaseId,

        [Parameter(Mandatory)]
        [int] $MinApi,

        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'RELEASE')]
        [string] $Mode
    )

    return '{0}--api{1}--{2}' -f $CaseId, $MinApi, $Mode.ToLowerInvariant()
}

function Get-R4AcceptanceKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CaseId,

        [Parameter(Mandatory)]
        [int] $MinApi,

        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'RELEASE')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [string] $CompilerVersion
    )

    return '{0}|minApi={1}|mode={2}|compiler={3}' -f $CaseId, $MinApi, $Mode, $CompilerVersion
}

function Assert-R4MatrixCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Matrix
    )

    if ($Matrix.schemaVersion -cne $script:MatrixSchemaVersion) {
        throw "Unsupported matrix schemaVersion '$($Matrix.schemaVersion)'."
    }

    $requiredMinApis = @(24..36)
    Assert-R4ExactSequence -Actual @($Matrix.minApis) -Expected $requiredMinApis -Label 'matrix minApis'
    Assert-R4ExactSequence -Actual @($Matrix.modes) -Expected @('DEBUG', 'RELEASE') -Label 'matrix modes'

    if ($Matrix.compiler.coordinate -cne $script:CompilerCoordinate -or
        $Matrix.compiler.pinnedVersion -cne $script:PinnedCompilerVersion -or
        $Matrix.compiler.rollbackVersion -cne $script:RollbackCompilerVersion -or
        $Matrix.compiler.candidateVersionProperty -cne $script:CandidateVersionProperty -or
        $Matrix.compiler.rollbackEvaluationProperty -cne $script:RollbackEvaluationProperty) {
        throw 'Matrix compiler governance values do not match the pinned R4.1-G1 contract.'
    }
    if ($Matrix.evidenceBoundary -cne $script:EvidenceBoundary) {
        throw "Matrix evidenceBoundary must be $($script:EvidenceBoundary)."
    }
    if ($Matrix.acceptanceKeyTemplate -cne $script:AcceptanceKeyTemplate) {
        throw 'Matrix acceptanceKeyTemplate does not match the R4.1-G1 contract.'
    }

    $caseIds = @($Matrix.cases | ForEach-Object { [string] $_.id })
    $duplicateCaseIds = @($caseIds | Group-Object -CaseSensitive | Where-Object Count -gt 1 | ForEach-Object Name)
    if ($duplicateCaseIds.Count -gt 0) {
        throw "Matrix contains duplicate case id values: $($duplicateCaseIds -join ', ')."
    }

    foreach ($case in $Matrix.cases) {
        foreach ($minApi in @($case.minApis)) {
            if ([int] $minApi -notin $requiredMinApis) {
                throw "Case '$($case.id)' contains minApi '$minApi' outside the matrix boundary."
            }
        }
        foreach ($mode in @($case.modes)) {
            if ([string] $mode -cnotin @('DEBUG', 'RELEASE')) {
                throw "Case '$($case.id)' contains unsupported mode '$mode'."
            }
        }
    }

    foreach ($javaVersion in @('8', '11', '17', '21')) {
        $matches = @($Matrix.cases | Where-Object {
            $_.fixtureKind -ceq 'JAVA_CLASSFILE' -and
            $_.languageVersion -ceq $javaVersion -and
            $_.jvmTarget -ceq $javaVersion -and
            $_.expectedOutcome -ceq 'COMPILE_SUCCESS'
        })
        if ($matches.Count -ne 1) {
            throw "Matrix must contain exactly one successful Java $javaVersion / JVM target $javaVersion case."
        }
    }

    $kotlinCases = @($Matrix.cases | Where-Object {
        $_.fixtureKind -ceq 'KOTLIN_CLASSFILE' -and
        $_.languageVersion -ceq 'CURRENT' -and
        $_.jvmTarget -ceq '21' -and
        $_.expectedOutcome -ceq 'COMPILE_SUCCESS'
    })
    if ($kotlinCases.Count -ne 1) {
        throw 'Matrix must contain exactly one successful Kotlin CURRENT / JVM target 21 case.'
    }

    $requiredFixtureOutcomes = [ordered]@{
        STANDARD_DESUGARING = 'COMPILE_SUCCESS'
        GENERATED_MULTIDEX = 'COMPILE_SUCCESS'
        MISSING_DEPENDENCY = 'COMPILE_SUCCESS'
        MALFORMED_CLASSFILE = 'COMPILE_FAILURE'
        UNSUPPORTED_CLASSFILE = 'COMPILE_FAILURE'
        DUPLICATE_DEFINITION = 'COMPILE_FAILURE'
    }
    foreach ($fixtureKind in $requiredFixtureOutcomes.Keys) {
        $matches = @($Matrix.cases | Where-Object {
            $_.fixtureKind -ceq $fixtureKind -and
            $_.expectedOutcome -ceq $requiredFixtureOutcomes[$fixtureKind]
        })
        if ($matches.Count -lt 1) {
            throw "Matrix is missing required fixtureKind '$fixtureKind' with outcome '$($requiredFixtureOutcomes[$fixtureKind])'."
        }
    }

    $java8Sweep = @($Matrix.cases | Where-Object {
        $_.id -ceq 'java8' -and
        $_.fixtureKind -ceq 'JAVA_CLASSFILE' -and
        $_.languageVersion -ceq '8' -and
        $_.jvmTarget -ceq '8'
    })
    if ($java8Sweep.Count -ne 1) {
        throw "Matrix must contain the canonical 'java8' min-api sweep case."
    }
    Assert-R4ExactSequence -Actual @($java8Sweep[0].minApis) -Expected $requiredMinApis -Label 'java8 sweep minApis'
    Assert-R4ExactSequence -Actual @($java8Sweep[0].modes) -Expected @('DEBUG', 'RELEASE') -Label 'java8 sweep modes'

    $expectedCases = @(
        @{ Id = 'java8'; FixtureKind = 'JAVA_CLASSFILE'; LanguageVersion = '8'; JvmTarget = '8'; MinApis = @(24..36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'java11'; FixtureKind = 'JAVA_CLASSFILE'; LanguageVersion = '11'; JvmTarget = '11'; MinApis = @(24, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'java17'; FixtureKind = 'JAVA_CLASSFILE'; LanguageVersion = '17'; JvmTarget = '17'; MinApis = @(24, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'java21'; FixtureKind = 'JAVA_CLASSFILE'; LanguageVersion = '21'; JvmTarget = '21'; MinApis = @(24, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'kotlin-current-target21'; FixtureKind = 'KOTLIN_CLASSFILE'; LanguageVersion = 'CURRENT'; JvmTarget = '21'; MinApis = @(24, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'standard-desugaring'; FixtureKind = 'STANDARD_DESUGARING'; LanguageVersion = '17'; JvmTarget = '17'; MinApis = @(24, 26, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'generated-multidex'; FixtureKind = 'GENERATED_MULTIDEX'; LanguageVersion = '21'; JvmTarget = '21'; MinApis = @(24, 36); Modes = @('DEBUG', 'RELEASE'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'missing-dependency'; FixtureKind = 'MISSING_DEPENDENCY'; LanguageVersion = '17'; JvmTarget = '17'; MinApis = @(24, 36); Modes = @('DEBUG'); ExpectedOutcome = 'COMPILE_SUCCESS' },
        @{ Id = 'malformed-classfile'; FixtureKind = 'MALFORMED_CLASSFILE'; LanguageVersion = 'N/A'; JvmTarget = 'N/A'; MinApis = @(24, 36); Modes = @('DEBUG'); ExpectedOutcome = 'COMPILE_FAILURE' },
        @{ Id = 'unsupported-classfile'; FixtureKind = 'UNSUPPORTED_CLASSFILE'; LanguageVersion = 'UNSUPPORTED'; JvmTarget = 'UNSUPPORTED'; MinApis = @(24, 36); Modes = @('DEBUG'); ExpectedOutcome = 'COMPILE_FAILURE' },
        @{ Id = 'duplicate-definition'; FixtureKind = 'DUPLICATE_DEFINITION'; LanguageVersion = '17'; JvmTarget = '17'; MinApis = @(24, 36); Modes = @('DEBUG'); ExpectedOutcome = 'COMPILE_FAILURE' }
    )
    if ($Matrix.cases.Count -ne $expectedCases.Count) {
        throw "Matrix must contain exactly $($expectedCases.Count) canonical cases; found $($Matrix.cases.Count)."
    }
    for ($caseIndex = 0; $caseIndex -lt $expectedCases.Count; $caseIndex++) {
        $actualCase = $Matrix.cases[$caseIndex]
        $expectedCase = $expectedCases[$caseIndex]
        foreach ($field in @('Id', 'FixtureKind', 'LanguageVersion', 'JvmTarget', 'ExpectedOutcome')) {
            $actualFieldName = $field.Substring(0, 1).ToLowerInvariant() + $field.Substring(1)
            if ([string] $actualCase.$actualFieldName -cne [string] $expectedCase[$field]) {
                throw "Canonical case index $caseIndex field '$actualFieldName' must be '$($expectedCase[$field])'; found '$($actualCase.$actualFieldName)'."
            }
        }
        Assert-R4ExactSequence -Actual @($actualCase.minApis) -Expected @($expectedCase.MinApis) -Label "case '$($expectedCase.Id)' minApis"
        Assert-R4ExactSequence -Actual @($actualCase.modes) -Expected @($expectedCase.Modes) -Label "case '$($expectedCase.Id)' modes"
    }
}

function Read-R4D8UpgradeMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MatrixPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    $matrix = Read-R4JsonWithSchema -Path $MatrixPath -SchemaPath $SchemaPath -Label 'R4 D8 upgrade matrix'
    Assert-R4MatrixCoverage -Matrix $matrix

    $cells = [System.Collections.Generic.List[object]]::new()
    $cellIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($case in $matrix.cases) {
        foreach ($minApiValue in $case.minApis) {
            foreach ($modeValue in $case.modes) {
                $cellId = Get-R4CellId -CaseId ([string] $case.id) -MinApi ([int] $minApiValue) -Mode ([string] $modeValue)
                if (-not $cellIds.Add($cellId)) {
                    throw "Expanded matrix contains duplicate cell id '$cellId'."
                }
                $cells.Add([pscustomobject][ordered]@{
                    cellId = $cellId
                    caseId = [string] $case.id
                    fixtureKind = [string] $case.fixtureKind
                    languageVersion = [string] $case.languageVersion
                    jvmTarget = [string] $case.jvmTarget
                    minApi = [int] $minApiValue
                    mode = [string] $modeValue
                    expectedOutcome = [string] $case.expectedOutcome
                })
            }
        }
    }

    return [pscustomobject][ordered]@{
        Manifest = $matrix
        Cells = @($cells)
    }
}

function Read-R4D8UpgradeReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ReportPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    return Read-R4JsonWithSchema -Path $ReportPath -SchemaPath $SchemaPath -Label 'R4 D8 upgrade report'
}

function Test-R4D8UpgradeGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MatrixPath,

        [Parameter(Mandatory)]
        [string] $MatrixSchemaPath,

        [Parameter(Mandatory)]
        [string] $ReportSchemaPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ReportPath,

        [string] $ExpectedCompilerVersion,

        [string] $ExpectedProducerInvocationId,

        [switch] $CandidateEvaluation,

        [switch] $RollbackEvaluation
    )

    $matrixRead = Read-R4D8UpgradeMatrix -MatrixPath $MatrixPath -SchemaPath $MatrixSchemaPath
    $matrix = $matrixRead.Manifest
    $cells = @($matrixRead.Cells)
    if ([string]::IsNullOrWhiteSpace($ExpectedCompilerVersion)) {
        $ExpectedCompilerVersion = [string] $matrix.compiler.pinnedVersion
    }
    if ($ExpectedCompilerVersion -cnotmatch '^[0-9][0-9A-Za-z.+_-]{0,63}$') {
        throw "ExpectedCompilerVersion '$ExpectedCompilerVersion' is invalid."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProducerInvocationId) -and
        $ExpectedProducerInvocationId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
        throw "ExpectedProducerInvocationId '$ExpectedProducerInvocationId' is invalid."
    }
    if ($CandidateEvaluation -and $RollbackEvaluation) {
        throw 'CandidateEvaluation and RollbackEvaluation are mutually exclusive.'
    }
    $evaluationKind = if ($CandidateEvaluation) {
        'CANDIDATE_OVERRIDE'
    } elseif ($RollbackEvaluation) {
        'OLD_PIN_ROLLBACK'
    } else {
        'PINNED_DEFAULT'
    }
    if ($CandidateEvaluation) {
        if ($ExpectedCompilerVersion -ceq $matrix.compiler.pinnedVersion) {
            throw "Candidate evaluation compiler version must differ from pinned '$($matrix.compiler.pinnedVersion)'."
        }
    } elseif ($RollbackEvaluation) {
        if ($ExpectedCompilerVersion -cne $matrix.compiler.rollbackVersion) {
            throw "Rollback evaluation requires compiler version '$($matrix.compiler.rollbackVersion)'."
        }
    } elseif ($ExpectedCompilerVersion -cne $matrix.compiler.pinnedVersion) {
        throw "Pinned default evaluation requires compiler version '$($matrix.compiler.pinnedVersion)'."
    }

    $cellById = @{}
    foreach ($cell in $cells) {
        $cellById[[string] $cell.cellId] = $cell
    }

    $reports = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $ReportPath.Count; $index++) {
        $path = $ReportPath[$index]
        $report = Read-R4D8UpgradeReport -ReportPath $path -SchemaPath $ReportSchemaPath
        $reports.Add([pscustomobject][ordered]@{
            SourceIndex = $index
            SourcePath = $path
            Value = $report
        })
    }

    $reportSetRecords = @($reports | ForEach-Object {
        [pscustomobject]@{
            CellId = [string] $_.Value.cellId
            FileName = [IO.Path]::GetFileName([string] $_.SourcePath)
            Sha256 = Get-R4Sha256File -Path ([string] $_.SourcePath)
        }
    } | Sort-Object `
        @{ Expression = 'CellId'; Ascending = $true },
        @{ Expression = 'FileName'; Ascending = $true },
        @{ Expression = 'Sha256'; Ascending = $true })
    $reportSetCanonicalText = ($reportSetRecords | ForEach-Object {
        "{0}`0{1}`0{2}`n" -f $_.CellId, $_.FileName, $_.Sha256
    }) -join ''
    $matrixSha256 = Get-R4Sha256File -Path $MatrixPath
    $reportSchemaSha256 = Get-R4Sha256File -Path $ReportSchemaPath
    $reportSetSha256 = Get-R4Sha256Text -Text $reportSetCanonicalText

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($reports.Count -eq 0) {
        $reasons.Add('No matrix reports were supplied.')
    }

    $reportIds = @($reports | ForEach-Object { [string] $_.Value.reportId })
    foreach ($group in @($reportIds | Group-Object -CaseSensitive | Where-Object Count -gt 1)) {
        $reasons.Add("Duplicate reportId '$($group.Name)' occurs $($group.Count) times.")
    }

    $producerInvocationIds = @(
        $reports |
            ForEach-Object { [string] $_.Value.producerInvocationId } |
            Sort-Object -Unique -CaseSensitive
    )
    $producerInvocationId = if ($producerInvocationIds.Count -eq 1) {
        [string] $producerInvocationIds[0]
    } else {
        $null
    }
    if ($producerInvocationIds.Count -ne 1) {
        $reasons.Add("Producer invocation drift exists within the report set: $($producerInvocationIds -join ', ').")
    } elseif (-not [string]::IsNullOrWhiteSpace($ExpectedProducerInvocationId) -and
        $producerInvocationId -cne $ExpectedProducerInvocationId) {
        $reasons.Add("Report producer invocation '$producerInvocationId' does not match expected '$ExpectedProducerInvocationId'.")
    }

    $compilerVersions = @($reports | ForEach-Object { [string] $_.Value.compiler.version } | Sort-Object -Unique -CaseSensitive)
    if ($compilerVersions.Count -gt 1) {
        $reasons.Add("Compiler version drift exists within the report set: $($compilerVersions -join ', ').")
    }

    foreach ($entry in $reports) {
        $report = $entry.Value
        # Persist only a stable report label; absolute input paths are private machine state.
        $source = [IO.Path]::GetFileName([string] $entry.SourcePath)
        if ($report.compiler.version -cne $ExpectedCompilerVersion) {
            $reasons.Add("Report '$source' compiler version '$($report.compiler.version)' drifts from expected '$ExpectedCompilerVersion'.")
        }
        if ($report.compiler.coordinate -cne $matrix.compiler.coordinate -or
            $report.compiler.candidateVersionProperty -cne $matrix.compiler.candidateVersionProperty) {
            $reasons.Add("Report '$source' compiler identity does not match the matrix contract.")
        }
        if ($report.evidenceBoundary -cne $matrix.evidenceBoundary) {
            $reasons.Add("Report '$source' evidenceBoundary does not match the matrix contract.")
        }

        $cellId = [string] $report.cellId
        if (-not $cellById.ContainsKey($cellId)) {
            $reasons.Add("Report '$source' has unexpected cellId '$cellId'.")
            continue
        }
        $cell = $cellById[$cellId]
        if ($report.caseId -cne $cell.caseId -or
            [int] $report.minApi -ne [int] $cell.minApi -or
            $report.mode -cne $cell.mode) {
            $reasons.Add("Report '$source' cell coordinates do not match cellId '$cellId'.")
        }

        $expectedAcceptanceKey = Get-R4AcceptanceKey `
            -CaseId $cell.caseId `
            -MinApi $cell.minApi `
            -Mode $cell.mode `
            -CompilerVersion $ExpectedCompilerVersion
        if ($report.acceptanceKey -cne $expectedAcceptanceKey) {
            $reasons.Add("Report '$source' acceptanceKey does not match '$expectedAcceptanceKey'.")
        }
        if ($report.observedCompilerOutcome -cne $cell.expectedOutcome) {
            $reasons.Add("Report '$source' observed '$($report.observedCompilerOutcome)' for '$cellId'; expected '$($cell.expectedOutcome)'.")
        }
        if ($report.outcome -cne 'PASS') {
            $reasons.Add("Report '$source' preserves outcome '$($report.outcome)' for '$cellId'; FAIL evidence cannot satisfy the gate.")
        }
        if ($report.outcome -ceq 'PASS' -and $report.behaviorDelta.classification -ceq 'UNEXPECTED') {
            $reasons.Add("Report '$source' claims PASS with an UNEXPECTED behavior delta.")
        }
        if ($report.determinismClaim -cne 'NOT_CLAIMED') {
            $reasons.Add("Report '$source' makes a prohibited determinism claim.")
        }
        if ($report.observedCompilerOutcome -ceq 'COMPILE_SUCCESS') {
            if (-not [bool] $report.repeatObservation.attempted -or
                [int] $report.repeatObservation.runCount -ne 2 -or
                $report.repeatObservation.identicalOutputDigest -isnot [bool]) {
                $reasons.Add("Report '$source' must record exactly two repeat observations with a boolean identicalOutputDigest for COMPILE_SUCCESS.")
            }
        } else {
            if ([bool] $report.repeatObservation.attempted -or
                [int] $report.repeatObservation.runCount -ne 1 -or
                $null -ne $report.repeatObservation.identicalOutputDigest) {
                $reasons.Add("Report '$source' must record attempted=false, runCount=1, and no digest comparison for COMPILE_FAILURE.")
            }
        }

        foreach ($summaryEntry in @(
            @{ Label = 'summary'; Value = $report.summary },
            @{ Label = 'input.summary'; Value = $report.input.summary },
            @{ Label = 'runtimeFingerprint.summary'; Value = $report.runtimeFingerprint.summary },
            @{ Label = 'output.summary'; Value = $report.output.summary },
            @{ Label = 'behaviorDelta.summary'; Value = $report.behaviorDelta.summary },
            @{ Label = 'repeatObservation.summary'; Value = $report.repeatObservation.summary }
        )) {
            if ([string]::IsNullOrWhiteSpace([string] $summaryEntry.Value)) {
                $reasons.Add("Report '$source' is missing non-blank $($summaryEntry.Label).")
            }
        }

        $dexEntryNames = @($report.output.dexManifest | ForEach-Object { [string] $_.entryName })
        foreach ($group in @($dexEntryNames | Group-Object -CaseSensitive | Where-Object Count -gt 1)) {
            $reasons.Add("Report '$source' repeats DEX manifest entryName '$($group.Name)'.")
        }
        if ($report.output.status -ceq 'PRODUCED') {
            for ($dexIndex = 0; $dexIndex -lt $dexEntryNames.Count; $dexIndex++) {
                $expectedDexEntryName = if ($dexIndex -eq 0) {
                    'classes.dex'
                } else {
                    'classes{0}.dex' -f ($dexIndex + 1)
                }
                if ($dexEntryNames[$dexIndex] -cne $expectedDexEntryName) {
                    $reasons.Add("Report '$source' DEX manifest must be strictly ordered and contiguous; index $dexIndex is '$($dexEntryNames[$dexIndex])', expected '$expectedDexEntryName'.")
                    break
                }
            }
        }
        if ($cell.fixtureKind -ceq 'GENERATED_MULTIDEX' -and $report.observedCompilerOutcome -ceq 'COMPILE_SUCCESS') {
            if ('classes.dex' -cnotin $dexEntryNames -or 'classes2.dex' -cnotin $dexEntryNames) {
                $reasons.Add("Report '$source' does not prove generated multidex output with both classes.dex and classes2.dex.")
            }
        }
    }

    foreach ($group in @($reports | Group-Object { [string] $_.Value.cellId })) {
        if ($group.Count -gt 1) {
            $reasons.Add("Duplicate cellId '$($group.Name)' occurs $($group.Count) times.")
        }
    }
    foreach ($group in @($reports | Group-Object { [string] $_.Value.acceptanceKey })) {
        if ($group.Count -gt 1) {
            $reasons.Add("Duplicate acceptanceKey '$($group.Name)' occurs $($group.Count) times.")
        }

        $orderedHistory = @($group.Group | Sort-Object `
            @{ Expression = { [long] $_.Value.observationSequence }; Ascending = $true },
            @{ Expression = { [int] $_.SourceIndex }; Ascending = $true })
        foreach ($sequenceGroup in @($orderedHistory | Group-Object { [long] $_.Value.observationSequence })) {
            if ($sequenceGroup.Count -gt 1) {
                $reasons.Add("AcceptanceKey '$($group.Name)' has ambiguous observationSequence '$($sequenceGroup.Name)'.")
            }
        }

        $failSeen = $false
        foreach ($historyEntry in $orderedHistory) {
            if ($historyEntry.Value.outcome -ceq 'FAIL') {
                $failSeen = $true
            } elseif ($failSeen -and $historyEntry.Value.outcome -ceq 'PASS') {
                $reasons.Add("AcceptanceKey '$($group.Name)' has a PASS after an earlier FAIL; FAIL evidence may not be overwritten or superseded.")
            }
        }
    }

    $observedCellIds = @($reports | ForEach-Object { [string] $_.Value.cellId } | Sort-Object -Unique -CaseSensitive)
    $missingCellIds = @($cells | ForEach-Object { [string] $_.cellId } | Where-Object { $_ -cnotin $observedCellIds })
    if ($missingCellIds.Count -gt 0) {
        $reasons.Add("Missing required matrix cellId values: $($missingCellIds -join ', ').")
    }

    $uniqueReasons = @($reasons | Sort-Object -Unique -CaseSensitive)
    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        matrixId = [string] $matrix.matrixId
        evidenceBoundary = $script:EvidenceBoundary
        evaluationKind = $evaluationKind
        matrixSha256 = $matrixSha256
        reportSchemaSha256 = $reportSchemaSha256
        reportSetSha256 = $reportSetSha256
        producerInvocationId = $producerInvocationId
        compiler = [pscustomobject][ordered]@{
            coordinate = $script:CompilerCoordinate
            pinnedVersion = $script:PinnedCompilerVersion
            rollbackVersion = $script:RollbackCompilerVersion
            evaluatedVersion = $ExpectedCompilerVersion
            candidateVersionProperty = $script:CandidateVersionProperty
            rollbackEvaluationProperty = $script:RollbackEvaluationProperty
        }
        passed = $uniqueReasons.Count -eq 0
        expectedCellCount = $cells.Count
        reportCount = $reports.Count
        observedUniqueCellCount = $observedCellIds.Count
        determinismClaim = 'NOT_CLAIMED'
        reasons = $uniqueReasons
    }
}

Export-ModuleMember -Function @(
    'Get-R4AcceptanceKey',
    'Get-R4CellId',
    'Read-R4D8UpgradeMatrix',
    'Read-R4D8UpgradeReport',
    'Resolve-R4SafeOutputPath',
    'Test-R4D8UpgradeGate',
    'Write-R4AtomicJsonFile'
)
