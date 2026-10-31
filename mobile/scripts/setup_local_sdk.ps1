# Cai OpenJDK 17 + Android SDK (command-line tools) vao D:\dev-tools de tu dong goi
# APK tren Windows (khong can Android Studio, khong ghi gi vao o C:).
# Dung: powershell -ExecutionPolicy Bypass -File mobile\scripts\setup_local_sdk.ps1
# Sau do: . .\mobile\scripts\flutter_env.ps1; cd mobile; flutter build apk --release

$ErrorActionPreference = 'Stop'
$env:FLUTTER_ENV_QUIET = '1'
. (Join-Path $PSScriptRoot 'flutter_env.ps1')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# Ban nen tang/build-tools ma AGP cua du an can; Gradle tu tai them neu thieu.
$AndroidPackages = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0')

function Get-Download([string]$Url, [string]$Name) {
    $file = Join-Path $env:TEMP $Name
    if (-not (Test-Path $file)) {
        Write-Host "[setup] Tai $Url"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile "$file.part"
        Move-Item -Force "$file.part" $file
    }
    return $file
}

# Giai nen vao thu muc tam roi chuyen thu muc con duy nhat thanh $Target.
function Expand-Single([string]$Zip, [string]$Target) {
    $stage = Join-Path $env:TEMP ('unzip_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $stage | Out-Null
    & tar.exe -xf $Zip -C $stage
    if ($LASTEXITCODE -ne 0) { Expand-Archive -Force -Path $Zip -DestinationPath $stage }
    $inner = Get-ChildItem $stage | Select-Object -First 1
    New-Item -ItemType Directory -Force (Split-Path $Target -Parent) | Out-Null
    if (Test-Path $Target) { Remove-Item -Recurse -Force $Target }
    Move-Item $inner.FullName $Target
    Remove-Item -Recurse -Force $stage
}

# ---- OpenJDK 17 (Eclipse Temurin) ----
if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $zip = Get-Download 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk' 'temurin-jdk17.zip'
    Expand-Single $zip $env:JAVA_HOME
    Remove-Item -Force $zip
    Write-Host "[setup] JDK 17 -> $($env:JAVA_HOME)"
} else { Write-Host "[setup] Da co JDK 17: $($env:JAVA_HOME)" }

# ---- Android command-line tools (ban moi nhat theo repository2-3.xml) ----
$latest = Join-Path $env:ANDROID_SDK_ROOT 'cmdline-tools\latest'
if (-not (Test-Path (Join-Path $latest 'bin\sdkmanager.bat'))) {
    $repo = (Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/repository2-3.xml').Content
    $names = [regex]::Matches($repo, 'commandlinetools-win-(\d+)_latest\.zip') |
             Sort-Object { [int]$_.Groups[1].Value } -Descending
    if (-not $names) { throw 'Khong tim thay ban command-line tools cho Windows.' }
    $name = $names[0].Value
    $zip = Get-Download "https://dl.google.com/android/repository/$name" $name
    Expand-Single $zip $latest
    Remove-Item -Force $zip
    Write-Host "[setup] Android cmdline-tools -> $latest"
} else { Write-Host "[setup] Da co Android cmdline-tools." }

$env:PATH = "$($env:JAVA_HOME)\bin;$latest\bin;$($env:ANDROID_SDK_ROOT)\platform-tools;$($env:PATH)"
$sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'

Write-Host '[setup] Chap nhan giay phep Android SDK...'
$yes = (1..30 | ForEach-Object { 'y' }) -join "`n"
$yes | & $sdkmanager --sdk_root="$($env:ANDROID_SDK_ROOT)" --licenses | Out-Null
Write-Host "[setup] Cai $($AndroidPackages -join ', ')..."
# sdkmanager.bat chay qua cmd: ';' la dau tach tham so nen moi goi phai nam trong ngoac kep.
$quoted = $AndroidPackages | ForEach-Object { '"' + $_ + '"' }
& $sdkmanager --sdk_root="$($env:ANDROID_SDK_ROOT)" @quoted
if ($LASTEXITCODE -ne 0) { throw 'sdkmanager loi.' }
foreach ($p in $AndroidPackages) {
    if (-not (Test-Path (Join-Path $env:ANDROID_SDK_ROOT ($p -replace ';', '\')))) { throw "Chua cai duoc $p." }
}

# Flutter doc ANDROID_SDK_ROOT/JAVA_HOME tu flutter_env.ps1; ghi them vao cau hinh
# flutter (vai byte trong %APPDATA%) de 'flutter doctor' cung thay.
flutter config --android-sdk "$($env:ANDROID_SDK_ROOT)" --jdk-dir "$($env:JAVA_HOME)" | Out-Null
Write-Host '[setup] Xong. Kiem tra: flutter doctor -v'
