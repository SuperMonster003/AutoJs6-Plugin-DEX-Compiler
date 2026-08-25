Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ContractSchemaVersion = 'autojs6.dex.r4.d8-promotion-contract/v1'
$script:StateSchemaVersion = 'autojs6.dex.r4.d8-promotion-state/v1'
$script:GateSchemaVersion = 'autojs6.dex.r4.d8-promotion-gate/v1'
$script:EvidenceBoundary = 'LOCAL_DEFAULT_PIN_PROMOTION_AND_ROLLBACK'
$script:Sha256Pattern = '^[0-9a-f]{64}$'
$script:UuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

function Get-R4D8PromotionSha256Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($Bytes))).ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-R4D8PromotionSha256File {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file does not exist: $Path"
    }
    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($stream))).ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Get-R4D8PromotionSha256Text {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)

    return Get-R4D8PromotionSha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Write-R4D8PromotionAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Json
    )

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

function Read-R4D8PromotionJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON input does not exist: $Path"
    }
    $raw = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'JSON input is empty.' }
    try {
        return $raw | ConvertFrom-Json -Depth 100 -NoEnumerate -DateKind String
    } catch {
        throw "JSON input is invalid: $($_.Exception.Message)"
    }
}

function Assert-R4D8PromotionExactProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Value,
        [Parameter(Mandatory)] [string[]] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )

    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    $wanted = @($Expected | Sort-Object -CaseSensitive)
    if (($actual -join "`0") -cne ($wanted -join "`0")) {
        throw "$Label properties differ; expected '$($wanted -join ', ')', found '$($actual -join ', ')'."
    }
}

function Read-R4D8PromotionContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $contract = Read-R4D8PromotionJson -Path $Path
    Assert-R4D8PromotionExactProperties -Value $contract -Expected @(
        'schemaVersion', 'evidenceBoundary', 'compiler', 'platformPlugin', 'stages'
    ) -Label 'contract'
    if ($contract.schemaVersion -cne $script:ContractSchemaVersion) { throw 'Contract schemaVersion changed.' }
    if ($contract.evidenceBoundary -cne $script:EvidenceBoundary) { throw 'Contract evidenceBoundary changed.' }
    Assert-R4D8PromotionExactProperties -Value $contract.compiler -Expected @(
        'coordinate', 'promotedVersion', 'rollbackVersion', 'catalogPath',
        'candidateVersionProperty', 'rollbackEvaluationProperty'
    ) -Label 'contract compiler'
    if ($contract.compiler.coordinate -cne 'com.android.tools:r8' -or
        $contract.compiler.promotedVersion -cne '8.13.22' -or
        $contract.compiler.rollbackVersion -cne '8.13.17' -or
        $contract.compiler.catalogPath -cne 'gradle/libs.versions.toml' -or
        $contract.compiler.candidateVersionProperty -cne 'd8CandidateVersion' -or
        $contract.compiler.rollbackEvaluationProperty -cne 'd8RollbackEvaluation') {
        throw 'Contract compiler governance changed.'
    }
    Assert-R4D8PromotionExactProperties -Value $contract.platformPlugin -Expected @(
        'coordinate', 'version', 'byteLength', 'sha256', 'sourceCommit'
    ) -Label 'contract platform plugin'
    if ($contract.platformPlugin.coordinate -cne 'org.autojs.build:autojs6-gradle-platform-versions:1.4.1' -or
        $contract.platformPlugin.version -cne '1.4.1' -or
        [long] $contract.platformPlugin.byteLength -ne 82427 -or
        $contract.platformPlugin.sha256 -cne '028ee9e96386e642313abb4d1904455959b87236f26a7ecaf8cd3bba35f2d9e8' -or
        $contract.platformPlugin.sourceCommit -cne 'dcf5d9a6b0de56fef34fcf6929478d86b1693fd0') {
        throw 'Contract platform plugin identity changed.'
    }
    $expectedStages = @(
        @('PROMOTED_DEFAULT', 1, '8.13.22', 'PINNED_DEFAULT'),
        @('OLD_PIN_ROLLBACK', 2, '8.13.17', 'OLD_PIN_ROLLBACK'),
        @('FINAL_PROMOTED_DEFAULT', 3, '8.13.22', 'PINNED_DEFAULT')
    )
    if (@($contract.stages).Count -ne 3) { throw 'Contract must contain exactly three stages.' }
    for ($index = 0; $index -lt 3; $index++) {
        $stage = @($contract.stages)[$index]
        Assert-R4D8PromotionExactProperties -Value $stage -Expected @(
            'id', 'ordinal', 'compilerVersion', 'gateEvaluationKind'
        ) -Label "contract stage $index"
        $expected = $expectedStages[$index]
        if ($stage.id -cne $expected[0] -or [int] $stage.ordinal -ne $expected[1] -or
            $stage.compilerVersion -cne $expected[2] -or $stage.gateEvaluationKind -cne $expected[3]) {
            throw "Contract stage $index changed."
        }
    }
    return $contract
}

function Get-R4D8PromotionSourceManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [psobject] $Contract,
        [Parameter(Mandatory)] [string] $ExpectedCompilerVersion
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $catalogRelative = [string] $Contract.compiler.catalogPath
    $filePaths = @(
        git -C $root ls-files -c -o --exclude-standard |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique -CaseSensitive
    )
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed while constructing source identity.' }
    if ($filePaths.Count -eq 0) { throw 'Source identity contains no files.' }
    if (@($filePaths | Where-Object { $_ -ceq $catalogRelative }).Count -ne 1) {
        throw 'Source identity does not contain the exact D8 catalog path.'
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in $filePaths) {
        if ($relative -match '[\x00-\x1f]' -or [IO.Path]::IsPathRooted($relative)) {
            throw 'Source identity contains an unsafe repository-relative path.'
        }
        $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $full = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $nativeRelative))
        $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Source identity path escapes the repository root.'
        }
        if (-not [IO.File]::Exists($full)) { throw "Source identity file is missing: $relative" }
        $rawBytes = [IO.File]::ReadAllBytes($full)
        $normalizedBytes = $rawBytes
        if ($relative -ceq $catalogRelative) {
            $text = [Text.UTF8Encoding]::new($false, $true).GetString($rawBytes)
            $pattern = '(?m)^r8\s*=\s*"' + [regex]::Escape($ExpectedCompilerVersion) + '"\s*$'
            $matches = [regex]::Matches($text, $pattern)
            if ($matches.Count -ne 1) {
                throw "Catalog must contain exactly one r8 pin for $ExpectedCompilerVersion."
            }
            $normalized = [regex]::Replace($text, $pattern, 'r8 = "<D8_DEFAULT_PIN>"')
            $normalizedBytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
        }
        $records.Add([pscustomobject][ordered]@{
            path = $relative.Replace('\', '/')
            byteLength = [long] $rawBytes.Length
            sha256 = Get-R4D8PromotionSha256Bytes -Bytes $rawBytes
            normalizedByteLength = [long] $normalizedBytes.Length
            normalizedSha256 = Get-R4D8PromotionSha256Bytes -Bytes $normalizedBytes
        })
    }
    $canonical = (@($records) | ForEach-Object {
        "{0}`0{1}`0{2}`n" -f $_.path, $_.normalizedByteLength, $_.normalizedSha256
    }) -join ''
    return [pscustomobject][ordered]@{
        fileCount = $records.Count
        normalizedSha256 = Get-R4D8PromotionSha256Text -Text $canonical
        records = @($records)
    }
}

function Test-R4D8PromotionCloseout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Contract,
        [Parameter(Mandatory)] [psobject[]] $State,
        [Parameter(Mandatory)] [string[]] $StateSha256
    )

    if ($State.Count -ne 3 -or $StateSha256.Count -ne 3) { throw 'Exactly three promotion states are required.' }
    $campaignIds = @($State | ForEach-Object { [string] $_.campaignId } | Sort-Object -Unique -CaseSensitive)
    if ($campaignIds.Count -ne 1 -or $campaignIds[0] -cnotmatch $script:UuidPattern) {
        throw 'Promotion states must share one canonical campaignId.'
    }
    $receiptIds = @($State | ForEach-Object { [string] $_.stateReceiptId })
    if (@($receiptIds | Sort-Object -Unique -CaseSensitive).Count -ne 3 -or
        @($receiptIds | Where-Object { $_ -cnotmatch $script:UuidPattern }).Count -ne 0) {
        throw 'Promotion state receipt IDs must be unique canonical UUIDs.'
    }
    $producerIds = @($State | ForEach-Object { [string] $_.gate.producerInvocationId })
    if (@($producerIds | Sort-Object -Unique -CaseSensitive).Count -ne 3 -or
        @($producerIds | Where-Object { $_ -cnotmatch $script:UuidPattern }).Count -ne 0) {
        throw 'Promotion producer invocation IDs must be unique canonical UUIDs.'
    }
    foreach ($digest in $StateSha256) {
        if ($digest -cnotmatch $script:Sha256Pattern) { throw 'State receipt SHA-256 is invalid.' }
    }

    $captured = [System.Collections.Generic.List[datetimeoffset]]::new()
    for ($index = 0; $index -lt 3; $index++) {
        $currentState = $State[$index]
        $expected = @($Contract.stages)[$index]
        if ($currentState.schemaVersion -cne $script:StateSchemaVersion -or
            $currentState.evidenceBoundary -cne $script:EvidenceBoundary -or
            $currentState.stage -cne $expected.id -or [int] $currentState.ordinal -ne [int] $expected.ordinal -or
            $currentState.compilerVersion -cne $expected.compilerVersion -or -not [bool] $currentState.passed) {
            throw "Promotion state $index identity changed."
        }
        if (-not [bool] $currentState.gate.passed -or $currentState.gate.evaluationKind -cne $expected.gateEvaluationKind -or
            $currentState.gate.compilerVersion -cne $expected.compilerVersion -or
            [int] $currentState.gate.expectedCellCount -ne 60 -or [int] $currentState.gate.reportCount -ne 60 -or
            $currentState.gate.determinismClaim -cne 'NOT_CLAIMED') {
            throw "Promotion state $index does not contain a passing 60-cell gate."
        }
        if ([bool] $currentState.candidateOverridePresent) { throw "Promotion state $index used a candidate override." }
        if ($currentState.repositoryHead -cnotmatch '^[0-9a-f]{40}$') { throw "Promotion state $index repositoryHead is invalid." }
        foreach ($digest in @(
            $currentState.gate.sha256, $currentState.gate.reportSetSha256, $currentState.gate.matrixSha256,
            $currentState.gate.reportSchemaSha256, $currentState.runtimeFingerprintSha256,
            $currentState.sourceManifest.normalizedSha256, $currentState.platformPlugin.sha256
        )) {
            if ([string] $digest -cnotmatch $script:Sha256Pattern) { throw "Promotion state $index contains an invalid digest." }
        }
        if ($currentState.platformPlugin.coordinate -cne $Contract.platformPlugin.coordinate -or
            $currentState.platformPlugin.version -cne $Contract.platformPlugin.version -or
            [long] $currentState.platformPlugin.byteLength -ne [long] $Contract.platformPlugin.byteLength -or
            $currentState.platformPlugin.sha256 -cne $Contract.platformPlugin.sha256 -or
            $currentState.platformPlugin.sourceCommit -cne $Contract.platformPlugin.sourceCommit) {
            throw "Promotion state $index platform plugin identity changed."
        }
        try {
            $parsed = [datetimeoffset]::Parse(
                [string] $currentState.capturedAtUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            )
        } catch {
            throw "Promotion state $index capturedAtUtc is invalid."
        }
        if ($parsed.ToString('O') -cne ([string] $currentState.capturedAtUtc)) {
            throw "Promotion state $index capturedAtUtc is not canonical."
        }
        $captured.Add($parsed)
    }
    if ($captured[0] -ge $captured[1] -or $captured[1] -ge $captured[2]) {
        throw 'Promotion state timestamps are not strictly increasing.'
    }

    foreach ($field in @('repositoryHead', 'runtimeFingerprintSha256')) {
        if (@($State | ForEach-Object { [string] $_.$field } | Sort-Object -Unique -CaseSensitive).Count -ne 1) {
            throw "Promotion states do not share one $field."
        }
    }
    if (@($State | ForEach-Object { [string] $_.sourceManifest.normalizedSha256 } | Sort-Object -Unique -CaseSensitive).Count -ne 1) {
        throw 'Promotion states do not share one normalized source/build identity.'
    }
    if (@($State | ForEach-Object { [string] $_.gate.sha256 } | Sort-Object -Unique -CaseSensitive).Count -ne 3 -or
        @($State | ForEach-Object { [string] $_.gate.reportSetSha256 } | Sort-Object -Unique -CaseSensitive).Count -ne 3) {
        throw 'Promotion states reused a gate or report set.'
    }

    $catalogPath = [string] $Contract.compiler.catalogPath
    $referenceRecords = @($State[0].sourceManifest.records)
    for ($stateIndex = 1; $stateIndex -lt 3; $stateIndex++) {
        $candidateRecords = @($State[$stateIndex].sourceManifest.records)
        if ($candidateRecords.Count -ne $referenceRecords.Count) { throw 'Promotion source file count changed.' }
        for ($recordIndex = 0; $recordIndex -lt $referenceRecords.Count; $recordIndex++) {
            $left = $referenceRecords[$recordIndex]
            $right = $candidateRecords[$recordIndex]
            if ($left.path -cne $right.path -or $left.normalizedSha256 -cne $right.normalizedSha256 -or
                [long] $left.normalizedByteLength -ne [long] $right.normalizedByteLength) {
                throw "Promotion normalized source record changed at index $recordIndex."
            }
            if ($left.path -cne $catalogPath -and
                ($left.sha256 -cne $right.sha256 -or [long] $left.byteLength -ne [long] $right.byteLength)) {
                throw "Non-catalog source changed during promotion: $($left.path)"
            }
        }
    }
    $catalogRecords = @($State | ForEach-Object {
        @($_.sourceManifest.records | Where-Object { $_.path -ceq $catalogPath })
    })
    if ($catalogRecords.Count -ne 3 -or
        $catalogRecords[0].sha256 -ceq $catalogRecords[1].sha256 -or
        $catalogRecords[0].sha256 -cne $catalogRecords[2].sha256) {
        throw 'Catalog pin did not prove promote, rollback, and final re-promotion bytes.'
    }

    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        evidenceBoundary = $script:EvidenceBoundary
        campaignId = $campaignIds[0]
        passed = $true
        promotedVersion = [string] $Contract.compiler.promotedVersion
        rollbackVersion = [string] $Contract.compiler.rollbackVersion
        repositoryHead = [string] $State[0].repositoryHead
        sourceBuildIdentitySha256 = [string] $State[0].sourceManifest.normalizedSha256
        runtimeFingerprintSha256 = [string] $State[0].runtimeFingerprintSha256
        platformPlugin = $State[0].platformPlugin
        producerInvocationIds = $producerIds
        stateReceiptSha256 = $StateSha256
        finalDefaultVersion = [string] $State[2].compilerVersion
        candidateOverrideUsed = $false
        determinismClaim = 'NOT_CLAIMED'
        publicOrRemoteActionPerformed = $false
    }
}

Export-ModuleMember -Function @(
    'Get-R4D8PromotionSha256File',
    'Get-R4D8PromotionSha256Text',
    'Get-R4D8PromotionSourceManifest',
    'Read-R4D8PromotionContract',
    'Read-R4D8PromotionJson',
    'Test-R4D8PromotionCloseout',
    'Write-R4D8PromotionAtomicJson'
)
