[CmdletBinding()]
param(
    [string] $RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$consumerPath = Join-Path $PSScriptRoot 'verify-r4-r8-boundary.ps1'
$contractPath = Join-Path $PSScriptRoot 'r4-r8-boundary-contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 30 -NoEnumerate
$script:PassedCount = 0
$script:FailedCount = 0
$script:ExpectedTestCount = 22
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('autojs6-r4-r8-boundary-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
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
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )
    if (-not $Condition) { throw $Message }
}

function New-RepositoryFixture {
    param([Parameter(Mandatory)] [string] $Name)
    $fixture = Join-Path $temporaryRoot $Name
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    foreach ($property in $contract.inputs.PSObject.Properties) {
        $relative = [string] $property.Value
        $source = Join-Path $RepositoryRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Fixture source does not exist: $source"
        }
        $destination = Join-Path $fixture $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    return $fixture
}

function Set-Utf8Text {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Invoke-FixtureGate {
    param(
        [Parameter(Mandatory)] [string] $Fixture,
        [string] $ConsumerPath = $consumerPath,
        [string] $ContractPath,
        [string] $ContractSchemaPath
    )
    $outputPath = Join-Path $Fixture 'gate.json'
    Set-Utf8Text -Path $outputPath -Value '{"passed":true,"stale":true}'
    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $ConsumerPath
        '-RepositoryRoot'
        $Fixture
        '-OutputPath'
        $outputPath
    )
    if (-not [string]::IsNullOrWhiteSpace($ContractPath)) {
        $arguments += @('-ContractPath', $ContractPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ContractSchemaPath)) {
        $arguments += @('-ContractSchemaPath', $ContractSchemaPath)
    }
    $lines = @(& pwsh @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Gate did not persist output: $($lines -join ' | ')"
    }
    $gate = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 30 -NoEnumerate
    return [pscustomobject]@{ ExitCode = $exitCode; Gate = $gate; Output = $lines }
}

function Assert-BootstrapRejected {
    param([Parameter(Mandatory)] [psobject] $Invocation)
    Assert-True ($Invocation.ExitCode -ne 0) 'Broken gate input unexpectedly returned exit code zero.'
    Assert-True (-not [bool] $Invocation.Gate.passed) 'Broken gate input retained stale passed=true output.'
    Assert-True (@($Invocation.Gate.PSObject.Properties.Name) -notcontains 'stale') 'Stale output was not replaced.'
    Assert-True ($Invocation.Gate.evidenceBoundary -ceq 'SOURCE_STATIC_ONLY') 'Bootstrap failure changed evidence boundary.'
    foreach ($claim in @('r8ProviderImplemented', 'jvmVerified', 'binderVerified', 'r8Executed', 'deviceVerified')) {
        Assert-True (-not [bool] $Invocation.Gate.$claim) "Bootstrap failure promoted $claim."
    }
    $json = $Invocation.Gate | ConvertTo-Json -Depth 30 -Compress
    Assert-True ($json.IndexOf($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
        'Bootstrap failure leaked the self-test temporary path.'
}

function Assert-RejectedMutation {
    param(
        [Parameter(Mandatory)] [psobject] $Invocation,
        [Parameter(Mandatory)] [string] $CheckId
    )
    Assert-True ($Invocation.ExitCode -ne 0) 'Mutation unexpectedly returned exit code zero.'
    Assert-True (-not [bool] $Invocation.Gate.passed) 'Mutation retained stale passed=true output.'
    Assert-True `
        (@($Invocation.Gate.checks | Where-Object { $_.id -ceq $CheckId -and -not $_.passed }).Count -eq 1) `
        "Mutation did not fail expected check '$CheckId'."
    Assert-True `
        ($Invocation.Gate.evidenceBoundary -ceq 'SOURCE_STATIC_ONLY') `
        'Failure output changed the evidence boundary.'
    foreach ($claim in @('r8ProviderImplemented', 'jvmVerified', 'binderVerified', 'r8Executed', 'deviceVerified')) {
        Assert-True (-not [bool] $Invocation.Gate.$claim) "Failure output promoted $claim."
    }
}

try {
    Invoke-TestCase -Name 'real repository fixture passes the pinned boundary' -Body {
        $fixture = New-RepositoryFixture -Name 'positive'
        $invocation = Invoke-FixtureGate -Fixture $fixture
        Assert-True ($invocation.ExitCode -eq 0) "Positive fixture failed: $($invocation.Output -join ' | ')"
        Assert-True ([bool] $invocation.Gate.passed) 'Positive fixture did not persist passed=true.'
        Assert-True (@($invocation.Gate.checks).Count -eq 15) 'Pinned check count changed.'
        foreach ($claim in @('r8ProviderImplemented', 'jvmVerified', 'binderVerified', 'r8Executed', 'deviceVerified')) {
            Assert-True (-not [bool] $invocation.Gate.$claim) "Positive output promoted $claim."
        }
        $json = $invocation.Gate | ConvertTo-Json -Depth 30 -Compress
        Assert-True ($invocation.Gate.repositoryRoot -ceq '.') 'Positive report persisted an absolute repository root.'
        Assert-True ($json.IndexOf($fixture, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
            'Positive report leaked its repository root.'
        Assert-True ($json.IndexOf([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -lt 0) `
            'Positive report leaked the system temporary path.'
    }

    Invoke-TestCase -Name 'provider identity mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'identity'
        $path = Join-Path $fixture ([string] $contract.inputs.runtime)
        $text = [IO.File]::ReadAllText($path).Replace('"autojs6-d8"', '"autojs6-r8"')
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'runtime-identity'
    }

    Invoke-TestCase -Name 'Gradle applicationId mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'gradle-application-id'
        $path = Join-Path $fixture ([string] $contract.inputs.appBuild)
        $text = [IO.File]::ReadAllText($path).Replace(
            'val globalApplicationId = "io.github.supermonster003.autojs6.plugin.dexcompiler"',
            'val globalApplicationId = "io.github.supermonster003.autojs6.plugin.r8compiler"'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'gradle-application-id'
    }

    Invoke-TestCase -Name 'service action mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'action'
        $path = Join-Path $fixture ([string] $contract.inputs.manifest)
        $text = [IO.File]::ReadAllText($path).Replace(
            'org.autojs.plugin.DEX_COMPILER',
            'org.autojs.plugin.R8_COMPILER'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'manifest-dex-boundary'
    }

    Invoke-TestCase -Name 'additional R8 provider declaration fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'r8-service'
        $path = Join-Path $fixture ([string] $contract.inputs.manifest)
        $text = [IO.File]::ReadAllText($path).Replace(
            '</application>',
            '<service android:name=".R8CompilerService" android:exported="true" android:permission="org.autojs.permission.PLUGIN" android:process=":r8"><intent-filter><action android:name="org.autojs.plugin.R8_COMPILER" /></intent-filter></service></application>'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'manifest-no-r8-provider'
    }

    Invoke-TestCase -Name 'production R8 runner mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'r8-runner'
        $path = Join-Path $fixture ([string] $contract.inputs.engine)
        $text = [IO.File]::ReadAllText($path) + [Environment]::NewLine +
            'private fun forbiddenR8Runner() { com.android.tools.r8.R8.run(error("forbidden")) }' +
            [Environment]::NewLine
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'production-no-r8-runner'
    }

    Invoke-TestCase -Name 'session engine dispatch mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'session-dispatch'
        $path = Join-Path $fixture ([string] $contract.inputs.session)
        $text = [IO.File]::ReadAllText($path).Replace(
            'D8DexCompilerEngine(runtimeLibraries)',
            'OptimizerEngine(runtimeLibraries)'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'session-d8-dispatch'
    }

    Invoke-TestCase -Name 'semantic mutation with old policy retained in a comment fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'comment-decoy'
        $path = Join-Path $fixture ([string] $contract.inputs.engine)
        $originalPolicy = @'
internal fun DexCompilerMode.toD8ExecutionMode(): D8ExecutionMode = when (this) {
    DexCompilerMode.DEBUG -> D8ExecutionMode(CompilationMode.DEBUG, "--debug")
    DexCompilerMode.RELEASE -> D8ExecutionMode(CompilationMode.RELEASE, "--release")
}
'@
        $mutatedPolicy = @'
internal fun DexCompilerMode.toD8ExecutionMode(): D8ExecutionMode = when (this) {
    DexCompilerMode.DEBUG -> D8ExecutionMode(CompilationMode.DEBUG, "--debug")
    DexCompilerMode.RELEASE -> D8ExecutionMode(CompilationMode.DEBUG, "--release")
}
'@
        $text = [IO.File]::ReadAllText($path).Replace($originalPolicy.Trim(), $mutatedPolicy.Trim()) +
            "`n/*`n$originalPolicy`n*/`n"
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'production-input-sha256'
    }

    Invoke-TestCase -Name 'alternative shrinker service and action fail the exact allowlist' -Body {
        $fixture = New-RepositoryFixture -Name 'alternate-service'
        $path = Join-Path $fixture ([string] $contract.inputs.manifest)
        $text = [IO.File]::ReadAllText($path).Replace(
            '</application>',
            '<service android:name=".OptimizerService" android:exported="true" android:permission="org.autojs.permission.PLUGIN" android:process=":optimizer"><intent-filter><action android:name="org.autojs.plugin.CODE_SHRINKER" /><category android:name="dex-compiler" /></intent-filter></service></application>'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'manifest-service-allowlist'
    }

    Invoke-TestCase -Name 'production Java R8 runner mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'java-r8-runner'
        $path = Join-Path $fixture 'app/src/main/java/forbidden/ForbiddenR8.java'
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        Set-Utf8Text -Path $path -Value @'
package forbidden;
final class ForbiddenR8 {
    void run() { com.android.tools.r8.R8.run(null); }
}
'@
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'production-no-r8-runner'
    }

    Invoke-TestCase -Name 'RELEASE CompilationMode mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'release-compilation-mode'
        $path = Join-Path $fixture ([string] $contract.inputs.engine)
        $text = [IO.File]::ReadAllText($path).Replace(
            'D8ExecutionMode(CompilationMode.RELEASE, "--release")',
            'D8ExecutionMode(CompilationMode.DEBUG, "--release")'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'd8-mode-policy'
    }

    Invoke-TestCase -Name 'RELEASE CLI flag mutation fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'release-cli-flag'
        $path = Join-Path $fixture ([string] $contract.inputs.engine)
        $text = [IO.File]::ReadAllText($path).Replace(
            'D8ExecutionMode(CompilationMode.RELEASE, "--release")',
            'D8ExecutionMode(CompilationMode.RELEASE, "--debug")'
        )
        Set-Utf8Text -Path $path -Value $text
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'd8-mode-policy'
    }

    Invoke-TestCase -Name 'dex compiler API AAR drift fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'aar-drift'
        $path = Join-Path $fixture ([string] $contract.inputs.apiAar)
        $stream = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.WriteByte(0) } finally { $stream.Dispose() }
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'dex-api-aar-sha256'
    }

    Invoke-TestCase -Name 'README boundary removal fails closed' -Body {
        $fixture = New-RepositoryFixture -Name 'docs'
        $path = Join-Path $fixture ([string] $contract.inputs.readme)
        $lines = @([IO.File]::ReadAllLines($path) | Where-Object { $_ -notmatch 'DexCompilerMode\.RELEASE' })
        Set-Utf8Text -Path $path -Value (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
        Assert-RejectedMutation (Invoke-FixtureGate -Fixture $fixture) 'readme-no-r8-boundary'
    }

    Invoke-TestCase -Name 'malformed contract atomically replaces stale PASS' -Body {
        $fixture = New-RepositoryFixture -Name 'malformed-contract'
        $gateInputs = Join-Path $fixture 'gate-inputs'
        [IO.Directory]::CreateDirectory($gateInputs) | Out-Null
        $fixtureContract = Join-Path $gateInputs 'contract.json'
        $fixtureSchema = Join-Path $gateInputs 'schema.json'
        Set-Utf8Text -Path $fixtureContract -Value '{not-json'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'r4-r8-boundary-contract.schema.json') -Destination $fixtureSchema
        Assert-BootstrapRejected (Invoke-FixtureGate `
            -Fixture $fixture `
            -ContractPath $fixtureContract `
            -ContractSchemaPath $fixtureSchema)
    }

    Invoke-TestCase -Name 'malformed schema atomically replaces stale PASS' -Body {
        $fixture = New-RepositoryFixture -Name 'malformed-schema'
        $gateInputs = Join-Path $fixture 'gate-inputs'
        [IO.Directory]::CreateDirectory($gateInputs) | Out-Null
        $fixtureContract = Join-Path $gateInputs 'contract.json'
        $fixtureSchema = Join-Path $gateInputs 'schema.json'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'r4-r8-boundary-contract.json') -Destination $fixtureContract
        Set-Utf8Text -Path $fixtureSchema -Value '{not-json'
        Assert-BootstrapRejected (Invoke-FixtureGate `
            -Fixture $fixture `
            -ContractPath $fixtureContract `
            -ContractSchemaPath $fixtureSchema)
    }

    Invoke-TestCase -Name 'broken gate module atomically replaces stale PASS' -Body {
        $fixture = New-RepositoryFixture -Name 'broken-module'
        $runner = Join-Path $fixture 'gate-runner'
        [IO.Directory]::CreateDirectory($runner) | Out-Null
        foreach ($name in @(
            'verify-r4-r8-boundary.ps1',
            'R4R8BoundaryGate.psm1',
            'r4-r8-boundary-contract.json',
            'r4-r8-boundary-contract.schema.json'
        )) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $runner $name)
        }
        Set-Utf8Text -Path (Join-Path $runner 'R4R8BoundaryGate.psm1') -Value 'function broken( {'
        Assert-BootstrapRejected (Invoke-FixtureGate `
            -Fixture $fixture `
            -ConsumerPath (Join-Path $runner 'verify-r4-r8-boundary.ps1'))
    }

    Invoke-TestCase -Name 'OutputPath cannot alias a protected README input' -Body {
        $fixture = New-RepositoryFixture -Name 'output-alias'
        $readme = Join-Path $fixture ([string] $contract.inputs.readme)
        $before = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        $output = @(& pwsh -NoLogo -NoProfile -File $consumerPath `
            -RepositoryRoot $fixture `
            -OutputPath $readme 2>&1)
        $exitCode = $LASTEXITCODE
        $after = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        Assert-True ($exitCode -ne 0) 'Protected input alias returned exit code zero.'
        Assert-True ($before -ceq $after) 'Protected README was overwritten.'
        Assert-True (($output -join ' ') -match 'aliases protected input') 'Alias rejection was not explicit.'
    }

    Invoke-TestCase -Name 'OutputPath cannot overwrite an unpinned production source' -Body {
        $fixture = New-RepositoryFixture -Name 'existing-source-output'
        $relativeSource = 'app/src/main/java/io/github/supermonster003/autojs6/plugin/dexcompiler/DexCompilerService.kt'
        $source = Join-Path $RepositoryRoot $relativeSource
        $destination = Join-Path $fixture $relativeSource
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        $before = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $output = @(& pwsh -NoLogo -NoProfile -File $consumerPath `
            -RepositoryRoot $fixture `
            -OutputPath $destination 2>&1)
        $exitCode = $LASTEXITCODE
        $after = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        Assert-True ($exitCode -ne 0) 'Production-source OutputPath returned exit code zero.'
        Assert-True ($before -ceq $after) 'An unpinned production source was overwritten.'
        Assert-True (($output -join ' ') -match 'protected input subtree') 'Production subtree rejection was not explicit.'
    }

    Invoke-TestCase -Name 'OutputPath cannot create a future production source' -Body {
        $fixture = New-RepositoryFixture -Name 'future-source-output'
        $destination = Join-Path $fixture 'app/src/main/java/forbidden/FutureR8.kt'
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'Future production source unexpectedly exists.'
        $output = @(& pwsh -NoLogo -NoProfile -File $consumerPath `
            -RepositoryRoot $fixture `
            -OutputPath $destination 2>&1)
        $exitCode = $LASTEXITCODE
        Assert-True ($exitCode -ne 0) 'Future production-source OutputPath returned exit code zero.'
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'Gate created a future production source.'
        Assert-True (($output -join ' ') -match 'protected input subtree') 'Future source rejection was not explicit.'
    }

    Invoke-TestCase -Name 'OutputPath cannot reach a protected input through an ancestor junction' -Body {
        $fixture = New-RepositoryFixture -Name 'ancestor-link'
        $readme = Join-Path $fixture ([string] $contract.inputs.readme)
        $before = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        $link = Join-Path $fixture 'repository-alias'
        New-Item -ItemType Junction -Path $link -Target $fixture | Out-Null
        $aliasOutput = Join-Path $link 'README.md'
        $output = @(& pwsh -NoLogo -NoProfile -File $consumerPath `
            -RepositoryRoot $fixture `
            -OutputPath $aliasOutput 2>&1)
        $exitCode = $LASTEXITCODE
        $after = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        Assert-True ($exitCode -ne 0) 'Ancestor-link alias returned exit code zero.'
        Assert-True ($before -ceq $after) 'Ancestor-link alias overwrote the protected README.'
        Assert-True (($output -join ' ') -match 'aliases protected input') 'Ancestor-link rejection was not explicit.'
    }

    Invoke-TestCase -Name 'OutputPath cannot be a hard link to a protected input' -Body {
        $fixture = New-RepositoryFixture -Name 'hard-link'
        $readme = Join-Path $fixture ([string] $contract.inputs.readme)
        $before = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        $hardLink = Join-Path $fixture 'hard-link-output.json'
        New-Item -ItemType HardLink -Path $hardLink -Target $readme | Out-Null
        $output = @(& pwsh -NoLogo -NoProfile -File $consumerPath `
            -RepositoryRoot $fixture `
            -OutputPath $hardLink 2>&1)
        $exitCode = $LASTEXITCODE
        $after = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
        Assert-True ($exitCode -ne 0) 'Hard-link alias returned exit code zero.'
        Assert-True ($before -ceq $after) 'Hard-link alias overwrote the protected README.'
        Assert-True (($output -join ' ') -match 'alias protected input content') 'Hard-link rejection was not explicit.'
    }
} finally {
    $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemporary.StartsWith($systemTemporary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:PassedCount + $script:FailedCount -ne $script:ExpectedTestCount) {
    throw "R4.2-G0 self-test count changed: expected $script:ExpectedTestCount, observed $($script:PassedCount + $script:FailedCount)."
}
Write-Host "R4.2-G0 R8 boundary self-tests: $($script:PassedCount)/$($script:ExpectedTestCount) passed."
if ($script:FailedCount -ne 0) { exit 1 }
