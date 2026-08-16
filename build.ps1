$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sdk = 'C:\Users\A\AppData\Local\Android\Sdk'
$BuildTools = Join-Path $Sdk 'build-tools\36.0.0'
$AndroidJar = Join-Path $Sdk 'platforms\android-35\android.jar'
$Aapt2 = Join-Path $BuildTools 'aapt2.exe'
$D8 = Join-Path $BuildTools 'd8.bat'
$Zipalign = Join-Path $BuildTools 'zipalign.exe'
$Apksigner = Join-Path $BuildTools 'apksigner.bat'
$JavaHome = $env:JAVA_HOME
if (-not $JavaHome) { $JavaHome = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot' }
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
$SignedAscii = Join-Path $OutDir 'MuMuAdCleaner.apk'
$OutApk = $SignedAscii
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

$share = 'C:\Users\A\Documents\MuMu共享文件夹\Download'
$desktop = [Environment]::GetFolderPath('Desktop')
New-Item -ItemType Directory -Force -Path $share | Out-Null
Copy-Item $OutApk (Join-Path $share 'MuMuAdCleaner.apk') -Force
Copy-Item $OutApk (Join-Path $desktop 'MuMuAdCleaner.apk') -Force

Write-Host ''
Write-Host "APK: $OutApk"
Write-Host "Desktop: $(Join-Path $desktop 'MuMu去广告.apk')"
Write-Host "MuMu share: $(Join-Path $share 'MuMu去广告.apk')"
