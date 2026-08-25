[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'R4D8UpgradeGate.psm1'
$matrixPath = Join-Path $PSScriptRoot 'r4-d8-upgrade-matrix.json'
$matrixSchemaPath = Join-Path $PSScriptRoot 'r4-d8-upgrade-matrix.schema.json'
$reportSchemaPath = Join-Path $PSScriptRoot 'r4-d8-upgrade-report.schema.json'
$consumerPath = Join-Path $PSScriptRoot 'verify-r4-d8-upgrade.ps1'
$comparisonPath = Join-Path $PSScriptRoot 'compare-r4-d8-upgrade.ps1'

Import-Module $modulePath -Force

$script:PassedCount = 0
$script:FailedCount = 0
$script:ExpectedTestCount = 31
$script:ProducerInvocationId = '11111111-1111-4111-8111-111111111111'

function Invoke-TestCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Body
    )

    try {
        & $Body
        $script:PassedCount++
        Write-Host "PASS $Name"
    } catch {
        $script:FailedCount++
        Write-Host "FAIL $Name -- $($_.Exception.Message)"
    }
}

function Assert-True {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ReasonMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Gate,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    $matches = @($Gate.reasons | Where-Object { $_ -match $Pattern })
    if ($matches.Count -eq 0) {
        throw "Expected a gate reason matching '$Pattern'; actual: $($Gate.reasons -join ' | ')"
    }
}

function Assert-ThrowsLike {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Body,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    try {
        & $Body
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected exception matching '$Pattern'; actual: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected exception matching '$Pattern', but no exception was thrown."
}

function Copy-JsonObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Value
    )

    return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30 -NoEnumerate
}

function New-R4TestReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Cell,

        [Parameter(Mandatory)]
        [int] $Sequence,

        [string] $CompilerVersion = '8.13.22',

        [string] $ProducerInvocationId = $script:ProducerInvocationId,

        [ValidateSet('PASS', 'FAIL')]
        [string] $Outcome = 'PASS'
    )

    $acceptanceKey = Get-R4AcceptanceKey `
        -CaseId $Cell.caseId `
        -MinApi $Cell.minApi `
        -Mode $Cell.mode `
        -CompilerVersion $CompilerVersion
    $successfulCompilation = $Cell.expectedOutcome -ceq 'COMPILE_SUCCESS'
    $dexManifest = if ($successfulCompilation) {
        $entries = @(
            [pscustomobject][ordered]@{
                entryName = 'classes.dex'
                sha256 = 'd' * 64
                byteLength = 128
            }
        )
        if ($Cell.fixtureKind -ceq 'GENERATED_MULTIDEX') {
            $entries += [pscustomobject][ordered]@{
                entryName = 'classes2.dex'
                sha256 = 'e' * 64
                byteLength = 64
            }
        }
        @($entries)
    } else {
        @()
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-upgrade-report/v2'
        matrixId = 'r4.1-g1-d8-upgrade'
        reportId = ([guid]::NewGuid().ToString())
        producerInvocationId = $ProducerInvocationId
        observationSequence = $Sequence
        recordedAtUtc = '2026-08-13T00:00:00Z'
        cellId = [string] $Cell.cellId
        acceptanceKey = $acceptanceKey
        caseId = [string] $Cell.caseId
        minApi = [int] $Cell.minApi
        mode = [string] $Cell.mode
        evidenceBoundary = 'JVM_COMPILER_ONLY'
        compiler = [pscustomobject][ordered]@{
            coordinate = 'com.android.tools:r8'
            version = $CompilerVersion
            candidateVersionProperty = 'd8CandidateVersion'
        }
        input = [pscustomobject][ordered]@{
            sha256 = 'a' * 64
            summary = 'Canonical fixture input digest.'
        }
        runtimeFingerprint = [pscustomobject][ordered]@{
            sha256 = 'b' * 64
            summary = 'JDK, Gradle, Kotlin, OS, architecture, and D8 runtime identity.'
        }
        observedCompilerOutcome = [string] $Cell.expectedOutcome
        output = [pscustomobject][ordered]@{
            status = if ($successfulCompilation) { 'PRODUCED' } else { 'NOT_PRODUCED' }
            sha256 = if ($successfulCompilation) { 'c' * 64 } else { $null }
            dexManifest = @($dexManifest)
            summary = if ($successfulCompilation) { 'DEX ZIP and entry digests captured.' } else { 'Expected compiler rejection produced no output.' }
        }
        outcome = $Outcome
        behaviorDelta = [pscustomobject][ordered]@{
            classification = 'NONE'
            summary = 'No behavior delta from the pinned baseline.'
        }
        repeatObservation = [pscustomobject][ordered]@{
            attempted = $successfulCompilation
            runCount = if ($successfulCompilation) { 2 } else { 1 }
            identicalOutputDigest = if ($successfulCompilation) { $true } else { $null }
            summary = if ($successfulCompilation) {
                'Two output observations recorded; determinism is not claimed.'
            } else {
                'One failure observation recorded; no output digest comparison applies.'
            }
        }
        determinismClaim = 'NOT_CLAIMED'
        summary = 'R4.1-G1 JVM compiler-only matrix observation.'
    }
}

function Write-R4TestReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Report,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $Report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline
    return $Path
}

function Invoke-R4ChildPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Arguments
    )

    $outputLines = @(
        & pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments 2>&1 |
            ForEach-Object { $_.ToString() }
    )
    return [pscustomobject][ordered]@{
        ExitCode = $LASTEXITCODE
        Output = $outputLines -join [Environment]::NewLine
    }
}

function Assert-R4BootstrapFailureReplacedStalePass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Invocation,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $ExpectedSchemaVersion
    )

    Assert-True -Condition ($Invocation.ExitCode -ne 0) -Message 'Broken bootstrap input returned a zero exit code.'
    Assert-True -Condition (Test-Path -LiteralPath $OutputPath -PathType Leaf) -Message 'Bootstrap failure did not persist output.'
    $persisted = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 30 -NoEnumerate
    Assert-True -Condition (-not [bool] $persisted.passed) -Message 'Bootstrap failure retained stale passed=true output.'
    Assert-True -Condition (@($persisted.PSObject.Properties.Name) -notcontains 'stale') -Message 'Bootstrap failure did not replace stale output.'
    Assert-True -Condition ($persisted.schemaVersion -ceq $ExpectedSchemaVersion) -Message 'Bootstrap failure schema identity changed.'
    Assert-True -Condition ($persisted.determinismClaim -ceq 'NOT_CLAIMED') -Message 'Bootstrap failure made a determinism claim.'
    $persistedJson = $persisted | ConvertTo-Json -Depth 30 -Compress
    Assert-True `
        -Condition ($persistedJson.IndexOf($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
        -Message 'Persisted bootstrap failure leaked the self-test temporary path.'
    Assert-True `
        -Condition ($Invocation.Output.IndexOf($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
        -Message 'Bootstrap failure output leaked the self-test temporary path.'
    $temporaryOutputs = @(Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File -Filter '*.tmp')
    Assert-True -Condition ($temporaryOutputs.Count -eq 0) -Message 'Bootstrap failure left an atomic-write temporary file.'
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("autojs6-r4-d8-upgrade-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    $matrixRead = Read-R4D8UpgradeMatrix -MatrixPath $matrixPath -SchemaPath $matrixSchemaPath
    $cells = @($matrixRead.Cells)
    $positiveDirectory = Join-Path $temporaryRoot 'positive'
    New-Item -ItemType Directory -Path $positiveDirectory | Out-Null
    $positivePaths = [System.Collections.Generic.List[string]]::new()
    $positiveReports = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $cells.Count; $index++) {
        $report = New-R4TestReport -Cell $cells[$index] -Sequence ($index + 1)
        $path = Join-Path $positiveDirectory ("{0:D3}-{1}.json" -f ($index + 1), $cells[$index].cellId)
        $positivePaths.Add((Write-R4TestReport -Report $report -Path $path))
        $positiveReports.Add($report)
    }

    Invoke-TestCase -Name 'manifest schema and semantic coverage are accepted' -Body {
        Assert-True -Condition ($matrixRead.Manifest.compiler.pinnedVersion -ceq '8.13.22') -Message 'Pinned compiler version changed.'
        Assert-True -Condition ($matrixRead.Manifest.compiler.rollbackVersion -ceq '8.13.17') -Message 'Rollback compiler version changed.'
        Assert-True -Condition ($matrixRead.Manifest.compiler.candidateVersionProperty -ceq 'd8CandidateVersion') -Message 'Candidate property changed.'
        Assert-True -Condition ($matrixRead.Manifest.compiler.rollbackEvaluationProperty -ceq 'd8RollbackEvaluation') -Message 'Rollback property changed.'
        Assert-True -Condition ($matrixRead.Manifest.evidenceBoundary -ceq 'JVM_COMPILER_ONLY') -Message 'Evidence boundary changed.'
        Assert-True -Condition ($cells.Count -eq 60) -Message "Expected 60 expanded cells; found $($cells.Count)."
    }

    Invoke-TestCase -Name 'contracted canonical matrix is rejected' -Body {
        $contractedMatrix = Copy-JsonObject -Value $matrixRead.Manifest
        $contractedMatrix.cases[1].minApis = @(24)
        $contractedMatrixPath = Join-Path $temporaryRoot 'contracted-matrix.json'
        $contractedMatrix | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $contractedMatrixPath -Encoding UTF8 -NoNewline
        Assert-ThrowsLike -Pattern "case 'java11' minApis" -Body {
            Read-R4D8UpgradeMatrix -MatrixPath $contractedMatrixPath -SchemaPath $matrixSchemaPath | Out-Null
        }
    }

    Invoke-TestCase -Name 'complete pinned report set passes' -Body {
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath @($positivePaths) `
            -ExpectedCompilerVersion '8.13.22'
        Assert-True -Condition $gate.passed -Message "Positive gate failed: $($gate.reasons -join ' | ')"
        Assert-True -Condition ($gate.expectedCellCount -eq 60) -Message 'Positive gate cell count changed.'
        Assert-True -Condition ($gate.determinismClaim -ceq 'NOT_CLAIMED') -Message 'Gate made a determinism claim.'
        Assert-True -Condition ($gate.evaluationKind -ceq 'PINNED_DEFAULT') -Message 'Pinned gate evaluationKind changed.'
        Assert-True -Condition ($gate.producerInvocationId -ceq $script:ProducerInvocationId) -Message 'Gate producerInvocationId changed.'
        foreach ($digestField in @('matrixSha256', 'reportSchemaSha256', 'reportSetSha256')) {
            Assert-True -Condition ([string] $gate.$digestField -cmatch '^[0-9a-f]{64}$') -Message "Gate field '$digestField' is not a SHA-256 digest."
        }
        $copiedReportDirectory = Join-Path $temporaryRoot 'path-independent-report-copy'
        New-Item -ItemType Directory -Path $copiedReportDirectory | Out-Null
        $copiedPaths = @($positivePaths | ForEach-Object {
            $destination = Join-Path $copiedReportDirectory ([IO.Path]::GetFileName($_))
            Copy-Item -LiteralPath $_ -Destination $destination
            $destination
        })
        $copiedGate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $copiedPaths `
            -ExpectedCompilerVersion '8.13.22'
        Assert-True -Condition ($copiedGate.reportSetSha256 -ceq $gate.reportSetSha256) -Message 'Report-set digest changed after a directory-only copy.'
    }

    Invoke-TestCase -Name 'mixed producer invocation reports fail closed' -Body {
        $mixedDirectory = Join-Path $temporaryRoot 'mixed-producer-invocation'
        New-Item -ItemType Directory -Path $mixedDirectory | Out-Null
        $mixedPaths = @($positivePaths | ForEach-Object {
            $destination = Join-Path $mixedDirectory ([IO.Path]::GetFileName($_))
            Copy-Item -LiteralPath $_ -Destination $destination
            $destination
        })
        $mutated = Copy-JsonObject -Value $positiveReports[0]
        $mutated.producerInvocationId = '22222222-2222-4222-8222-222222222222'
        Write-R4TestReport -Report $mutated -Path $mixedPaths[0] | Out-Null
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $mixedPaths `
            -ExpectedCompilerVersion '8.13.22' `
            -ExpectedProducerInvocationId $script:ProducerInvocationId
        Assert-True -Condition (-not $gate.passed) -Message 'Mixed producer invocation reports unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'Producer invocation drift'
    }

    Invoke-TestCase -Name 'consumer emits a passing machine-readable gate summary' -Body {
        $consumerJson = & $consumerPath `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath @($positivePaths) `
            -ExpectedCompilerVersion '8.13.22' `
            -ExpectedProducerInvocationId $script:ProducerInvocationId | Out-String
        $consumerResult = $consumerJson | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition ([bool] $consumerResult.passed) -Message 'Consumer did not emit passed=true.'
        Assert-True -Condition ([int] $consumerResult.reportCount -eq 60) -Message 'Consumer reportCount changed.'
        Assert-True -Condition ($consumerResult.determinismClaim -ceq 'NOT_CLAIMED') -Message 'Consumer made a determinism claim.'
    }

    Invoke-TestCase -Name 'old pin rollback requires an explicit switch and passes only in rollback mode' -Body {
        $rollbackDirectory = Join-Path $temporaryRoot 'old-pin-rollback'
        New-Item -ItemType Directory -Path $rollbackDirectory | Out-Null
        for ($index = 0; $index -lt $positiveReports.Count; $index++) {
            $rollback = Copy-JsonObject -Value $positiveReports[$index]
            $rollback.compiler.version = '8.13.17'
            $rollback.acceptanceKey = Get-R4AcceptanceKey `
                -CaseId $cells[$index].caseId `
                -MinApi $cells[$index].minApi `
                -Mode $cells[$index].mode `
                -CompilerVersion '8.13.17'
            Write-R4TestReport `
                -Report $rollback `
                -Path (Join-Path $rollbackDirectory ("{0:D3}-{1}.json" -f ($index + 1), $cells[$index].cellId)) | Out-Null
        }
        $implicitRollback = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $rollbackDirectory,
            '-ExpectedCompilerVersion', '8.13.17',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId
        )
        Assert-True -Condition ($implicitRollback.ExitCode -ne 0) -Message 'Old pin passed without RollbackEvaluation.'
        Assert-True -Condition ($implicitRollback.Output -match 'Pinned default evaluation requires') -Message 'Implicit rollback rejection was not explicit.'

        $explicitRollback = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $rollbackDirectory,
            '-ExpectedCompilerVersion', '8.13.17',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-RollbackEvaluation'
        )
        Assert-True -Condition ($explicitRollback.ExitCode -eq 0) -Message "Explicit rollback failed: $($explicitRollback.Output)"
        $rollbackGate = $explicitRollback.Output | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition ([bool] $rollbackGate.passed) -Message 'Explicit rollback did not pass.'
        Assert-True -Condition ($rollbackGate.evaluationKind -ceq 'OLD_PIN_ROLLBACK') -Message 'Rollback gate evaluationKind changed.'
        Assert-True -Condition ($rollbackGate.compiler.pinnedVersion -ceq '8.13.22') -Message 'Rollback gate lost the promoted default.'
        Assert-True -Condition ($rollbackGate.compiler.rollbackVersion -ceq '8.13.17') -Message 'Rollback gate lost the old pin.'
        Assert-True -Condition ($rollbackGate.compiler.evaluatedVersion -ceq '8.13.17') -Message 'Rollback gate evaluated the wrong compiler.'
    }

    Invoke-TestCase -Name 'candidate and rollback modes are mutually exclusive' -Body {
        Assert-ThrowsLike -Pattern 'mutually exclusive' -Body {
            Test-R4D8UpgradeGate `
                -MatrixPath $matrixPath `
                -MatrixSchemaPath $matrixSchemaPath `
                -ReportSchemaPath $reportSchemaPath `
                -ReportPath @($positivePaths) `
                -ExpectedCompilerVersion '8.13.17' `
                -CandidateEvaluation `
                -RollbackEvaluation | Out-Null
        }
    }

    Invoke-TestCase -Name 'candidate evaluation requires an explicit switch' -Body {
        $candidateModeDirectory = Join-Path $temporaryRoot 'candidate-mode'
        New-Item -ItemType Directory -Path $candidateModeDirectory | Out-Null
        for ($index = 0; $index -lt $positiveReports.Count; $index++) {
            $candidate = Copy-JsonObject -Value $positiveReports[$index]
            $candidate.compiler.version = '8.13.23'
            $candidate.acceptanceKey = Get-R4AcceptanceKey `
                -CaseId $cells[$index].caseId `
                -MinApi $cells[$index].minApi `
                -Mode $cells[$index].mode `
                -CompilerVersion '8.13.23'
            Write-R4TestReport -Report $candidate -Path (Join-Path $candidateModeDirectory ("{0:D3}-{1}.json" -f ($index + 1), $cells[$index].cellId)) | Out-Null
        }
        $implicitCandidate = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $candidateModeDirectory,
            '-ExpectedCompilerVersion', '8.13.23',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId
        )
        Assert-True -Condition ($implicitCandidate.ExitCode -ne 0) -Message 'Non-pinned version passed without CandidateEvaluation.'
        Assert-True -Condition ($implicitCandidate.Output -match 'Pinned default evaluation requires') -Message 'Implicit candidate rejection was not explicit.'

        $explicitCandidate = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $candidateModeDirectory,
            '-ExpectedCompilerVersion', '8.13.23',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-CandidateEvaluation'
        )
        Assert-True -Condition ($explicitCandidate.ExitCode -eq 0) -Message "Explicit candidate failed: $($explicitCandidate.Output)"
        $candidateGate = $explicitCandidate.Output | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition ([bool] $candidateGate.passed) -Message 'Explicit candidate did not pass.'
        Assert-True -Condition ($candidateGate.evaluationKind -ceq 'CANDIDATE_OVERRIDE') -Message 'Candidate gate evaluationKind changed.'
    }

    Invoke-TestCase -Name 'comparison records candidate byte changes without a determinism claim' -Body {
        $candidateDirectory = Join-Path $temporaryRoot 'candidate'
        New-Item -ItemType Directory -Path $candidateDirectory | Out-Null
        for ($index = 0; $index -lt $positiveReports.Count; $index++) {
            $candidate = Copy-JsonObject -Value $positiveReports[$index]
            $candidate.compiler.version = '8.13.23'
            $candidate.acceptanceKey = Get-R4AcceptanceKey `
                -CaseId $cells[$index].caseId `
                -MinApi $cells[$index].minApi `
                -Mode $cells[$index].mode `
                -CompilerVersion '8.13.23'
            if ($candidate.output.status -ceq 'PRODUCED') {
                $candidate.output.sha256 = '9' * 64
            }
            Write-R4TestReport `
                -Report $candidate `
                -Path (Join-Path $candidateDirectory ("{0:D3}-{1}.json" -f ($index + 1), $cells[$index].cellId)) | Out-Null
        }
        $comparisonJson = & $comparisonPath `
            -BaselineReportDirectory $positiveDirectory `
            -CandidateReportDirectory $candidateDirectory `
            -BaselineVersion '8.13.22' `
            -CandidateVersion '8.13.23' | Out-String
        $comparison = $comparisonJson | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition ([bool] $comparison.passed) -Message 'Synthetic candidate comparison did not pass.'
        Assert-True -Condition ([int] $comparison.compilerOutcomeDifferenceCount -eq 0) -Message 'Synthetic candidate changed compiler outcomes.'
        Assert-True -Condition ([int] $comparison.outputDigestDifferenceCount -gt 0) -Message 'Synthetic candidate did not record byte-output changes.'
        Assert-True -Condition ($comparison.determinismClaim -ceq 'NOT_CLAIMED') -Message 'Comparison made a determinism claim.'
        Assert-True -Condition ($comparison.baselineReportSetSha256 -cmatch '^[0-9a-f]{64}$') -Message 'Comparison omitted baseline report-set binding.'
        Assert-True -Condition ($comparison.candidateReportSetSha256 -cmatch '^[0-9a-f]{64}$') -Message 'Comparison omitted candidate report-set binding.'
    }

    Invoke-TestCase -Name 'candidate DEX topology change fails comparison' -Body {
        $topologyDirectory = Join-Path $temporaryRoot 'candidate-topology-change'
        New-Item -ItemType Directory -Path $topologyDirectory | Out-Null
        for ($index = 0; $index -lt $positiveReports.Count; $index++) {
            $candidate = Copy-JsonObject -Value $positiveReports[$index]
            $candidate.compiler.version = '8.13.23'
            $candidate.acceptanceKey = Get-R4AcceptanceKey `
                -CaseId $cells[$index].caseId `
                -MinApi $cells[$index].minApi `
                -Mode $cells[$index].mode `
                -CompilerVersion '8.13.23'
            if ($index -eq 0) {
                $candidate.output.dexManifest = @($candidate.output.dexManifest) + [pscustomobject][ordered]@{
                    entryName = 'classes2.dex'
                    sha256 = 'e' * 64
                    byteLength = 64
                }
                $candidate.output.sha256 = '9' * 64
            }
            Write-R4TestReport -Report $candidate -Path (Join-Path $topologyDirectory ("{0:D3}-{1}.json" -f ($index + 1), $cells[$index].cellId)) | Out-Null
        }
        $comparisonInvocation = Invoke-R4ChildPowerShell -ScriptPath $comparisonPath -Arguments @(
            '-BaselineReportDirectory', $positiveDirectory,
            '-CandidateReportDirectory', $topologyDirectory,
            '-BaselineVersion', '8.13.22',
            '-CandidateVersion', '8.13.23',
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath
        )
        Assert-True -Condition ($comparisonInvocation.ExitCode -ne 0) -Message 'Candidate topology change unexpectedly passed comparison.'
        $comparison = $comparisonInvocation.Output | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition (-not [bool] $comparison.passed) -Message 'Topology comparison emitted passed=true.'
        Assert-True -Condition ([int] $comparison.dexEntryNamesDifferenceCount -eq 1) -Message 'Topology comparison did not record exactly one changed cell.'
    }

    Invoke-TestCase -Name 'report schema accepts classes10.dex' -Body {
        $classes10 = Copy-JsonObject -Value $positiveReports[0]
        $expandedDexManifest = [System.Collections.Generic.List[object]]::new()
        $expandedDexManifest.Add($classes10.output.dexManifest[0])
        for ($dexNumber = 2; $dexNumber -le 10; $dexNumber++) {
            $expandedDexManifest.Add([pscustomobject][ordered]@{
                entryName = "classes$dexNumber.dex"
                sha256 = 'f' * 64
                byteLength = 32
            })
        }
        $classes10.output.dexManifest = @($expandedDexManifest)
        $classes10Path = Write-R4TestReport -Report $classes10 -Path (Join-Path $temporaryRoot 'classes10.json')
        $validated = Read-R4D8UpgradeReport -ReportPath $classes10Path -SchemaPath $reportSchemaPath
        $entryNames = @($validated.output.dexManifest | ForEach-Object { [string] $_.entryName })
        Assert-True -Condition ('classes10.dex' -cin $entryNames) -Message 'classes10.dex was not retained by report validation.'
        $paths = @($classes10Path) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition $gate.passed -Message "Contiguous classes10 manifest failed gate: $($gate.reasons -join ' | ')"
    }

    Invoke-TestCase -Name 'failed consumers atomically replace stale passing output' -Body {
        $missingDirectory = Join-Path $temporaryRoot 'missing-for-persisted-failure'
        New-Item -ItemType Directory -Path $missingDirectory | Out-Null
        @($positivePaths | Select-Object -SkipLast 1) | ForEach-Object {
            Copy-Item -LiteralPath $_ -Destination $missingDirectory
        }
        $gatePath = Join-Path $missingDirectory 'gate.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $gatePath -Encoding UTF8 -NoNewline
        $gateInvocation = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $missingDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-OutputPath', $gatePath
        )
        Assert-True -Condition ($gateInvocation.ExitCode -ne 0) -Message 'Failing consumer returned a zero exit code.'
        $persistedGate = Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition (-not [bool] $persistedGate.passed) -Message 'Stale passing gate output was not replaced by passed=false.'
        Assert-True -Condition ($persistedGate.schemaVersion -ceq 'autojs6.dex.r4.d8-upgrade-gate/v3') -Message 'Failing gate did not persist its structured result.'

        $comparisonOutputPath = Join-Path $temporaryRoot 'stale-comparison.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $comparisonOutputPath -Encoding UTF8 -NoNewline
        $comparisonInvocation = Invoke-R4ChildPowerShell -ScriptPath $comparisonPath -Arguments @(
            '-BaselineReportDirectory', $positiveDirectory,
            '-CandidateReportDirectory', $positiveDirectory,
            '-BaselineVersion', '8.13.22',
            '-CandidateVersion', '8.13.22',
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-OutputPath', $comparisonOutputPath
        )
        Assert-True -Condition ($comparisonInvocation.ExitCode -ne 0) -Message 'Failing comparison returned a zero exit code.'
        $persistedComparison = Get-Content -LiteralPath $comparisonOutputPath -Raw | ConvertFrom-Json -Depth 30 -NoEnumerate
        Assert-True -Condition (-not [bool] $persistedComparison.passed) -Message 'Stale passing comparison output was not replaced by passed=false.'
        Assert-True -Condition ($persistedComparison.schemaVersion -ceq 'autojs6.dex.r4.d8-upgrade-comparison-error/v1') -Message 'Comparison exception did not persist its error result.'

        $temporaryOutputs = @(Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File -Filter '*.tmp')
        $temporaryOutputNames = @($temporaryOutputs | ForEach-Object FullName)
        Assert-True -Condition ($temporaryOutputs.Count -eq 0) -Message "Atomic output left temporary files: $($temporaryOutputNames -join ', ')"
    }

    Invoke-TestCase -Name 'missing expected producer invocation id atomically replaces stale PASS' -Body {
        $outputPath = Join-Path $temporaryRoot 'missing-expected-producer-id-gate.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $positiveDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-gate-error/v3'
    }

    Invoke-TestCase -Name 'malformed expected producer invocation id atomically replaces stale PASS' -Body {
        $outputPath = Join-Path $temporaryRoot 'malformed-expected-producer-id-gate.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $positiveDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-ExpectedProducerInvocationId', 'NOT-A-CANONICAL-UUID',
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-gate-error/v3'
    }

    Invoke-TestCase -Name 'missing verifier module atomically replaces stale PASS' -Body {
        $runner = Join-Path $temporaryRoot 'missing-verifier-module'
        New-Item -ItemType Directory -Path $runner | Out-Null
        $isolatedConsumer = Join-Path $runner 'verify-r4-d8-upgrade.ps1'
        Copy-Item -LiteralPath $consumerPath -Destination $isolatedConsumer
        $outputPath = Join-Path $runner 'gate.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $isolatedConsumer -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $positiveDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-gate-error/v3'
    }

    Invoke-TestCase -Name 'broken verifier module atomically replaces stale PASS' -Body {
        $runner = Join-Path $temporaryRoot 'broken-verifier-module'
        New-Item -ItemType Directory -Path $runner | Out-Null
        $isolatedConsumer = Join-Path $runner 'verify-r4-d8-upgrade.ps1'
        Copy-Item -LiteralPath $consumerPath -Destination $isolatedConsumer
        'function broken( {' | Set-Content -LiteralPath (Join-Path $runner 'R4D8UpgradeGate.psm1') -Encoding UTF8 -NoNewline
        $outputPath = Join-Path $runner 'gate.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $isolatedConsumer -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $positiveDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-gate-error/v3'
    }

    Invoke-TestCase -Name 'missing comparison module atomically replaces stale PASS' -Body {
        $runner = Join-Path $temporaryRoot 'missing-comparison-module'
        New-Item -ItemType Directory -Path $runner | Out-Null
        $isolatedComparison = Join-Path $runner 'compare-r4-d8-upgrade.ps1'
        Copy-Item -LiteralPath $comparisonPath -Destination $isolatedComparison
        $outputPath = Join-Path $runner 'comparison.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $isolatedComparison -Arguments @(
            '-BaselineReportDirectory', $positiveDirectory,
            '-CandidateReportDirectory', $positiveDirectory,
            '-BaselineVersion', '8.13.22',
            '-CandidateVersion', '8.13.23',
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-comparison-error/v1'
    }

    Invoke-TestCase -Name 'broken comparison module atomically replaces stale PASS' -Body {
        $runner = Join-Path $temporaryRoot 'broken-comparison-module'
        New-Item -ItemType Directory -Path $runner | Out-Null
        $isolatedComparison = Join-Path $runner 'compare-r4-d8-upgrade.ps1'
        Copy-Item -LiteralPath $comparisonPath -Destination $isolatedComparison
        'function broken( {' | Set-Content -LiteralPath (Join-Path $runner 'R4D8UpgradeGate.psm1') -Encoding UTF8 -NoNewline
        $outputPath = Join-Path $runner 'comparison.json'
        '{"passed":true,"stale":true}' | Set-Content -LiteralPath $outputPath -Encoding UTF8 -NoNewline
        $invocation = Invoke-R4ChildPowerShell -ScriptPath $isolatedComparison -Arguments @(
            '-BaselineReportDirectory', $positiveDirectory,
            '-CandidateReportDirectory', $positiveDirectory,
            '-BaselineVersion', '8.13.22',
            '-CandidateVersion', '8.13.23',
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-OutputPath', $outputPath
        )
        Assert-R4BootstrapFailureReplacedStalePass `
            -Invocation $invocation `
            -OutputPath $outputPath `
            -ExpectedSchemaVersion 'autojs6.dex.r4.d8-upgrade-comparison-error/v1'
    }

    Invoke-TestCase -Name 'output aliases are rejected without changing report inputs' -Body {
        $protectedReportPath = [string] $positivePaths[0]
        $beforeHash = (Get-FileHash -LiteralPath $protectedReportPath -Algorithm SHA256).Hash
        $consumerInvocation = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-ReportDirectory', $positiveDirectory,
            '-ExpectedCompilerVersion', '8.13.22',
            '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
            '-OutputPath', $protectedReportPath
        )
        Assert-True -Condition ($consumerInvocation.ExitCode -ne 0) -Message 'Consumer accepted an OutputPath alias to a report input.'
        Assert-True -Condition ($consumerInvocation.Output -match 'aliases protected input path') -Message 'Consumer alias rejection was not explicit.'
        $afterConsumerHash = (Get-FileHash -LiteralPath $protectedReportPath -Algorithm SHA256).Hash
        Assert-True -Condition ($afterConsumerHash -ceq $beforeHash) -Message 'Consumer changed its aliased report input.'

        $comparisonInvocation = Invoke-R4ChildPowerShell -ScriptPath $comparisonPath -Arguments @(
            '-BaselineReportDirectory', $positiveDirectory,
            '-CandidateReportDirectory', $positiveDirectory,
            '-BaselineVersion', '8.13.22',
            '-CandidateVersion', '8.13.23',
            '-MatrixPath', $matrixPath,
            '-MatrixSchemaPath', $matrixSchemaPath,
            '-ReportSchemaPath', $reportSchemaPath,
            '-OutputPath', $protectedReportPath
        )
        Assert-True -Condition ($comparisonInvocation.ExitCode -ne 0) -Message 'Comparison accepted an OutputPath alias to a report input.'
        Assert-True -Condition ($comparisonInvocation.Output -match 'aliases protected input path') -Message 'Comparison alias rejection was not explicit.'
        $afterComparisonHash = (Get-FileHash -LiteralPath $protectedReportPath -Algorithm SHA256).Hash
        Assert-True -Condition ($afterComparisonHash -ceq $beforeHash) -Message 'Comparison changed its aliased report input.'
        Read-R4D8UpgradeReport -ReportPath $protectedReportPath -SchemaPath $reportSchemaPath | Out-Null
    }

    Invoke-TestCase -Name 'ancestor link output alias is rejected without changing report input' -Body {
        $aliasPath = Join-Path $temporaryRoot 'positive-through-link'
        try {
            try {
                New-Item -ItemType SymbolicLink -Path $aliasPath -Target $positiveDirectory -ErrorAction Stop | Out-Null
            } catch {
                if (-not [OperatingSystem]::IsWindows()) {
                    throw
                }
                New-Item -ItemType Junction -Path $aliasPath -Target $positiveDirectory -ErrorAction Stop | Out-Null
            }
            $protectedReportPath = [string] $positivePaths[0]
            $aliasedOutputPath = Join-Path $aliasPath ([IO.Path]::GetFileName($protectedReportPath))
            $beforeHash = (Get-FileHash -LiteralPath $protectedReportPath -Algorithm SHA256).Hash
            $consumerInvocation = Invoke-R4ChildPowerShell -ScriptPath $consumerPath -Arguments @(
                '-MatrixPath', $matrixPath,
                '-MatrixSchemaPath', $matrixSchemaPath,
                '-ReportSchemaPath', $reportSchemaPath,
                '-ReportDirectory', $positiveDirectory,
                '-ExpectedCompilerVersion', '8.13.22',
                '-ExpectedProducerInvocationId', $script:ProducerInvocationId,
                '-OutputPath', $aliasedOutputPath
            )
            Assert-True -Condition ($consumerInvocation.ExitCode -ne 0) -Message 'Consumer accepted an OutputPath through an ancestor link to a report input.'
            Assert-True -Condition ($consumerInvocation.Output -match 'aliases protected input path') -Message 'Ancestor-link alias rejection was not explicit.'
            $afterHash = (Get-FileHash -LiteralPath $protectedReportPath -Algorithm SHA256).Hash
            Assert-True -Condition ($afterHash -ceq $beforeHash) -Message 'Consumer changed the report reached through an ancestor link.'
            Read-R4D8UpgradeReport -ReportPath $protectedReportPath -SchemaPath $reportSchemaPath | Out-Null
        } finally {
            if (Test-Path -LiteralPath $aliasPath) {
                [IO.Directory]::Delete([IO.Path]::GetFullPath($aliasPath), $false)
            }
        }
    }

    Invoke-TestCase -Name 'missing cell fails closed' -Body {
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath @($positivePaths | Select-Object -SkipLast 1)
        Assert-True -Condition (-not $gate.passed) -Message 'Missing cell unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'Missing required matrix cellId values'
    }

    Invoke-TestCase -Name 'duplicate cell id fails closed' -Body {
        $duplicate = Copy-JsonObject -Value $positiveReports[0]
        $duplicate.reportId = [guid]::NewGuid().ToString()
        $duplicate.observationSequence = 1001
        $duplicatePath = Write-R4TestReport -Report $duplicate -Path (Join-Path $temporaryRoot 'duplicate-cell.json')
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath @(@($positivePaths) + $duplicatePath)
        Assert-True -Condition (-not $gate.passed) -Message 'Duplicate cell unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern "Duplicate cellId 'java8--api24--debug'"
    }

    Invoke-TestCase -Name 'compiler version drift fails closed' -Body {
        $drifted = Copy-JsonObject -Value $positiveReports[0]
        $drifted.compiler.version = '8.13.18'
        $driftedPath = Write-R4TestReport -Report $drifted -Path (Join-Path $temporaryRoot 'version-drift.json')
        $paths = @($driftedPath) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths `
            -ExpectedCompilerVersion '8.13.22'
        Assert-True -Condition (-not $gate.passed) -Message 'Compiler version drift unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'Compiler version drift|drifts from expected'
        $gateJson = $gate | ConvertTo-Json -Depth 30 -Compress
        Assert-True `
            -Condition ($gateJson.IndexOf($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
            -Message 'Rejected gate leaked an absolute report path.'
    }

    Invoke-TestCase -Name 'successful compilation requires exactly two repeat observations' -Body {
        $wrongRepeat = Copy-JsonObject -Value $positiveReports[0]
        $wrongRepeat.repeatObservation.runCount = 3
        $wrongRepeat.repeatObservation.summary = 'Three observations must not satisfy the exact-two gate.'
        $wrongRepeatPath = Write-R4TestReport -Report $wrongRepeat -Path (Join-Path $temporaryRoot 'success-repeat-count-three.json')
        $paths = @($wrongRepeatPath) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition (-not $gate.passed) -Message 'Successful compilation with runCount=3 unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'exactly two repeat observations'
    }

    Invoke-TestCase -Name 'failed compilation prohibits repeat output comparison' -Body {
        $failureIndex = -1
        for ($index = 0; $index -lt $cells.Count; $index++) {
            if ($cells[$index].expectedOutcome -ceq 'COMPILE_FAILURE') {
                $failureIndex = $index
                break
            }
        }
        Assert-True -Condition ($failureIndex -ge 0) -Message 'No failure cell exists for repeat testing.'
        $wrongRepeat = Copy-JsonObject -Value $positiveReports[$failureIndex]
        $wrongRepeat.repeatObservation.attempted = $true
        $wrongRepeat.repeatObservation.runCount = 2
        $wrongRepeat.repeatObservation.identicalOutputDigest = $true
        $wrongRepeat.repeatObservation.summary = 'Failure reports must not compare nonexistent output digests.'
        $wrongRepeatPath = Write-R4TestReport -Report $wrongRepeat -Path (Join-Path $temporaryRoot 'failure-repeat-attempted.json')
        $paths = @($positivePaths)
        $paths[$failureIndex] = $wrongRepeatPath
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition (-not $gate.passed) -Message 'Failed compilation with repeat comparison unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'attempted=false, runCount=1'
    }

    Invoke-TestCase -Name 'out-of-order DEX manifest fails closed' -Body {
        $outOfOrder = Copy-JsonObject -Value $positiveReports[0]
        $outOfOrder.output.dexManifest = @(
            [pscustomobject][ordered]@{
                entryName = 'classes2.dex'
                sha256 = 'e' * 64
                byteLength = 64
            },
            [pscustomobject][ordered]@{
                entryName = 'classes.dex'
                sha256 = 'd' * 64
                byteLength = 128
            }
        )
        $outOfOrderPath = Write-R4TestReport -Report $outOfOrder -Path (Join-Path $temporaryRoot 'dex-manifest-out-of-order.json')
        $paths = @($outOfOrderPath) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition (-not $gate.passed) -Message 'Out-of-order DEX manifest unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'strictly ordered and contiguous'
    }

    Invoke-TestCase -Name 'gapped DEX manifest fails closed' -Body {
        $gapped = Copy-JsonObject -Value $positiveReports[0]
        $gapped.output.dexManifest = @(
            [pscustomobject][ordered]@{
                entryName = 'classes.dex'
                sha256 = 'd' * 64
                byteLength = 128
            },
            [pscustomobject][ordered]@{
                entryName = 'classes3.dex'
                sha256 = 'e' * 64
                byteLength = 64
            }
        )
        $gappedPath = Write-R4TestReport -Report $gapped -Path (Join-Path $temporaryRoot 'dex-manifest-gap.json')
        $paths = @($gappedPath) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition (-not $gate.passed) -Message 'Gapped DEX manifest unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'strictly ordered and contiguous'
    }

    Invoke-TestCase -Name 'missing summary is rejected by report schema' -Body {
        $missingSummary = Copy-JsonObject -Value $positiveReports[0]
        $missingSummary.PSObject.Properties.Remove('summary')
        $missingSummaryPath = Write-R4TestReport -Report $missingSummary -Path (Join-Path $temporaryRoot 'missing-summary.json')
        Assert-ThrowsLike -Pattern 'does not conform to schema' -Body {
            Read-R4D8UpgradeReport -ReportPath $missingSummaryPath -SchemaPath $reportSchemaPath | Out-Null
        }
    }

    Invoke-TestCase -Name 'successful report without output digest is rejected' -Body {
        $missingDigest = Copy-JsonObject -Value $positiveReports[0]
        $missingDigest.output.sha256 = $null
        $missingDigestPath = Write-R4TestReport -Report $missingDigest -Path (Join-Path $temporaryRoot 'missing-output-digest.json')
        Assert-ThrowsLike -Pattern 'does not conform to schema' -Body {
            Read-R4D8UpgradeReport -ReportPath $missingDigestPath -SchemaPath $reportSchemaPath | Out-Null
        }
    }

    Invoke-TestCase -Name 'determinism claim is rejected even with repeat fields' -Body {
        $claimed = Copy-JsonObject -Value $positiveReports[0]
        $claimed.repeatObservation.attempted = $true
        $claimed.repeatObservation.runCount = 2
        $claimed.repeatObservation.identicalOutputDigest = $true
        $claimed.determinismClaim = 'DETERMINISTIC'
        $claimedPath = Write-R4TestReport -Report $claimed -Path (Join-Path $temporaryRoot 'determinism-claim.json')
        Assert-ThrowsLike -Pattern 'does not conform to schema' -Body {
            Read-R4D8UpgradeReport -ReportPath $claimedPath -SchemaPath $reportSchemaPath | Out-Null
        }
    }

    Invoke-TestCase -Name 'coexisting FAIL and later PASS history is rejected' -Body {
        $failed = Copy-JsonObject -Value $positiveReports[0]
        $failed.reportId = [guid]::NewGuid().ToString()
        $failed.observationSequence = 1
        $failed.outcome = 'FAIL'
        $failed.summary = 'Preserved failing observation.'
        $laterPass = Copy-JsonObject -Value $positiveReports[0]
        $laterPass.reportId = [guid]::NewGuid().ToString()
        $laterPass.observationSequence = 2
        $failPath = Write-R4TestReport -Report $failed -Path (Join-Path $temporaryRoot 'history-fail.json')
        $passPath = Write-R4TestReport -Report $laterPass -Path (Join-Path $temporaryRoot 'history-later-pass.json')
        $paths = @($failPath, $passPath) + @($positivePaths | Select-Object -Skip 1)
        $gate = Test-R4D8UpgradeGate `
            -MatrixPath $matrixPath `
            -MatrixSchemaPath $matrixSchemaPath `
            -ReportSchemaPath $reportSchemaPath `
            -ReportPath $paths
        Assert-True -Condition (-not $gate.passed) -Message 'PASS after FAIL unexpectedly passed.'
        Assert-ReasonMatches -Gate $gate -Pattern 'PASS after an earlier FAIL; FAIL evidence may not be overwritten or superseded'
    }
} finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot) -like 'autojs6-r4-d8-upgrade-tests-*') {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    } else {
        throw "Refusing to remove unexpected test directory: $resolvedTemporaryRoot"
    }
}

Write-Host "RESULT passed=$($script:PassedCount) failed=$($script:FailedCount)"
if (($script:PassedCount + $script:FailedCount) -ne $script:ExpectedTestCount) {
    Write-Host "FAIL expected $($script:ExpectedTestCount) test cases, executed $($script:PassedCount + $script:FailedCount)"
    exit 1
}
if ($script:FailedCount -gt 0 -or $script:PassedCount -ne $script:ExpectedTestCount) {
    exit 1
}
