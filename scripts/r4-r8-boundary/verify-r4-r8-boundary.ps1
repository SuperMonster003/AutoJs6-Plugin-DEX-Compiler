[CmdletBinding()]
param(
    [string] $RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))),

    [string] $ContractPath = (Join-Path $PSScriptRoot 'r4-r8-boundary-contract.json'),

    [string] $ContractSchemaPath = (Join-Path $PSScriptRoot 'r4-r8-boundary-contract.schema.json'),

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This bootstrap deliberately has no module dependency. It establishes the only safe failure-output
# path before the contract, schema, or module is parsed, so a broken gate input cannot leave stale PASS.
function Get-BootstrapCanonicalPath {
    param([Parameter(Mandatory)] [string] $Path)
    $pathToResolve = [IO.Path]::GetFullPath($Path)
    for ($pass = 0; $pass -lt 64; $pass++) {
        $root = [IO.Path]::GetPathRoot($pathToResolve)
        if ([string]::IsNullOrWhiteSpace($root)) { throw "Path has no filesystem root." }
        [char[]] $separators = @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $segments = @($pathToResolve.Substring($root.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries))
        $current = $root
        $linkResolved = $false
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $candidate = [IO.Path]::Combine($current, $segments[$index])
            if (Test-Path -LiteralPath $candidate) {
                $item = Get-Item -LiteralPath $candidate -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $target = $item.ResolveLinkTarget($true)
                    if ($null -eq $target) { throw "Unable to resolve a reparse point in path." }
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
    foreach ($inputPath in $ProtectedPath) {
        $resolvedInput = Get-BootstrapCanonicalPath -Path $inputPath
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
    foreach ($subtreePath in $ProtectedSubtreePath) {
        $resolvedSubtree = Get-BootstrapCanonicalPath -Path $subtreePath
        $subtreePrefix = $resolvedSubtree.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ) + [IO.Path]::DirectorySeparatorChar
        if (
            [string]::Equals($resolvedOutput, $resolvedSubtree, $comparison) -or
            $resolvedOutput.StartsWith($subtreePrefix, $comparison)
        ) {
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
    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'OutputPath has no parent directory.' }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = [IO.Path]::Combine(
        $parent,
        ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path), [guid]::NewGuid().ToString('N'))
    )
    try {
        [IO.File]::WriteAllText($temporary, $Json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, [IO.Path]::GetFullPath($Path), $true)
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
    $orderedRoots = @($PrivateRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object Length -Descending -Unique)
    foreach ($privatePath in $orderedRoots) {
        $safe = [regex]::Replace(
            $safe,
            [regex]::Escape([IO.Path]::GetFullPath($privatePath)),
            '<private-path>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    return $safe
}

$modulePath = Join-Path $PSScriptRoot 'R4R8BoundaryGate.psm1'
$fixedRepositoryInputs = @(
    'app/src/main/AndroidManifest.xml'
    'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/DexCompilerRuntime.kt'
    'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/DexCompilerPluginInfoService.kt'
    'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/D8DexCompilerEngine.kt'
    'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/service/RemoteDexCompileSession.kt'
    'app/build.gradle.kts'
    'libs/dex-compiler-api.aar'
    'README.md'
)
$resolvedOutputPath = $null
$safeOutputEstablished = $false
$repositoryRootFull = [IO.Path]::GetFullPath($RepositoryRoot)

try {
    $outputCandidate = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Join-Path $repositoryRootFull 'app/build/reports/r8-boundary/gate.json'
    } elseif ([IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    } else {
        Join-Path $repositoryRootFull $OutputPath
    }
    $protectedPaths = @(
        $ContractPath
        $ContractSchemaPath
        $modulePath
        $PSCommandPath
    ) + @($fixedRepositoryInputs | ForEach-Object { Join-Path $repositoryRootFull $_ })
    $protectedSubtrees = @(
        (Join-Path $repositoryRootFull 'app/src/main')
        $PSScriptRoot
    )
    $resolvedOutputPath = Resolve-BootstrapSafeOutputPath `
        -Candidate $outputCandidate `
        -ProtectedPath $protectedPaths `
        -ProtectedSubtreePath $protectedSubtrees
    $safeOutputEstablished = $true

    Import-Module $modulePath -Force -ErrorAction Stop
    # The module independently resolves every ancestor link before any output is written.
    $resolvedOutputPath = Resolve-R4R8SafeOutputPath `
        -OutputPath $resolvedOutputPath `
        -ProtectedInputPath $protectedPaths `
        -ProtectedSubtreePath $protectedSubtrees
    $contract = Read-R4R8Contract -ContractPath $ContractPath -SchemaPath $ContractSchemaPath
    $result = Test-R4R8BoundaryGate `
        -RepositoryRoot $repositoryRootFull `
        -ContractPath $ContractPath `
        -ContractSchemaPath $ContractSchemaPath
    $json = $result | ConvertTo-Json -Depth 30
    Write-R4R8AtomicJsonFile -Path $resolvedOutputPath -Json $json
    $json
    if (-not $result.passed) { exit 1 }
} catch {
    $safeMessage = ConvertTo-SafeFailureMessage `
        -Message $_.Exception.Message `
        -PrivateRoot @($repositoryRootFull, $PSScriptRoot, [IO.Path]::GetTempPath())
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.r8-boundary-gate/v1'
        contractId = 'r4.2-g0-d8-r8-separation'
        passed = $false
        evidenceBoundary = 'SOURCE_STATIC_ONLY'
        r8ProviderImplemented = $false
        jvmVerified = $false
        binderVerified = $false
        r8Executed = $false
        deviceVerified = $false
        repositoryRoot = '.'
        checks = @()
        reasons = @($safeMessage)
        summary = 'R4.2-G0 D8/R8 boundary gate could not complete safely.'
    }
    $failureJson = $failure | ConvertTo-Json -Depth 10
    if ($safeOutputEstablished -and $null -ne $resolvedOutputPath) {
        try {
            Write-BootstrapAtomicJson -Path $resolvedOutputPath -Json $failureJson
        } catch {
            $failure | Add-Member -NotePropertyName persistenceError -NotePropertyValue 'Atomic failure report persistence failed.'
            $failureJson = $failure | ConvertTo-Json -Depth 10
        }
    }
    $failureJson
    exit 1
}
