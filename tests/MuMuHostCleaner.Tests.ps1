$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$cleaner = Join-Path $root 'windows\MuMuHostCleaner.ps1'
$testRoot = Join-Path $root ('build\host-cleaner-test-' + [guid]::NewGuid().ToString('N'))
$mumuRoot = Join-Path $testRoot 'MuMuPlayer'
$dataDir = Join-Path $testRoot 'startupImage'
$stateDir = Join-Path $testRoot 'state'
$originalConfig = '{"info":[{"campaignId":"abc","normalImageUrl":"https://example.invalid/ad.jpg"}]}'

try {
    foreach ($dir in @(
        (Join-Path $mumuRoot 'shell'),
        (Join-Path $mumuRoot 'nx_main'),
        (Join-Path $mumuRoot 'bin'),
        $dataDir
    )) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    [IO.File]::WriteAllText((Join-Path $mumuRoot 'shell\MuMuPlayer.exe'), 'shell')
    [IO.File]::WriteAllText((Join-Path $mumuRoot 'nx_main\MuMuNxMain.exe'), 'main')
    $reporter = Join-Path $mumuRoot 'bin\MuMuPlayerUpdater.exe'
    [IO.File]::WriteAllText($reporter, 'updater')
    [IO.File]::WriteAllText((Join-Path $dataDir 'imageManager.json'), $originalConfig)

    & $cleaner -Action Apply -MuMuRoot $mumuRoot -DataDir $dataDir -StateDir $stateDir -Force -InstallGuard
    Assert-True (Test-Path "$reporter.adclean.bak") 'reporter should be renamed'
    Assert-True (-not (Test-Path $reporter)) 'active reporter should be gone'
    Assert-True ($null -ne (Get-ScheduledTask -TaskName 'MuMuAdCleanerStartupGuard' -ErrorAction SilentlyContinue)) 'startup guard task should be installed'
    $cleared = Get-Content -Raw -LiteralPath (Join-Path $dataDir 'imageManager.json')
    Assert-True ($cleared -notmatch 'campaignId') 'campaign config should be cleared'
    Assert-True (Test-Path (Join-Path $dataDir 'imageManager.adclean-original.json')) 'original config should be backed up'

    [IO.File]::WriteAllText(
        (Join-Path $dataDir 'imageManager.json'),
        '{"info":[{"campaignId":"second"}]}'
    )
    & $cleaner -Action Apply -MuMuRoot $mumuRoot -DataDir $dataDir -StateDir $stateDir -Force
    $backup = Get-Content -Raw -LiteralPath (Join-Path $dataDir 'imageManager.adclean-original.json')
    Assert-True ($backup -eq $originalConfig) 'repeated apply must not overwrite the original backup'

    & $cleaner -Action Restore -MuMuRoot $mumuRoot -DataDir $dataDir -StateDir $stateDir -Force
    Assert-True (Test-Path $reporter) 'reporter should be restored'
    Assert-True (-not (Test-Path "$reporter.adclean.bak")) 'temporary backup should be renamed back'
    Assert-True ($null -eq (Get-ScheduledTask -TaskName 'MuMuAdCleanerStartupGuard' -ErrorAction SilentlyContinue)) 'startup guard task should be removed'
    $restored = Get-Content -Raw -LiteralPath (Join-Path $dataDir 'imageManager.json')
    Assert-True ($restored -eq $originalConfig) 'original startup config should be restored'

    Write-Host 'MuMuHostCleaner tests passed.'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $workspace = [IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
