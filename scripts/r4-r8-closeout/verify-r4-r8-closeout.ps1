[CmdletBinding()]
param(
    [string] $DexRepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))),

    [string] $R8RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../AutoJs6-Plugin-R8-Compiler'))),

    [string] $HostRepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../AutoJs6'))),

    [string] $ContractPath = (Join-Path $PSScriptRoot 'r4-r8-closeout-contract.json'),

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This dependency-free bootstrap establishes a safe failure-report location before parsing the
# contract or importing the module. A damaged input therefore cannot leave a stale PASS behind.
function Get-BootstrapCanonicalPath {
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
                    if ($null -eq $target) { throw 'Unable to resolve a reparse point.' }
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

function Resolve-BootstrapSafeOutputPath {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string[]] $ProtectedPath,
        [Parameter(Mandatory)] [string[]] $ProtectedSubtreePath
    )

    $resolvedOutput = Get-BootstrapCanonicalPath -Path $Candidate
    if (Test-Path -LiteralPath $resolvedOutput -PathType Container) {
        throw 'OutputPath must be a file path, not a directory.'
    }
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    foreach ($protected in $ProtectedPath) {
        $resolvedProtected = Get-BootstrapCanonicalPath -Path $protected
        if ([string]::Equals($resolvedOutput, $resolvedProtected, $comparison)) {
            throw 'OutputPath aliases protected input path.'
        }
        if ((Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -and
            (Test-Path -LiteralPath $resolvedProtected -PathType Leaf)) {
            $left = Get-Item -LiteralPath $resolvedOutput
            $right = Get-Item -LiteralPath $resolvedProtected
            if ($left.Length -eq $right.Length -and
                (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash -ceq
                    (Get-FileHash -LiteralPath $resolvedProtected -Algorithm SHA256).Hash) {
                throw 'OutputPath may alias protected input content.'
            }
        }
    }
    foreach ($subtree in $ProtectedSubtreePath) {
        $resolvedSubtree = Get-BootstrapCanonicalPath -Path $subtree
        $prefix = $resolvedSubtree.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ) + [IO.Path]::DirectorySeparatorChar
        if ([string]::Equals($resolvedOutput, $resolvedSubtree, $comparison) -or
            $resolvedOutput.StartsWith($prefix, $comparison)) {
            throw 'OutputPath is inside a protected input subtree.'
        }
    }
    return $resolvedOutput
}

function Write-BootstrapAtomicJson {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Json
    )

    $resolved = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'OutputPath has no parent directory.' }
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

function ConvertTo-SafeFailureMessage {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message,
        [Parameter(Mandatory)] [string[]] $PrivateRoot
    )

    $safe = $Message
    foreach ($root in @($PrivateRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object Length -Descending -Unique)) {
        $safe = [regex]::Replace(
            $safe,
            [regex]::Escape([IO.Path]::GetFullPath($root)),
            '<private-path>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    return $safe
}

$modulePath = Join-Path $PSScriptRoot 'R4R8CloseoutGate.psm1'
$dexRootFull = [IO.Path]::GetFullPath($DexRepositoryRoot)
$r8RootFull = [IO.Path]::GetFullPath($R8RepositoryRoot)
$hostRootFull = [IO.Path]::GetFullPath($HostRepositoryRoot)
$fixedR8Inputs = @(
    'build/reports/r42-g2/provider-gate.json',
    'build/reports/r42-g3/host-control-plane-gate.json',
    'build/reports/r42-g4/compatibility-corpus-gate.json',
    'build/reports/r42-g5/local-release-gate.json',
    'build/reports/r42-g6/device-acceptance-gate.json',
    'build/reports/r42-g7/local-release-gate.json',
    'build/reports/r42-g7/art-jni-retrace-gate.json',
    'build/reports/r42-g8/private-remote-release-gate.json',
    'releases/provider/0.1.0-provider-dev/local.5/autojs6-r8-compiler-provider-0.1.0-provider-dev-signed.apk',
    'releases/provider/0.1.0-provider-dev/local.5/protocol-wire-api-0.1.0.aar',
    'releases/provider/0.1.0-provider-dev/local.5/r8-compiler-api-0.1.0.aar',
    'releases/provider/0.1.0-provider-dev/local.5/release-manifest.json',
    'build/reports/r42-g8/autojs6-r8-compiler-provider-0.1.0-provider-dev-private.1-SHA256SUMS.txt'
)
$protectedPaths = @(
    $ContractPath,
    $modulePath,
    $PSCommandPath,
    (Join-Path $dexRootFull 'ROADMAP.md'),
    (Join-Path $dexRootFull 'README.md'),
    (Join-Path $dexRootFull 'build.gradle.kts'),
    (Join-Path $dexRootFull 'settings.gradle.kts'),
    (Join-Path $hostRootFull 'libs/r8-compiler-api-0_1_0/r8-compiler-api-0.1.0.aar')
) + @($fixedR8Inputs | ForEach-Object { Join-Path $r8RootFull $_ })
$protectedSubtrees = @(
    (Join-Path $dexRootFull '.git'),
    (Join-Path $dexRootFull 'app/src'),
    (Join-Path $dexRootFull 'gradle'),
    $PSScriptRoot,
    $r8RootFull,
    $hostRootFull
)
$resolvedOutput = $null
$safeOutputEstablished = $false

try {
    $candidate = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Join-Path $dexRootFull 'app/build/reports/r8-closeout/gate.json'
    } elseif ([IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    } else {
        Join-Path $dexRootFull $OutputPath
    }
    $resolvedOutput = Resolve-BootstrapSafeOutputPath -Candidate $candidate `
        -ProtectedPath $protectedPaths -ProtectedSubtreePath $protectedSubtrees
    $safeOutputEstablished = $true

    Import-Module $modulePath -Force -ErrorAction Stop
    $contract = Read-R4R8CloseoutContract -Path $ContractPath
    $result = Test-R4R8CloseoutGate -R8RepositoryRoot $r8RootFull `
        -HostRepositoryRoot $hostRootFull -Contract $contract
    $json = $result | ConvertTo-Json -Depth 30
    Write-R4R8CloseoutAtomicJson -Path $resolvedOutput -Json $json
    $json
    if (-not [bool] $result.passed) { exit 1 }
} catch {
    $safeMessage = ConvertTo-SafeFailureMessage -Message $_.Exception.Message `
        -PrivateRoot @($dexRootFull, $r8RootFull, $hostRootFull, $PSScriptRoot, [IO.Path]::GetTempPath())
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.r8-closeout-gate/v1'
        invocationId = [guid]::NewGuid().ToString()
        passed = $false
        evidenceBoundary = 'INDEPENDENT_R8_PRIVATE_RELEASE_AND_HOST_ACCEPTANCE_CLOSEOUT'
        claims = [pscustomobject][ordered]@{
            independentR8ProviderIdentity = $false
            crossApkBinderAndPfdVerified = $false
            deviceMatrixVerified = $false
            artJniAndRetraceVerified = $false
            remotePublished = $false
            remoteVisibility = 'UNVERIFIED'
            publicPublished = $false
        }
        operations = [pscustomobject][ordered]@{
            githubMutationPerformed = $false
            adbOrDeviceTaskPerformed = $false
            signingMaterialRead = $false
            dexRemoteMutationPerformed = $false
        }
        reasons = @($safeMessage)
        summary = 'R4.2 R8 cross-repository closeout could not complete safely.'
    }
    $failureJson = $failure | ConvertTo-Json -Depth 15
    if ($safeOutputEstablished -and $null -ne $resolvedOutput) {
        try {
            Write-BootstrapAtomicJson -Path $resolvedOutput -Json $failureJson
        } catch {
            $failure | Add-Member -NotePropertyName persistenceError -NotePropertyValue 'Atomic failure report persistence failed.'
            $failureJson = $failure | ConvertTo-Json -Depth 15
        }
    }
    $failureJson
    exit 1
}
