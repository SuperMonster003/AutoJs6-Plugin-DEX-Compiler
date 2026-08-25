[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CampaignId,

    [Parameter(Mandatory)]
    [ValidateSet('PROMOTED_DEFAULT', 'OLD_PIN_ROLLBACK', 'FINAL_PROMOTED_DEFAULT')]
    [string] $Stage,

    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '..\..'),

    [string] $ContractPath = (Join-Path $PSScriptRoot 'r4-d8-promotion-contract.json'),

    [Parameter(Mandatory)]
    [string] $GatePath,

    [Parameter(Mandatory)]
    [string] $ReportDirectory,

    [Parameter(Mandatory)]
    [string] $PlatformPluginJarPath,

    [Parameter(Mandatory)]
    [string] $PlatformPluginSourceRoot,

    [Parameter(Mandatory)]
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-BootstrapAtomicJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Json)

    $resolved = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
    $temporary = [IO.Path]::Combine(
        $parent,
        ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($resolved), [guid]::NewGuid().ToString('N'))
    )
    try {
        [IO.File]::WriteAllText($temporary, $Json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $resolved, $true)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function ConvertTo-SafeFailureMessage {
    param([Parameter(Mandatory)] [string] $Message, [Parameter(Mandatory)] [string[]] $PrivatePath)

    $safe = $Message
    foreach ($path in @($PrivatePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique)) {
        try {
            $resolved = [IO.Path]::GetFullPath($path)
            $safe = [regex]::Replace($safe, [regex]::Escape($resolved), '<private-path>', 'IgnoreCase')
        } catch { }
    }
    return $safe
}

$promotionModulePath = Join-Path $PSScriptRoot 'R4D8PromotionGate.psm1'
$upgradeModulePath = Join-Path $RepositoryRoot 'scripts\r4-d8-upgrade\R4D8UpgradeGate.psm1'
$matrixPath = Join-Path $RepositoryRoot 'scripts\r4-d8-upgrade\r4-d8-upgrade-matrix.json'
$matrixSchemaPath = Join-Path $RepositoryRoot 'scripts\r4-d8-upgrade\r4-d8-upgrade-matrix.schema.json'
$reportSchemaPath = Join-Path $RepositoryRoot 'scripts\r4-d8-upgrade\r4-d8-upgrade-report.schema.json'
$privatePaths = @(
    $RepositoryRoot, $PSScriptRoot, [IO.Path]::GetTempPath(), $ContractPath, $GatePath,
    $ReportDirectory, $PlatformPluginJarPath, $PlatformPluginSourceRoot, $OutputPath,
    $promotionModulePath, $upgradeModulePath, $matrixPath, $matrixSchemaPath, $reportSchemaPath
)
$resolvedOutput = $null
$safeOutputEstablished = $false

try {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $parent = [IO.Path]::GetDirectoryName($resolvedOutput)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
    foreach ($input in @($ContractPath, $GatePath, $promotionModulePath, $upgradeModulePath, $matrixPath, $matrixSchemaPath, $reportSchemaPath)) {
        if ([string]::Equals($resolvedOutput, [IO.Path]::GetFullPath($input), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'OutputPath aliases a protected input.'
        }
    }
    $safeOutputEstablished = $true
    Write-BootstrapAtomicJson -Path $resolvedOutput -Json (([pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-state-error/v1'
        passed = $false
        stage = $Stage
        error = 'INVALIDATED_BEFORE_STATE_CAPTURE'
    } | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

    if ($CampaignId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
        throw 'CampaignId must be a canonical lowercase UUID.'
    }
    Import-Module $promotionModulePath -Force
    Import-Module $upgradeModulePath -Force

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { throw 'RepositoryRoot is not a Git worktree.' }
    $contract = Read-R4D8PromotionContract -Path $ContractPath
    $expectedStage = @($contract.stages | Where-Object { $_.id -ceq $Stage })
    if ($expectedStage.Count -ne 1) { throw 'Stage is absent or duplicated in the contract.' }
    $expectedStage = $expectedStage[0]

    $repositoryHead = (git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $repositoryHead -cnotmatch '^[0-9a-f]{40}$') { throw 'Repository HEAD is invalid.' }
    $platformRoot = [IO.Path]::GetFullPath($PlatformPluginSourceRoot)
    $platformStatus = @(git -C $platformRoot status --porcelain=v1)
    if ($LASTEXITCODE -ne 0 -or $platformStatus.Count -ne 0) { throw 'Platform plugin source worktree is not clean.' }
    $platformCommit = (git -C $platformRoot rev-parse HEAD).Trim()
    if ($platformCommit -cne $contract.platformPlugin.sourceCommit) { throw 'Platform plugin source commit differs from the contract.' }
    $platformJar = Get-Item -LiteralPath $PlatformPluginJarPath -ErrorAction Stop
    $platformJarSha256 = Get-R4D8PromotionSha256File -Path $platformJar.FullName
    if ($platformJar.Length -ne [long] $contract.platformPlugin.byteLength -or
        $platformJarSha256 -cne $contract.platformPlugin.sha256) {
        throw 'Platform plugin artifact differs from the byte-pinned contract.'
    }

    $sourceManifest = Get-R4D8PromotionSourceManifest `
        -RepositoryRoot $root `
        -Contract $contract `
        -ExpectedCompilerVersion ([string] $expectedStage.compilerVersion)

    $persistedGate = Read-R4D8PromotionJson -Path $GatePath
    if ($persistedGate.schemaVersion -cne 'autojs6.dex.r4.d8-upgrade-gate/v3' -or
        -not [bool] $persistedGate.passed -or
        $persistedGate.evaluationKind -cne $expectedStage.gateEvaluationKind -or
        $persistedGate.compiler.pinnedVersion -cne $contract.compiler.promotedVersion -or
        $persistedGate.compiler.rollbackVersion -cne $contract.compiler.rollbackVersion -or
        $persistedGate.compiler.evaluatedVersion -cne $expectedStage.compilerVersion -or
        [int] $persistedGate.expectedCellCount -ne 60 -or
        [int] $persistedGate.reportCount -ne 60 -or
        $persistedGate.determinismClaim -cne 'NOT_CLAIMED') {
        throw 'Persisted D8 gate does not match the requested promotion stage.'
    }
    $producerInvocationId = [string] $persistedGate.producerInvocationId
    if ($producerInvocationId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
        throw 'Persisted D8 gate producer invocation ID is invalid.'
    }
    $reportPaths = @(
        Get-ChildItem -LiteralPath $ReportDirectory -File -Filter '*.json' |
            Sort-Object Name |
            ForEach-Object FullName
    )
    if ($reportPaths.Count -ne 60) { throw "Promotion state requires exactly 60 reports; found $($reportPaths.Count)." }
    $gateArguments = @{
        MatrixPath = $matrixPath
        MatrixSchemaPath = $matrixSchemaPath
        ReportSchemaPath = $reportSchemaPath
        ReportPath = $reportPaths
        ExpectedCompilerVersion = [string] $expectedStage.compilerVersion
        ExpectedProducerInvocationId = $producerInvocationId
    }
    if ($Stage -ceq 'OLD_PIN_ROLLBACK') { $gateArguments.RollbackEvaluation = $true }
    $independentGate = Test-R4D8UpgradeGate @gateArguments
    if (-not $independentGate.passed) { throw "Independent D8 gate failed: $($independentGate.reasons -join ' | ')" }
    foreach ($field in @('evaluationKind', 'matrixSha256', 'reportSchemaSha256', 'reportSetSha256', 'producerInvocationId', 'reportCount')) {
        if ([string] $independentGate.$field -cne [string] $persistedGate.$field) {
            throw "Independent D8 gate field '$field' differs from the persisted gate."
        }
    }

    $runtimeFingerprints = @(
        $reportPaths | ForEach-Object {
            $report = Read-R4D8UpgradeReport -ReportPath $_ -SchemaPath $reportSchemaPath
            [string] $report.runtimeFingerprint.sha256
        } | Sort-Object -Unique -CaseSensitive
    )
    if ($runtimeFingerprints.Count -ne 1 -or $runtimeFingerprints[0] -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Promotion reports do not share one runtime fingerprint.'
    }

    $receipt = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-state/v1'
        evidenceBoundary = [string] $contract.evidenceBoundary
        campaignId = $CampaignId
        stateReceiptId = [guid]::NewGuid().ToString()
        capturedAtUtc = [datetimeoffset]::UtcNow.ToString('O')
        stage = $Stage
        ordinal = [int] $expectedStage.ordinal
        compilerVersion = [string] $expectedStage.compilerVersion
        passed = $true
        candidateOverridePresent = $false
        repositoryHead = $repositoryHead
        sourceManifest = $sourceManifest
        runtimeFingerprintSha256 = $runtimeFingerprints[0]
        platformPlugin = [pscustomobject][ordered]@{
            coordinate = [string] $contract.platformPlugin.coordinate
            version = [string] $contract.platformPlugin.version
            byteLength = [long] $platformJar.Length
            sha256 = $platformJarSha256
            sourceCommit = $platformCommit
        }
        gate = [pscustomobject][ordered]@{
            sha256 = Get-R4D8PromotionSha256File -Path $GatePath
            passed = $true
            evaluationKind = [string] $persistedGate.evaluationKind
            compilerVersion = [string] $persistedGate.compiler.evaluatedVersion
            producerInvocationId = $producerInvocationId
            matrixSha256 = [string] $persistedGate.matrixSha256
            reportSchemaSha256 = [string] $persistedGate.reportSchemaSha256
            reportSetSha256 = [string] $persistedGate.reportSetSha256
            expectedCellCount = [int] $persistedGate.expectedCellCount
            reportCount = [int] $persistedGate.reportCount
            determinismClaim = 'NOT_CLAIMED'
        }
    }
    $json = ($receipt | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    Write-R4D8PromotionAtomicJson -Path $resolvedOutput -Json $json
    $json
} catch {
    $safeMessage = ConvertTo-SafeFailureMessage -Message $_.Exception.Message -PrivatePath $privatePaths
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-state-error/v1'
        passed = $false
        stage = $Stage
        error = $safeMessage
    }
    $json = ($failure | ConvertTo-Json -Depth 10) + [Environment]::NewLine
    if ($safeOutputEstablished -and $null -ne $resolvedOutput) {
        try { Write-BootstrapAtomicJson -Path $resolvedOutput -Json $json } catch { }
    }
    $json
    exit 1
}
