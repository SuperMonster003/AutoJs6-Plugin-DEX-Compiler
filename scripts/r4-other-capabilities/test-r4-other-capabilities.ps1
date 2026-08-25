[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'R4OtherCapabilitiesGate.psm1'
$contractPath = Join-Path $PSScriptRoot 'r4-other-capabilities-contract.json'
$verifierPath = Join-Path $PSScriptRoot 'verify-r4-other-capabilities.ps1'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module $modulePath -Force
$contract = Read-R4OtherCapabilitiesContract -Path $contractPath

$script:Passed = 0
$script:Failed = 0
$script:Expected = 13

function Invoke-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )

    try {
        & $Body
        $script:Passed++
        Write-Host "PASS $Name"
    } catch {
        $script:Failed++
        Write-Host "FAIL $Name -- $($_.Exception.Message)"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)] [scriptblock] $Body,
        [Parameter(Mandatory)] [string] $Pattern
    )

    try { & $Body } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected '$Pattern'; found '$($_.Exception.Message)'."
        }
        return
    }
    throw "Expected failure '$Pattern', but the call passed."
}

function Invoke-TextMutation {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [scriptblock] $Mutator,
        [Parameter(Mandatory)] [scriptblock] $Assertion
    )

    $original = [IO.File]::ReadAllBytes($Path)
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($original)
        $mutated = & $Mutator $text
        [IO.File]::WriteAllText($Path, [string] $mutated, [Text.UTF8Encoding]::new($false))
        & $Assertion
    } finally {
        [IO.File]::WriteAllBytes($Path, $original)
    }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('autojs6-r4-other-capabilities-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    $fixtureRoot = Join-Path $temporaryRoot 'repository'
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $fixtureInputs = @(
        'app/src/main/AndroidManifest.xml',
        'app/build.gradle.kts',
        'libs/dex-compiler-api.aar'
    )
    $fixtureInputs += @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'app/src/main/java') -File -Recurse |
        ForEach-Object { $_.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/') })
    foreach ($relative in $fixtureInputs) {
        $source = Join-Path $repositoryRoot $relative
        $target = Join-Path $fixtureRoot $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($source, $target, $true)
    }

    $runtimePath = Join-Path $fixtureRoot ([string] $contract.inputs.runtime)
    $validatorPath = Join-Path $fixtureRoot ([string] $contract.inputs.validator)
    $manifestPath = Join-Path $fixtureRoot ([string] $contract.inputs.manifest)
    $buildPath = Join-Path $fixtureRoot ([string] $contract.inputs.appBuild)
    $apiPath = Join-Path $fixtureRoot ([string] $contract.inputs.apiAar)

    Invoke-Case -Name 'validated JAR to DEX boundary passes' -Body {
        $gate = Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract
        Assert-True -Condition ([bool] $gate.passed) -Message 'Positive boundary did not pass.'
        Assert-True -Condition ([int] $gate.productionSources.fileCount -eq 20) -Message 'Source count changed.'
        Assert-True -Condition (-not [bool] $gate.claims.sourceCompilationImplementedInPlugin) `
            -Message 'Positive boundary claimed an in-plugin source compiler.'
    }

    Invoke-Case -Name 'unexpected production source is rejected' -Body {
        $unexpected = Join-Path $fixtureRoot 'app/src/main/java/Unexpected.kt'
        try {
            [IO.File]::WriteAllText($unexpected, 'internal object Unexpected', [Text.UTF8Encoding]::new($false))
            Assert-Throws -Pattern 'source file count' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        } finally {
            if ([IO.File]::Exists($unexpected)) { [IO.File]::Delete($unexpected) }
        }
    }

    Invoke-Case -Name 'Java production source extension is rejected' -Body {
        $kotlinPath = Join-Path $fixtureRoot 'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/WakeActivity.kt'
        $javaPath = [IO.Path]::ChangeExtension($kotlinPath, '.java')
        try {
            [IO.File]::Move($kotlinPath, $javaPath)
            Assert-Throws -Pattern 'source extension' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        } finally {
            if ([IO.File]::Exists($javaPath)) { [IO.File]::Move($javaPath, $kotlinPath) }
        }
    }

    Invoke-Case -Name 'Java compiler API is rejected' -Body {
        Invoke-TextMutation -Path $runtimePath -Mutator { param($text) $text + "`n// javax.tools.JavaCompiler`n" } -Assertion {
            Assert-Throws -Pattern 'java-compiler-api' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'external compiler process launch is rejected' -Body {
        Invoke-TextMutation -Path $runtimePath -Mutator { param($text) $text + "`n// ProcessBuilder(`"kotlinc`")`n" } -Assertion {
            Assert-Throws -Pattern 'kotlin-source-compiler-api|source-compiler-process|external-process-launch' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'AAR resource merger is rejected' -Body {
        Invoke-TextMutation -Path $runtimePath -Mutator { param($text) $text + "`n// AarResourceMerger`n" } -Assertion {
            Assert-Throws -Pattern 'aar-runtime-pipeline' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'package installation API is rejected' -Body {
        Invoke-TextMutation -Path $runtimePath -Mutator { param($text) $text + "`n// android.content.pm.PackageInstaller`n" } -Assertion {
            Assert-Throws -Pattern 'package-installation-api' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'validated class-bearing JAR evidence is required' -Body {
        Invoke-TextMutation -Path $validatorPath -Mutator {
            param($text)
            $text.Replace('Program JAR contains no class files', 'Program archive is empty')
        } -Assertion {
            Assert-Throws -Pattern 'validated-JAR-to-DEX evidence.*validator' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'install manifest permission is rejected' -Body {
        Invoke-TextMutation -Path $manifestPath -Mutator {
            param($text)
            $text.Replace(
                '<uses-permission android:name="org.autojs.permission.PLUGIN" />',
                '<uses-permission android:name="org.autojs.permission.PLUGIN" />' + "`n    " +
                    '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
            )
        } -Assertion {
            Assert-Throws -Pattern 'manifest permission/action/service boundary' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'build-layer signing marker is required' -Body {
        Invoke-TextMutation -Path $buildPath -Mutator {
            param($text)
            $text.Replace('signingConfigs {', 'signingConfigs /* removed boundary marker */ {')
        } -Assertion {
            Assert-Throws -Pattern 'Build-layer responsibility marker' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'source compiler runtime dependency is rejected' -Body {
        Invoke-TextMutation -Path $buildPath -Mutator {
            param($text)
            $text + "`n// implementation(`"org.jetbrains.kotlin:kotlin-compiler-embeddable:2.3.20`")`n"
        } -Assertion {
            Assert-Throws -Pattern 'runtime dependency entered' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        }
    }

    Invoke-Case -Name 'frozen protocol AAR mutation is rejected' -Body {
        $original = [IO.File]::ReadAllBytes($apiPath)
        try {
            $mutated = [byte[]] $original.Clone()
            $mutated[$mutated.Length - 1] = $mutated[$mutated.Length - 1] -bxor 0x01
            [IO.File]::WriteAllBytes($apiPath, $mutated)
            Assert-Throws -Pattern 'API AAR identity' -Body {
                Test-R4OtherCapabilitiesBoundary -RepositoryRoot $fixtureRoot -Contract $contract | Out-Null
            }
        } finally {
            [IO.File]::WriteAllBytes($apiPath, $original)
        }
    }

    Invoke-Case -Name 'bootstrap failure atomically replaces stale PASS' -Body {
        $brokenContract = Join-Path $temporaryRoot 'broken-contract.json'
        [IO.File]::WriteAllText($brokenContract, '{"schemaVersion":"broken"}', [Text.UTF8Encoding]::new($false))
        $output = Join-Path $temporaryRoot 'gate.json'
        [IO.File]::WriteAllText($output, '{"passed":true,"stale":true}', [Text.UTF8Encoding]::new($false))
        & pwsh -NoLogo -NoProfile -File $verifierPath `
            -RepositoryRoot $fixtureRoot `
            -ContractPath $brokenContract `
            -OutputPath $output *> $null
        Assert-True -Condition ($LASTEXITCODE -ne 0) -Message 'Broken contract exited zero.'
        $persisted = Read-R4OtherCapabilitiesJson -Path $output
        Assert-True -Condition (-not [bool] $persisted.passed) -Message 'Broken verifier retained stale PASS.'
        Assert-True -Condition (@($persisted.PSObject.Properties.Name) -notcontains 'stale') `
            -Message 'Broken verifier did not replace stale output.'
        Assert-True -Condition ([string] $persisted.reasons[0] -notmatch [regex]::Escape($temporaryRoot)) `
            -Message 'Failure report leaked a temporary absolute path.'
    }
} finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $temporaryPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemporaryRoot.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($resolvedTemporaryRoot).StartsWith('autojs6-r4-other-capabilities-tests-', [StringComparison]::Ordinal)) {
        throw 'Refusing to delete a temporary directory outside the expected boundary.'
    }
    if ([IO.Directory]::Exists($resolvedTemporaryRoot)) { [IO.Directory]::Delete($resolvedTemporaryRoot, $true) }
}

Write-Host "RESULT passed=$($script:Passed) failed=$($script:Failed)"
if ($script:Passed + $script:Failed -ne $script:Expected -or $script:Failed -ne 0) { exit 1 }
