[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Status', 'Apply', 'Restore')]
    [string]$Action = 'Status',

    [string[]]$MuMuRoot,

    [string]$DataDir,

    [string]$StateDir,

    [switch]$IncludeServices,

    [switch]$InstallGuard,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$TaskName = 'MuMuAdCleanerStartupGuard'
$BackupSuffix = '.adclean.bak'
$ReporterNames = @(
    'MuMuStatisticsReporter.exe',
    'MuMuPlayerCrashReporter.exe',
    'MuMuPlayerUpdater.exe',
    'MuMuPlayerUpdate.exe'
)

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    )
}

function Get-StateDir {
    if ($StateDir) {
        $resolved = Resolve-FullPath $StateDir
    } else {
        $resolved = Join-Path $env:LOCALAPPDATA 'MuMuAdCleanerHost'
    }
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
    return $resolved
}

function Get-MuMuDataDir {
    if ($DataDir) {
        return Resolve-FullPath $DataDir
    }
    return Join-Path $env:APPDATA 'Netease\MuMuPlayer\data\startupImage'
}

function Test-MuMuRoot([string]$Path) {
    return (Test-Path (Join-Path $Path 'shell\MuMuPlayer.exe')) -or
        (Test-Path (Join-Path $Path 'nx_main\MuMuNxMain.exe')) -or
        (Test-Path (Join-Path $Path 'nx_device'))
}

function Find-MuMuRoots {
    $roots = New-Object 'System.Collections.Generic.List[string]'

    if ($MuMuRoot) {
        foreach ($item in $MuMuRoot) {
            $path = Resolve-FullPath $item
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw "MuMu installation directory not found: $path"
            }
            if (-not (Test-MuMuRoot $path)) {
                throw "This does not look like a MuMu installation: $path"
            }
            if (-not $roots.Contains($path)) {
                $roots.Add($path)
            }
        }
        return @($roots)
    }

    $candidates = @()
    foreach ($base in @(
        (Join-Path $env:ProgramFiles 'Netease'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Netease' })
    )) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            $candidates += $base
            $candidates += Get-ChildItem -LiteralPath $base -Directory -Depth 2 -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName }
        }
    }

    foreach ($path in $candidates | Select-Object -Unique) {
        if (Test-MuMuRoot $path) {
            $resolved = Resolve-FullPath $path
            if (-not $roots.Contains($resolved)) {
                $roots.Add($resolved)
            }
        }
    }

    if ($roots.Count -eq 0) {
        throw 'MuMu installation was not found. Pass -MuMuRoot with the MuMu program directory.'
    }
    return @($roots)
}

function Get-RunningMuMuProcess {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(MuMuPlayer|MuMuNxMain|MuMuNxDevice|mumunxdevice|MuMuVMMHeadless|MuMuPlayerService)$'
    }
}

function Assert-MuMuCanBeChanged {
    if ($Force) {
        return
    }
    $running = @(Get-RunningMuMuProcess)
    if ($running.Count -gt 0) {
        $names = ($running.ProcessName | Sort-Object -Unique) -join ', '
        throw "MuMu is running ($names). Close all MuMu processes and try again, or use -Force to stop them."
    }
}

function Stop-MuMuProcesses {
    $running = @(Get-RunningMuMuProcess)
    if ($running.Count -eq 0) {
        return
    }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Save-State([string]$StatePath, $State) {
    $json = $State | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $StatePath,
        $json,
        (New-Object System.Text.UTF8Encoding $false)
    )
}

function Load-State([string]$StatePath) {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }
    return Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
}

function Apply-ReporterChanges($State, [string[]]$Roots, $PreviousState) {
    $renamed = New-Object 'System.Collections.Generic.List[object]'
    if ($PreviousState -and $PreviousState.RenamedFiles) {
        foreach ($item in @($PreviousState.RenamedFiles)) {
            $renamed.Add($item) | Out-Null
        }
    }

    foreach ($rootPath in $Roots) {
        foreach ($name in $ReporterNames) {
            Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $source = $_.FullName
                    $backup = "$source$BackupSuffix"
                    if (Test-Path -LiteralPath $backup) {
                        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
                        $backup = "$source.adclean-$stamp.bak"
                    }

                    if ($PSCmdlet.ShouldProcess($source, "Rename to $([System.IO.Path]::GetFileName($backup))")) {
                        Rename-Item -LiteralPath $source -NewName ([System.IO.Path]::GetFileName($backup))
                        $renamed.Add([PSCustomObject]@{
                            Source = $source
                            Backup = $backup
                        }) | Out-Null
                    }
                }
        }
    }
    $State.RenamedFiles = $renamed.ToArray()
}

function Apply-StartupConfig($State, [string]$ConfigPath, $PreviousState) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $State.StartupConfig = $null
        $State.StartupConfigBackup = $null
        return
    }

    $backup = if ($PreviousState -and $PreviousState.StartupConfigBackup -and
        (Test-Path -LiteralPath $PreviousState.StartupConfigBackup)) {
        $PreviousState.StartupConfigBackup
    } else {
        Join-Path (Split-Path -Parent $ConfigPath) 'imageManager.adclean-original.json'
    }
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $ConfigPath -Destination $backup
    }

    $empty = "{`n  `"info`": []`n}`n"
    if ($PSCmdlet.ShouldProcess($ConfigPath, 'Clear startup campaign entries')) {
        [System.IO.File]::WriteAllText(
            (Resolve-FullPath $ConfigPath),
            $empty,
            (New-Object System.Text.UTF8Encoding $false)
        )
    }
    $State.StartupConfig = Resolve-FullPath $ConfigPath
    $State.StartupConfigBackup = Resolve-FullPath $backup
}

function Get-MuMuServices([string[]]$Roots) {
    $services = @()
    foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $path = [string]$service.PathName
        if ($service.Name -match 'MuMu|Nemu|Netease' -or
            $service.DisplayName -match 'MuMu|Nemu|Netease') {
            $services += $service
            continue
        }
        foreach ($rootPath in $Roots) {
            if ($path -and $path.IndexOf($rootPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $services += $service
                break
            }
        }
    }
    return @($services | Sort-Object Name -Unique)
}

function Apply-ServiceChanges($State, [string[]]$Roots, $PreviousState) {
    $changes = New-Object 'System.Collections.Generic.List[object]'
    if ($PreviousState -and $PreviousState.Services) {
        foreach ($item in @($PreviousState.Services)) {
            $changes.Add($item) | Out-Null
        }
    }

    foreach ($service in @(Get-MuMuServices $Roots)) {
        if ($PSCmdlet.ShouldProcess($service.Name, 'Set startup type to Manual')) {
            Set-Service -Name $service.Name -StartupType Manual
            if ($service.State -eq 'Running') {
                Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
            }
            $changes.Add([PSCustomObject]@{
                Name = $service.Name
                OriginalStartMode = $service.StartMode
            }) | Out-Null
        }
    }
    $State.Services = $changes.ToArray()
}

function Restore-ReporterChanges($State) {
    if (-not $State -or -not $State.RenamedFiles) {
        return
    }
    foreach ($item in @($State.RenamedFiles)) {
        if ((Test-Path -LiteralPath $item.Backup) -and -not (Test-Path -LiteralPath $item.Source)) {
            if ($PSCmdlet.ShouldProcess($item.Backup, 'Restore original executable name')) {
                Rename-Item -LiteralPath $item.Backup -NewName (Split-Path -Leaf $item.Source)
            }
        }
    }
}

function Restore-StartupConfig($State) {
    if (-not $State -or -not $State.StartupConfigBackup) {
        return
    }
    if (Test-Path -LiteralPath $State.StartupConfigBackup) {
        if ($PSCmdlet.ShouldProcess($State.StartupConfig, 'Restore original startup configuration')) {
            Copy-Item -LiteralPath $State.StartupConfigBackup -Destination $State.StartupConfig -Force
        }
    }
}

function Restore-ServiceChanges($State) {
    if (-not $State -or -not $State.Services) {
        return
    }
    foreach ($item in @($State.Services)) {
        $service = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
        if (-not $service) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($item.Name, "Restore startup type to $($item.OriginalStartMode)")) {
            $mode = switch ($item.OriginalStartMode) {
                'Auto' { 'Automatic' }
                'Manual' { 'Manual' }
                'Disabled' { 'Disabled' }
                default { 'Manual' }
            }
            Set-Service -Name $item.Name -StartupType $mode
        }
    }
}

function Get-GuardExePath([string]$StatePath) {
    return Join-Path $StatePath 'MuMuAdCleanerGuard.exe'
}

function Install-Guard([string]$StatePath, [string]$ConfigDir) {
    $source = Join-Path $PSScriptRoot 'MuMuAdCleanerGuard.cs'
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Guard source not found: $source"
    }

    $framework = if ([Environment]::Is64BitOperatingSystem) {
        Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    } else {
        Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path -LiteralPath $framework)) {
        throw 'The .NET Framework C# compiler was not found.'
    }

    $exe = Get-GuardExePath $StatePath
    & $framework /nologo /target:winexe /optimize+ "/out:$exe" $source
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
        throw 'Failed to compile the startup guard.'
    }

    Remove-Item -LiteralPath (Join-Path $StatePath 'guard.stop') -Force -ErrorAction SilentlyContinue
    $arguments = '--data-dir "{0}" --state-dir "{1}"' -f $ConfigDir, $StatePath
    $taskAction = New-ScheduledTaskAction -Execute $exe -Argument $arguments
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $principal `
        -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
}

function Remove-Guard([string]$StatePath) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $stopPath = Join-Path $StatePath 'guard.stop'
    [System.IO.File]::WriteAllText(
        $stopPath,
        'stop',
        (New-Object System.Text.UTF8Encoding $false)
    )
    Get-Process -Name 'MuMuAdCleanerGuard' -ErrorAction SilentlyContinue |
        Stop-Process -Force
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
}

function Write-Status([string[]]$Roots, [string]$ConfigPath, [string]$StatePath) {
    Write-Host 'MuMu installations:'
    foreach ($rootPath in $Roots) {
        Write-Host "  $rootPath"
        foreach ($name in $ReporterNames) {
            $files = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
            foreach ($file in $files) {
                Write-Host "    active: $($file.FullName)"
            }
            $backups = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter "$name$BackupSuffix" -ErrorAction SilentlyContinue)
            foreach ($file in $backups) {
                Write-Host "    disabled: $($file.FullName)"
            }
        }
    }

    Write-Host "Startup config: $ConfigPath"
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -Raw -LiteralPath $ConfigPath
            $hasCampaign = $raw -match '"campaignId"|"normalImageUrl"|"hoverImageUrl"'
            $label = if ($hasCampaign) { 'present' } else { 'none' }
            Write-Host "  campaign entries: $label"
        } catch {
            Write-Host '  campaign entries: unreadable'
        }
    } else {
        Write-Host '  not created yet'
    }

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $guardState = if ($task) { $task.State } else { 'not installed' }
    Write-Host "Startup guard: $guardState"
    Write-Host "State: $StatePath"
}

$roots = @(Find-MuMuRoots)
$statePath = Get-StateDir
$stateFile = Join-Path $statePath 'state.json'
$configDir = Get-MuMuDataDir
$configPath = Join-Path $configDir 'imageManager.json'

if ($Action -eq 'Status') {
    Write-Status $roots $configPath $statePath
    return
}

$previousState = Load-State $stateFile

if ($Action -eq 'Apply') {
    Assert-MuMuCanBeChanged
    if ($Force) {
        Stop-MuMuProcesses
    }

    $state = [PSCustomObject]@{
        Version = 2
        AppliedAt = (Get-Date).ToString('o')
        Roots = $roots
        RenamedFiles = @()
        StartupConfig = $null
        StartupConfigBackup = $null
        Services = @()
    }
    Apply-ReporterChanges $state $roots $previousState
    Apply-StartupConfig $state $configPath $previousState
    if ($IncludeServices) {
        Apply-ServiceChanges $state $roots $previousState
    } elseif ($previousState -and $previousState.Services) {
        $state.Services = @($previousState.Services)
    }
    Save-State $stateFile $state

    if ($InstallGuard) {
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        }
        Install-Guard $statePath $configDir
    }

    Write-Host 'Host cleanup applied. Start MuMu and verify that the startup promotion is gone.'
    if (-not $InstallGuard) {
        Write-Host 'The campaign may be downloaded again. Use -InstallGuard for persistent protection.'
    }
    return
}

if ($Action -eq 'Restore') {
    Assert-MuMuCanBeChanged
    if ($Force) {
        Stop-MuMuProcesses
    }

    Remove-Guard $statePath
    if (-not $previousState) {
        throw "No cleanup state was found at $stateFile"
    }
    Restore-ServiceChanges $previousState
    Restore-ReporterChanges $previousState
    Restore-StartupConfig $previousState
    Remove-Item -LiteralPath $stateFile -Force
    Write-Host 'MuMu host cleanup restored.'
}
