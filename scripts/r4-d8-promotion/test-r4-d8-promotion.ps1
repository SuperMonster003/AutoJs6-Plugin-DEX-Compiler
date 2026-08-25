[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'R4D8PromotionGate.psm1'
$contractPath = Join-Path $PSScriptRoot 'r4-d8-promotion-contract.json'
$verifierPath = Join-Path $PSScriptRoot 'verify-r4-d8-promotion.ps1'
Import-Module $modulePath -Force
$contract = Read-R4D8PromotionContract -Path $contractPath

$script:Passed = 0
$script:Failed = 0
$script:Expected = 10

function Invoke-Case {
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [scriptblock] $Body)
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
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)] [scriptblock] $Body, [Parameter(Mandatory)] [string] $Pattern)
    try { & $Body } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected '$Pattern'; found '$($_.Exception.Message)'."
        }
        return
    }
    throw "Expected failure '$Pattern', but the call passed."
}

function Copy-Value {
    param([Parameter(Mandatory)] [psobject] $Value)
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -NoEnumerate -DateKind String
}

function New-State {
    param([Parameter(Mandatory)] [int] $Index)

    $stage = @($contract.stages)[$Index]
    $isRollback = $Index -eq 1
    $gateChar = @('2', '3', '4')[$Index]
    $reportSetChar = @('5', '6', '7')[$Index]
    $receiptId = @(
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333'
    )[$Index]
    $producerId = @(
        '44444444-4444-4444-8444-444444444444',
        '55555555-5555-4555-8555-555555555555',
        '66666666-6666-4666-8666-666666666666'
    )[$Index]
    return [pscustomobject][ordered]@{
        schemaVersion = 'autojs6.dex.r4.d8-promotion-state/v1'
        evidenceBoundary = 'LOCAL_DEFAULT_PIN_PROMOTION_AND_ROLLBACK'
        campaignId = '77777777-7777-4777-8777-777777777777'
        stateReceiptId = $receiptId
        capturedAtUtc = ('2026-08-25T00:00:0{0}.0000000+00:00' -f ($Index + 1))
        stage = [string] $stage.id
        ordinal = [int] $stage.ordinal
        compilerVersion = [string] $stage.compilerVersion
        passed = $true
        candidateOverridePresent = $false
        repositoryHead = 'a' * 40
        sourceManifest = [pscustomobject][ordered]@{
            fileCount = 2
            normalizedSha256 = 'b' * 64
            records = @(
                [pscustomobject][ordered]@{
                    path = 'app/source.kt'
                    byteLength = 10
                    sha256 = 'c' * 64
                    normalizedByteLength = 10
                    normalizedSha256 = 'c' * 64
                },
                [pscustomobject][ordered]@{
                    path = 'gradle/libs.versions.toml'
                    byteLength = 20
                    sha256 = $(if ($isRollback) { 'e' * 64 } else { 'd' * 64 })
                    normalizedByteLength = 24
                    normalizedSha256 = 'f' * 64
                }
            )
        }
        runtimeFingerprintSha256 = '1' * 64
        platformPlugin = [pscustomobject][ordered]@{
            coordinate = [string] $contract.platformPlugin.coordinate
            version = [string] $contract.platformPlugin.version
            byteLength = [long] $contract.platformPlugin.byteLength
            sha256 = [string] $contract.platformPlugin.sha256
            sourceCommit = [string] $contract.platformPlugin.sourceCommit
        }
        gate = [pscustomobject][ordered]@{
            sha256 = $gateChar * 64
            passed = $true
            evaluationKind = [string] $stage.gateEvaluationKind
            compilerVersion = [string] $stage.compilerVersion
            producerInvocationId = $producerId
            matrixSha256 = '8' * 64
            reportSchemaSha256 = '9' * 64
            reportSetSha256 = $reportSetChar * 64
            expectedCellCount = 60
            reportCount = 60
            determinismClaim = 'NOT_CLAIMED'
        }
    }
}

$states = @(0..2 | ForEach-Object { New-State -Index $_ })
$stateHashes = @(('a' * 64), ('b' * 64), ('c' * 64))
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('autojs6-r4-d8-promotion-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    Invoke-Case -Name 'three fresh states close the promotion gate' -Body {
        $gate = Test-R4D8PromotionCloseout -Contract $contract -State $states -StateSha256 $stateHashes
        Assert-True -Condition ([bool] $gate.passed) -Message 'Positive closeout did not pass.'
        Assert-True -Condition ($gate.finalDefaultVersion -ceq '8.13.22') -Message 'Final default changed.'
        Assert-True -Condition (-not [bool] $gate.candidateOverrideUsed) -Message 'Positive closeout claimed a candidate override.'
    }

    Invoke-Case -Name 'campaign drift is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[1].campaignId = '88888888-8888-4888-8888-888888888888'
        Assert-Throws -Pattern 'one canonical campaignId' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'producer UUID reuse is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[2].gate.producerInvocationId = $mutated[0].gate.producerInvocationId
        Assert-Throws -Pattern 'producer invocation IDs' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'normalized source identity drift is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[1].sourceManifest.normalizedSha256 = '0' * 64
        Assert-Throws -Pattern 'normalized source/build identity' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'non-catalog source mutation is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[1].sourceManifest.records[0].sha256 = '0' * 64
        Assert-Throws -Pattern 'Non-catalog source changed' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'missing rollback byte transition is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[1].sourceManifest.records[1].sha256 = $mutated[0].sourceManifest.records[1].sha256
        Assert-Throws -Pattern 'promote, rollback, and final re-promotion' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'gate or report-set reuse is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[2].gate.reportSetSha256 = $mutated[0].gate.reportSetSha256
        Assert-Throws -Pattern 'reused a gate or report set' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'candidate override is rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[0].candidateOverridePresent = $true
        Assert-Throws -Pattern 'used a candidate override' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'non-monotonic timestamps are rejected' -Body {
        $mutated = @($states | ForEach-Object { Copy-Value $_ })
        $mutated[2].capturedAtUtc = $mutated[1].capturedAtUtc
        Assert-Throws -Pattern 'strictly increasing' -Body {
            Test-R4D8PromotionCloseout -Contract $contract -State $mutated -StateSha256 $stateHashes | Out-Null
        }
    }

    Invoke-Case -Name 'verifier failure atomically replaces stale PASS' -Body {
        $paths = @('promoted.json', 'rollback.json', 'final.json') | ForEach-Object { Join-Path $temporaryRoot $_ }
        for ($index = 0; $index -lt 3; $index++) {
            [IO.File]::WriteAllText($paths[$index], ($states[$index] | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        }
        $output = Join-Path $temporaryRoot 'gate.json'
        [IO.File]::WriteAllText($output, '{"passed":true,"stale":true}', [Text.UTF8Encoding]::new($false))
        $broken = Copy-Value $states[1]
        $broken.campaignId = '88888888-8888-4888-8888-888888888888'
        [IO.File]::WriteAllText($paths[1], ($broken | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        & pwsh -NoLogo -NoProfile -File $verifierPath `
            -ContractPath $contractPath `
            -PromotedStatePath $paths[0] `
            -RollbackStatePath $paths[1] `
            -FinalPromotedStatePath $paths[2] `
            -OutputPath $output *> $null
        Assert-True -Condition ($LASTEXITCODE -ne 0) -Message 'Broken verifier input exited zero.'
        $persisted = Read-R4D8PromotionJson -Path $output
        Assert-True -Condition (-not [bool] $persisted.passed) -Message 'Broken verifier retained stale PASS.'
        Assert-True -Condition (@($persisted.PSObject.Properties.Name) -notcontains 'stale') -Message 'Broken verifier did not replace stale output.'
    }
} finally {
    if ([IO.Directory]::Exists($temporaryRoot)) { [IO.Directory]::Delete($temporaryRoot, $true) }
}

Write-Host "RESULT passed=$($script:Passed) failed=$($script:Failed)"
if ($script:Passed + $script:Failed -ne $script:Expected -or $script:Failed -ne 0) { exit 1 }
