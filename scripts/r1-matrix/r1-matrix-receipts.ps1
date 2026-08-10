#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('Append', 'Verify', 'Gate')]
    [string] $Command,

    [Parameter(Mandatory)]
    [string] $JournalPath,

    [string] $ReceiptPath,

    [string] $ReportPath,

    [string] $AttemptDirectory,

    [string] $SchemaPath = (Join-Path $PSScriptRoot 'r1-matrix-receipt.schema.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'R1MatrixReceipts.psm1') -Force

try {
    switch ($Command) {
        'Append' {
            if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
                throw '-ReceiptPath is required for Append'
            }
            $result = Add-R1MatrixReceipt `
                -JournalPath $JournalPath `
                -ReceiptPath $ReceiptPath `
                -SchemaPath $SchemaPath
            $result | ConvertTo-Json -Depth 20
            exit 0
        }
        'Verify' {
            $journal = Read-R1MatrixJournal -JournalPath $JournalPath -SchemaPath $SchemaPath
            [pscustomobject][ordered]@{
                schemaVersion = 'autojs6.dex.r1.matrix-journal-verification/v1'
                valid = $true
                campaignId = $journal.CampaignId
                entryCount = $journal.Entries.Count
                headEntrySha256 = $journal.HeadEntrySha256
            } | ConvertTo-Json -Depth 20
            exit 0
        }
        'Gate' {
            if ([string]::IsNullOrWhiteSpace($AttemptDirectory)) {
                throw '-AttemptDirectory is required for Gate'
            }
            $result = Invoke-R1MatrixGate `
                -JournalPath $JournalPath `
                -SchemaPath $SchemaPath `
                -AttemptDirectory $AttemptDirectory
            $json = $result | ConvertTo-Json -Depth 100
            if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
                Write-R1CreateNewUtf8File -Path $ReportPath -Content $json
            }
            $json
            if ($result.passed) { exit 0 }
            exit 3
        }
    }
} catch {
    [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r1.matrix-tool-error/v1'
        valid = $false
        command = $Command
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 20
    exit 2
}
