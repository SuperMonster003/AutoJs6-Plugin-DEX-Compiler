[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{1,63}$')]
    [string] $Serial,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')]
    [string] $MatrixCellId,

    [Parameter(Mandatory)]
    [ValidateSet('EMULATOR', 'PHYSICAL')]
    [string] $DeviceKind,

    [Parameter(Mandatory)]
    [ValidateRange(24, 36)]
    [int] $ExpectedApi,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x86_64', 'arm64-v8a')]
    [string] $ExpectedAbi,

    [string] $ExpectedAvdName = '',

    [string] $AndroidSdk = 'E:\.android\sdk',
    [string] $JavaExecutable = 'E:\.java\jdk-21.0.1\bin\java.exe',
    [string] $HostRepo = 'D:\idea-projects\AutoJs6-R5-Classpath',
    [string] $PluginRepo = 'D:\idea-projects\AutoJs6-Plugin-DEX-Compiler',
    [string] $HostApk = 'D:\idea-projects\AutoJs6-R5-Classpath\app\build\outputs\apk\app\debug\autojs6-v6.8.0-universal.apk',
    [string] $TestApk = 'D:\idea-projects\AutoJs6-R5-Classpath\app\build\outputs\apk\androidTest\app\debug\app-app-debug-androidTest.apk',
    [string] $PluginApk = 'D:\idea-projects\AutoJs6-Plugin-DEX-Compiler\app\build\outputs\apk\release\autojs6-plugin-dex-compiler-v1.0.0.apk',
    [string] $EvidenceRoot = 'D:\idea-projects\AutoJs6-DEX-R5-Evidence-20260827',

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $CampaignId,

    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $RunId = ([guid]::NewGuid().ToString()),

    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string] $ExpectedHostApkSha256 = '24f4ee855174b994d9e37472b48120b2059cc82f3e64507c447799b95dfcaa8f',

    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string] $ExpectedTestApkSha256 = '2b82aabf644cc1c2cc2983faf902d57ca93975bfb59197245fca9e34eea2fdcb',

    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string] $ExpectedPluginApkSha256 = '3b9418227d90fccac495519f61552a78ef8ece5946602930a9100f7ba77981ad'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Scope is intentionally one explicitly named R5.3 representative cell. This runner never
# enumerates devices, starts or stops an emulator, invokes Gradle, or talks to another serial.
$HostPackage = 'org.autojs.autojs6'
$TestPackage = 'org.autojs.autojs6.test'
$PluginPackage = 'io.github.supermonster003.autojs6.plugin.dexcompiler'
$FakePackage = 'org.autojs.plugin.dexcompiler.fake'
$Runner = 'org.autojs.autojs6.test/androidx.test.runner.AndroidJUnitRunner'
$Selector = 'org.autojs.autojs.core.plugin.dex.DexCompilerRealProviderAndroidTest#representativeRhinoClasspathEntryUsesRealProviderAndRetainsLegacyLoadJar'
$ExpectedHostApkSha256 = $ExpectedHostApkSha256.ToLowerInvariant()
$ExpectedTestApkSha256 = $ExpectedTestApkSha256.ToLowerInvariant()
$ExpectedPluginApkSha256 = $ExpectedPluginApkSha256.ToLowerInvariant()
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$StartedUtc = [DateTime]::UtcNow
$CampaignId = $CampaignId.ToLowerInvariant()
$RunId = $RunId.ToLowerInvariant()
$RunDirectory = Join-Path $EvidenceRoot ("classpath-{0}-{1}" -f $MatrixCellId, $RunId)
$RawDirectory = Join-Path $RunDirectory 'raw'
$ArtifactDirectory = Join-Path $RunDirectory 'artifacts'
$Adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$Aapt = Join-Path $AndroidSdk 'build-tools\37.0.0\aapt.exe'
$ApkSignerJar = Join-Path $AndroidSdk 'build-tools\37.0.0\lib\apksigner.jar'
$GitExecutable = (Get-Command git.exe -ErrorAction Stop).Source

$script:CommandOrdinal = 0
$script:CommandRecords = [System.Collections.Generic.List[object]]::new()
$script:InstalledPackages = [System.Collections.Generic.List[string]]::new()
$script:FrozenApkPaths = @{}
$script:CleanupFailures = [System.Collections.Generic.List[string]]::new()
$script:PrimaryFailure = $null
$script:PreflightClean = $false
$script:PostflightClean = $false
$script:ScenarioPassed = $false

function Write-Utf8Text {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text
    )
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Write-Json {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Value,
        [int] $Depth = 12
    )
    Write-Utf8Text -Path $Path -Text (($Value | ConvertTo-Json -Depth $Depth) + "`n")
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Quote-DisplayArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)
    if ($Value -notmatch '[\s"#]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-RecordedProcess {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $Label,
        [ValidateRange(1, 600)][int] $TimeoutSeconds = 60,
        [switch] $AllowFailure
    )

    $script:CommandOrdinal++
    $ordinal = $script:CommandOrdinal
    $safeLabel = $Label -replace '[^A-Za-z0-9._-]', '-'
    $prefix = '{0:D3}-{1}' -f $ordinal, $safeLabel
    $stdoutPath = Join-Path $RawDirectory ($prefix + '.stdout.txt')
    $stderrPath = Join-Path $RawDirectory ($prefix + '.stderr.txt')
    $display = (@($FilePath) + ($Arguments | ForEach-Object { Quote-DisplayArgument $_ })) -join ' '
    $started = [DateTime]::UtcNow
    $stdout = ''
    $stderr = ''
    $timedOut = $false
    $exitCode = $null
    $terminationError = $null

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void] $info.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void] $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try {
                $process.Kill($true)
            } catch {
                $terminationError = $_.Exception.Message
            }
            if (-not $process.WaitForExit(5000) -and $null -eq $terminationError) {
                $terminationError = 'process tree did not exit within five seconds after Kill(true)'
            }
        }
        if ($process.HasExited) {
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $exitCode = $process.ExitCode
        }
    } finally {
        $process.Dispose()
    }

    Write-Utf8Text -Path $stdoutPath -Text $stdout
    Write-Utf8Text -Path $stderrPath -Text $stderr
    $ended = [DateTime]::UtcNow
    $record = [pscustomobject][ordered]@{
        ordinal = $ordinal
        label = $Label
        command = $display
        startedUtc = $started.ToString('o')
        endedUtc = $ended.ToString('o')
        timeoutSeconds = $TimeoutSeconds
        exitCode = $exitCode
        timedOut = $timedOut
        terminationError = $terminationError
        stdoutFile = [IO.Path]::GetRelativePath($RunDirectory, $stdoutPath).Replace('\', '/')
        stderrFile = [IO.Path]::GetRelativePath($RunDirectory, $stderrPath).Replace('\', '/')
    }
    $script:CommandRecords.Add($record)

    if ($timedOut) {
        throw "Command timed out after $TimeoutSeconds seconds: $display; terminationError=$terminationError"
    }
    if ($null -eq $exitCode) {
        throw "Command exited without an observable exit code: $display"
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Command failed ($exitCode): $display`n$stderr$stdout"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        Record = $record
    }
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $Label,
        [ValidateRange(1, 600)][int] $TimeoutSeconds = 60,
        [switch] $AllowFailure
    )
    if ($Arguments -contains '-s' -or $Arguments -contains '--serial') {
        throw 'Nested ADB serial selection is forbidden; the runner owns the exact target serial.'
    }
    return Invoke-RecordedProcess `
        -FilePath $Adb `
        -Arguments (@('-s', $Serial) + $Arguments) `
        -Label $Label `
        -TimeoutSeconds $TimeoutSeconds `
        -AllowFailure:$AllowFailure
}

function Get-ExactPackageState {
    param([Parameter(Mandatory)][string] $PackageName)

    $registered = Invoke-Adb `
        -Arguments @('shell', 'pm', 'list', 'packages', '-u', '--user', '0', $PackageName) `
        -Label "package-registered-$PackageName"
    $installed = Invoke-Adb `
        -Arguments @('shell', 'pm', 'list', 'packages', '--user', '0', $PackageName) `
        -Label "package-installed-$PackageName"
    $parse = {
        param([string] $Text)
        $names = @()
        foreach ($line in ($Text -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -cnotmatch '^package:([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)$') {
                throw "Malformed package probe row: $line"
            }
            $names += $Matches[1]
        }
        return @($names | Sort-Object -Unique)
    }
    $registeredNames = @(& $parse $registered.Stdout)
    $installedNames = @(& $parse $installed.Stdout)
    return [pscustomobject][ordered]@{
        packageName = $PackageName
        registeredMatches = $registeredNames
        installedMatches = $installedNames
        exactRegistered = $registeredNames -ccontains $PackageName
        exactInstalled = $installedNames -ccontains $PackageName
    }
}

function Get-PackageSnapshot {
    param([Parameter(Mandatory)][string] $Label)

    $users = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'users') -Label "$Label-users"
    $currentUser = Invoke-Adb -Arguments @('shell', 'am', 'get-current-user') -Label "$Label-current-user"
    $userIds = @(
        [regex]::Matches($users.Stdout, 'UserInfo\{([0-9]+):') |
            ForEach-Object { [int]$_.Groups[1].Value } |
            Sort-Object -Unique
    )
    if ($userIds.Count -ne 1 -or $userIds[0] -ne 0 -or $currentUser.Stdout.Trim() -cne '0') {
        throw "R5.3 runner requires a single current user 0; users=$($userIds -join ',') current=$($currentUser.Stdout.Trim())"
    }
    return [pscustomobject][ordered]@{
        label = $Label
        capturedUtc = [DateTime]::UtcNow.ToString('o')
        users = $userIds
        currentUser = 0
        packages = @(
            Get-ExactPackageState $HostPackage
            Get-ExactPackageState $TestPackage
            Get-ExactPackageState $PluginPackage
            Get-ExactPackageState $FakePackage
        )
    }
}

function Assert-FourPackagesAbsent {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)][string] $Context
    )
    foreach ($state in $Snapshot.packages) {
        if ($state.exactRegistered -or $state.exactInstalled) {
            throw "$Context package is not absent: $($state.packageName)"
        }
    }
}

function Assert-InstallResult {
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $PackageName
    )
    $lines = @($Result.Stdout -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $accepted =
        ($lines.Count -eq 1 -and $lines[0] -ceq 'Success') -or
        ($lines.Count -eq 2 -and $lines[0] -ceq 'Performing Push Install' -and $lines[1] -ceq 'Success')
    if (-not $accepted) {
        throw "Install did not return a recognized success form for $PackageName`: $($Result.Stdout)"
    }
}

function Assert-InstrumentationPass {
    param([Parameter(Mandatory)] $Result)

    $lines = @($Result.Stdout -split '\r?\n' | ForEach-Object { $_.Trim() })
    if (@($lines | Where-Object { $_ -ceq 'OK (1 test)' }).Count -ne 1) {
        throw 'R5.3 selector did not report exactly OK (1 test)'
    }
    if (@($lines | Where-Object { $_ -ceq 'INSTRUMENTATION_CODE: -1' }).Count -ne 1) {
        throw 'R5.3 selector did not report exactly one successful instrumentation terminal'
    }
    if ($Result.Stdout -match 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed|AssumptionViolated|INSTRUMENTATION_ABORTED') {
        throw 'R5.3 selector output contains a failure, crash, abort, or skipped-test marker'
    }
}

function Get-ApkIdentity {
    param(
        [Parameter(Mandatory)][ValidateSet('host', 'test', 'plugin')][string] $Role,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ExpectedPackage,
        [Parameter(Mandatory)][string] $ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "APK is missing: $Path"
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $actualSha256 = Get-Sha256 $resolved
    if ($actualSha256 -cne $ExpectedSha256) {
        throw "APK digest changed for $Role`: expected=$ExpectedSha256 actual=$actualSha256"
    }

    $badging = Invoke-RecordedProcess `
        -FilePath $Aapt `
        -Arguments @('dump', 'badging', $resolved) `
        -Label "identity-$Role-aapt" `
        -TimeoutSeconds 60
    $packageLine = @($badging.Stdout -split '\r?\n' | Where-Object { $_ -match "^package: name='" })
    if ($packageLine.Count -ne 1 -or $packageLine[0] -cnotmatch "^package: name='([^']+)' ") {
        throw "Unable to read a unique package identity from $resolved"
    }
    if ($Matches[1] -cne $ExpectedPackage) {
        throw "Unexpected package in $resolved`: $($Matches[1])"
    }

    $signing = Invoke-RecordedProcess `
        -FilePath $JavaExecutable `
        -Arguments @('-Xmx1024M', '-Xss1m', '-jar', $ApkSignerJar, 'verify', '--verbose', '--print-certs', $resolved) `
        -Label "identity-$Role-apksigner" `
        -TimeoutSeconds 60
    if ($signing.Stdout -notmatch 'Verified using v2 scheme \(APK Signature Scheme v2\): true') {
        throw "APK is not v2 verified: $resolved"
    }
    if ($signing.Stdout -cnotmatch '(?m)^Number of signers: 1\s*$') {
        throw "APK must have exactly one signer: $resolved"
    }
    $signerMatches = @([regex]::Matches(
        $signing.Stdout,
        '(?m)^(?:V2 Signer:\s+|Signer #[0-9]+\s+)certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$'
    ))
    if ($signerMatches.Count -ne 1) {
        throw "Unable to read the unique v2 signer digest: $resolved"
    }

    $frozen = Join-Path $ArtifactDirectory "$Role.apk"
    Copy-Item -LiteralPath $resolved -Destination $frozen
    if ((Get-Sha256 $frozen) -cne $ExpectedSha256) {
        throw "Frozen APK copy changed during acquisition: $Role"
    }
    $script:FrozenApkPaths[$ExpectedPackage] = $frozen
    return [pscustomobject][ordered]@{
        role = $Role
        packageName = $ExpectedPackage
        sourcePath = $resolved
        frozenPath = $frozen
        sizeBytes = (Get-Item -LiteralPath $frozen).Length
        sha256 = $ExpectedSha256
        signerCertificateSha256 = $signerMatches[0].Groups[1].Value.ToLowerInvariant()
        v2Verified = $true
    }
}

function Get-RepoIdentity {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Label
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $head = Invoke-RecordedProcess `
        -FilePath $GitExecutable `
        -Arguments @('-C', $resolved, 'rev-parse', 'HEAD') `
        -Label "identity-$Label-head" `
        -TimeoutSeconds 30
    $commit = $head.Stdout.Trim()
    if ($commit -cnotmatch '^[0-9a-f]{40}$') {
        throw "Unable to resolve a full commit identity for $Label`: $commit"
    }
    $status = Invoke-RecordedProcess `
        -FilePath $GitExecutable `
        -Arguments @('-C', $resolved, 'status', '--porcelain=v1', '--untracked-files=all') `
        -Label "identity-$Label-status" `
        -TimeoutSeconds 30
    $statusLines = @($status.Stdout -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [pscustomobject][ordered]@{
        path = $resolved
        commit = $commit
        clean = $statusLines.Count -eq 0
        dirtyEntryCount = $statusLines.Count
    }
}

function Remove-InstalledPackages {
    foreach ($packageName in @($TestPackage, $PluginPackage, $HostPackage)) {
        if ($script:InstalledPackages -cnotcontains $packageName) { continue }
        try {
            $state = Get-ExactPackageState $packageName
            if ($state.exactRegistered -or $state.exactInstalled) {
                $result = Invoke-Adb `
                    -Arguments @('uninstall', $packageName) `
                    -Label "uninstall-$packageName" `
                    -TimeoutSeconds 120 `
                    -AllowFailure
                if ($result.ExitCode -ne 0 -or $result.Stdout.Trim() -cne 'Success') {
                    throw "Uninstall failed for $packageName`: $($result.Stderr)$($result.Stdout)"
                }
            }
        } catch {
            $script:CleanupFailures.Add($_.Exception.ToString())
        }
    }
}

foreach ($path in @($Adb, $Aapt, $ApkSignerJar, $JavaExecutable, $GitExecutable, $HostApk, $TestApk, $PluginApk, $PSCommandPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}
foreach ($path in @($HostRepo, $PluginRepo)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Required repository directory is missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    throw "Evidence root is missing: $EvidenceRoot"
}
if (Test-Path -LiteralPath $RunDirectory) {
    throw "Evidence directory already exists: $RunDirectory"
}
[void](New-Item -ItemType Directory -Path $RunDirectory)
[void](New-Item -ItemType Directory -Path $RawDirectory)
[void](New-Item -ItemType Directory -Path $ArtifactDirectory)

$apkIdentities = @()
$repoIdentities = $null
$deviceIdentity = $null
$preflight = $null
$postflight = $null
$instrumentationOrdinal = $null

try {
    $repoIdentities = [ordered]@{
        host = Get-RepoIdentity -Path $HostRepo -Label 'host-repo'
        plugin = Get-RepoIdentity -Path $PluginRepo -Label 'plugin-repo'
    }
    if (-not $repoIdentities.host.clean -or -not $repoIdentities.plugin.clean) {
        throw 'R5.3 formal evidence requires clean host and plugin repositories.'
    }
    $apkIdentities = @(
        Get-ApkIdentity -Role host -Path $HostApk -ExpectedPackage $HostPackage -ExpectedSha256 $ExpectedHostApkSha256
        Get-ApkIdentity -Role test -Path $TestApk -ExpectedPackage $TestPackage -ExpectedSha256 $ExpectedTestApkSha256
        Get-ApkIdentity -Role plugin -Path $PluginApk -ExpectedPackage $PluginPackage -ExpectedSha256 $ExpectedPluginApkSha256
    )
    if (@($apkIdentities.signerCertificateSha256 | Sort-Object -Unique).Count -ne 1) {
        throw 'Host, test, and plugin APK signer identities do not match'
    }

    $state = Invoke-Adb -Arguments @('get-state') -Label 'device-state' -TimeoutSeconds 30
    if ($state.Stdout.Trim() -cne 'device') {
        throw "ADB target is not ready: $($state.Stdout.Trim())"
    }
    $boot = Invoke-Adb -Arguments @('shell', 'getprop', 'sys.boot_completed') -Label 'boot-completed' -TimeoutSeconds 30
    $api = Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.sdk') -Label 'device-api' -TimeoutSeconds 30
    $abi = Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.cpu.abi') -Label 'device-abi' -TimeoutSeconds 30
    $serialProperty = Invoke-Adb -Arguments @('shell', 'getprop', 'ro.serialno') -Label 'device-serial-property' -TimeoutSeconds 30
    $manufacturer = Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.manufacturer') -Label 'device-manufacturer' -TimeoutSeconds 30
    $model = Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.model') -Label 'device-model' -TimeoutSeconds 30
    $reportedAvd = @()
    if ($DeviceKind -ceq 'EMULATOR') {
        if ($Serial -cnotmatch '^emulator-[0-9]+$' -or [string]::IsNullOrWhiteSpace($ExpectedAvdName)) {
            throw 'An EMULATOR cell requires an emulator-* serial and a non-empty ExpectedAvdName.'
        }
        $avd = Invoke-Adb -Arguments @('emu', 'avd', 'name') -Label 'device-avd' -TimeoutSeconds 30
        $reportedAvd = @($avd.Stdout -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -cne 'OK' })
        if ($reportedAvd.Count -ne 1 -or $reportedAvd[0] -cne $ExpectedAvdName) {
            throw "Unexpected AVD name: $($reportedAvd -join ',')"
        }
    } elseif ($Serial -cmatch '^emulator-[0-9]+$' -or -not [string]::IsNullOrWhiteSpace($ExpectedAvdName)) {
        throw 'A PHYSICAL cell must not use an emulator serial or ExpectedAvdName.'
    }
    if ($boot.Stdout.Trim() -cne '1' -or [int]$api.Stdout.Trim() -ne $ExpectedApi -or $abi.Stdout.Trim() -cne $ExpectedAbi) {
        throw "Unexpected device: boot=$($boot.Stdout.Trim()) api=$($api.Stdout.Trim()) abi=$($abi.Stdout.Trim())"
    }
    if ([string]::IsNullOrWhiteSpace($serialProperty.Stdout)) {
        throw 'Device ro.serialno is empty'
    }
    $deviceIdentity = [pscustomobject][ordered]@{
        adbSerial = $Serial
        roSerialno = $serialProperty.Stdout.Trim()
        kind = $DeviceKind
        manufacturer = $manufacturer.Stdout.Trim()
        model = $model.Stdout.Trim()
        avdName = if ($reportedAvd.Count -eq 1) { $reportedAvd[0] } else { $null }
        apiLevel = $ExpectedApi
        abi = $ExpectedAbi
    }

    $preflight = Get-PackageSnapshot 'preflight'
    Assert-FourPackagesAbsent $preflight 'Preflight'
    Write-Json -Path (Join-Path $RunDirectory 'preflight.json') -Value $preflight
    $script:PreflightClean = $true

    foreach ($install in @(
        [pscustomobject]@{ packageName = $HostPackage; sha256 = $ExpectedHostApkSha256; testOnly = $false },
        [pscustomobject]@{ packageName = $PluginPackage; sha256 = $ExpectedPluginApkSha256; testOnly = $false },
        [pscustomobject]@{ packageName = $TestPackage; sha256 = $ExpectedTestApkSha256; testOnly = $true }
    )) {
        $frozenPath = $script:FrozenApkPaths[$install.packageName]
        if ((Get-Sha256 $frozenPath) -cne $install.sha256) {
            throw "Frozen APK changed immediately before install: $($install.packageName)"
        }
        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.AddRange([string[]]@('install', '--no-streaming', '--user', '0'))
        if ($install.testOnly) { $arguments.Add('-t') }
        $arguments.Add($frozenPath)
        $script:InstalledPackages.Add($install.packageName)
        $installed = Invoke-Adb `
            -Arguments $arguments.ToArray() `
            -Label "install-$($install.packageName)" `
            -TimeoutSeconds 180
        Assert-InstallResult -Result $installed -PackageName $install.packageName
        $installedState = Get-ExactPackageState $install.packageName
        if (-not $installedState.exactInstalled) {
            throw "Installed package is not visible to user 0: $($install.packageName)"
        }
    }

    $instrumentation = Invoke-Adb `
        -Arguments @(
            'shell', 'am', 'instrument', '-w', '-r',
            '-e', 'autojs.dexCompiler.realProvider.enabled', 'true',
            '-e', 'class', $Selector,
            $Runner
        ) `
        -Label 'r5-classpath-entry-instrumentation' `
        -TimeoutSeconds 300
    Assert-InstrumentationPass $instrumentation
    $instrumentationOrdinal = $instrumentation.Record.ordinal
    $script:ScenarioPassed = $true
} catch {
    $script:PrimaryFailure = $_.Exception
} finally {
    Remove-InstalledPackages
    try {
        $postflight = Get-PackageSnapshot 'postflight'
        Assert-FourPackagesAbsent $postflight 'Postflight'
        Write-Json -Path (Join-Path $RunDirectory 'postflight.json') -Value $postflight
        $script:PostflightClean = $true
    } catch {
        $script:CleanupFailures.Add($_.Exception.ToString())
    }

    $outcome = if (
        $null -eq $script:PrimaryFailure -and
        $script:CleanupFailures.Count -eq 0 -and
        $script:PreflightClean -and
        $script:PostflightClean -and
        $script:ScenarioPassed
    ) { 'PASS' } else { 'FAIL' }
    $report = [ordered]@{
        schemaVersion = 'autojs6.dex.r5.classpath-cell-evidence/v1'
        campaignId = $CampaignId
        matrixCellId = $MatrixCellId
        runId = $RunId
        startedUtc = $StartedUtc.ToString('o')
        endedUtc = [DateTime]::UtcNow.ToString('o')
        outcome = $outcome
        runner = [ordered]@{
            path = $PSCommandPath
            sha256 = Get-Sha256 $PSCommandPath
        }
        scope = [ordered]@{
            selector = $Selector
            scenarioCount = 1
            representativeR5MatrixCell = $true
        }
        device = $deviceIdentity
        repositories = $repoIdentities
        apks = $apkIdentities
        scenario = [ordered]@{
            passed = $script:ScenarioPassed
            instrumentationCommandOrdinal = $instrumentationOrdinal
            claims = @(
                "public Rhino runtime.loadJarWithClasspath executed through the real provider on API $ExpectedApi / $ExpectedAbi",
                'ordered compile-only classpath populated an exact V1.1 cache generation without leaking the stub into emitted DEX',
                'legacy runtime.loadJar independently populated and reopened its exact V1.0 cache generation'
            )
        }
        safety = [ordered]@{
            allAdbCommandsPinnedTo = $Serial
            preflightFourPackagesAbsent = $script:PreflightClean
            postflightFourPackagesAbsent = $script:PostflightClean
            cleanupFailures = @($script:CleanupFailures)
        }
        commands = @($script:CommandRecords)
        failure = if ($null -eq $script:PrimaryFailure) {
            $null
        } else {
            [ordered]@{
                type = $script:PrimaryFailure.GetType().FullName
                message = $script:PrimaryFailure.Message
            }
        }
    }
    Write-Json -Path (Join-Path $RunDirectory 'report.json') -Value $report -Depth 20
    $hashEntries = @(
        Get-ChildItem -LiteralPath $RunDirectory -Recurse -File |
            Where-Object { $_.Name -cne 'files.sha256.json' } |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    path = [IO.Path]::GetRelativePath($RunDirectory, $_.FullName).Replace('\', '/')
                    sizeBytes = $_.Length
                    sha256 = Get-Sha256 $_.FullName
                }
            }
    )
    Write-Json -Path (Join-Path $RunDirectory 'files.sha256.json') -Value $hashEntries -Depth 5
}

if ($null -ne $script:PrimaryFailure) {
    throw $script:PrimaryFailure
}
if ($script:CleanupFailures.Count -ne 0) {
    throw "R5.3 cleanup failed: $($script:CleanupFailures -join "`n")"
}
if (-not $script:ScenarioPassed) {
    throw 'R5.3 scenario did not pass'
}
Write-Output $RunDirectory
