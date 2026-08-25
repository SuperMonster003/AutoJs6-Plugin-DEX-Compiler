[CmdletBinding()]
param(
    [string] $ContractPath = (Join-Path $PSScriptRoot 'r4-d8-promotion-contract.json'),

    [Parameter(Mandatory)]
    [string] $PromotedStatePath,

    [Parameter(Mandatory)]
    [string] $RollbackStatePath,

    [Parameter(Mandatory)]
    [string] $FinalPromotedStatePath,

    [Parameter(Mandatory)]
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-BootstrapAtomicJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Json)

    $resolved = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
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
    param([Parameter(Mandatory)] [string] $Message, [Parameter(Mandatory)] [string[]] $PrivatePath)

    $safe = $Message
    foreach ($path in @($PrivatePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique)) {
        try {
            $resolved = [IO.Path]::GetFullPath($path)
            $safe = [regex]::Replace($safe, [regex]::Escape($resolved), '<private-path>', 'IgnoreCase')
        } catch { }
    }
    return $safe
}

$modulePath = Join-Path $PSScriptRoot 'R4D8PromotionGate.psm1'
$statePaths = @($PromotedStatePath, $RollbackStatePath, $FinalPromotedStatePath)
$privatePaths = @($PSScriptRoot, [IO.Path]::GetTempPath(), $ContractPath, $modulePath, $OutputPath) + $statePaths
$resolvedOutput = $null
$safeOutputEstablished = $false

try {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $parent = [IO.Path]::GetDirectoryName($resolvedOutput)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'Output directory does not exist.'
    }
    foreach ($input in @($ContractPath, $modulePath) + $statePaths) {
        if ([string]::Equals($resolvedOutput, [IO.Path]::GetFullPath($input), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'OutputPath aliases a protected input.'
        }
    }
    $safeOutputEstablished = $true
    Write-BootstrapAtomicJson -Path $resolvedOutput -Json (([pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-gate-error/v1'
        passed = $false
        determinismClaim = 'NOT_CLAIMED'
        error = 'INVALIDATED_BEFORE_CLOSEOUT_VERIFICATION'
    } | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

    Import-Module $modulePath -Force
    $contract = Read-R4D8PromotionContract -Path $ContractPath
    $states = @($statePaths | ForEach-Object { Read-R4D8PromotionJson -Path $_ })
    $stateSha256 = @($statePaths | ForEach-Object { Get-R4D8PromotionSha256File -Path $_ })
    $gate = Test-R4D8PromotionCloseout -Contract $contract -State $states -StateSha256 $stateSha256
    $json = ($gate | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    Write-R4D8PromotionAtomicJson -Path $resolvedOutput -Json $json
    $json
} catch {
    $safeMessage = ConvertTo-SafeFailureMessage -Message $_.Exception.Message -PrivatePath $privatePaths
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-gate-error/v1'
        passed = $false
        determinismClaim = 'NOT_CLAIMED'
        error = $safeMessage
    }
    $json = ($failure | ConvertTo-Json -Depth 10) + [Environment]::NewLine
    if ($safeOutputEstablished -and $null -ne $resolvedOutput) {
        try { Write-BootstrapAtomicJson -Path $resolvedOutput -Json $json } catch { }
    }
    $json
    exit 1
}
