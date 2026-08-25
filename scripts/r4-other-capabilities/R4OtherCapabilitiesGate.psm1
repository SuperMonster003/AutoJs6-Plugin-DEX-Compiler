Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ContractSchemaVersion = 'autojs6.dex.r4.other-capabilities-contract/v1'
$script:GateSchemaVersion = 'autojs6.dex.r4.other-capabilities-gate/v1'
$script:EvidenceBoundary = 'STATIC_PRODUCTION_CAPABILITY_AND_BUILD_LAYER_SEPARATION'
$script:Sha256Pattern = '^[0-9a-f]{64}$'

function Get-R4OtherCapabilitiesSha256Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($Bytes))).ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-R4OtherCapabilitiesSha256File {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not [IO.File]::Exists([IO.Path]::GetFullPath($Path))) { throw 'Required file does not exist.' }
    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($stream))).ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Get-R4OtherCapabilitiesSha256Text {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)

    return Get-R4OtherCapabilitiesSha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Read-R4OtherCapabilitiesJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not [IO.File]::Exists([IO.Path]::GetFullPath($Path))) { throw 'Required JSON input does not exist.' }
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

function Assert-R4OtherCapabilitiesExactProperties {
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

function Assert-R4OtherCapabilitiesSafeRelativePath {
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

function Read-R4OtherCapabilitiesContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $contract = Read-R4OtherCapabilitiesJson -Path $Path
    Assert-R4OtherCapabilitiesExactProperties -Value $contract -Expected @(
        'schemaVersion', 'contractId', 'evidenceBoundary', 'inputs', 'runtimeSurface',
        'manifestBoundary', 'buildLayer', 'apiAar', 'claims'
    ) -Label 'contract'
    if ($contract.schemaVersion -cne $script:ContractSchemaVersion -or
        $contract.contractId -cne 'r4.3-source-and-packaging-responsibility-boundary' -or
        $contract.evidenceBoundary -cne $script:EvidenceBoundary) {
        throw 'Contract identity changed.'
    }

    $inputKeys = @(
        'productionSourceRoot', 'manifest', 'runtime', 'materializer', 'validator',
        'engine', 'appBuild', 'apiAar'
    )
    Assert-R4OtherCapabilitiesExactProperties -Value $contract.inputs -Expected $inputKeys -Label 'contract inputs'
    foreach ($key in $inputKeys) {
        Assert-R4OtherCapabilitiesSafeRelativePath -Path ([string] $contract.inputs.$key) -Label "contract input $key"
    }
    if ($contract.inputs.productionSourceRoot -cne 'app/src/main/java' -or
        $contract.inputs.manifest -cne 'app/src/main/AndroidManifest.xml' -or
        $contract.inputs.appBuild -cne 'app/build.gradle.kts' -or
        $contract.inputs.apiAar -cne 'libs/dex-compiler-api.aar') {
        throw 'Contract primary input paths changed.'
    }

    Assert-R4OtherCapabilitiesExactProperties -Value $contract.runtimeSurface -Expected @(
        'expectedSourceFileCount', 'allowedSourceExtensions', 'requiredSourceEvidence', 'forbiddenPatterns'
    ) -Label 'contract runtimeSurface'
    if ([int] $contract.runtimeSurface.expectedSourceFileCount -ne 20 -or
        (@($contract.runtimeSurface.allowedSourceExtensions) -join ',') -cne '.kt' -or
        @($contract.runtimeSurface.requiredSourceEvidence).Count -ne 9 -or
        @($contract.runtimeSurface.forbiddenPatterns).Count -ne 9) {
        throw 'Contract runtime surface dimensions changed.'
    }
    foreach ($record in @($contract.runtimeSurface.requiredSourceEvidence)) {
        Assert-R4OtherCapabilitiesExactProperties -Value $record -Expected @('pathKey', 'literal') `
            -Label 'contract required source evidence'
        if ($inputKeys -notcontains [string] $record.pathKey -or [string]::IsNullOrWhiteSpace([string] $record.literal)) {
            throw 'Contract required source evidence is invalid.'
        }
    }
    $patternIds = @()
    foreach ($record in @($contract.runtimeSurface.forbiddenPatterns)) {
        Assert-R4OtherCapabilitiesExactProperties -Value $record -Expected @('id', 'regex') `
            -Label 'contract forbidden pattern'
        if ([string]::IsNullOrWhiteSpace([string] $record.id) -or [string]::IsNullOrWhiteSpace([string] $record.regex)) {
            throw 'Contract forbidden pattern is empty.'
        }
        try { [void] [regex]::new([string] $record.regex, [Text.RegularExpressions.RegexOptions]::CultureInvariant) } catch {
            throw "Contract forbidden pattern '$($record.id)' is invalid."
        }
        $patternIds += [string] $record.id
    }
    if (@($patternIds | Sort-Object -Unique -CaseSensitive).Count -ne $patternIds.Count) {
        throw 'Contract forbidden pattern IDs are not unique.'
    }

    Assert-R4OtherCapabilitiesExactProperties -Value $contract.manifestBoundary -Expected @(
        'permissions', 'actions', 'serviceCount'
    ) -Label 'contract manifestBoundary'
    if ((@($contract.manifestBoundary.permissions) -join ',') -cne 'org.autojs.permission.PLUGIN' -or
        (@($contract.manifestBoundary.actions) -join ',') -cne
            'org.autojs.plugin.DEX_COMPILER,org.autojs.plugin.INFO,org.autojs.plugin.action.WAKE' -or
        [int] $contract.manifestBoundary.serviceCount -ne 2) {
        throw 'Contract manifest boundary changed.'
    }

    Assert-R4OtherCapabilitiesExactProperties -Value $contract.buildLayer -Expected @(
        'requiredMarkers', 'forbiddenRuntimeDependencyPatterns'
    ) -Label 'contract buildLayer'
    if (@($contract.buildLayer.requiredMarkers).Count -ne 5 -or
        @($contract.buildLayer.forbiddenRuntimeDependencyPatterns).Count -ne 2) {
        throw 'Contract build-layer marker dimensions changed.'
    }
    foreach ($pattern in @($contract.buildLayer.forbiddenRuntimeDependencyPatterns)) {
        try { [void] [regex]::new([string] $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant) } catch {
            throw 'Contract forbidden dependency pattern is invalid.'
        }
    }

    Assert-R4OtherCapabilitiesExactProperties -Value $contract.apiAar -Expected @(
        'byteLength', 'sha256', 'inputFormats', 'inputRoles', 'outputFormats'
    ) -Label 'contract apiAar'
    if ([long] $contract.apiAar.byteLength -ne 163690 -or
        $contract.apiAar.sha256 -cne '6beea0450017956ec9a5469083142529dc5f893c4e6450848a8a9dd5e1526b7c' -or
        (@($contract.apiAar.inputFormats) -join ',') -cne 'JAR' -or
        (@($contract.apiAar.inputRoles) -join ',') -cne 'PROGRAM,CLASSPATH' -or
        (@($contract.apiAar.outputFormats) -join ',') -cne 'DEX_ZIP') {
        throw 'Contract API AAR boundary changed.'
    }

    Assert-R4OtherCapabilitiesExactProperties -Value $contract.claims -Expected @(
        'sourceCompilationImplementedInPlugin', 'validatedJarRequiredBeforeDex',
        'aarResourceMergeImplementedInPlugin', 'apkPackagingImplementedInPlugin',
        'apkSigningImplementedInPlugin', 'apkInstallationImplementedInPlugin',
        'buildLayerOwnsPluginPackagingAndSigning'
    ) -Label 'contract claims'
    foreach ($falseClaim in @(
        'sourceCompilationImplementedInPlugin', 'aarResourceMergeImplementedInPlugin',
        'apkPackagingImplementedInPlugin', 'apkSigningImplementedInPlugin',
        'apkInstallationImplementedInPlugin'
    )) {
        $value = $contract.claims.PSObject.Properties[$falseClaim].Value
        if ($value -isnot [bool] -or [bool] $value) { throw "Contract claim '$falseClaim' changed." }
    }
    foreach ($trueClaim in @('validatedJarRequiredBeforeDex', 'buildLayerOwnsPluginPackagingAndSigning')) {
        $value = $contract.claims.PSObject.Properties[$trueClaim].Value
        if ($value -isnot [bool] -or -not [bool] $value) { throw "Contract claim '$trueClaim' changed." }
    }
    return $contract
}

function Get-R4OtherCapabilitiesCanonicalPath {
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

function Resolve-R4OtherCapabilitiesInputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter(Mandatory)] [string] $Label,
        [switch] $Directory
    )

    Assert-R4OtherCapabilitiesSafeRelativePath -Path $RelativePath -Label $Label
    $root = Get-R4OtherCapabilitiesCanonicalPath -Path $RepositoryRoot
    if (-not [IO.Directory]::Exists($root)) { throw 'Repository root does not exist.' }
    $candidate = Get-R4OtherCapabilitiesCanonicalPath -Path (
        [IO.Path]::Combine($root, $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    )
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $prefix = $root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, $comparison)) { throw "$Label escapes the repository root." }
    if ($Directory) {
        if (-not [IO.Directory]::Exists($candidate)) { throw "$Label directory does not exist." }
    } elseif (-not [IO.File]::Exists($candidate)) {
        throw "$Label file does not exist."
    }
    return $candidate
}

function Read-R4OtherCapabilitiesUtf8Text {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    try {
        return [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.UTF8Encoding]::new($false, $true))
    } catch {
        throw 'A scanned text input is not canonical UTF-8.'
    }
}

function Test-R4OtherCapabilitiesBoundary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [psobject] $Contract
    )

    $root = Get-R4OtherCapabilitiesCanonicalPath -Path $RepositoryRoot
    $sourceRoot = Resolve-R4OtherCapabilitiesInputPath -RepositoryRoot $root `
        -RelativePath $Contract.inputs.productionSourceRoot -Label 'production source root' -Directory
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Sort-Object FullName)
    if ($sourceFiles.Count -ne [int] $Contract.runtimeSurface.expectedSourceFileCount) {
        throw 'Production source file count changed.'
    }
    $sourceRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $sourceFiles) {
        $canonicalFile = Get-R4OtherCapabilitiesCanonicalPath -Path $file.FullName
        $relative = $canonicalFile.Substring(
            $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Length + 1
        ).Replace('\', '/')
        if (@($Contract.runtimeSurface.allowedSourceExtensions) -cnotcontains $file.Extension) {
            throw "Production source extension is not allowed: $relative"
        }
        $text = Read-R4OtherCapabilitiesUtf8Text -Path $canonicalFile
        foreach ($pattern in @($Contract.runtimeSurface.forbiddenPatterns)) {
            if ([regex]::IsMatch(
                $text,
                [string] $pattern.regex,
                [Text.RegularExpressions.RegexOptions]::CultureInvariant
            )) {
                throw "Production source violates forbidden capability '$($pattern.id)': $relative"
            }
        }
        $sourceRecords.Add([pscustomobject][ordered]@{
            path = $relative
            byteLength = [long] $file.Length
            sha256 = Get-R4OtherCapabilitiesSha256File -Path $canonicalFile
        })
    }
    $canonicalManifest = (@($sourceRecords) | ForEach-Object {
        "{0}`0{1}`0{2}`n" -f $_.path, $_.byteLength, $_.sha256
    }) -join ''
    $sourceManifestSha256 = Get-R4OtherCapabilitiesSha256Text -Text $canonicalManifest

    foreach ($required in @($Contract.runtimeSurface.requiredSourceEvidence)) {
        $path = Resolve-R4OtherCapabilitiesInputPath -RepositoryRoot $root `
            -RelativePath ([string] $Contract.inputs.([string] $required.pathKey)) `
            -Label "required source $($required.pathKey)"
        $text = Read-R4OtherCapabilitiesUtf8Text -Path $path
        if (-not $text.Contains([string] $required.literal, [StringComparison]::Ordinal)) {
            throw "Required validated-JAR-to-DEX evidence '$($required.pathKey)' changed."
        }
    }

    $manifestPath = Resolve-R4OtherCapabilitiesInputPath -RepositoryRoot $root `
        -RelativePath $Contract.inputs.manifest -Label 'Android manifest'
    $manifestText = Read-R4OtherCapabilitiesUtf8Text -Path $manifestPath
    try { [xml] $manifest = $manifestText } catch { throw 'Android manifest is not valid XML.' }
    $namespace = [Xml.XmlNamespaceManager]::new($manifest.NameTable)
    $namespace.AddNamespace('android', 'http://schemas.android.com/apk/res/android')
    $androidNamespace = 'http://schemas.android.com/apk/res/android'
    $permissions = @($manifest.SelectNodes('/manifest/uses-permission', $namespace) | ForEach-Object {
        $_.GetAttribute('name', $androidNamespace)
    } | Sort-Object -CaseSensitive)
    $actions = @($manifest.SelectNodes('//intent-filter/action', $namespace) | ForEach-Object {
        $_.GetAttribute('name', $androidNamespace)
    } | Sort-Object -CaseSensitive)
    $services = @($manifest.SelectNodes('/manifest/application/service', $namespace))
    if (($permissions -join "`0") -cne (@($Contract.manifestBoundary.permissions | Sort-Object -CaseSensitive) -join "`0") -or
        ($actions -join "`0") -cne (@($Contract.manifestBoundary.actions | Sort-Object -CaseSensitive) -join "`0") -or
        $services.Count -ne [int] $Contract.manifestBoundary.serviceCount) {
        throw 'Android manifest permission/action/service boundary changed.'
    }

    $buildPath = Resolve-R4OtherCapabilitiesInputPath -RepositoryRoot $root `
        -RelativePath $Contract.inputs.appBuild -Label 'app build layer'
    $buildText = Read-R4OtherCapabilitiesUtf8Text -Path $buildPath
    foreach ($marker in @($Contract.buildLayer.requiredMarkers)) {
        $count = ([regex]::Matches($buildText, [regex]::Escape([string] $marker))).Count
        if ($count -ne 1) { throw "Build-layer responsibility marker changed: $marker" }
    }
    foreach ($pattern in @($Contract.buildLayer.forbiddenRuntimeDependencyPatterns)) {
        if ([regex]::IsMatch($buildText, [string] $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            throw 'A source/compiler/packaging runtime dependency entered the plugin application.'
        }
    }

    $apiPath = Resolve-R4OtherCapabilitiesInputPath -RepositoryRoot $root `
        -RelativePath $Contract.inputs.apiAar -Label 'frozen DEX API AAR'
    $apiItem = Get-Item -LiteralPath $apiPath
    if ([long] $apiItem.Length -ne [long] $Contract.apiAar.byteLength -or
        (Get-R4OtherCapabilitiesSha256File -Path $apiPath) -cne $Contract.apiAar.sha256) {
        throw 'Frozen DEX API AAR identity changed.'
    }

    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        invocationId = [guid]::NewGuid().ToString()
        contractId = [string] $Contract.contractId
        passed = $true
        evidenceBoundary = $script:EvidenceBoundary
        productionSources = [pscustomobject][ordered]@{
            fileCount = $sourceRecords.Count
            manifestSha256 = $sourceManifestSha256
            forbiddenCapabilityPatternCount = @($Contract.runtimeSurface.forbiddenPatterns).Count
            forbiddenCapabilityMatches = 0
        }
        protocol = [pscustomobject][ordered]@{
            apiAarSha256 = [string] $Contract.apiAar.sha256
            inputFormats = @($Contract.apiAar.inputFormats)
            inputRoles = @($Contract.apiAar.inputRoles)
            outputFormats = @($Contract.apiAar.outputFormats)
            validatedProgramJarRequired = $true
        }
        manifest = [pscustomobject][ordered]@{
            permissionCount = $permissions.Count
            actionCount = $actions.Count
            serviceCount = $services.Count
            installPermissionOrActionPresent = $false
        }
        buildLayer = [pscustomobject][ordered]@{
            appBuildSha256 = Get-R4OtherCapabilitiesSha256File -Path $buildPath
            packagingMarkerPresent = $true
            signingMarkerPresent = $true
            assembleReleaseMarkerPresent = $true
            forbiddenRuntimeDependencyMatches = 0
        }
        claims = [pscustomobject][ordered]@{
            sourceCompilationImplementedInPlugin = $false
            sourceCompilationMustProduceValidatedJarFirst = $true
            aarResourceMergeImplementedInPlugin = $false
            apkPackagingImplementedInPlugin = $false
            apkSigningImplementedInPlugin = $false
            apkInstallationImplementedInPlugin = $false
            packagingSigningAndInstallationRemainBuildOrHostResponsibilities = $true
        }
        operations = [pscustomobject][ordered]@{
            sourceCompilationPerformed = $false
            packagingOrSigningPerformed = $false
            adbOrInstallationPerformed = $false
            repositoryMutationPerformed = $false
        }
        summary = 'Production runtime remains validated-JAR-to-DEX only; source compilation and AAR/APK resource, packaging, signing, and installation responsibilities stay outside this plugin runtime.'
    }
}

function Write-R4OtherCapabilitiesAtomicJson {
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
    'Get-R4OtherCapabilitiesCanonicalPath',
    'Get-R4OtherCapabilitiesSha256File',
    'Read-R4OtherCapabilitiesContract',
    'Read-R4OtherCapabilitiesJson',
    'Test-R4OtherCapabilitiesBoundary',
    'Write-R4OtherCapabilitiesAtomicJson'
)
