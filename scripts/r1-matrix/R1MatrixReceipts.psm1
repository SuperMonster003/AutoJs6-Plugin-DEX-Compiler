#Requires -Version 7.5

Set-StrictMode -Version Latest

$script:ReceiptSchemaVersion = 'autojs6.dex.r1.matrix-receipt/v1'
$script:JournalSchemaVersion = 'autojs6.dex.r1.matrix-journal-entry/v1'
$script:GateSchemaVersion = 'autojs6.dex.r1.matrix-gate/v1'
$script:GenesisHash = 'GENESIS'
$script:EmptySha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
$script:DefaultRequiredApiLevels = @(24, 25, 26, 28, 34, 36)

function Get-R1Sha256Text {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $digest = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($digest).ToLowerInvariant()
}

function ConvertTo-R1CanonicalJson {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [string]) {
        return [System.Text.Json.JsonSerializer]::Serialize([string] $Value, [string])
    }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]
    ) {
        return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $names = @($Value.Keys | ForEach-Object { [string] $_ })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $members = foreach ($name in $names) {
            $encodedName = [System.Text.Json.JsonSerializer]::Serialize($name, [string])
            $encodedValue = ConvertTo-R1CanonicalJson -Value $Value[$name]
            "$encodedName`:$encodedValue"
        }
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $propertyMap = @{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -in @('NoteProperty', 'Property')) {
                $propertyMap[$property.Name] = $property.Value
            }
        }
        return ConvertTo-R1CanonicalJson -Value $propertyMap
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = foreach ($item in $Value) {
            ConvertTo-R1CanonicalJson -Value $item
        }
        return '[' + ($items -join ',') + ']'
    }
    throw "Unsupported value type in canonical JSON: $($Value.GetType().FullName)"
}

function Assert-R1NoDuplicateJsonProperties {
    param(
        [Parameter(Mandatory)]
        [string] $Json,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json)

        function Visit-R1JsonElement {
            param(
                [System.Text.Json.JsonElement] $Element,
                [string] $Path
            )

            if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($property in $Element.EnumerateObject()) {
                    if (-not $seen.Add($property.Name)) {
                        throw "$Label contains duplicate JSON property '$($property.Name)' at $Path"
                    }
                    Visit-R1JsonElement -Element $property.Value -Path "$Path.$($property.Name)"
                }
            } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                $index = 0
                foreach ($item in $Element.EnumerateArray()) {
                    Visit-R1JsonElement -Element $item -Path "$Path[$index]"
                    $index++
                }
            }
        }

        Visit-R1JsonElement -Element $document.RootElement -Path '$'
    } catch {
        throw "$Label is not strict JSON: $($_.Exception.Message)"
    } finally {
        if ($null -ne $document) {
            $document.Dispose()
        }
    }
}

function ConvertFrom-R1StrictJson {
    param(
        [Parameter(Mandatory)]
        [string] $Json,

        [Parameter(Mandatory)]
        [string] $Label
    )

    Assert-R1NoDuplicateJsonProperties -Json $Json -Label $Label
    try {
        return $Json | ConvertFrom-Json -Depth 100 -NoEnumerate -DateKind String -ErrorAction Stop
    } catch {
        throw "$Label could not be decoded: $($_.Exception.Message)"
    }
}

function Assert-R1UtcTimestamp {
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $parsed = [datetimeoffset]::MinValue
    $valid = [datetimeoffset]::TryParseExact(
        $Value,
        [string[]] @("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'"),
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref] $parsed
    )
    if (-not $valid -or $parsed.Offset -ne [timespan]::Zero) {
        throw "$Label must be an exact UTC timestamp ending in Z"
    }
    return $parsed
}

function Assert-R1SignerSet {
    param(
        [Parameter(Mandatory)]
        [object[]] $Signers,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($signer in $Signers) {
        if (-not $seen.Add([string] $signer)) {
            throw "$Label contains a duplicate signer certificate digest"
        }
    }
}

function Assert-R1ReceiptSemantics {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Receipt
    )

    $runStart = Assert-R1UtcTimestamp -Value $Receipt.run.startedAtUtc -Label 'run.startedAtUtc'
    $runEnd = Assert-R1UtcTimestamp -Value $Receipt.run.finishedAtUtc -Label 'run.finishedAtUtc'
    if ($runEnd -lt $runStart) {
        throw 'run.finishedAtUtc precedes run.startedAtUtc'
    }

    if ($Receipt.device.allAbis -cnotcontains $Receipt.device.abi) {
        throw 'device.abi must be present in device.allAbis with exact case'
    }
    if ($Receipt.device.kind -eq 'EMULATOR' -and [string]::IsNullOrWhiteSpace($Receipt.device.avdName)) {
        throw 'device.avdName is required for an emulator receipt'
    }
    if ($Receipt.device.kind -eq 'PHYSICAL' -and $null -ne $Receipt.device.avdName) {
        throw 'device.avdName must be null for a physical-device receipt'
    }

    Assert-R1SignerSet -Signers @($Receipt.apks.host.signerCertificateSha256) -Label 'apks.host.signerCertificateSha256'
    Assert-R1SignerSet -Signers @($Receipt.apks.plugin.signerCertificateSha256) -Label 'apks.plugin.signerCertificateSha256'
    if ($Receipt.apks.PSObject.Properties.Name -contains 'test') {
        Assert-R1SignerSet -Signers @($Receipt.apks.test.signerCertificateSha256) -Label 'apks.test.signerCertificateSha256'
    }
    Assert-R1SignerSet -Signers @($Receipt.provider.signerCertificateSha256) -Label 'provider.signerCertificateSha256'

    if ($Receipt.outcome -eq 'PASS' -and $null -ne $Receipt.failure) {
        throw 'A PASS receipt must set failure to null'
    }
    if ($Receipt.outcome -ne 'PASS' -and $null -eq $Receipt.failure) {
        throw 'A FAIL or BLOCKED receipt must include failure details'
    }
    if (-not $Receipt.output.present) {
        if ($Receipt.output.sizeBytes -ne 0 -or $Receipt.output.dexEntryCount -ne 0) {
            throw 'An absent output must have zero size and zero DEX entries'
        }
        if ($null -ne $Receipt.output.sha256 -or $null -ne $Receipt.output.entryManifestSha256) {
            throw 'An absent output must have null digests'
        }
    } elseif ($Receipt.output.sizeBytes -le 0 -or $null -eq $Receipt.output.sha256) {
        throw 'A present output must have a non-zero size and SHA-256 digest'
    }

    $expectedOrdinal = 1
    foreach ($command in $Receipt.commands) {
        if ($command.ordinal -ne $expectedOrdinal) {
            throw "commands must use contiguous ordinals beginning at 1; expected $expectedOrdinal"
        }
        if ($command.command.Contains("`r") -or $command.command.Contains("`n")) {
            throw "commands[$($command.ordinal)].command must be one resolved command line"
        }
        $commandStart = Assert-R1UtcTimestamp -Value $command.startedAtUtc -Label "commands[$($command.ordinal)].startedAtUtc"
        $commandEnd = Assert-R1UtcTimestamp -Value $command.finishedAtUtc -Label "commands[$($command.ordinal)].finishedAtUtc"
        if ($commandEnd -lt $commandStart) {
            throw "commands[$($command.ordinal)].finishedAtUtc precedes its start"
        }
        if ($commandStart -lt $runStart -or $commandEnd -gt $runEnd) {
            throw "commands[$($command.ordinal)] falls outside the recorded run interval"
        }
        $expectedOrdinal++
    }

    if ($Receipt.outcome -eq 'PASS') {
        if (-not $Receipt.output.present -or $Receipt.output.sizeBytes -le 0 -or $Receipt.output.dexEntryCount -le 0) {
            throw 'A PASS receipt requires a non-empty DEX ZIP output'
        }
        if ($null -eq $Receipt.output.sha256 -or $null -eq $Receipt.output.entryManifestSha256) {
            throw 'A PASS receipt requires output and entry-manifest digests'
        }
        if (-not $Receipt.execution.attempted -or -not $Receipt.execution.passed) {
            throw 'A PASS receipt requires a successful real class execution'
        }
        if ([string]::IsNullOrWhiteSpace($Receipt.execution.className) -or $null -eq $Receipt.execution.resultSha256) {
            throw 'A PASS receipt requires the executed class and result digest'
        }
        foreach ($command in $Receipt.commands) {
            if ($command.exitCode -ne 0) {
                throw "A PASS receipt contains non-zero command exit code at ordinal $($command.ordinal)"
            }
        }
        if (
            -not $Receipt.cleanup.attempted -or
            -not $Receipt.cleanup.succeeded -or
            -not $Receipt.cleanup.packagesRestoredToPreflight -or
            -not $Receipt.cleanup.processesStopped -or
            -not $Receipt.cleanup.workspaceClean
        ) {
            throw 'A PASS receipt requires complete, successful cleanup and state restoration'
        }
    }
}

function Read-R1Receipt {
    param(
        [Parameter(Mandatory)]
        [string] $Json,

        [Parameter(Mandatory)]
        [string] $SchemaPath,

        [string] $Label = 'receipt'
    )

    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "Receipt schema does not exist: $SchemaPath"
    }
    Assert-R1NoDuplicateJsonProperties -Json $Json -Label $Label
    $schemaErrors = @()
    $valid = Test-Json -Json $Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue -ErrorVariable schemaErrors
    if (-not $valid) {
        $detail = if ($schemaErrors.Count -gt 0) { $schemaErrors[0].Exception.Message } else { 'unknown schema violation' }
        throw "$Label violates the R1 receipt schema: $detail"
    }
    $receipt = ConvertFrom-R1StrictJson -Json $Json -Label $Label
    Assert-R1ReceiptSemantics -Receipt $receipt
    return $receipt
}

function Get-R1UnsignedJournalEntry {
    param(
        [Parameter(Mandatory)]
        [long] $Sequence,

        [Parameter(Mandatory)]
        [string] $PreviousEntrySha256,

        [Parameter(Mandatory)]
        [string] $AppendedAtUtc,

        [Parameter(Mandatory)]
        [pscustomobject] $Receipt
    )

    return [ordered]@{
        schemaVersion = $script:JournalSchemaVersion
        sequence = $Sequence
        previousEntrySha256 = $PreviousEntrySha256
        appendedAtUtc = $AppendedAtUtc
        receipt = $Receipt
    }
}

function Assert-R1ExactProperties {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Object,

        [Parameter(Mandatory)]
        [string[]] $Expected,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $actual = @($Object.PSObject.Properties.Name)
    $unexpected = @($actual | Where-Object { $_ -notin $Expected })
    $missing = @($Expected | Where-Object { $_ -notin $actual })
    if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
        throw "$Label property mismatch; missing=[$($missing -join ',')], unexpected=[$($unexpected -join ',')]"
    }
}

function Read-R1MatrixJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    $resolvedJournal = [IO.Path]::GetFullPath($JournalPath)
    if (-not (Test-Path -LiteralPath $resolvedJournal)) {
        return [pscustomobject][ordered]@{
            JournalPath = $resolvedJournal
            Entries = @()
            HeadEntrySha256 = $script:GenesisHash
            CampaignId = $null
        }
    }
    if (-not (Test-Path -LiteralPath $resolvedJournal -PathType Leaf)) {
        throw "Journal path is not a regular file: $resolvedJournal"
    }

    $journalBytes = [IO.File]::ReadAllBytes($resolvedJournal)
    if ($journalBytes.Length -gt 0 -and $journalBytes[$journalBytes.Length - 1] -ne 0x0A) {
        throw 'Journal does not end with LF and may contain a truncated final append'
    }
    $lines = [IO.File]::ReadAllLines($resolvedJournal, [Text.UTF8Encoding]::new($false, $true))
    $entries = [Collections.Generic.List[object]]::new()
    $receiptIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $previousHash = $script:GenesisHash
    $campaignId = $null
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw "Journal contains an empty or truncated line at $lineNumber"
        }
        $entry = ConvertFrom-R1StrictJson -Json $line -Label "journal line $lineNumber"
        Assert-R1ExactProperties -Object $entry -Expected @(
            'schemaVersion',
            'sequence',
            'previousEntrySha256',
            'appendedAtUtc',
            'receipt',
            'entrySha256'
        ) -Label "journal line $lineNumber"
        if ($entry.schemaVersion -cne $script:JournalSchemaVersion) {
            throw "Unsupported journal schema at line $lineNumber"
        }
        if ($entry.sequence -isnot [long] -and $entry.sequence -isnot [int]) {
            throw "Journal sequence is not an integer at line $lineNumber"
        }
        if ([long] $entry.sequence -ne $lineNumber) {
            throw "Journal sequence mismatch at line $lineNumber"
        }
        if ($entry.previousEntrySha256 -cne $previousHash) {
            throw "Journal hash chain is broken at line $lineNumber"
        }
        [void](Assert-R1UtcTimestamp -Value $entry.appendedAtUtc -Label "journal line $lineNumber appendedAtUtc")

        $receiptJson = ConvertTo-R1CanonicalJson -Value $entry.receipt
        $receipt = Read-R1Receipt -Json $receiptJson -SchemaPath $SchemaPath -Label "journal line $lineNumber receipt"
        if (-not $receiptIds.Add($receipt.receiptId)) {
            throw "Duplicate receiptId at journal line $lineNumber"
        }
        if ($null -eq $campaignId) {
            $campaignId = $receipt.campaignId
        } elseif ($receipt.campaignId -cne $campaignId) {
            throw "Mixed campaignId values at journal line $lineNumber"
        }

        $unsigned = Get-R1UnsignedJournalEntry `
            -Sequence ([long] $entry.sequence) `
            -PreviousEntrySha256 $entry.previousEntrySha256 `
            -AppendedAtUtc $entry.appendedAtUtc `
            -Receipt $receipt
        $computedHash = Get-R1Sha256Text -Text (ConvertTo-R1CanonicalJson -Value $unsigned)
        if ($entry.entrySha256 -cne $computedHash) {
            throw "Journal entry hash mismatch at line $lineNumber"
        }
        $previousHash = $computedHash
        $entries.Add([pscustomobject][ordered]@{
            Sequence = [long] $entry.sequence
            AppendedAtUtc = $entry.appendedAtUtc
            Receipt = $receipt
            EntrySha256 = $computedHash
        })
    }

    return [pscustomobject][ordered]@{
        JournalPath = $resolvedJournal
        Entries = @($entries)
        HeadEntrySha256 = $previousHash
        CampaignId = $campaignId
    }
}

function Open-R1JournalLock {
    param(
        [Parameter(Mandatory)]
        [string] $LockPath,

        [int] $TimeoutSeconds = 30
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            return [IO.File]::Open(
                $LockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        } catch [IO.IOException] {
            if ([datetime]::UtcNow -ge $deadline) {
                throw "Timed out acquiring the journal lock: $LockPath"
            }
            Start-Sleep -Milliseconds 100
        }
    } while ($true)
}

function Add-R1MatrixReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $ReceiptPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    $resolvedJournal = [IO.Path]::GetFullPath($JournalPath)
    $resolvedReceipt = [IO.Path]::GetFullPath($ReceiptPath)
    if (-not (Test-Path -LiteralPath $resolvedReceipt -PathType Leaf)) {
        throw "Receipt file does not exist: $resolvedReceipt"
    }
    $journalDirectory = [IO.Path]::GetDirectoryName($resolvedJournal)
    if (-not (Test-Path -LiteralPath $journalDirectory -PathType Container)) {
        throw "Journal directory does not exist: $journalDirectory"
    }

    $receiptJson = [IO.File]::ReadAllText($resolvedReceipt, [Text.UTF8Encoding]::new($false, $true))
    $receipt = Read-R1Receipt -Json $receiptJson -SchemaPath $SchemaPath -Label 'candidate receipt'
    $lock = Open-R1JournalLock -LockPath "$resolvedJournal.lock"
    try {
        $journal = Read-R1MatrixJournal -JournalPath $resolvedJournal -SchemaPath $SchemaPath
        if ($journal.Entries.Count -gt 0 -and $journal.CampaignId -cne $receipt.campaignId) {
            throw 'Candidate receipt campaignId does not match the append-only journal campaign'
        }
        if (@($journal.Entries | Where-Object { $_.Receipt.receiptId -ieq $receipt.receiptId }).Count -gt 0) {
            throw "Candidate receiptId already exists in the journal: $($receipt.receiptId)"
        }

        $sequence = [long] $journal.Entries.Count + 1L
        $appendedAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
        $unsigned = Get-R1UnsignedJournalEntry `
            -Sequence $sequence `
            -PreviousEntrySha256 $journal.HeadEntrySha256 `
            -AppendedAtUtc $appendedAtUtc `
            -Receipt $receipt
        $entryHash = Get-R1Sha256Text -Text (ConvertTo-R1CanonicalJson -Value $unsigned)
        $entry = [ordered]@{
            schemaVersion = $script:JournalSchemaVersion
            sequence = $sequence
            previousEntrySha256 = $journal.HeadEntrySha256
            appendedAtUtc = $appendedAtUtc
            receipt = $receipt
            entrySha256 = $entryHash
        }
        $line = $entry | ConvertTo-Json -Depth 100 -Compress

        $stream = [IO.File]::Open(
            $resolvedJournal,
            [IO.FileMode]::Append,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read
        )
        try {
            $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false), 4096, $true)
            try {
                $writer.NewLine = "`n"
                $writer.WriteLine($line)
                $writer.Flush()
                $stream.Flush($true)
            } finally {
                $writer.Dispose()
            }
        } finally {
            $stream.Dispose()
        }

        return [pscustomobject][ordered]@{
            schemaVersion = $script:JournalSchemaVersion
            journalPath = $resolvedJournal
            campaignId = $receipt.campaignId
            receiptId = $receipt.receiptId
            sequence = $sequence
            entrySha256 = $entryHash
        }
    } finally {
        $lock.Dispose()
    }
}

function Get-R1NormalizedSignerKey {
    param(
        [Parameter(Mandatory)]
        [object[]] $Signers
    )

    return (@($Signers | ForEach-Object { ([string] $_).ToLowerInvariant() } | Sort-Object) -join ',')
}

function Get-R1CampaignIdentityKey {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Receipt
    )

    $identity = [ordered]@{
        repositories = $Receipt.repositories
        apks = $Receipt.apks
        input = $Receipt.input
        request = [ordered]@{
            mode = $Receipt.request.mode
            multiDexExpected = $Receipt.request.multiDexExpected
            outputFormat = $Receipt.request.outputFormat
        }
    }
    return Get-R1Sha256Text -Text (ConvertTo-R1CanonicalJson -Value $identity)
}

function Test-R1ResolvedAdbSerial {
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [string] $Serial
    )

    if ($Command -notmatch '(?i)(?:^|[\s"''])(?:[A-Z]:[\\/][^"'']*[\\/])?adb(?:\.exe)?(?=$|[\s"''])') {
        return $true
    }
    $escapedSerial = [regex]::Escape($Serial)
    return $Command -match "(?i)(?:^|\s)-s\s+(?:`"$escapedSerial`"|'$escapedSerial'|$escapedSerial)(?:\s|$)"
}

function Invoke-R1MatrixGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $JournalPath,

        [Parameter(Mandatory)]
        [string] $SchemaPath,

        [int[]] $RequiredApiLevels = $script:DefaultRequiredApiLevels
    )

    $expectedApis = @($RequiredApiLevels | Sort-Object -Unique)
    if (($expectedApis -join ',') -ne ($script:DefaultRequiredApiLevels -join ',')) {
        throw "The canonical R1 gate API set is fixed at: $($script:DefaultRequiredApiLevels -join ', ')"
    }

    $journal = Read-R1MatrixJournal -JournalPath $JournalPath -SchemaPath $SchemaPath
    $reasons = [Collections.Generic.List[string]]::new()
    $canonical = @($journal.Entries | Where-Object { $_.Receipt.evidenceClass -eq 'CANONICAL' })
    $nonCanonical = @($journal.Entries | Where-Object { $_.Receipt.evidenceClass -ne 'CANONICAL' })
    $passingCanonical = @($canonical | Where-Object { $_.Receipt.outcome -eq 'PASS' })
    $failedCanonical = @($canonical | Where-Object { $_.Receipt.outcome -ne 'PASS' })

    if ($canonical.Count -eq 0) {
        $reasons.Add('No CANONICAL receipts are present; smoke and diagnostic receipts never satisfy the gate.')
    }
    foreach ($entry in $failedCanonical) {
        $reasons.Add("Canonical receipt $($entry.Receipt.receiptId) is $($entry.Receipt.outcome); later PASS receipts cannot overwrite it.")
    }

    $cellGroups = @($canonical | Group-Object { $_.Receipt.matrixCellId })
    foreach ($group in $cellGroups) {
        if ($group.Count -gt 1) {
            $reasons.Add("Canonical matrixCellId '$($group.Name)' occurs $($group.Count) times and is ambiguous.")
        }
    }

    $identityKeys = @($canonical | ForEach-Object { Get-R1CampaignIdentityKey -Receipt $_.Receipt } | Sort-Object -Unique)
    if ($identityKeys.Count -gt 1) {
        $reasons.Add('Canonical receipts mix repository, APK, input, or compile-request identities within one campaign.')
    }

    foreach ($entry in $canonical) {
        $receipt = $entry.Receipt
        if ($receipt.repositories.host.treeState -ne 'CLEAN' -or $receipt.repositories.plugin.treeState -ne 'CLEAN') {
            $reasons.Add("Canonical receipt $($receipt.receiptId) was not collected from two clean source trees.")
        }
        if (
            $receipt.repositories.host.treeState -eq 'CLEAN' -and
            $receipt.repositories.host.treeDigestSha256 -ine $script:EmptySha256
        ) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) has a non-empty host tree digest while marked CLEAN.")
        }
        if (
            $receipt.repositories.plugin.treeState -eq 'CLEAN' -and
            $receipt.repositories.plugin.treeDigestSha256 -ine $script:EmptySha256
        ) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) has a non-empty plugin tree digest while marked CLEAN.")
        }
        if ($receipt.provider.kind -ne 'REAL') {
            $reasons.Add("Canonical receipt $($receipt.receiptId) used a fake provider.")
        }
        if (-not $receipt.safety.userAuthorized -or -not $receipt.safety.explicitSerialEveryAdbCommand) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) lacks user authorization or explicit-serial evidence.")
        }
        if ($receipt.safety.fakeProviderInstalled) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) had a fake provider installed.")
        }
        if ($receipt.provider.packageName -cne $receipt.apks.plugin.packageName) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) provider package does not match the plugin APK.")
        }
        if (-not $receipt.provider.component.StartsWith("$($receipt.provider.packageName)/", [StringComparison]::Ordinal)) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) provider component is not pinned inside its package.")
        }
        if (
            $receipt.provider.versionName -cne $receipt.apks.plugin.versionName -or
            $receipt.provider.versionCode -ne $receipt.apks.plugin.versionCode
        ) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) provider version does not match the plugin APK.")
        }
        if (
            $receipt.repositories.host.versionName -cne $receipt.apks.host.versionName -or
            $receipt.repositories.host.versionCode -ne $receipt.apks.host.versionCode -or
            $receipt.repositories.plugin.versionName -cne $receipt.apks.plugin.versionName -or
            $receipt.repositories.plugin.versionCode -ne $receipt.apks.plugin.versionCode
        ) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) repository and APK versions do not match.")
        }

        $hostSigners = Get-R1NormalizedSignerKey -Signers @($receipt.apks.host.signerCertificateSha256)
        $pluginSigners = Get-R1NormalizedSignerKey -Signers @($receipt.apks.plugin.signerCertificateSha256)
        $providerSigners = Get-R1NormalizedSignerKey -Signers @($receipt.provider.signerCertificateSha256)
        if ($hostSigners -cne $pluginSigners -or $pluginSigners -cne $providerSigners) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) does not preserve the exact host/plugin/provider signer set.")
        }
        if ($receipt.apks.PSObject.Properties.Name -contains 'test') {
            $testSigners = Get-R1NormalizedSignerKey -Signers @($receipt.apks.test.signerCertificateSha256)
            if ($hostSigners -cne $testSigners) {
                $reasons.Add("Canonical receipt $($receipt.receiptId) test APK signer set differs from the host.")
            }
        }

        $expectedCompilerPath = if ($receipt.device.apiLevel -le 25) { 'D8_CLI_FALLBACK' } else { 'D8_COMMAND' }
        if ($receipt.request.minApi -ne $receipt.device.apiLevel) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) request.minApi $($receipt.request.minApi) does not equal device API $($receipt.device.apiLevel).")
        }
        if ($receipt.request.compilerPath -cne $expectedCompilerPath) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) uses $($receipt.request.compilerPath) on API $($receipt.device.apiLevel); expected $expectedCompilerPath.")
        }
        if (@($receipt.commands | Where-Object { $_.phase -eq 'TEST' }).Count -eq 0) {
            $reasons.Add("Canonical receipt $($receipt.receiptId) has no TEST command receipt.")
        }
        foreach ($command in $receipt.commands) {
            if (-not (Test-R1ResolvedAdbSerial -Command $command.command -Serial $receipt.device.serial)) {
                $reasons.Add("Canonical receipt $($receipt.receiptId) command ordinal $($command.ordinal) invokes adb without the recorded explicit serial.")
            }
        }
    }

    $coveredApis = @($passingCanonical | ForEach-Object { [int] $_.Receipt.device.apiLevel } | Sort-Object -Unique)
    $missingApis = @($expectedApis | Where-Object { $_ -notin $coveredApis })
    if ($missingApis.Count -gt 0) {
        $reasons.Add("Missing passing CANONICAL API levels: $($missingApis -join ', ').")
    }

    $physicalArm64 = @($passingCanonical | Where-Object {
        $_.Receipt.device.kind -eq 'PHYSICAL' -and $_.Receipt.device.abi -eq 'arm64-v8a'
    }).Count -gt 0
    $emulatorX64 = @($passingCanonical | Where-Object {
        $_.Receipt.device.kind -eq 'EMULATOR' -and $_.Receipt.device.abi -eq 'x86_64'
    }).Count -gt 0
    if (-not $physicalArm64) {
        $reasons.Add('No passing CANONICAL arm64-v8a physical-device receipt is present.')
    }
    if (-not $emulatorX64) {
        $reasons.Add('No passing CANONICAL x86_64 emulator receipt is present.')
    }

    $uniqueReasons = @($reasons | Sort-Object -Unique)
    return [pscustomobject][ordered]@{
        schemaVersion = $script:GateSchemaVersion
        generatedAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
        passed = $uniqueReasons.Count -eq 0
        campaignId = $journal.CampaignId
        journalEntryCount = $journal.Entries.Count
        journalHeadEntrySha256 = $journal.HeadEntrySha256
        canonicalReceiptCount = $canonical.Count
        passingCanonicalReceiptCount = $passingCanonical.Count
        failedCanonicalReceiptIds = @($failedCanonical | ForEach-Object { $_.Receipt.receiptId })
        ignoredNonCanonicalReceiptCount = $nonCanonical.Count
        requiredApiLevels = $expectedApis
        coveredApiLevels = $coveredApis
        missingApiLevels = $missingApis
        physicalArm64Covered = $physicalArm64
        emulatorX86_64Covered = $emulatorX64
        campaignIdentitySha256 = if ($identityKeys.Count -eq 1) { $identityKeys[0] } else { $null }
        reasons = $uniqueReasons
    }
}

function Write-R1CreateNewUtf8File {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Content
    )

    $resolved = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($resolved)
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Output directory does not exist: $directory"
    }
    $stream = [IO.File]::Open($resolved, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
}

Export-ModuleMember -Function @(
    'Add-R1MatrixReceipt',
    'ConvertTo-R1CanonicalJson',
    'Get-R1Sha256Text',
    'Invoke-R1MatrixGate',
    'Read-R1MatrixJournal',
    'Read-R1Receipt',
    'Write-R1CreateNewUtf8File'
)
