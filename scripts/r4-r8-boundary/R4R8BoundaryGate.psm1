Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GateSchemaVersion = 'autojs6.dex.r4.r8-boundary-gate/v1'
$script:EvidenceBoundary = 'SOURCE_STATIC_ONLY'

function Get-R4R8CanonicalPath {
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
        [char[]] $separators = @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $segments = @($pathToResolve.Substring($root.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries))
        $current = $root
        $resolvedLink = $false
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $candidate = [IO.Path]::Combine($current, $segments[$index])
            if (Test-Path -LiteralPath $candidate) {
                $item = Get-Item -LiteralPath $candidate -Force
                $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                if ($isReparsePoint) {
                    $target = $item.ResolveLinkTarget($true)
                    if ($null -eq $target) {
                        throw "Unable to resolve reparse point in path: $candidate"
                    }
                    $remaining = if ($index + 1 -lt $segments.Count) {
                        [IO.Path]::Combine([string[]] $segments[($index + 1)..($segments.Count - 1)])
                    } else {
                        ''
                    }
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
        if (-not $resolvedLink) {
            return [IO.Path]::GetFullPath($current)
        }
    }
    throw "Path contains too many symbolic-link or junction resolutions: $Path"
}

function Get-R4R8Sha256File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-R4R8SafeOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ProtectedInputPath,

        [string[]] $ProtectedSubtreePath = @()
    )

    $resolvedOutput = Get-R4R8CanonicalPath -Path $OutputPath
    if (Test-Path -LiteralPath $resolvedOutput -PathType Container) {
        throw "OutputPath must be a file path, not a directory: $resolvedOutput"
    }
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    foreach ($inputPath in $ProtectedInputPath) {
        $resolvedInput = Get-R4R8CanonicalPath -Path $inputPath
        if ([string]::Equals($resolvedOutput, $resolvedInput, $comparison)) {
            throw "OutputPath aliases protected input path '$resolvedInput'."
        }
        # A pre-existing hard link is not a reparse point. Equal length and content is a
        # deliberately conservative rejection before the atomic replacement can touch it.
        if (
            (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -and
            (Test-Path -LiteralPath $resolvedInput -PathType Leaf)
        ) {
            $outputItem = Get-Item -LiteralPath $resolvedOutput
            $inputItem = Get-Item -LiteralPath $resolvedInput
            if (
                $outputItem.Length -eq $inputItem.Length -and
                (Get-R4R8Sha256File -Path $resolvedOutput) -ceq (Get-R4R8Sha256File -Path $resolvedInput)
            ) {
                throw "OutputPath may alias protected input content '$resolvedInput'."
            }
        }
    }
    foreach ($subtreePath in $ProtectedSubtreePath) {
        $resolvedSubtree = Get-R4R8CanonicalPath -Path $subtreePath
        $subtreePrefix = $resolvedSubtree.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ) + [IO.Path]::DirectorySeparatorChar
        if (
            [string]::Equals($resolvedOutput, $resolvedSubtree, $comparison) -or
            $resolvedOutput.StartsWith($subtreePrefix, $comparison)
        ) {
            throw "OutputPath is inside protected input subtree '$resolvedSubtree'."
        }
    }
    return $resolvedOutput
}

function Write-R4R8AtomicJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolvedPath)
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "OutputPath has no parent directory: $resolvedPath"
    }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = [IO.Path]::Combine(
        $parent,
        ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($resolvedPath), [guid]::NewGuid().ToString('N'))
    )
    try {
        [IO.File]::WriteAllText($temporary, $Json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $resolvedPath, $true)
    } finally {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Read-R4R8Contract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ContractPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    foreach ($path in @($ContractPath, $SchemaPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Pinned contract input does not exist: $path"
        }
    }
    $raw = [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($ContractPath),
        [Text.UTF8Encoding]::new($false, $true)
    )
    $schemaRaw = [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($SchemaPath),
        [Text.UTF8Encoding]::new($false, $true)
    )
    try {
        $null = $schemaRaw | ConvertFrom-Json -Depth 100 -NoEnumerate
    } catch {
        throw "Pinned R8 boundary contract schema is not valid JSON. $($_.Exception.Message)"
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
        throw "Pinned R8 boundary contract does not conform to its schema.$detail"
    }
    return $raw | ConvertFrom-Json -Depth 50 -NoEnumerate
}

function Resolve-R4R8RepositoryInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "Contract repository input must be relative: $RelativePath"
    }
    $root = Get-R4R8CanonicalPath -Path $RepositoryRoot
    $candidate = Get-R4R8CanonicalPath -Path ([IO.Path]::Combine($root, $RelativePath))
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, $comparison)) {
        throw "Contract repository input escapes RepositoryRoot: $RelativePath"
    }
    return $candidate
}

function Read-R4R8Utf8Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($Path),
        [Text.UTF8Encoding]::new($false, $true)
    )
}

function Get-R4R8CompactSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source
    )

    return [regex]::Replace($Source, '\s+', '')
}

function Read-R4R8Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        return $document
    } finally {
        $reader.Dispose()
    }
}

function Test-R4R8BoundaryGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $ContractPath,

        [Parameter(Mandatory)]
        [string] $ContractSchemaPath
    )

    $contract = Read-R4R8Contract -ContractPath $ContractPath -SchemaPath $ContractSchemaPath
    $resolvedRoot = Get-R4R8CanonicalPath -Path $RepositoryRoot
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "RepositoryRoot does not exist: $resolvedRoot"
    }

    $inputPaths = [ordered]@{}
    foreach ($property in $contract.inputs.PSObject.Properties) {
        $inputPaths[$property.Name] = Resolve-R4R8RepositoryInput `
            -RepositoryRoot $resolvedRoot `
            -RelativePath ([string] $property.Value
        )
    }

    $checks = [Collections.Generic.List[object]]::new()
    $reasons = [Collections.Generic.List[string]]::new()
    function Add-Check {
        param([string] $Id, [bool] $Passed, [string] $Summary)
        $checks.Add([pscustomobject][ordered]@{
            id = $Id
            passed = $Passed
            summary = $Summary
        })
        if (-not $Passed) {
            $reasons.Add("${Id}: $Summary")
        }
    }

    $missing = @($inputPaths.GetEnumerator() | Where-Object {
        -not (Test-Path -LiteralPath $_.Value -PathType Leaf)
    })
    Add-Check `
        -Id 'inputs-present' `
        -Passed ($missing.Count -eq 0) `
        -Summary $(if ($missing.Count -eq 0) {
            'All pinned repository inputs are regular files.'
        } else {
            'Missing repository inputs: ' + (($missing | ForEach-Object Key) -join ', ')
        })

    if ($missing.Count -eq 0) {
        $productionDigestDrift = [Collections.Generic.List[string]]::new()
        foreach ($key in @('manifest', 'runtime', 'pluginInfo', 'engine', 'session', 'appBuild')) {
            $actualDigest = Get-R4R8Sha256File -Path $inputPaths[$key]
            $expectedDigest = [string] $contract.productionInputSha256.$key
            if ($actualDigest -cne $expectedDigest) {
                $productionDigestDrift.Add($key)
            }
        }
        Add-Check `
            -Id 'production-input-sha256' `
            -Passed ($productionDigestDrift.Count -eq 0) `
            -Summary $(if ($productionDigestDrift.Count -eq 0) {
                'Manifest, runtime, PluginInfo, engine, session dispatch, and app build match pinned source digests.'
            } else {
                'Pinned production source digest drift: ' + ($productionDigestDrift -join ', ')
            })

        $manifest = Read-R4R8Manifest -Path $inputPaths.manifest
        $androidNamespace = 'http://schemas.android.com/apk/res/android'
        $services = @($manifest.SelectNodes('/manifest/application/service'))
        $compilerServices = @($services | Where-Object {
            $_.GetAttribute('name', $androidNamespace) -ceq [string] $contract.dexProvider.serviceName
        })
        $manifestPassed = $compilerServices.Count -eq 1
        $manifestSummary = 'The DEX service identity or count changed.'
        if ($manifestPassed) {
            $service = $compilerServices[0]
            $actions = @($service.SelectNodes('intent-filter/action') | ForEach-Object {
                $_.GetAttribute('name', $androidNamespace)
            })
            $categories = @($service.SelectNodes('intent-filter/category') | ForEach-Object {
                $_.GetAttribute('name', $androidNamespace)
            })
            $manifestPassed =
                $service.GetAttribute('exported', $androidNamespace) -ceq 'true' -and
                $service.GetAttribute('permission', $androidNamespace) -ceq [string] $contract.dexProvider.servicePermission -and
                $service.GetAttribute('process', $androidNamespace) -ceq [string] $contract.dexProvider.serviceProcess -and
                $actions.Count -eq 1 -and
                $actions[0] -ceq [string] $contract.dexProvider.serviceAction -and
                $categories.Count -eq 1 -and
                $categories[0] -ceq [string] $contract.dexProvider.serviceCategory
            $manifestSummary = if ($manifestPassed) {
                'DEX action, category, service, process, permission, and exported state match the pinned boundary.'
            } else {
                'DEX action, category, service, process, permission, or exported state changed.'
            }
        }
        Add-Check -Id 'manifest-dex-boundary' -Passed $manifestPassed -Summary $manifestSummary

        $serviceAllowlistPassed = $services.Count -eq 2
        $serviceAllowlistSummary = 'The application service set changed.'
        if ($serviceAllowlistPassed) {
            $serviceSpecifications = @(
                [pscustomobject]@{
                    Name = [string] $contract.dexProvider.infoServiceName
                    Action = [string] $contract.dexProvider.infoServiceAction
                    Category = [string] $contract.dexProvider.serviceCategory
                    Process = ''
                }
                [pscustomobject]@{
                    Name = [string] $contract.dexProvider.serviceName
                    Action = [string] $contract.dexProvider.serviceAction
                    Category = [string] $contract.dexProvider.serviceCategory
                    Process = [string] $contract.dexProvider.serviceProcess
                }
            )
            foreach ($specification in $serviceSpecifications) {
                $matches = @($services | Where-Object {
                    $_.GetAttribute('name', $androidNamespace) -ceq $specification.Name
                })
                if ($matches.Count -ne 1) {
                    $serviceAllowlistPassed = $false
                    break
                }
                $candidate = $matches[0]
                $candidateActions = @($candidate.SelectNodes('intent-filter/action') | ForEach-Object {
                    $_.GetAttribute('name', $androidNamespace)
                })
                $candidateCategories = @($candidate.SelectNodes('intent-filter/category') | ForEach-Object {
                    $_.GetAttribute('name', $androidNamespace)
                })
                if (
                    $candidate.GetAttribute('exported', $androidNamespace) -cne 'true' -or
                    $candidate.GetAttribute('permission', $androidNamespace) -cne [string] $contract.dexProvider.servicePermission -or
                    $candidate.GetAttribute('process', $androidNamespace) -cne $specification.Process -or
                    $candidateActions.Count -ne 1 -or
                    $candidateActions[0] -cne $specification.Action -or
                    $candidateCategories.Count -ne 1 -or
                    $candidateCategories[0] -cne $specification.Category
                ) {
                    $serviceAllowlistPassed = $false
                    break
                }
            }
            $serviceAllowlistSummary = if ($serviceAllowlistPassed) {
                'The manifest contains exactly the pinned INFO and DEX services with exact filters and isolation.'
            } else {
                'A pinned service identity, filter, permission, exported state, or process changed.'
            }
        }
        Add-Check `
            -Id 'manifest-service-allowlist' `
            -Passed $serviceAllowlistPassed `
            -Summary $serviceAllowlistSummary

        $manifestHasR8 = $manifest.OuterXml -match '(?i)(org\.autojs\.plugin\.R8_COMPILER|R8Compiler|r8compiler)'
        Add-Check `
            -Id 'manifest-no-r8-provider' `
            -Passed (-not $manifestHasR8) `
            -Summary $(if ($manifestHasR8) {
                'The D8 APK manifest declares an R8 action or provider identity.'
            } else {
                'The D8 APK manifest declares no R8 action or provider identity.'
            })

        $runtime = Read-R4R8Utf8Text -Path $inputPaths.runtime
        $runtimeCompact = Get-R4R8CompactSource -Source $runtime
        $expectedRuntimeIdentity = @(
            ('constvalAPPLICATION_ID="' + [string] $contract.dexProvider.applicationId + '"')
            ('constvalPLUGIN_ID="' + [string] $contract.dexProvider.pluginId + '"')
            ('constvalPLUGIN_VARIANT="' + [string] $contract.dexProvider.variant + '"')
            ('constvalPROVIDER_ID="' + [string] $contract.dexProvider.providerId + '"')
        )
        $runtimeIdentityPassed = @($expectedRuntimeIdentity | Where-Object {
            -not $runtimeCompact.Contains($_, [StringComparison]::Ordinal)
        }).Count -eq 0
        Add-Check `
            -Id 'runtime-identity' `
            -Passed $runtimeIdentityPassed `
            -Summary $(if ($runtimeIdentityPassed) {
                'Application, plugin, variant, and provider IDs match the pinned D8 identity.'
            } else {
                'A pinned D8 runtime identity changed.'
            })

        $appBuild = Read-R4R8Utf8Text -Path $inputPaths.appBuild
        $appBuildCompact = Get-R4R8CompactSource -Source $appBuild
        $applicationIdDeclaration = 'valglobalApplicationId="' + [string] $contract.dexProvider.applicationId + '"'
        $applicationIdPassed =
            ([regex]::Matches($appBuildCompact, [regex]::Escape($applicationIdDeclaration)).Count -eq 1) -and
            ([regex]::Matches($appBuildCompact, 'applicationId=globalApplicationId').Count -eq 1)
        Add-Check `
            -Id 'gradle-application-id' `
            -Passed $applicationIdPassed `
            -Summary $(if ($applicationIdPassed) {
                'The Android applicationId is assigned exactly once from the pinned global D8 package ID.'
            } else {
                'The Android applicationId declaration or assignment changed.'
            })

        $capabilitySentinels = @(
            ('compilerFamily=DexCompilerFamily.' + [string] $contract.dexProvider.compilerFamily)
            ('inputFormats=listOf(DexCompilerInputFormat.' + [string] $contract.dexProvider.inputFormats[0] + ')')
            ('outputFormats=listOf(DexCompilerOutputFormat.' + [string] $contract.dexProvider.outputFormats[0] + ')')
            ('modes=listOf(DexCompilerMode.' + [string] $contract.dexProvider.modes[0] + ',DexCompilerMode.' + [string] $contract.dexProvider.modes[1] + ')')
            ('determinismClaim=DexCompilerDeterminismClaim.' + [string] $contract.dexProvider.determinismClaim)
        )
        $capabilitiesPassed = @($capabilitySentinels | Where-Object {
            -not $runtimeCompact.Contains($_, [StringComparison]::Ordinal)
        }).Count -eq 0
        Add-Check `
            -Id 'runtime-d8-capabilities' `
            -Passed $capabilitiesPassed `
            -Summary $(if ($capabilitiesPassed) {
                'Runtime advertises only the pinned D8/JAR/DEX_ZIP/DEBUG/RELEASE/NOT_CLAIMED surface.'
            } else {
                'The pinned D8 capability surface changed.'
            })

        $pluginInfo = Read-R4R8Utf8Text -Path $inputPaths.pluginInfo
        $pluginCompact = Get-R4R8CompactSource -Source $pluginInfo
        $familyDeclaration = 'internalvalD8_PLUGIN_FAMILY_ID:String=DexCompilerFamily.D8.name.lowercase(Locale.ROOT)'
        $pluginSentinels = @(
            $familyDeclaration,
            'id=DexCompilerRuntime.PLUGIN_ID',
            'engine=' + [string] $contract.dexProvider.engineIdExpression,
            'variant=DexCompilerRuntime.PLUGIN_VARIANT',
            'putString("compilerFamily",D8_PLUGIN_FAMILY_ID)'
        )
        $pluginInfoPassed = @($pluginSentinels | Where-Object {
            -not $pluginCompact.Contains($_, [StringComparison]::Ordinal)
        }).Count -eq 0
        Add-Check `
            -Id 'plugin-info-d8-identity' `
            -Passed $pluginInfoPassed `
            -Summary $(if ($pluginInfoPassed) {
                'PluginInfo derives and consumes the D8 family identity and pinned discovery IDs.'
            } else {
                'PluginInfo family derivation, consumption, or discovery identity changed.'
            })

        $engine = Read-R4R8Utf8Text -Path $inputPaths.engine
        $engineCompact = Get-R4R8CompactSource -Source $engine
        $expectedPolicy =
            'internalfunDexCompilerMode.toD8ExecutionMode():D8ExecutionMode=when(this){' +
            'DexCompilerMode.DEBUG->D8ExecutionMode(CompilationMode.DEBUG,"--debug")' +
            'DexCompilerMode.RELEASE->D8ExecutionMode(CompilationMode.RELEASE,"--release")' +
            '}'
        $policyPassed =
            $engineCompact.Contains($expectedPolicy, [StringComparison]::Ordinal) -and
            $engineCompact.Contains('request.mode.toD8ExecutionMode().cliFlag', [StringComparison]::Ordinal) -and
            $engineCompact.Contains('.setMode(request.mode.toD8ExecutionMode().compilationMode)', [StringComparison]::Ordinal)
        Add-Check `
            -Id 'd8-mode-policy' `
            -Passed $policyPassed `
            -Summary $(if ($policyPassed) {
                'DEBUG and RELEASE map exactly to D8 CompilationMode and matching CLI flags through one policy.'
            } else {
                'The single D8 execution-mode policy or one of its consumers changed.'
            })

        $requiredRunnerPassed =
            ([regex]::Matches($engine, '\bD8Command\s*\.\s*builder\s*\(').Count -eq 1) -and
            ([regex]::Matches($engine, '\bD8\s*\.\s*run\s*\(').Count -eq 1) -and
            ([regex]::Matches($engine, '\bD8\s*\.\s*main\s*\(').Count -eq 1)
        Add-Check `
            -Id 'd8-runner-surface' `
            -Passed $requiredRunnerPassed `
            -Summary $(if ($requiredRunnerPassed) {
                'Production engine has exactly one D8Command builder, D8.run, and D8.main invocation.'
            } else {
                'The pinned production D8 runner invocation surface changed.'
            })

        $session = Read-R4R8Utf8Text -Path $inputPaths.session
        $sessionCompact = Get-R4R8CompactSource -Source $session
        $sessionDispatchPassed =
            ([regex]::Matches($sessionCompact, [regex]::Escape('D8DexCompilerEngine(runtimeLibraries)')).Count -eq 1) -and
            ([regex]::Matches($sessionCompact, [regex]::Escape('engine.compile(')).Count -eq 1) -and
            $sessionCompact.Contains('valartifact=engine.compile(request=request,', [StringComparison]::Ordinal)
        Add-Check `
            -Id 'session-d8-dispatch' `
            -Passed $sessionDispatchPassed `
            -Summary $(if ($sessionDispatchPassed) {
                'Remote session constructs one D8 engine and hands the validated request to its sole compile call.'
            } else {
                'The production session engine construction or compile handoff changed.'
            })

        $mainSourceRoot = Join-Path $resolvedRoot 'app/src/main'
        $productionSources = if (Test-Path -LiteralPath $mainSourceRoot -PathType Container) {
            @(Get-ChildItem -LiteralPath $mainSourceRoot -Recurse -File | Where-Object {
                $_.Extension -in @('.kt', '.java')
            })
        } else {
            @()
        }
        $forbiddenHits = [Collections.Generic.List[string]]::new()
        foreach ($sourceFile in $productionSources) {
            $source = Read-R4R8Utf8Text -Path $sourceFile.FullName
            if (
                $source -match '\bR8Command\b' -or
                $source -match '\bR8\s*\.\s*(run|main)\s*\(' -or
                $source -match 'com\.android\.tools\.r8\.R8\b'
            ) {
                $forbiddenHits.Add($sourceFile.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/'))
            }
        }
        Add-Check `
            -Id 'production-no-r8-runner' `
            -Passed ($forbiddenHits.Count -eq 0) `
            -Summary $(if ($forbiddenHits.Count -eq 0) {
                'Production Kotlin and Java invoke no R8 or R8Command runner.'
            } else {
                'Forbidden R8 runner references: ' + ($forbiddenHits -join ', ')
            })

        $actualAarSha256 = Get-R4R8Sha256File -Path $inputPaths.apiAar
        $aarPassed = $actualAarSha256 -ceq [string] $contract.apiAarSha256
        Add-Check `
            -Id 'dex-api-aar-sha256' `
            -Passed $aarPassed `
            -Summary $(if ($aarPassed) {
                "dex-compiler-api.aar matches pinned SHA-256 $actualAarSha256."
            } else {
                "dex-compiler-api.aar SHA-256 drifted: $actualAarSha256."
            })

        $readme = Read-R4R8Utf8Text -Path $inputPaths.readme
        $boundaryLines = @($readme -split '\r?\n' | Where-Object { $_ -cmatch 'DexCompilerMode\.RELEASE' })
        $readmePassed = $boundaryLines.Count -eq 1
        if ($readmePassed) {
            $line = $boundaryLines[0]
            $missingKeywords = @($contract.readmeBoundaryKeywords | Where-Object {
                $line.IndexOf([string] $_, [StringComparison]::Ordinal) -lt 0
            })
            $readmePassed = $missingKeywords.Count -eq 0 -and $line.Contains('只') -and $line.Contains('不')
        }
        Add-Check `
            -Id 'readme-no-r8-boundary' `
            -Passed $readmePassed `
            -Summary $(if ($readmePassed) {
                'README states that RELEASE is only D8 release compilation mode and denies R8 artifact semantics.'
            } else {
                'README lacks one unambiguous RELEASE/D8/no-R8 boundary line with all pinned semantic keywords.'
            })
    }

    $inputEvidence = [ordered]@{}
    foreach ($entry in $inputPaths.GetEnumerator()) {
        if (Test-Path -LiteralPath $entry.Value -PathType Leaf) {
            $file = Get-Item -LiteralPath $entry.Value
            $inputEvidence[$entry.Key] = [pscustomobject][ordered]@{
                relativePath = [string] $contract.inputs.($entry.Key)
                byteLength = $file.Length
                sha256 = Get-R4R8Sha256File -Path $entry.Value
            }
        }
    }
    $passed = $reasons.Count -eq 0
    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        contractId = [string] $contract.contractId
        passed = $passed
        evidenceBoundary = $script:EvidenceBoundary
        r8ProviderImplemented = $false
        jvmVerified = $false
        binderVerified = $false
        r8Executed = $false
        deviceVerified = $false
        repositoryRoot = '.'
        contract = [pscustomobject][ordered]@{
            relativePath = [IO.Path]::GetFileName($ContractPath)
            sha256 = Get-R4R8Sha256File -Path $ContractPath
            schemaSha256 = Get-R4R8Sha256File -Path $ContractSchemaPath
        }
        checks = @($checks)
        reasons = @($reasons)
        inputs = [pscustomobject] $inputEvidence
        summary = if ($passed) {
            'Pinned D8 production surface remains separate from an unimplemented R8 provider.'
        } else {
            'R4.2-G0 D8/R8 boundary gate rejected source, artifact, or documentation drift.'
        }
    }
}

Export-ModuleMember -Function @(
    'Get-R4R8CanonicalPath',
    'Get-R4R8Sha256File',
    'Resolve-R4R8SafeOutputPath',
    'Write-R4R8AtomicJsonFile',
    'Read-R4R8Contract',
    'Test-R4R8BoundaryGate'
)
