[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'R4R8CloseoutGate.psm1'
$contractPath = Join-Path $PSScriptRoot 'r4-r8-closeout-contract.json'
$verifierPath = Join-Path $PSScriptRoot 'verify-r4-r8-closeout.ps1'
$dexRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$r8Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../AutoJs6-Plugin-R8-Compiler'))
$hostRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../AutoJs6'))

Import-Module $modulePath -Force
$contract = Read-R4R8CloseoutContract -Path $contractPath

$script:Passed = 0
$script:Failed = 0
$script:Expected = 12

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

    try {
        & $Body
    } catch {
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

function New-GateMap {
    $map = [ordered]@{}
    foreach ($record in @($contract.gates)) {
        $path = Join-Path $r8Root ([string] $record.path)
        $map[[string] $record.id] = Copy-Value (Read-R4R8CloseoutJson -Path $path)
    }
    return $map
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('autojs6-r4-r8-closeout-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    Invoke-Case -Name 'frozen G2-G8 evidence graph closes' -Body {
        $map = New-GateMap
        Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
    }

    Invoke-Case -Name 'non-passing prerequisite gate is rejected' -Body {
        $map = New-GateMap
        $map['g6'].passed = $false
        Assert-Throws -Pattern 'G6.*PASS state' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'invocation drift is rejected' -Body {
        $map = New-GateMap
        $map['g7Runtime'].invocationId = '11111111-1111-4111-8111-111111111111'
        Assert-Throws -Pattern 'g7Runtime.*metadata' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'broken G5 prerequisite chain is rejected' -Body {
        $map = New-GateMap
        $map['g5'].priorEvidence = @($map['g5'].priorEvidence[0..1])
        Assert-Throws -Pattern 'G5 prerequisite count' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'missing Binder claim is rejected' -Body {
        $map = New-GateMap
        $map['g6'].claims.crossApkBinderVerified = $false
        Assert-Throws -Pattern 'crossApkBinderVerified.*true' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'G6 receipt count drift is rejected' -Body {
        $map = New-GateMap
        $map['g6'].tests.structuredReceipts = 8
        Assert-Throws -Pattern 'G6 acceptance matrix' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'missing JNI claim is rejected' -Body {
        $map = New-GateMap
        $map['g7Runtime'].claims.jniLinked = $false
        Assert-Throws -Pattern 'jniLinked.*true' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'Retrace execution count drift is rejected' -Body {
        $map = New-GateMap
        $map['g7Runtime'].tests.retraceExecutions = 2
        Assert-Throws -Pattern 'G7 ART/JNI/Retrace matrix' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'public release claim is rejected' -Body {
        $map = New-GateMap
        $map['g8'].claims.publicPublished = $true
        Assert-Throws -Pattern 'publicPublished.*false' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'remote asset mutation is rejected' -Body {
        $map = New-GateMap
        $map['g8'].release.assets[0].sha256 = '0' * 64
        Assert-Throws -Pattern 'remote release asset.*identity changed' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'noreply identity drift is rejected' -Body {
        $map = New-GateMap
        $map['g8'].privacyMigration.targetNoreplyIdentity = 'wrong@users.noreply.github.com'
        Assert-Throws -Pattern 'privacy migration evidence' -Body {
            Assert-R4R8CloseoutEvidenceGraph -Contract $contract -GateById $map
        }
    }

    Invoke-Case -Name 'bootstrap failure atomically replaces stale PASS' -Body {
        $brokenContract = Join-Path $temporaryRoot 'broken-contract.json'
        [IO.File]::WriteAllText($brokenContract, '{"schemaVersion":"broken"}', [Text.UTF8Encoding]::new($false))
        $output = Join-Path $temporaryRoot 'gate.json'
        [IO.File]::WriteAllText($output, '{"passed":true,"stale":true}', [Text.UTF8Encoding]::new($false))
        & pwsh -NoLogo -NoProfile -File $verifierPath `
            -DexRepositoryRoot $dexRoot `
            -R8RepositoryRoot $r8Root `
            -HostRepositoryRoot $hostRoot `
            -ContractPath $brokenContract `
            -OutputPath $output *> $null
        Assert-True -Condition ($LASTEXITCODE -ne 0) -Message 'Broken contract exited zero.'
        $persisted = Read-R4R8CloseoutJson -Path $output
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
        -not [IO.Path]::GetFileName($resolvedTemporaryRoot).StartsWith('autojs6-r4-r8-closeout-tests-', [StringComparison]::Ordinal)) {
        throw 'Refusing to delete a temporary directory outside the expected boundary.'
    }
    if ([IO.Directory]::Exists($resolvedTemporaryRoot)) { [IO.Directory]::Delete($resolvedTemporaryRoot, $true) }
}

Write-Host "RESULT passed=$($script:Passed) failed=$($script:Failed)"
if ($script:Passed + $script:Failed -ne $script:Expected -or $script:Failed -ne 0) { exit 1 }
