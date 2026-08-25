Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ContractSchemaVersion = 'autojs6.dex.r4.r8-closeout-contract/v1'
$script:GateSchemaVersion = 'autojs6.dex.r4.r8-closeout-gate/v1'
$script:EvidenceBoundary = 'INDEPENDENT_R8_PRIVATE_RELEASE_AND_HOST_ACCEPTANCE_CLOSEOUT'
$script:Sha256Pattern = '^[0-9a-f]{64}$'
$script:CommitPattern = '^[0-9a-f]{40}$'
$script:UuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

function Get-R4R8CloseoutSha256Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($Bytes))).ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-R4R8CloseoutSha256File {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not [IO.File]::Exists([IO.Path]::GetFullPath($Path))) {
        throw 'Required evidence file does not exist.'
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

function Read-R4R8CloseoutJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not [IO.File]::Exists([IO.Path]::GetFullPath($Path))) {
        throw 'Required JSON input does not exist.'
    }
    try {
        $raw = [IO.File]::ReadAllText(
            [IO.Path]::GetFullPath($Path),
            [Text.UTF8Encoding]::new($false, $true)
        )
    } catch {
        throw "JSON input is not canonical UTF-8: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'JSON input is empty.' }
    try {
        return $raw | ConvertFrom-Json -Depth 100 -NoEnumerate -DateKind String
    } catch {
        throw "JSON input is invalid: $($_.Exception.Message)"
    }
}

function Assert-R4R8CloseoutExactProperties {
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

function Assert-R4R8CloseoutSafeRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or $Path -match '[\x00-\x1f]' -or
        @($Path.Split('/') | Where-Object { $_ -ceq '' -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
        throw "$Label is not a canonical repository-relative path."
    }
}

function Read-R4R8CloseoutContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $contract = Read-R4R8CloseoutJson -Path $Path
    Assert-R4R8CloseoutExactProperties -Value $contract -Expected @(
        'schemaVersion', 'evidenceBoundary', 'r8Repository', 'annotatedTag',
        'host', 'gates', 'releaseAssets', 'github'
    ) -Label 'contract'
    if ($contract.schemaVersion -cne $script:ContractSchemaVersion) { throw 'Contract schemaVersion changed.' }
    if ($contract.evidenceBoundary -cne $script:EvidenceBoundary) { throw 'Contract evidenceBoundary changed.' }

    Assert-R4R8CloseoutExactProperties -Value $contract.r8Repository -Expected @(
        'nameWithOwner', 'originUrl', 'defaultBranch', 'head', 'tree', 'reachableCommitCount',
        'identityName', 'identityEmail'
    ) -Label 'contract r8Repository'
    if ($contract.r8Repository.nameWithOwner -cne 'SuperMonster003/AutoJs6-Plugin-R8-Compiler' -or
        $contract.r8Repository.originUrl -cne 'https://github.com/SuperMonster003/AutoJs6-Plugin-R8-Compiler.git' -or
        $contract.r8Repository.defaultBranch -cne 'master' -or
        $contract.r8Repository.identityName -cne 'SuperMonster003' -or
        $contract.r8Repository.identityEmail -cne '30370009+SuperMonster003@users.noreply.github.com' -or
        $contract.r8Repository.head -cnotmatch $script:CommitPattern -or
        $contract.r8Repository.tree -cnotmatch $script:CommitPattern -or
        [int] $contract.r8Repository.reachableCommitCount -ne 4) {
        throw 'Contract R8 repository identity changed.'
    }

    Assert-R4R8CloseoutExactProperties -Value $contract.annotatedTag -Expected @(
        'name', 'object', 'target', 'taggerName', 'taggerEmail'
    ) -Label 'contract annotatedTag'
    if ($contract.annotatedTag.name -cne 'v0.1.0-provider-dev-private.1' -or
        $contract.annotatedTag.object -cnotmatch $script:CommitPattern -or
        $contract.annotatedTag.target -cnotmatch $script:CommitPattern -or
        $contract.annotatedTag.taggerName -cne $contract.r8Repository.identityName -or
        $contract.annotatedTag.taggerEmail -cne $contract.r8Repository.identityEmail) {
        throw 'Contract annotated tag identity changed.'
    }

    Assert-R4R8CloseoutExactProperties -Value $contract.host -Expected @(
        'integrationCommit', 'r8ApiAarPath', 'r8ApiAarByteLength', 'r8ApiAarSha256'
    ) -Label 'contract host'
    if ($contract.host.integrationCommit -cne '4a9718d63923834c9a99fd70e0cd58c898e138f6' -or
        $contract.host.r8ApiAarPath -cne 'libs/r8-compiler-api-0_1_0/r8-compiler-api-0.1.0.aar' -or
        [long] $contract.host.r8ApiAarByteLength -ne 179855 -or
        $contract.host.r8ApiAarSha256 -cne 'e9df49b7e49992615a15bc0af2372a4525f02b4a2a915a560ddab3128bb2f066') {
        throw 'Contract host integration identity changed.'
    }

    $expectedGateIds = @('g2', 'g3', 'g4', 'g5', 'g6', 'g7Local', 'g7Runtime', 'g8')
    if (@($contract.gates).Count -ne $expectedGateIds.Count) { throw 'Contract must contain exactly eight gates.' }
    for ($index = 0; $index -lt $expectedGateIds.Count; $index++) {
        $gate = @($contract.gates)[$index]
        Assert-R4R8CloseoutExactProperties -Value $gate -Expected @(
            'id', 'path', 'schemaVersion', 'invocationId', 'evidenceBoundary', 'byteLength', 'sha256'
        ) -Label "contract gate $index"
        if ($gate.id -cne $expectedGateIds[$index] -or
            [string]::IsNullOrWhiteSpace([string] $gate.schemaVersion) -or
            [string]::IsNullOrWhiteSpace([string] $gate.evidenceBoundary) -or
            $gate.invocationId -cnotmatch $script:UuidPattern -or
            [long] $gate.byteLength -le 0 -or $gate.sha256 -cnotmatch $script:Sha256Pattern) {
            throw "Contract gate $index identity is invalid."
        }
        Assert-R4R8CloseoutSafeRelativePath -Path ([string] $gate.path) -Label "contract gate $index path"
    }
    if (@($contract.gates | ForEach-Object { $_.path } | Sort-Object -Unique -CaseSensitive).Count -ne 8) {
        throw 'Contract gate paths are not unique.'
    }

    $expectedAssetNames = @(
        'autojs6-r8-compiler-provider-0.1.0-provider-dev-signed.apk',
        'protocol-wire-api-0.1.0.aar',
        'r8-compiler-api-0.1.0.aar',
        'release-manifest.json',
        'autojs6-r8-compiler-provider-0.1.0-provider-dev-private.1-SHA256SUMS.txt'
    )
    if (@($contract.releaseAssets).Count -ne $expectedAssetNames.Count) {
        throw 'Contract must contain exactly five release assets.'
    }
    for ($index = 0; $index -lt $expectedAssetNames.Count; $index++) {
        $asset = @($contract.releaseAssets)[$index]
        Assert-R4R8CloseoutExactProperties -Value $asset -Expected @(
            'name', 'localPath', 'byteLength', 'sha256'
        ) -Label "contract release asset $index"
        if ($asset.name -cne $expectedAssetNames[$index] -or [long] $asset.byteLength -le 0 -or
            $asset.sha256 -cnotmatch $script:Sha256Pattern) {
            throw "Contract release asset $index identity is invalid."
        }
        Assert-R4R8CloseoutSafeRelativePath -Path ([string] $asset.localPath) -Label "contract asset $index path"
    }

    Assert-R4R8CloseoutExactProperties -Value $contract.github -Expected @(
        'repositoryId', 'visibility', 'releaseId', 'draft', 'prerelease'
    ) -Label 'contract github'
    if ([long] $contract.github.repositoryId -ne 1345668157 -or
        $contract.github.visibility -cne 'PRIVATE' -or [long] $contract.github.releaseId -ne 376144423 -or
        $contract.github.draft -isnot [bool] -or [bool] $contract.github.draft -or
        $contract.github.prerelease -isnot [bool] -or -not [bool] $contract.github.prerelease) {
        throw 'Contract GitHub private prerelease identity changed.'
    }
    return $contract
}

function Get-R4R8CloseoutCanonicalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $pathToResolve = [IO.Path]::GetFullPath($Path)
    for ($pass = 0; $pass -lt 64; $pass++) {
        $root = [IO.Path]::GetPathRoot($pathToResolve)
        if ([string]::IsNullOrWhiteSpace($root)) { throw 'Path has no filesystem root.' }
        [char[]] $separators = @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $segments = @($pathToResolve.Substring($root.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries))
        $current = $root
        $resolvedLink = $false
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $candidate = [IO.Path]::Combine($current, $segments[$index])
            if (Test-Path -LiteralPath $candidate) {
                $item = Get-Item -LiteralPath $candidate -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $target = $item.ResolveLinkTarget($true)
                    if ($null -eq $target) { throw 'Unable to resolve reparse point.' }
                    $remaining = if ($index + 1 -lt $segments.Count) {
                        [IO.Path]::Combine([string[]] $segments[($index + 1)..($segments.Count - 1)])
                    } else { '' }
                    $pathToResolve = if ([string]::IsNullOrEmpty($remaining)) {
                        [IO.Path]::GetFullPath($target.FullName)
                    } else {
                        [IO.Path]::GetFullPath([IO.Path]::Combine($target.FullName, $remaining))
                    }
                    $resolvedLink = $true
                    break
                }
            }
            $current = $candidate
        }
        if (-not $resolvedLink) { return [IO.Path]::GetFullPath($current) }
    }
    throw 'Path contains too many reparse-point resolutions.'
}

function Resolve-R4R8CloseoutRelativeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter(Mandatory)] [string] $Label
    )

    Assert-R4R8CloseoutSafeRelativePath -Path $RelativePath -Label $Label
    $canonicalRoot = Get-R4R8CloseoutCanonicalPath -Path $Root
    if (-not [IO.Directory]::Exists($canonicalRoot)) { throw "$Label root does not exist." }
    $native = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $candidate = Get-R4R8CloseoutCanonicalPath -Path ([IO.Path]::Combine($canonicalRoot, $native))
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $prefix = $canonicalRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, $comparison)) { throw "$Label escapes its repository root." }
    if (-not [IO.File]::Exists($candidate)) { throw "$Label does not exist." }
    return $candidate
}

function Assert-R4R8CloseoutFileIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [long] $ByteLength,
        [Parameter(Mandatory)] [string] $Sha256,
        [Parameter(Mandatory)] [string] $Label
    )

    $item = Get-Item -LiteralPath $Path
    if ([long] $item.Length -ne $ByteLength) { throw "$Label byte length changed." }
    if ((Get-R4R8CloseoutSha256File -Path $Path) -cne $Sha256) { throw "$Label SHA-256 changed." }
}

function Invoke-R4R8CloseoutProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [int[]] $AllowedExitCode = @(0)
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) { [void] $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Unable to start $FilePath." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($AllowedExitCode -notcontains $process.ExitCode) {
            $detail = ($stderr.Trim(), $stdout.Trim() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' | '
            if ($detail.Length -gt 1200) { $detail = $detail.Substring(0, 1200) }
            throw "$FilePath exited $($process.ExitCode): $detail"
        }
        return [pscustomobject]@{
            exitCode = $process.ExitCode
            stdout = $stdout
            stderr = $stderr
        }
    } finally {
        $process.Dispose()
    }
}

function Get-R4R8CloseoutGateContractMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Contract)

    $map = [ordered]@{}
    foreach ($record in @($Contract.gates)) { $map[[string] $record.id] = $record }
    return $map
}

function Assert-R4R8CloseoutGateMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Expected,
        [Parameter(Mandatory)] [psobject] $Actual
    )

    if ($Actual.schemaVersion -cne $Expected.schemaVersion -or
        $Actual.invocationId -cne $Expected.invocationId -or
        $Actual.evidenceBoundary -cne $Expected.evidenceBoundary -or
        $Actual.passed -isnot [bool] -or -not [bool] $Actual.passed) {
        throw "Gate '$($Expected.id)' metadata or PASS state changed."
    }
}

function Assert-R4R8CloseoutClaims {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Claims,
        [string[]] $RequiredTrue = @(),
        [string[]] $RequiredFalse = @(),
        [Parameter(Mandatory)] [string] $Label
    )

    foreach ($name in $RequiredTrue) {
        $property = $Claims.PSObject.Properties[$name]
        if ($null -eq $property -or $property.Value -isnot [bool] -or -not [bool] $property.Value) {
            throw "$Label claim '$name' is not canonical true."
        }
    }
    foreach ($name in $RequiredFalse) {
        $property = $Claims.PSObject.Properties[$name]
        if ($null -eq $property -or $property.Value -isnot [bool] -or [bool] $property.Value) {
            throw "$Label claim '$name' is not canonical false."
        }
    }
}

function Assert-R4R8CloseoutPriorEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()] [object] $Actual,
        [Parameter(Mandatory)] [string[]] $ExpectedGateId,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $ContractGateById,
        [Parameter(Mandatory)] [string] $Label
    )

    $records = @($Actual)
    if ($records.Count -ne $ExpectedGateId.Count) { throw "$Label prerequisite count changed." }
    for ($index = 0; $index -lt $ExpectedGateId.Count; $index++) {
        $record = $records[$index]
        $expected = $ContractGateById[$ExpectedGateId[$index]]
        if ($record.path -cne $expected.path -or $record.schemaVersion -cne $expected.schemaVersion -or
            $record.invocationId -cne $expected.invocationId -or [long] $record.byteLength -ne [long] $expected.byteLength -or
            $record.sha256 -cne $expected.sha256) {
            throw "$Label prerequisite $index changed."
        }
    }
}

function Assert-R4R8CloseoutAssetRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Actual,
        [Parameter(Mandatory)] [psobject[]] $Expected,
        [Parameter(Mandatory)] [string] $IdentityProperty,
        [Parameter(Mandatory)] [string] $ExpectedIdentityProperty,
        [Parameter(Mandatory)] [string] $Label
    )

    if ($Actual.Count -ne $Expected.Count) { throw "$Label asset count changed." }
    foreach ($expectedAsset in $Expected) {
        $identity = [string] $expectedAsset.$ExpectedIdentityProperty
        $matches = @($Actual | Where-Object { [string] $_.$IdentityProperty -ceq $identity })
        if ($matches.Count -ne 1) { throw "$Label asset '$identity' is missing or duplicated." }
        $actualAsset = $matches[0]
        if ([long] $actualAsset.byteLength -ne [long] $expectedAsset.byteLength -or
            $actualAsset.sha256 -cne $expectedAsset.sha256) {
            throw "$Label asset '$identity' identity changed."
        }
    }
}

function Assert-R4R8CloseoutEvidenceGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Contract,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $GateById
    )

    $expectedMap = Get-R4R8CloseoutGateContractMap -Contract $Contract
    foreach ($id in $expectedMap.Keys) {
        if (-not $GateById.Contains($id)) { throw "Evidence gate '$id' is missing." }
        Assert-R4R8CloseoutGateMetadata -Expected $expectedMap[$id] -Actual $GateById[$id]
    }

    $g2 = $GateById['g2']
    $g3 = $GateById['g3']
    $g4 = $GateById['g4']
    $g5 = $GateById['g5']
    $g6 = $GateById['g6']
    $g7Local = $GateById['g7Local']
    $g7Runtime = $GateById['g7Runtime']
    $g8 = $GateById['g8']

    if ($g4.priorEvidence.g2InvocationId -cne $expectedMap['g2'].invocationId -or
        $g4.priorEvidence.g2ReportSha256 -cne $expectedMap['g2'].sha256 -or
        $g4.priorEvidence.g3InvocationId -cne $expectedMap['g3'].invocationId -or
        $g4.priorEvidence.g3ReportSha256 -cne $expectedMap['g3'].sha256) {
        throw 'G4 prerequisite chain changed.'
    }
    Assert-R4R8CloseoutPriorEvidence -Actual $g5.priorEvidence -ExpectedGateId @('g2', 'g3', 'g4') `
        -ContractGateById $expectedMap -Label 'G5'
    Assert-R4R8CloseoutPriorEvidence -Actual $g6.priorEvidence -ExpectedGateId @('g2', 'g3', 'g4', 'g5') `
        -ContractGateById $expectedMap -Label 'G6'
    Assert-R4R8CloseoutPriorEvidence -Actual $g7Local.priorEvidence -ExpectedGateId @('g6') `
        -ContractGateById $expectedMap -Label 'G7 local'
    Assert-R4R8CloseoutPriorEvidence -Actual $g7Runtime.priorEvidence -ExpectedGateId @('g6', 'g7Local') `
        -ContractGateById $expectedMap -Label 'G7 runtime'
    Assert-R4R8CloseoutPriorEvidence -Actual $g8.priorEvidence -ExpectedGateId @('g7Local', 'g7Runtime') `
        -ContractGateById $expectedMap -Label 'G8'

    Assert-R4R8CloseoutClaims -Claims $g6.claims -Label 'G6' -RequiredTrue @(
        'localPublished', 'officialG5ProviderBytesInstalled', 'sameSignerCrossApkBoundaryVerified',
        'crossApkBinderVerified', 'canonicalPfdTransactionVerified', 'realR8Executed',
        'canonicalFiveArtifactBundleVerified', 'verifiedCacheHit', 'postR8DexRuntimeExecuted',
        'pfdLifecycleVerified', 'hostileInputVerified', 'busyAndCancellationVerified',
        'processDeathVerified', 'authenticatedRebindVerified', 'api25Verified', 'api28Verified',
        'physicalDeviceVerified', 'deviceVerified'
    ) -RequiredFalse @('remotePublished', 'jniLinked')
    if ([int] $g6.tests.tests -ne 9 -or [int] $g6.tests.structuredReceipts -ne 9 -or
        [int] $g6.tests.failures -ne 0 -or [int] $g6.tests.errors -ne 0 -or [int] $g6.tests.skipped -ne 0 -or
        [int] $g6.matrix.physicalDevices -ne 1 -or [int] $g6.matrix.avds -ne 2 -or
        (@($g6.matrix.sdkLevels | ForEach-Object { [int] $_ }) -join ',') -cne '25,28') {
        throw 'G6 acceptance matrix or test totals changed.'
    }

    Assert-R4R8CloseoutClaims -Claims $g7Local.claims -Label 'G7 local' -RequiredTrue @(
        'localPublished', 'signedApkVerified', 'sameEnvironmentReproducible', 'platformLibraryFixPackaged'
    ) -RequiredFalse @('remotePublished', 'deviceVerified', 'retraceExecuted', 'jniLinked')
    Assert-R4R8CloseoutClaims -Claims $g7Runtime.claims -Label 'G7 runtime' -RequiredTrue @(
        'localPublished', 'officialLocal5ProviderBytesInstalled', 'crossApkBinderVerified',
        'canonicalFiveArtifactsVerified', 'artExecuted', 'reflectionExecuted', 'dynamicNameExecuted',
        'serializationExecuted', 'publicEntryExecuted', 'jniLinked', 'retraceExecuted',
        'mappingHashVerified', 'api25CliVerified', 'api28CommandVerified', 'api37MinApi36Verified',
        'pageSize16KiBVerified', 'physicalDeviceVerified', 'deviceVerified'
    ) -RequiredFalse @('remotePublished')
    if ([int] $g7Runtime.tests.tests -ne 3 -or [int] $g7Runtime.tests.structuredReceipts -ne 3 -or
        [int] $g7Runtime.tests.retraceExecutions -ne 3 -or [int] $g7Runtime.tests.failures -ne 0 -or
        [int] $g7Runtime.tests.errors -ne 0 -or [int] $g7Runtime.tests.skipped -ne 0 -or
        [int] $g7Runtime.matrix.physicalDevices -ne 1 -or [int] $g7Runtime.matrix.avds -ne 2 -or
        (@($g7Runtime.matrix.sdkLevels | ForEach-Object { [int] $_ }) -join ',') -cne '25,28,37' -or
        -not [bool] $g7Runtime.matrix.includes16KiBPageDevice) {
        throw 'G7 ART/JNI/Retrace matrix or test totals changed.'
    }

    Assert-R4R8CloseoutClaims -Claims $g8.claims -Label 'G8' -RequiredTrue @(
        'localPublished', 'remotePublished', 'sourcePushed', 'releaseAssetsPublished',
        'releaseAssetsRedownloadedAndRehashed'
    ) -RequiredFalse @('publicPublished')
    if ($g8.claims.remoteVisibility -cne 'PRIVATE' -or
        $g8.repository.nameWithOwner -cne $Contract.r8Repository.nameWithOwner -or
        [long] $g8.repository.repositoryId -ne [long] $Contract.github.repositoryId -or
        $g8.repository.visibility -cne 'PRIVATE' -or $g8.repository.private -isnot [bool] -or
        -not [bool] $g8.repository.private -or
        $g8.repository.defaultBranch -cne $Contract.r8Repository.defaultBranch -or
        $g8.repository.branchHeadAtVerification -cne $Contract.annotatedTag.target) {
        throw 'G8 private repository evidence changed.'
    }
    if ($g8.privacyMigration.targetNoreplyIdentity -cne $Contract.r8Repository.identityEmail -or
        -not [bool] $g8.privacyMigration.authorAndCommitterIdentityVerified -or
        -not [bool] $g8.privacyMigration.annotatedTaggerIdentityVerified -or
        [bool] $g8.privacyMigration.legacyCommitIdsReachable) {
        throw 'G8 privacy migration evidence changed.'
    }
    if ([long] $g8.release.releaseId -ne [long] $Contract.github.releaseId -or
        $g8.release.tag -cne $Contract.annotatedTag.name -or
        $g8.release.taggedCommit -cne $Contract.annotatedTag.target -or
        $g8.release.draft -isnot [bool] -or [bool] $g8.release.draft -or
        $g8.release.prerelease -isnot [bool] -or -not [bool] $g8.release.prerelease -or
        -not [bool] $g8.release.allAssetsRedownloaded) {
        throw 'G8 private prerelease evidence changed.'
    }
    if ([bool] $g8.operations.githubMutationPerformedByVerifier -or [bool] $g8.operations.adbInvoked -or
        [bool] $g8.operations.signingMaterialRead -or [bool] $g8.operations.remoteMavenPublished) {
        throw 'G8 verifier operation boundary changed.'
    }

    $expectedAssets = @($Contract.releaseAssets)
    Assert-R4R8CloseoutAssetRecords -Actual @($g8.release.assets) -Expected $expectedAssets `
        -IdentityProperty 'name' -ExpectedIdentityProperty 'name' -Label 'G8 remote release'
    $g8Local = @($g8.localSource.files) + @($g8.localSource.checksumAsset)
    Assert-R4R8CloseoutAssetRecords -Actual $g8Local -Expected $expectedAssets `
        -IdentityProperty 'path' -ExpectedIdentityProperty 'localPath' -Label 'G8 local source'
    Assert-R4R8CloseoutAssetRecords -Actual @($g7Local.release.files) -Expected @($expectedAssets[0..3]) `
        -IdentityProperty 'path' -ExpectedIdentityProperty 'localPath' -Label 'G7 local release'

    $protocolAsset = @($expectedAssets | Where-Object { $_.name -ceq 'protocol-wire-api-0.1.0.aar' })[0]
    $r8ApiAsset = @($expectedAssets | Where-Object { $_.name -ceq 'r8-compiler-api-0.1.0.aar' })[0]
    if (@($g2.contractAars).Count -ne 2 -or
        @($g2.contractAars | Where-Object {
            $_.path -ceq 'plugin-api/r8-compiler-api/releases/0.1.0/protocol-wire-api-0.1.0.aar' -and
            [long] $_.byteLength -eq [long] $protocolAsset.byteLength -and $_.sha256 -ceq $protocolAsset.sha256
        }).Count -ne 1 -or
        @($g2.contractAars | Where-Object {
            $_.path -ceq 'plugin-api/r8-compiler-api/releases/0.1.0/r8-compiler-api-0.1.0.aar' -and
            [long] $_.byteLength -eq [long] $r8ApiAsset.byteLength -and $_.sha256 -ceq $r8ApiAsset.sha256
        }).Count -ne 1 -or
        [long] $g3.contract.r8ApiAarByteLength -ne [long] $Contract.host.r8ApiAarByteLength -or
        $g3.contract.r8ApiAarSha256 -cne $Contract.host.r8ApiAarSha256) {
        throw 'Frozen G2/G3 API contract identity changed.'
    }
}

function Get-R4R8CloseoutHostRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $GateById)

    $records = [System.Collections.Generic.List[object]]::new()
    $g3 = $GateById['g3']
    foreach ($group in @($g3.hostProductionSources, $g3.hostTestSources, $g3.hostIntegrationFiles)) {
        foreach ($record in @($group)) { $records.Add($record) }
    }
    $records.Add($g3.hostDesign)
    foreach ($record in @($GateById['g6'].hostAndroidTestSources)) {
        if (-not ([string] $record.path).StartsWith('AutoJs6/', [StringComparison]::Ordinal)) {
            throw 'G6 host source path lost its AutoJs6 repository prefix.'
        }
        $records.Add([pscustomobject]@{
            path = ([string] $record.path).Substring('AutoJs6/'.Length)
            byteLength = [long] $record.byteLength
            sha256 = [string] $record.sha256
        })
    }
    $g7Record = $GateById['g7Runtime'].hostAndroidTestSource
    if (-not ([string] $g7Record.path).StartsWith('AutoJs6/', [StringComparison]::Ordinal)) {
        throw 'G7 host source path lost its AutoJs6 repository prefix.'
    }
    $records.Add([pscustomobject]@{
        path = ([string] $g7Record.path).Substring('AutoJs6/'.Length)
        byteLength = [long] $g7Record.byteLength
        sha256 = [string] $g7Record.sha256
    })
    $ordered = @($records | Sort-Object path -CaseSensitive)
    if ($ordered.Count -ne 57 -or @($ordered.path | Sort-Object -Unique -CaseSensitive).Count -ne 57) {
        throw 'Host evidence must bind exactly 57 unique files.'
    }
    return $ordered
}

function Test-R4R8CloseoutGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $R8RepositoryRoot,
        [Parameter(Mandatory)] [string] $HostRepositoryRoot,
        [Parameter(Mandatory)] [psobject] $Contract
    )

    $r8Root = Get-R4R8CloseoutCanonicalPath -Path $R8RepositoryRoot
    $hostRoot = Get-R4R8CloseoutCanonicalPath -Path $HostRepositoryRoot
    foreach ($root in @($r8Root, $hostRoot)) {
        if (-not [IO.Directory]::Exists($root)) { throw 'Required sibling repository does not exist.' }
    }

    $expectedGateMap = Get-R4R8CloseoutGateContractMap -Contract $Contract
    $gateMap = [ordered]@{}
    foreach ($id in $expectedGateMap.Keys) {
        $record = $expectedGateMap[$id]
        $path = Resolve-R4R8CloseoutRelativeFile -Root $r8Root -RelativePath $record.path -Label "gate $id"
        Assert-R4R8CloseoutFileIdentity -Path $path -ByteLength ([long] $record.byteLength) `
            -Sha256 ([string] $record.sha256) -Label "gate $id"
        $gateMap[$id] = Read-R4R8CloseoutJson -Path $path
    }
    Assert-R4R8CloseoutEvidenceGraph -Contract $Contract -GateById $gateMap

    $gitStatus = Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'status', '--porcelain=v1', '--untracked-files=all')
    if (-not [string]::IsNullOrWhiteSpace($gitStatus.stdout)) { throw 'R8 repository worktree is not clean.' }
    $head = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-parse', 'HEAD')).stdout.Trim()
    $tree = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-parse', 'HEAD^{tree}')).stdout.Trim()
    $trackingHead = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-parse', 'refs/remotes/origin/master')).stdout.Trim()
    $branch = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'symbolic-ref', '--short', 'HEAD')).stdout.Trim()
    $origin = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'remote', 'get-url', 'origin')).stdout.Trim()
    $commitCount = [int] (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-list', '--count', '--all')).stdout.Trim()
    if ($head -cne $Contract.r8Repository.head -or $tree -cne $Contract.r8Repository.tree -or
        $trackingHead -cne $head -or $branch -cne $Contract.r8Repository.defaultBranch -or
        $origin -cne $Contract.r8Repository.originUrl -or
        $commitCount -ne [int] $Contract.r8Repository.reachableCommitCount) {
        throw 'R8 local/remote-tracking repository identity changed.'
    }

    $identityLog = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'log', '--all', '--format=%H%x00%an%x00%ae%x00%cn%x00%ce')).stdout
    $identityLines = @($identityLog -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($identityLines.Count -ne $commitCount) { throw 'Reachable R8 commit enumeration changed.' }
    foreach ($line in $identityLines) {
        $fields = @($line.Split([char] 0))
        if ($fields.Count -ne 5 -or $fields[0] -cnotmatch $script:CommitPattern -or
            $fields[1] -cne $Contract.r8Repository.identityName -or
            $fields[2] -cne $Contract.r8Repository.identityEmail -or
            $fields[3] -cne $Contract.r8Repository.identityName -or
            $fields[4] -cne $Contract.r8Repository.identityEmail) {
            throw 'A reachable R8 commit is not privacy-normalized.'
        }
    }

    $tagRef = "refs/tags/$($Contract.annotatedTag.name)"
    $tagObject = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-parse', $tagRef)).stdout.Trim()
    $tagType = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'cat-file', '-t', $tagObject)).stdout.Trim()
    $tagTarget = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'rev-parse', "$tagRef^{}")).stdout.Trim()
    $tagText = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $r8Root `
        -ArgumentList @('-C', $r8Root, 'cat-file', '-p', $tagObject)).stdout
    $taggerMatch = [regex]::Match($tagText, '(?m)^tagger (.+) <([^>]+)> [0-9]+ [+-][0-9]{4}\r?$')
    if ($tagObject -cne $Contract.annotatedTag.object -or $tagType -cne 'tag' -or
        $tagTarget -cne $Contract.annotatedTag.target -or -not $taggerMatch.Success -or
        $taggerMatch.Groups[1].Value -cne $Contract.annotatedTag.taggerName -or
        $taggerMatch.Groups[2].Value -cne $Contract.annotatedTag.taggerEmail) {
        throw 'Annotated R8 release tag identity changed.'
    }

    foreach ($asset in @($Contract.releaseAssets)) {
        $assetPath = Resolve-R4R8CloseoutRelativeFile -Root $r8Root -RelativePath $asset.localPath `
            -Label "release asset $($asset.name)"
        Assert-R4R8CloseoutFileIdentity -Path $assetPath -ByteLength ([long] $asset.byteLength) `
            -Sha256 ([string] $asset.sha256) -Label "release asset $($asset.name)"
    }

    $hostHead = (Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $hostRoot `
        -ArgumentList @('-C', $hostRoot, 'rev-parse', 'HEAD')).stdout.Trim()
    if ($hostHead -cnotmatch $script:CommitPattern) { throw 'Host HEAD is invalid.' }
    Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $hostRoot `
        -ArgumentList @('-C', $hostRoot, 'merge-base', '--is-ancestor', $Contract.host.integrationCommit, 'HEAD') | Out-Null
    $hostRecords = Get-R4R8CloseoutHostRecords -GateById $gateMap
    $hostPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $hostRecords) {
        $path = Resolve-R4R8CloseoutRelativeFile -Root $hostRoot -RelativePath $record.path `
            -Label "host evidence $($record.path)"
        Assert-R4R8CloseoutFileIdentity -Path $path -ByteLength ([long] $record.byteLength) `
            -Sha256 ([string] $record.sha256) -Label "host evidence $($record.path)"
        $hostPaths.Add([string] $record.path)
    }
    $hostDiffArguments = @('-C', $hostRoot, 'diff', '--quiet', "$($Contract.host.integrationCommit)..HEAD", '--') + @($hostPaths)
    Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $hostRoot -ArgumentList $hostDiffArguments | Out-Null
    $hostStatusArguments = @('-C', $hostRoot, 'status', '--porcelain=v1', '--untracked-files=all', '--') + @($hostPaths)
    $hostStatus = Invoke-R4R8CloseoutProcess -FilePath 'git' -WorkingDirectory $hostRoot -ArgumentList $hostStatusArguments
    if (-not [string]::IsNullOrWhiteSpace($hostStatus.stdout)) { throw 'Host R8 evidence paths have working-tree changes.' }
    $hostAarPath = Resolve-R4R8CloseoutRelativeFile -Root $hostRoot -RelativePath $Contract.host.r8ApiAarPath `
        -Label 'host frozen R8 API AAR'
    Assert-R4R8CloseoutFileIdentity -Path $hostAarPath -ByteLength ([long] $Contract.host.r8ApiAarByteLength) `
        -Sha256 ([string] $Contract.host.r8ApiAarSha256) -Label 'host frozen R8 API AAR'

    $nameWithOwner = [string] $Contract.r8Repository.nameWithOwner
    $repositoryRemote = Read-R4R8CloseoutJsonText -Json ((Invoke-R4R8CloseoutProcess -FilePath 'gh' `
        -WorkingDirectory $r8Root -ArgumentList @('api', "repos/$nameWithOwner")).stdout) -Label 'GitHub repository response'
    $branchRemote = Read-R4R8CloseoutJsonText -Json ((Invoke-R4R8CloseoutProcess -FilePath 'gh' `
        -WorkingDirectory $r8Root -ArgumentList @('api', "repos/$nameWithOwner/git/ref/heads/$($Contract.r8Repository.defaultBranch)")).stdout) -Label 'GitHub branch response'
    $tagRemote = Read-R4R8CloseoutJsonText -Json ((Invoke-R4R8CloseoutProcess -FilePath 'gh' `
        -WorkingDirectory $r8Root -ArgumentList @('api', "repos/$nameWithOwner/git/ref/tags/$($Contract.annotatedTag.name)")).stdout) -Label 'GitHub tag response'
    $releaseRemote = Read-R4R8CloseoutJsonText -Json ((Invoke-R4R8CloseoutProcess -FilePath 'gh' `
        -WorkingDirectory $r8Root -ArgumentList @('api', "repos/$nameWithOwner/releases/tags/$($Contract.annotatedTag.name)")).stdout) -Label 'GitHub release response'

    if ([long] $repositoryRemote.id -ne [long] $Contract.github.repositoryId -or
        $repositoryRemote.full_name -cne $nameWithOwner -or $repositoryRemote.private -isnot [bool] -or
        -not [bool] $repositoryRemote.private -or ([string] $repositoryRemote.visibility).ToUpperInvariant() -cne $Contract.github.visibility -or
        $repositoryRemote.default_branch -cne $Contract.r8Repository.defaultBranch) {
        throw 'Live GitHub repository is not the pinned Private repository.'
    }
    if ($branchRemote.ref -cne "refs/heads/$($Contract.r8Repository.defaultBranch)" -or
        $branchRemote.object.type -cne 'commit' -or $branchRemote.object.sha -cne $Contract.r8Repository.head) {
        throw 'Live GitHub default branch identity changed.'
    }
    if ($tagRemote.ref -cne $tagRef -or $tagRemote.object.type -cne 'tag' -or
        $tagRemote.object.sha -cne $Contract.annotatedTag.object) {
        throw 'Live GitHub annotated tag identity changed.'
    }
    if ([long] $releaseRemote.id -ne [long] $Contract.github.releaseId -or
        $releaseRemote.tag_name -cne $Contract.annotatedTag.name -or
        $releaseRemote.draft -isnot [bool] -or [bool] $releaseRemote.draft -or
        $releaseRemote.prerelease -isnot [bool] -or -not [bool] $releaseRemote.prerelease) {
        throw 'Live GitHub prerelease identity changed.'
    }
    $remoteAssets = @($releaseRemote.assets | ForEach-Object {
        [pscustomobject]@{
            name = [string] $_.name
            byteLength = [long] $_.size
            sha256 = if ([string] $_.digest -match '^sha256:([0-9a-f]{64})$') { $Matches[1] } else { '' }
        }
    })
    Assert-R4R8CloseoutAssetRecords -Actual $remoteAssets -Expected @($Contract.releaseAssets) `
        -IdentityProperty 'name' -ExpectedIdentityProperty 'name' -Label 'live GitHub release'

    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        invocationId = [guid]::NewGuid().ToString()
        passed = $true
        evidenceBoundary = $script:EvidenceBoundary
        r8Repository = [pscustomobject][ordered]@{
            head = $head
            tree = $tree
            branch = $branch
            reachableCommitCount = $commitCount
            authorAndCommitterIdentityVerified = $true
            annotatedTagVerified = $true
            clean = $true
            originTrackingSynchronized = $true
        }
        host = [pscustomobject][ordered]@{
            integrationCommit = [string] $Contract.host.integrationCommit
            currentHead = $hostHead
            integrationCommitIsAncestor = $true
            frozenR8ApiAarVerified = $true
            evidenceFileCount = $hostRecords.Count
            evidencePathsUnchangedAndClean = $true
        }
        evidence = [pscustomobject][ordered]@{
            gateCount = $expectedGateMap.Count
            gateSha256 = @($Contract.gates | ForEach-Object { [string] $_.sha256 })
            prerequisiteChainVerified = $true
            g6Tests = 9
            g6StructuredReceipts = 9
            g7RuntimeTests = 3
            g7RetraceExecutions = 3
        }
        release = [pscustomobject][ordered]@{
            tag = [string] $Contract.annotatedTag.name
            releaseId = [long] $Contract.github.releaseId
            assetCount = @($Contract.releaseAssets).Count
            localAssetsVerified = $true
            remoteAssetDigestsVerified = $true
            draft = $false
            prerelease = $true
        }
        claims = [pscustomobject][ordered]@{
            independentR8ProviderIdentity = $true
            explicitHostSelectionAndNoFallback = $true
            crossApkBinderAndPfdVerified = $true
            deviceMatrixVerified = $true
            artJniAndRetraceVerified = $true
            localPublished = $true
            remotePublished = $true
            remoteVisibility = 'PRIVATE'
            publicPublished = $false
        }
        operations = [pscustomobject][ordered]@{
            githubReadOnlyVerified = $true
            githubMutationPerformed = $false
            adbOrDeviceTaskPerformed = $false
            signingMaterialRead = $false
            dexRemoteMutationPerformed = $false
        }
        summary = 'Independent R8 provider G2-G8, host integration, device/ART/JNI/Retrace acceptance, and exact Private prerelease are closed without public or DEX-remote mutation.'
    }
}

function Read-R4R8CloseoutJsonText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Json,
        [Parameter(Mandatory)] [string] $Label
    )

    if ([string]::IsNullOrWhiteSpace($Json)) { throw "$Label is empty." }
    try {
        return $Json | ConvertFrom-Json -Depth 100 -NoEnumerate -DateKind String
    } catch {
        throw "$Label is invalid JSON: $($_.Exception.Message)"
    }
}

function Write-R4R8CloseoutAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Json
    )

    $resolved = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'Output path has no parent directory.' }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
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

Export-ModuleMember -Function @(
    'Assert-R4R8CloseoutEvidenceGraph',
    'Get-R4R8CloseoutCanonicalPath',
    'Get-R4R8CloseoutSha256File',
    'Read-R4R8CloseoutContract',
    'Read-R4R8CloseoutJson',
    'Test-R4R8CloseoutGate',
    'Write-R4R8CloseoutAtomicJson'
)
