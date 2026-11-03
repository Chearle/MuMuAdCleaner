$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('build\host-core-test-' + [guid]::NewGuid().ToString('N'))
$exe = Join-Path $testRoot 'MuMuHostCoreTest.exe'
$guard = Join-Path $testRoot 'MuMuAdCleanerGuard.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    & $csc /nologo /target:winexe /optimize+ /codepage:65001 `
        "/out:$guard" `
        (Join-Path $root 'windows\MuMuAdCleanerGuard.cs')
    if ($LASTEXITCODE -ne 0) {
        throw 'Guard compilation failed.'
    }

    & $csc /nologo /target:exe /optimize+ /codepage:65001 `
        /r:System.dll `
        /r:System.Core.dll `
        /r:System.Management.dll `
        /r:System.Web.Extensions.dll `
        "/resource:$guard,GuardPayload" `
        "/out:$exe" `
        (Join-Path $root 'windows\HostCleanerCore.cs') `
        (Join-Path $PSScriptRoot 'MuMuHostCoreTest.cs')
    if ($LASTEXITCODE -ne 0) {
        throw 'Core test compilation failed.'
    }

    $mumuRoot = Join-Path $testRoot 'MuMuPlayer'
    $dataDir = Join-Path $testRoot 'startupImage'
    $stateDir = Join-Path $testRoot 'state'
    & $exe $mumuRoot $dataDir $stateDir 1
    if ($LASTEXITCODE -ne 0) {
        throw 'Core behavior test failed.'
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $workspace = [IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
