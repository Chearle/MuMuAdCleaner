$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutMs = 5000) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
        if (& $Condition) {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('build\guard-test-' + [guid]::NewGuid().ToString('N'))
$dataDir = Join-Path $testRoot 'data'
$stateDir = Join-Path $testRoot 'state'
$exe = Join-Path $testRoot 'MuMuAdCleanerGuard.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

try {
    New-Item -ItemType Directory -Force -Path $dataDir, $stateDir | Out-Null
    & $csc /nologo /target:winexe /optimize+ "/out:$exe" (Join-Path $root 'windows\MuMuAdCleanerGuard.cs')
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path $exe)) 'guard should compile'

    $arguments = @(
        '--data-dir', ('"' + $dataDir + '"'),
        '--state-dir', ('"' + $stateDir + '"')
    )
    $guard = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500

    $config = Join-Path $dataDir 'imageManager.json'
    [IO.File]::WriteAllText(
        $config,
        '{"info":[{"campaignId":"abc","normalImageUrl":"https://example.invalid/ad.jpg"}]}'
    )
    Assert-True (Wait-Until {
        (Get-Content -Raw -LiteralPath $config) -notmatch 'campaignId|normalImageUrl'
    }) 'guard should remove campaign fields'

    $plain = '{"info":[]}'
    [IO.File]::WriteAllText($config, $plain)
    Start-Sleep -Milliseconds 500
    Assert-True ((Get-Content -Raw -LiteralPath $config) -eq $plain) 'guard should leave clean config alone'

    [IO.File]::WriteAllText((Join-Path $stateDir 'guard.stop'), 'stop')
    Assert-True ($guard.WaitForExit(5000)) 'guard should stop when requested'
    Assert-True ($guard.ExitCode -eq 0) 'guard should exit successfully'

    Write-Host 'MuMuAdCleanerGuard tests passed.'
} finally {
    Get-Process -Name 'MuMuAdCleanerGuard' -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $workspace = [IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
