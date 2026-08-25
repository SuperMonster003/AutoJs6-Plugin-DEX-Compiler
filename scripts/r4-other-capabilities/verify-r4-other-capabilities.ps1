[CmdletBinding()]
param(
    [string] $RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))),

    [string] $ContractPath = (Join-Path $PSScriptRoot 'r4-other-capabilities-contract.json'),

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Establish a dependency-free, path-safe failure output before contract or module loading. This is
# deliberately duplicated at the bootstrap boundary so module damage cannot preserve a stale PASS.
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

$modulePath = Join-Path $PSScriptRoot 'R4OtherCapabilitiesGate.psm1'
$rootFull = [IO.Path]::GetFullPath($RepositoryRoot)
$protectedPaths = @(
    $ContractPath,
    $modulePath,
    $PSCommandPath,
    (Join-Path $rootFull 'app/build.gradle.kts'),
    (Join-Path $rootFull 'app/src/main/AndroidManifest.xml'),
    (Join-Path $rootFull 'libs/dex-compiler-api.aar'),
    (Join-Path $rootFull 'ROADMAP.md'),
    (Join-Path $rootFull 'README.md'),
    (Join-Path $rootFull 'build.gradle.kts'),
    (Join-Path $rootFull 'settings.gradle.kts')
)
$protectedSubtrees = @(
    (Join-Path $rootFull '.git'),
    (Join-Path $rootFull 'app/src/main'),
    (Join-Path $rootFull 'gradle'),
    (Join-Path $rootFull 'libs'),
    $PSScriptRoot
)
$resolvedOutput = $null
$safeOutputEstablished = $false

try {
    $candidate = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Join-Path $rootFull 'app/build/reports/other-capabilities/gate.json'
    } elseif ([IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    } else {
        Join-Path $rootFull $OutputPath
    }
    $resolvedOutput = Resolve-BootstrapSafeOutputPath -Candidate $candidate `
        -ProtectedPath $protectedPaths -ProtectedSubtreePath $protectedSubtrees
    $safeOutputEstablished = $true

    Import-Module $modulePath -Force -ErrorAction Stop
    $contract = Read-R4OtherCapabilitiesContract -Path $ContractPath
    $result = Test-R4OtherCapabilitiesBoundary -RepositoryRoot $rootFull -Contract $contract
    $json = $result | ConvertTo-Json -Depth 30
    Write-R4OtherCapabilitiesAtomicJson -Path $resolvedOutput -Json $json
    $json
    if (-not [bool] $result.passed) { exit 1 }
} catch {
    $safeMessage = ConvertTo-SafeFailureMessage -Message $_.Exception.Message `
        -PrivateRoot @($rootFull, $PSScriptRoot, [IO.Path]::GetTempPath())
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.other-capabilities-gate/v1'
        invocationId = [guid]::NewGuid().ToString()
        contractId = 'r4.3-source-and-packaging-responsibility-boundary'
        passed = $false
        evidenceBoundary = 'STATIC_PRODUCTION_CAPABILITY_AND_BUILD_LAYER_SEPARATION'
        claims = [pscustomobject][ordered]@{
            sourceCompilationImplementedInPlugin = $false
            sourceCompilationMustProduceValidatedJarFirst = $false
            aarResourceMergeImplementedInPlugin = $false
            apkPackagingImplementedInPlugin = $false
            apkSigningImplementedInPlugin = $false
            apkInstallationImplementedInPlugin = $false
            packagingSigningAndInstallationRemainBuildOrHostResponsibilities = $false
        }
        operations = [pscustomobject][ordered]@{
            sourceCompilationPerformed = $false
            packagingOrSigningPerformed = $false
            adbOrInstallationPerformed = $false
            repositoryMutationPerformed = $false
        }
        reasons = @($safeMessage)
        summary = 'R4.3 source/compiler and packaging responsibility boundary could not complete safely.'
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
