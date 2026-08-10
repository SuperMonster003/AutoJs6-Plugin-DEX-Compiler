#Requires -Version 7.5

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'R1MatrixReceipts.psm1'
$schemaPath = Join-Path $PSScriptRoot 'r1-matrix-receipt.schema.json'
$cliPath = Join-Path $PSScriptRoot 'r1-matrix-receipts.ps1'
Import-Module $modulePath -Force

$script:EmptySha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
$script:CampaignSigner = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
$script:CanonicalAttemptSchemaVersion = 'autojs6.dex.r1.matrix-canonical-attempt/v1'
$script:CanonicalAttemptRunnerSha256 = '1111111111111111111111111111111111111111111111111111111111111111'
$script:TestsPassed = 0
$script:TestsFailed = 0

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $MessagePattern
    )

    $caught = $null
    try {
        & $Action
    } catch {
        $caught = $_
    }
    if ($null -eq $caught) {
        throw "Expected an exception matching '$MessagePattern', but no exception was thrown"
    }
    if ($caught.Exception.Message -notlike $MessagePattern) {
        throw "Expected exception '$MessagePattern', got '$($caught.Exception.Message)'"
    }
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Action
    )

    try {
        & $Action
        $script:TestsPassed++
        Write-Output "PASS $Name"
    } catch {
        $script:TestsFailed++
        Write-Output "FAIL $Name :: $($_.Exception.Message)"
    }
}

function New-TestReceipt {
    param(
        [Parameter(Mandatory)]
        [string] $CampaignId,

        [Parameter(Mandatory)]
        [int] $ApiLevel,

        [string] $ReceiptId = ([guid]::NewGuid().ToString()),

        [string] $MatrixCellId = "api$ApiLevel-x86_64-emulator",

        [ValidateSet('CANONICAL', 'SMOKE', 'DIAGNOSTIC')]
        [string] $EvidenceClass = 'CANONICAL',

        [ValidateSet('PASS', 'FAIL', 'BLOCKED')]
        [string] $Outcome = 'PASS',

        [ValidateSet('PHYSICAL', 'EMULATOR')]
        [string] $DeviceKind = 'EMULATOR',

        [string] $Abi = 'x86_64'
    )

    $serial = if ($DeviceKind -eq 'PHYSICAL') {
        'QV710AF65F'
    } else {
        switch ($ApiLevel) {
            24 { 'emulator-5580' }
            25 { 'emulator-5582' }
            26 { 'emulator-5584' }
            28 { 'emulator-5586' }
            34 { 'emulator-5588' }
            36 { 'emulator-5590' }
            default { "emulator-$ApiLevel" }
        }
    }
    $avdName = if ($DeviceKind -eq 'EMULATOR') { "DEX_R1_API${ApiLevel}_X64" } else { $null }
    $passed = $Outcome -eq 'PASS'
    $commandExit = if ($passed) { 0 } else { 17 }
    $failure = if ($passed) {
        $null
    } else {
        [ordered]@{
            stage = 'INFRASTRUCTURE'
            code = 'TEST_FAILURE'
            messageSha256 = ('a' * 64)
        }
    }

    return [ordered]@{
        schemaVersion = 'autojs6.dex.r1.matrix-receipt/v1'
        campaignId = $CampaignId
        receiptId = $ReceiptId
        matrixCellId = $MatrixCellId
        evidenceClass = $EvidenceClass
        outcome = $Outcome
        run = [ordered]@{
            startedAtUtc = '2026-08-10T01:00:00Z'
            finishedAtUtc = '2026-08-10T01:01:00Z'
        }
        repositories = [ordered]@{
            host = [ordered]@{
                versionName = '6.8.0 Alpha7'
                versionCode = 5274
                commit = ('a' * 40)
                treeState = 'CLEAN'
                treeDigestSha256 = $script:EmptySha256
            }
            plugin = [ordered]@{
                versionName = '1.0.0'
                versionCode = 4
                commit = ('b' * 40)
                treeState = 'CLEAN'
                treeDigestSha256 = $script:EmptySha256
            }
        }
        apks = [ordered]@{
            host = [ordered]@{
                packageName = 'org.autojs.autojs6'
                versionName = '6.8.0 Alpha7'
                versionCode = 5274
                sha256 = ('c' * 64)
                signerCertificateSha256 = @($script:CampaignSigner)
            }
            plugin = [ordered]@{
                packageName = 'io.github.supermonster003.autojs6.plugin.dexcompiler'
                versionName = '1.0.0'
                versionCode = 4
                sha256 = ('d' * 64)
                signerCertificateSha256 = @($script:CampaignSigner)
            }
            test = [ordered]@{
                packageName = 'org.autojs.autojs6.test'
                sha256 = ('e' * 64)
                signerCertificateSha256 = @($script:CampaignSigner)
            }
        }
        device = [ordered]@{
            serial = $serial
            apiLevel = $ApiLevel
            abi = $Abi
            allAbis = @($Abi)
            kind = $DeviceKind
            avdName = $avdName
            buildFingerprintSha256 = ('7' * 64)
        }
        safety = [ordered]@{
            userAuthorized = $true
            explicitSerialEveryAdbCommand = $true
            fakeProviderInstalled = $false
            preflightStateSha256 = ('8' * 64)
        }
        input = [ordered]@{
            corpusId = 'r1-real-d8-load-v1'
            sizeBytes = 4096
            sha256 = ('3' * 64)
        }
        request = [ordered]@{
            compilerPath = if ($ApiLevel -le 25) { 'D8_CLI_FALLBACK' } else { 'D8_COMMAND' }
            mode = 'RELEASE'
            minApi = $ApiLevel
            multiDexExpected = $false
            outputFormat = 'DEX_ZIP'
        }
        provider = [ordered]@{
            kind = 'REAL'
            component = 'io.github.supermonster003.autojs6.plugin.dexcompiler/.DexCompilerService'
            packageName = 'io.github.supermonster003.autojs6.plugin.dexcompiler'
            uid = 10123
            versionName = '1.0.0'
            versionCode = 4
            signerCertificateSha256 = @($script:CampaignSigner)
            protocolMajor = 1
            protocolMinor = 0
            runtimeLibraryFingerprintSha256 = ('1' * 64)
            compilerFamily = 'D8'
            compilerVersion = '8.13.17'
            capabilityDigestSha256 = ('2' * 64)
        }
        output = [ordered]@{
            present = $passed
            sizeBytes = if ($passed) { 8192 } else { 0 }
            sha256 = if ($passed) { ('4' * 64) } else { $null }
            dexEntryCount = if ($passed) { 1 } else { 0 }
            entryManifestSha256 = if ($passed) { ('5' * 64) } else { $null }
        }
        execution = [ordered]@{
            attempted = $passed
            passed = $passed
            className = if ($passed) { 'org.autojs.matrix.Entry' } else { $null }
            resultSha256 = if ($passed) { ('6' * 64) } else { $null }
        }
        commands = @(
            [ordered]@{
                ordinal = 1
                phase = 'TEST'
                command = "adb -s $serial shell am instrument -w -e class org.autojs.MatrixTest org.autojs.autojs6.test/androidx.test.runner.AndroidJUnitRunner"
                exitCode = $commandExit
                stdoutSha256 = $script:EmptySha256
                stderrSha256 = $script:EmptySha256
                startedAtUtc = '2026-08-10T01:00:05Z'
                finishedAtUtc = '2026-08-10T01:00:50Z'
            }
        )
        cleanup = [ordered]@{
            attempted = $true
            succeeded = $passed
            packagesRestoredToPreflight = $passed
            processesStopped = $passed
            workspaceClean = $passed
            postStateSha256 = ('9' * 64)
        }
        failure = $failure
    }
}

function Set-TestReceiptFailure {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Receipt
    )

    $Receipt.outcome = 'FAIL'
    $Receipt.output.present = $false
    $Receipt.output.sizeBytes = 0
    $Receipt.output.sha256 = $null
    $Receipt.output.dexEntryCount = 0
    $Receipt.output.entryManifestSha256 = $null
    $Receipt.execution.attempted = $false
    $Receipt.execution.passed = $false
    $Receipt.execution.className = $null
    $Receipt.execution.resultSha256 = $null
    $Receipt.commands[0].exitCode = 17
    $Receipt.cleanup.succeeded = $false
    $Receipt.cleanup.packagesRestoredToPreflight = $false
    $Receipt.cleanup.processesStopped = $false
    $Receipt.cleanup.workspaceClean = $false
    $Receipt.failure = [ordered]@{
        stage = 'INFRASTRUCTURE'
        code = 'TEST_FAILURE'
        messageSha256 = ('a' * 64)
    }
}

function Write-TestReceipt {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Receipt,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $json = $Receipt | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Add-TestReceipt {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Receipt,

        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $ReceiptPath
    )

    Write-TestReceipt -Receipt $Receipt -Path $ReceiptPath
    return Add-R1MatrixReceipt -JournalPath $JournalPath -ReceiptPath $ReceiptPath -SchemaPath $schemaPath
}

function Write-TestAttemptMarker {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Marker,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $json = $Marker | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Write-TestAttemptMarkersFromJournal {
    param(
        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $CaseDirectory,

        [string] $RunnerSha256 = $script:CanonicalAttemptRunnerSha256
    )

    $journal = Read-R1MatrixJournal -JournalPath $JournalPath -SchemaPath $schemaPath
    $attemptDirectory = Join-Path $CaseDirectory "externalRoot\runs\$($journal.CampaignId)\attempts"
    [void](New-Item -ItemType Directory -Path $attemptDirectory -Force)
    foreach ($entry in @($journal.Entries | Where-Object { $_.Receipt.evidenceClass -eq 'CANONICAL' })) {
        $receipt = $entry.Receipt
        $testApkSha256 = if ($receipt.apks.PSObject.Properties.Name -contains 'test') {
            $receipt.apks.test.sha256
        } else {
            ('e' * 64)
        }
        $marker = [ordered]@{
            schemaVersion = $script:CanonicalAttemptSchemaVersion
            campaignId = $receipt.campaignId
            matrixCellId = $receipt.matrixCellId
            receiptId = $receipt.receiptId
            serial = $receipt.device.serial
            createdAtUtc = $receipt.run.startedAtUtc
            runnerSha256 = $RunnerSha256
            hostCommit = $receipt.repositories.host.commit
            pluginCommit = $receipt.repositories.plugin.commit
            hostApkSha256 = $receipt.apks.host.sha256
            pluginApkSha256 = $receipt.apks.plugin.sha256
            testApkSha256 = $testApkSha256
        }
        $path = Join-Path $attemptDirectory "$($receipt.matrixCellId).canonical-attempt.json"
        Write-TestAttemptMarker -Marker $marker -Path $path
    }
    return $attemptDirectory
}

function Invoke-TestMatrixGate {
    param(
        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $CaseDirectory
    )

    $attemptDirectory = Write-TestAttemptMarkersFromJournal `
        -JournalPath $JournalPath `
        -CaseDirectory $CaseDirectory
    return Invoke-R1MatrixGate `
        -JournalPath $JournalPath `
        -SchemaPath $schemaPath `
        -AttemptDirectory $attemptDirectory
}

function Add-CompleteMatrix {
    param(
        [Parameter(Mandatory)]
        [string] $CampaignId,

        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $ReceiptPath,

        [scriptblock] $Mutate
    )

    foreach ($api in @(24, 25, 26, 28, 34, 36)) {
        $receipt = New-TestReceipt -CampaignId $CampaignId -ApiLevel $api
        if ($null -ne $Mutate) {
            & $Mutate $receipt $api
        }
        [void](Add-TestReceipt -Receipt $receipt -JournalPath $JournalPath -ReceiptPath $ReceiptPath)
    }

    $physicalReceipt = New-TestReceipt `
        -CampaignId $CampaignId `
        -ApiLevel 31 `
        -MatrixCellId 'api31-arm64-v8a-physical-qv710af65f' `
        -DeviceKind PHYSICAL `
        -Abi 'arm64-v8a'
    if ($null -ne $Mutate) {
        & $Mutate $physicalReceipt 31
    }
    [void](Add-TestReceipt -Receipt $physicalReceipt -JournalPath $JournalPath -ReceiptPath $ReceiptPath)
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tempRoot = Join-Path $tempBase ("autojs6-r1-matrix-tests-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)

try {
    Invoke-TestCase -Name 'complete canonical matrix passes' -Action {
        $caseDir = Join-Path $tempRoot 'complete'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition $gate.passed -Message ($gate.reasons -join '; ')
        Assert-True -Condition ($gate.canonicalReceiptCount -eq 7) -Message 'Expected seven canonical receipts'
        Assert-True -Condition ($gate.passingCanonicalReceiptCount -eq 7) -Message 'Expected seven passing canonical receipts'
        Assert-True -Condition ($gate.coveredApiLevels.Count -eq 7) -Message 'Expected seven covered device APIs'
        Assert-True -Condition (($gate.coveredApiLevels -join ',') -ceq '24,25,26,28,31,34,36') -Message 'Covered device API set drifted'
        Assert-True -Condition ($gate.requiredMatrixCellIds.Count -eq 7) -Message 'Expected seven required matrix cells'
        Assert-True -Condition ($gate.coveredMatrixCellIds.Count -eq 7) -Message 'Expected seven covered matrix cells'
        Assert-True -Condition ($gate.missingMatrixCellIds.Count -eq 0) -Message 'Complete matrix reported missing cells'
        Assert-True -Condition ($gate.unexpectedMatrixCellIds.Count -eq 0) -Message 'Complete matrix reported unexpected cells'
        Assert-True -Condition ($gate.attemptMarkerFileCount -eq 7) -Message 'Expected seven attempt marker files'
        Assert-True -Condition ($gate.validAttemptMarkerCount -eq 7) -Message 'Expected seven valid attempt markers'
        Assert-True -Condition ($gate.boundAttemptMarkerCount -eq 7) -Message 'Expected seven receipt-bound attempt markers'
        Assert-True -Condition ($gate.missingAttemptReceiptIds.Count -eq 0) -Message 'Complete matrix reported unbound receipts'
        Assert-True -Condition ($gate.attemptRunnerSha256 -ceq $script:CanonicalAttemptRunnerSha256) -Message 'Attempt runner identity drifted'
        Assert-True -Condition $gate.physicalArm64Covered -Message 'Physical arm64 coverage missing'
        Assert-True -Condition $gate.emulatorX86_64Covered -Message 'Emulator x86_64 coverage missing'

        $verified = Read-R1MatrixJournal -JournalPath $journal -SchemaPath $schemaPath
        Assert-True -Condition ($verified.Entries.Count -eq 7) -Message 'Journal verification lost entries'
        Assert-True -Condition ($verified.HeadEntrySha256 -match '^[a-f0-9]{64}$') -Message 'Journal head hash missing'
        $minApis = @($verified.Entries | ForEach-Object { $_.Receipt.request.minApi } | Sort-Object -Unique)
        Assert-True -Condition ($minApis.Count -eq 7) -Message 'Cross-device campaign did not retain one device-specific minApi per row'
    }

    Invoke-TestCase -Name 'missing canonical attempt marker fails closed' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-missing'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        Remove-Item -LiteralPath (Join-Path $attemptDirectory 'api28-x86_64-emulator.canonical-attempt.json')

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'A missing attempt marker incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*Missing canonical attempt marker files*api28-x86_64-emulator*') -Message 'Missing marker filename was not explained'
        Assert-True -Condition ($gate.validAttemptMarkerCount -eq 6) -Message 'Missing marker did not reduce the valid marker count'
        Assert-True -Condition ($gate.missingAttemptReceiptIds.Count -eq 1) -Message 'Missing receipt binding was not reported'
    }

    Invoke-TestCase -Name 'dangling extra canonical attempt marker fails closed' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-dangling'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        $sourcePath = Join-Path $attemptDirectory 'api28-x86_64-emulator.canonical-attempt.json'
        $extraMarker = [IO.File]::ReadAllText($sourcePath, [Text.UTF8Encoding]::new($false, $true)) |
            ConvertFrom-Json -AsHashtable -DateKind String
        $extraMarker.matrixCellId = 'api99-x86_64-emulator'
        $extraMarker.receiptId = [guid]::NewGuid().ToString()
        $extraMarker.serial = 'emulator-5592'
        Write-TestAttemptMarker `
            -Marker $extraMarker `
            -Path (Join-Path $attemptDirectory 'api99-x86_64-emulator.canonical-attempt.json')

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'A dangling extra attempt marker incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*Unexpected canonical attempt marker files*api99-x86_64-emulator*') -Message 'Extra marker filename was not explained'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*is dangling*') -Message 'Dangling receipt binding was not explained'
    }

    Invoke-TestCase -Name 'malformed canonical attempt marker exact fields fail closed' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-malformed-fields'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        $path = Join-Path $attemptDirectory 'api34-x86_64-emulator.canonical-attempt.json'
        $marker = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)) |
            ConvertFrom-Json -AsHashtable -DateKind String
        $marker.Add('inventedField', 'forbidden')
        Write-TestAttemptMarker -Marker $marker -Path $path

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'A marker with an extra field incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*is malformed*exact field set*') -Message 'Malformed marker fields were not explained'
        Assert-True -Condition ($gate.validAttemptMarkerCount -eq 6) -Message 'Malformed marker was counted as valid'
    }

    Invoke-TestCase -Name 'canonical attempt marker framing is exact' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-malformed-framing'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        $path = Join-Path $attemptDirectory 'api25-x86_64-emulator.canonical-attempt.json'
        $withoutFinalLf = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)).TrimEnd("`n")
        [IO.File]::WriteAllText($path, $withoutFinalLf, [Text.UTF8Encoding]::new($false))

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'A marker without its terminal LF incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*is malformed*exactly one LF*') -Message 'Malformed marker framing was not explained'
    }

    Invoke-TestCase -Name 'canonical attempt marker identity must bind its receipt' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-identity-mismatch'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        $path = Join-Path $attemptDirectory 'api34-x86_64-emulator.canonical-attempt.json'
        $marker = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)) |
            ConvertFrom-Json -AsHashtable -DateKind String
        $marker.campaignId = [guid]::NewGuid().ToString()
        $marker.matrixCellId = 'api35-x86_64-emulator'
        $marker.serial = 'emulator-9998'
        $marker.hostCommit = ('0' * 40)
        $marker.pluginCommit = ('1' * 40)
        $marker.hostApkSha256 = ('0' * 64)
        $marker.pluginApkSha256 = ('1' * 64)
        $marker.testApkSha256 = ('2' * 64)
        Write-TestAttemptMarker -Marker $marker -Path $path

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        $reasons = $gate.reasons -join ' '
        Assert-True -Condition (-not $gate.passed) -Message 'A marker with mismatched receipt identity incorrectly passed'
        foreach ($field in @('campaignId', 'matrixCellId', 'serial', 'hostCommit', 'pluginCommit', 'hostApkSha256', 'pluginApkSha256', 'testApkSha256')) {
            Assert-True -Condition ($reasons -like "*$field*") -Message "Marker mismatch for $field was not explained"
        }
    }

    Invoke-TestCase -Name 'canonical attempt markers use one runner binary' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-runner-drift'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir
        $path = Join-Path $attemptDirectory 'api36-x86_64-emulator.canonical-attempt.json'
        $marker = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)) |
            ConvertFrom-Json -AsHashtable -DateKind String
        $marker.runnerSha256 = ('2' * 64)
        Write-TestAttemptMarker -Marker $marker -Path $path

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'Mixed runner identities incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*share exactly one runnerSha256; found 2*') -Message 'Runner identity drift was not explained'
        Assert-True -Condition ($null -eq $gate.attemptRunnerSha256) -Message 'Mixed runners produced one gate runner identity'
    }

    Invoke-TestCase -Name 'canonical attempt marker binds only a PASS receipt' -Action {
        $caseDir = Join-Path $tempRoot 'attempt-non-pass'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 34) { Set-TestReceiptFailure -Receipt $receipt }
            }
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir

        $gate = Invoke-R1MatrixGate -JournalPath $journal -SchemaPath $schemaPath -AttemptDirectory $attemptDirectory
        Assert-True -Condition (-not $gate.passed) -Message 'An attempt marker bound to a FAIL receipt incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*with outcome FAIL, not PASS*') -Message 'Non-PASS attempt binding was not explained'
    }

    Invoke-TestCase -Name 'canonical failure cannot be overwritten by a later pass' -Action {
        $caseDir = Join-Path $tempRoot 'failure-preserved'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $campaign = [guid]::NewGuid().ToString()
        $failure = New-TestReceipt `
            -CampaignId $campaign `
            -ApiLevel 24 `
            -MatrixCellId 'api24-x86_64-emulator' `
            -Outcome FAIL
        [void](Add-TestReceipt -Receipt $failure -JournalPath $journal -ReceiptPath $candidate)
        $laterPass = New-TestReceipt `
            -CampaignId $campaign `
            -ApiLevel 24 `
            -MatrixCellId 'api24-x86_64-emulator'
        [void](Add-TestReceipt -Receipt $laterPass -JournalPath $journal -ReceiptPath $candidate)

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'A later PASS incorrectly masked a formal failure'
        Assert-True -Condition ($gate.failedCanonicalReceiptIds -contains $failure.receiptId) -Message 'Failed receipt ID was not preserved'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*later PASS receipts cannot overwrite it*') -Message 'Missing non-overwrite gate reason'
        Assert-True -Condition (([IO.File]::ReadAllLines($journal)).Count -eq 2) -Message 'Append did not preserve both entries'
    }

    Invoke-TestCase -Name 'smoke evidence never satisfies canonical coverage' -Action {
        $caseDir = Join-Path $tempRoot 'smoke'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $smoke = New-TestReceipt `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -ApiLevel 24 `
            -EvidenceClass SMOKE
        [void](Add-TestReceipt -Receipt $smoke -JournalPath $journal -ReceiptPath $candidate)

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Smoke evidence incorrectly passed the canonical gate'
        Assert-True -Condition ($gate.canonicalReceiptCount -eq 0) -Message 'Smoke evidence was counted as canonical'
        Assert-True -Condition ($gate.ignoredNonCanonicalReceiptCount -eq 1) -Message 'Smoke receipt was not reported as ignored'
    }

    Invoke-TestCase -Name 'journal tampering breaks the hash chain' -Action {
        $caseDir = Join-Path $tempRoot 'tamper'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        [void](Add-TestReceipt -Receipt $receipt -JournalPath $journal -ReceiptPath $candidate)
        $line = [IO.File]::ReadAllText($journal, [Text.UTF8Encoding]::new($false, $true))
        $tampered = $line.Replace('"apiLevel":24', '"apiLevel":25')
        Assert-True -Condition ($tampered -cne $line) -Message 'Test did not locate the API field to tamper'
        [IO.File]::WriteAllText($journal, $tampered, [Text.UTF8Encoding]::new($false))

        Assert-Throws `
            -Action { Read-R1MatrixJournal -JournalPath $journal -SchemaPath $schemaPath } `
            -MessagePattern '*hash mismatch*'
    }

    Invoke-TestCase -Name 'missing final LF is treated as a truncated append' -Action {
        $caseDir = Join-Path $tempRoot 'truncated'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        [void](Add-TestReceipt -Receipt $receipt -JournalPath $journal -ReceiptPath $candidate)
        $bytes = [IO.File]::ReadAllBytes($journal)
        Assert-True -Condition ($bytes[$bytes.Length - 1] -eq 0x0A) -Message 'Writer did not terminate the journal entry with LF'
        [IO.File]::WriteAllBytes($journal, $bytes[0..($bytes.Length - 2)])

        Assert-Throws `
            -Action { Read-R1MatrixJournal -JournalPath $journal -SchemaPath $schemaPath } `
            -MessagePattern '*truncated final append*'
    }

    Invoke-TestCase -Name 'duplicate receipt IDs are rejected before append' -Action {
        $caseDir = Join-Path $tempRoot 'duplicate-id'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        [void](Add-TestReceipt -Receipt $receipt -JournalPath $journal -ReceiptPath $candidate)

        Assert-Throws `
            -Action { Add-TestReceipt -Receipt $receipt -JournalPath $journal -ReceiptPath $candidate } `
            -MessagePattern '*receiptId already exists*'
        Assert-True -Condition (([IO.File]::ReadAllLines($journal)).Count -eq 1) -Message 'Rejected duplicate changed the journal'
    }

    Invoke-TestCase -Name 'mixed artifact identity fails closed' -Action {
        $caseDir = Join-Path $tempRoot 'identity-drift'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 34) { $receipt.apks.plugin.sha256 = ('0' * 64) }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Mixed plugin APK identity incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*mix repository, APK, input, or compile-request identities*') -Message 'Identity drift was not explained'
    }

    Invoke-TestCase -Name 'canonical receipt must identify the exact Android test APK' -Action {
        $caseDir = Join-Path $tempRoot 'missing-test-apk'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 28) { [void]$receipt.apks.Remove('test') }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Canonical receipt without a test APK identity incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*does not identify the exact Android test APK*') -Message 'Missing-test-APK reason was not explained'
    }

    Invoke-TestCase -Name 'test APK SHA drift changes the campaign identity' -Action {
        $caseDir = Join-Path $tempRoot 'test-apk-drift'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 34) { $receipt.apks.test.sha256 = ('0' * 64) }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Mixed test APK identity incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*mix repository, APK, input, or compile-request identities*') -Message 'Test APK drift was not included in the campaign identity'
        Assert-True -Condition ($null -eq $gate.campaignIdentitySha256) -Message 'Mixed test APK identities produced one campaign identity'
    }

    Invoke-TestCase -Name 'unexpected canonical cell ID fails closed' -Action {
        $caseDir = Join-Path $tempRoot 'unexpected-cell'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 28) { $receipt.matrixCellId = 'api29-x86_64-emulator' }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Unexpected canonical matrixCellId incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*Missing required CANONICAL matrixCellId values*api28-x86_64-emulator*') -Message 'Missing canonical cell was not explained'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*Unexpected CANONICAL matrixCellId values*api29-x86_64-emulator*') -Message 'Unexpected canonical cell was not explained'
    }

    Invoke-TestCase -Name 'canonical receipt count is exactly seven' -Action {
        $caseDir = Join-Path $tempRoot 'canonical-count'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 31) { $receipt.evidenceClass = 'SMOKE' }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Six canonical receipts incorrectly passed the seven-cell gate'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*Expected exactly 7 CANONICAL receipts, found 6*') -Message 'Exact canonical-count reason missing'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*api31-arm64-v8a-physical-qv710af65f*') -Message 'Missing physical cell was not explained'
    }

    Invoke-TestCase -Name 'canonical cell device shape is exact' -Action {
        $caseDir = Join-Path $tempRoot 'cell-shape'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 34) { $receipt.device.avdName = 'DEX_R1_API33_X64' }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Wrong AVD shape incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like "*api34-x86_64-emulator*device.avdName*DEX_R1_API34_X64*") -Message 'Wrong AVD shape was not explained'
    }

    Invoke-TestCase -Name 'dirty source tree fails canonical gate' -Action {
        $caseDir = Join-Path $tempRoot 'dirty-tree'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 28) {
                    $receipt.repositories.host.treeState = 'DIRTY'
                    $receipt.repositories.host.treeDigestSha256 = ('a' * 64)
                }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Dirty source tree incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*not collected from two clean source trees*') -Message 'Dirty-tree reason missing'
    }

    Invoke-TestCase -Name 'request minApi must equal the receipt device API' -Action {
        $caseDir = Join-Path $tempRoot 'min-api-drift'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        Add-CompleteMatrix `
            -CampaignId ([guid]::NewGuid().ToString()) `
            -JournalPath $journal `
            -ReceiptPath $candidate `
            -Mutate {
                param($receipt, $api)
                if ($api -eq 34) { $receipt.request.minApi = 33 }
            }

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'A device/request minApi mismatch incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*request.minApi 33 does not equal device API 34*') -Message 'minApi mismatch reason missing'
    }

    Invoke-TestCase -Name 'schema omissions are rejected before journal creation' -Action {
        $caseDir = Join-Path $tempRoot 'schema-reject'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        $receipt.Remove('provider')
        Write-TestReceipt -Receipt $receipt -Path $candidate

        Assert-Throws `
            -Action { Add-R1MatrixReceipt -JournalPath $journal -ReceiptPath $candidate -SchemaPath $schemaPath } `
            -MessagePattern '*violates the R1 receipt schema*'
        Assert-True -Condition (-not (Test-Path -LiteralPath $journal)) -Message 'Invalid receipt created a journal'
    }

    Invoke-TestCase -Name 'test APK identity rejects invented version fields' -Action {
        $caseDir = Join-Path $tempRoot 'test-apk-version-reject'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        $receipt.apks.test.Add('versionName', '6.8.0 Alpha7')
        $receipt.apks.test.Add('versionCode', 5274)
        Write-TestReceipt -Receipt $receipt -Path $candidate

        Assert-Throws `
            -Action { Add-R1MatrixReceipt -JournalPath $journal -ReceiptPath $candidate -SchemaPath $schemaPath } `
            -MessagePattern '*violates the R1 receipt schema*'
        Assert-True -Condition (-not (Test-Path -LiteralPath $journal)) -Message 'Invented test APK version fields created a journal'
    }

    Invoke-TestCase -Name 'resolved explicit serial is independently enforced' -Action {
        $caseDir = Join-Path $tempRoot 'serial-reject'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        $receipt.commands[0].command = 'adb shell am instrument -w org.autojs.autojs6.test/androidx.test.runner.AndroidJUnitRunner'
        [void](Add-TestReceipt -Receipt $receipt -JournalPath $journal -ReceiptPath $candidate)

        $gate = Invoke-TestMatrixGate -JournalPath $journal -CaseDirectory $caseDir
        Assert-True -Condition (-not $gate.passed) -Message 'Unscoped adb command incorrectly passed'
        Assert-True -Condition (($gate.reasons -join ' ') -like '*invokes adb without the recorded explicit serial*') -Message 'Explicit-serial reason missing'
    }

    Invoke-TestCase -Name 'CLI Append and Verify remain independent of attempt markers' -Action {
        $caseDir = Join-Path $tempRoot 'cli-compatible'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $receipt = New-TestReceipt -CampaignId ([guid]::NewGuid().ToString()) -ApiLevel 24
        Write-TestReceipt -Receipt $receipt -Path $candidate

        & pwsh -NoLogo -NoProfile -File $cliPath Append -JournalPath $journal -ReceiptPath $candidate | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Expected CLI Append without -AttemptDirectory to exit 0, got $LASTEXITCODE"
        & pwsh -NoLogo -NoProfile -File $cliPath Verify -JournalPath $journal | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Expected CLI Verify without -AttemptDirectory to exit 0, got $LASTEXITCODE"
    }

    Invoke-TestCase -Name 'CLI report creation is create-new and non-overwriting' -Action {
        $caseDir = Join-Path $tempRoot 'cli'
        [void](New-Item -ItemType Directory -Path $caseDir)
        $journal = Join-Path $caseDir 'journal.jsonl'
        $candidate = Join-Path $caseDir 'candidate.json'
        $report = Join-Path $caseDir 'gate.json'
        $missingAttemptReport = Join-Path $caseDir 'missing-attempt-gate.json'
        Add-CompleteMatrix -CampaignId ([guid]::NewGuid().ToString()) -JournalPath $journal -ReceiptPath $candidate
        $attemptDirectory = Write-TestAttemptMarkersFromJournal -JournalPath $journal -CaseDirectory $caseDir

        & pwsh -NoLogo -NoProfile -File $cliPath Gate -JournalPath $journal -ReportPath $missingAttemptReport | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 2) -Message "Expected missing -AttemptDirectory refusal exit 2, got $LASTEXITCODE"
        Assert-True -Condition (-not (Test-Path -LiteralPath $missingAttemptReport)) -Message 'CLI wrote a report without -AttemptDirectory'

        & pwsh -NoLogo -NoProfile -File $cliPath Gate -JournalPath $journal -AttemptDirectory $attemptDirectory -ReportPath $report | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Expected CLI gate exit 0, got $LASTEXITCODE"
        Assert-True -Condition (Test-Path -LiteralPath $report -PathType Leaf) -Message 'CLI report was not created'
        $before = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
        & pwsh -NoLogo -NoProfile -File $cliPath Gate -JournalPath $journal -AttemptDirectory $attemptDirectory -ReportPath $report | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 2) -Message "Expected create-new refusal exit 2, got $LASTEXITCODE"
        $after = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
        Assert-True -Condition ($before -ceq $after) -Message 'Existing report was overwritten'
    }
} finally {
    $resolvedRoot = [IO.Path]::GetFullPath($tempRoot)
    $parent = [IO.Path]::GetDirectoryName($resolvedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $leaf = [IO.Path]::GetFileName($resolvedRoot)
    if ($parent -cne $tempBase -or $leaf -notlike 'autojs6-r1-matrix-tests-*') {
        throw "Refusing to remove unexpected test directory: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

Write-Output "RESULT passed=$script:TestsPassed failed=$script:TestsFailed"
if ($script:TestsFailed -ne 0) {
    exit 1
}
exit 0
