$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-AndroidSdk {
    foreach ($candidate in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    throw 'Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT.'
}

function Resolve-JavaHome {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\javac.exe'))) {
        return $env:JAVA_HOME
    }
    $fallback = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
    if (Test-Path (Join-Path $fallback 'bin\javac.exe')) {
        return $fallback
    }
    throw 'JDK not found. Set JAVA_HOME to JDK 17.'
}

function Resolve-BuildTools([string]$Sdk) {
    $preferred = @(
        (Join-Path $Sdk 'build-tools\36.0.0'),
        (Join-Path $Sdk 'build-tools\35.0.1'),
        (Join-Path $Sdk 'build-tools\34.0.0')
    )
    foreach ($dir in $preferred) {
        if (Test-Path (Join-Path $dir 'aapt2.exe')) {
            return $dir
        }
    }
    $found = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Where-Object { Test-Path (Join-Path $_.FullName 'aapt2.exe') } |
        Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    throw "No Android build-tools with aapt2.exe under $Sdk"
}

$Sdk = Resolve-AndroidSdk
$BuildTools = Resolve-BuildTools $Sdk
$AndroidJar = Join-Path $Sdk 'platforms\android-35\android.jar'
$Aapt2 = Join-Path $BuildTools 'aapt2.exe'
$D8 = Join-Path $BuildTools 'd8.bat'
$Zipalign = Join-Path $BuildTools 'zipalign.exe'
$Apksigner = Join-Path $BuildTools 'apksigner.bat'
$JavaHome = Resolve-JavaHome
$Javac = Join-Path $JavaHome 'bin\javac.exe'
$Keytool = Join-Path $JavaHome 'bin\keytool.exe'

foreach ($p in @($Aapt2, $D8, $Zipalign, $Apksigner, $Javac, $AndroidJar)) {
    if (-not (Test-Path $p)) { throw "Missing tool: $p" }
}

$Work = Join-Path $Root 'build'
$Gen = Join-Path $Work 'gen'
$Classes = Join-Path $Work 'classes'
$ResFlat = Join-Path $Work 'res.zip'
$Unsigned = Join-Path $Work 'unsigned.apk'
$Aligned = Join-Path $Work 'aligned.apk'
$OutDir = Join-Path $Root 'dist'
$OutApk = Join-Path $OutDir 'MuMuAdCleaner.apk'
$Keystore = Join-Path $Root 'debug.keystore'

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work, $Gen, $Classes, $OutDir | Out-Null

Write-Host '== unix line endings for shell assets =='
$utf8 = New-Object System.Text.UTF8Encoding $false
Get-ChildItem (Join-Path $Root 'assets\*.sh') | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    [System.IO.File]::WriteAllText($_.FullName, $text, $utf8)
}

Write-Host '== compile resources =='
& $Aapt2 compile --dir (Join-Path $Root 'res') -o $ResFlat
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }

Write-Host '== link apk =='
& $Aapt2 link `
    -o $Unsigned `
    --manifest (Join-Path $Root 'AndroidManifest.xml') `
    -I $AndroidJar `
    --java $Gen `
    --auto-add-overlay `
    -A (Join-Path $Root 'assets') `
    $ResFlat
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

Write-Host '== javac =='
$sources = Get-ChildItem -Path (Join-Path $Root 'src'), $Gen -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& $Javac -encoding UTF-8 -source 8 -target 8 -bootclasspath $AndroidJar -classpath $AndroidJar -d $Classes @sources
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }

Write-Host '== d8 =='
$classFiles = Get-ChildItem -Path $Classes -Recurse -Filter *.class | ForEach-Object { $_.FullName }
$env:JAVA_HOME = $JavaHome
cmd /c "`"$D8`" --lib `"$AndroidJar`" --min-api 26 --output `"$Work`" $($classFiles -join ' ')"
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }

Write-Host '== add classes.dex =='
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apkZip = [System.IO.Compression.ZipFile]::Open($Unsigned, 'Update')
try {
    $existing = $apkZip.GetEntry('classes.dex')
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apkZip, (Join-Path $Work 'classes.dex'), 'classes.dex') | Out-Null
} finally {
    $apkZip.Dispose()
}

if (-not (Test-Path $Keystore)) {
    Write-Host '== create debug keystore =='
    & $Keytool -genkeypair -v -keystore $Keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=MuMuAdClean,O=Local,C=CN'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
}

Write-Host '== zipalign =='
& $Zipalign -f -p 4 $Unsigned $Aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

Write-Host '== sign =='
cmd /c "`"$Apksigner`" sign --ks `"$Keystore`" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out `"$OutApk`" `"$Aligned`""
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }

Write-Host '== verify =='
cmd /c "`"$Apksigner`" verify --verbose `"$OutApk`""
if ($LASTEXITCODE -ne 0) { throw 'apk verify failed' }

Write-Host ''
Write-Host "APK: $OutApk"
