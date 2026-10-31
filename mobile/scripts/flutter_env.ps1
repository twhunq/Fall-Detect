# Thiet lap moi truong Flutter tren o D: (o C: sap day).
# Dung: . .\mobile\scripts\flutter_env.ps1   (dau cham + cach: nap vao phien hien tai)
#
# Moi SDK va cache nam duoi D:\dev-tools (doi bang bien DEV_TOOLS_ROOT neu can).
# Neu chua co Flutter SDK, script tu tai ban stable Windows (portable zip) ve
# D:\dev-tools\flutter. Khong ghi gi vao bien moi truong he thong (chi phien nay).

$ErrorActionPreference = 'Stop'

$DevRoot = if ($env:DEV_TOOLS_ROOT) { $env:DEV_TOOLS_ROOT } else { 'D:\dev-tools' }
if (-not (Test-Path (Split-Path $DevRoot -Qualifier))) {
    throw "Khong tim thay o dia cua $DevRoot. Dat DEV_TOOLS_ROOT tro toi o con trong."
}

$env:DEV_TOOLS_ROOT     = $DevRoot
$env:FLUTTER_ROOT       = Join-Path $DevRoot 'flutter'
$env:JAVA_HOME          = Join-Path $DevRoot 'jdk-17'
$env:ANDROID_SDK_ROOT   = Join-Path $DevRoot 'android-sdk'
$env:ANDROID_HOME       = $env:ANDROID_SDK_ROOT
$env:PUB_CACHE          = Join-Path $DevRoot 'cache\pub'
$env:GRADLE_USER_HOME   = Join-Path $DevRoot 'cache\gradle'
$env:ANDROID_USER_HOME  = Join-Path $DevRoot 'cache\android'
$env:ANDROID_EMULATOR_HOME = $env:ANDROID_USER_HOME
Remove-Item Env:ANDROID_PREFS_ROOT -ErrorAction SilentlyContinue
$env:ANALYZER_STATE_LOCATION_OVERRIDE = Join-Path $DevRoot 'cache\dart-server'
$env:TEMP               = Join-Path $DevRoot 'temp'
$env:TMP                = $env:TEMP
# Kotlin chay trong tien trinh Gradle (android/gradle.properties) nen khong ghi gi vao %LOCALAPPDATA%\kotlin.
$env:GRADLE_OPTS       = "-Djava.io.tmpdir=$($env:TEMP)"
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'

foreach ($dir in @($DevRoot, $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:ANDROID_USER_HOME,
                   $env:ANALYZER_STATE_LOCATION_OVERRIDE, $env:TEMP)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}

# Thu vien analytics cua AGP bo qua ANDROID_USER_HOME va ghi %USERPROFILE%\.android\analytics.settings.
# Doi user.home trong JVM Gradle (file gradle.properties cap nguoi dung, nam tren D:) de no ghi vao D:.
$gradleUserProps = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$jvmHome = (Join-Path $DevRoot 'cache\jvm-home') -replace '\\', '/'
$wanted = "systemProp.user.home=$jvmHome"
if (-not (Test-Path $gradleUserProps) -or -not (Select-String -Quiet -SimpleMatch $wanted $gradleUserProps)) {
    Add-Content -Encoding ascii -Path $gradleUserProps -Value $wanted
}

function Install-FlutterSdk {
    param([string]$Target)
    Write-Host "[flutter_env] Chua co Flutter SDK, dang tai ban stable ve $Target ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $base = 'https://storage.googleapis.com/flutter_infra_release/releases'
    $index = Invoke-RestMethod -UseBasicParsing "$base/releases_windows.json"
    $hash = $index.current_release.stable
    $release = $index.releases | Where-Object { $_.hash -eq $hash } | Select-Object -First 1
    if (-not $release) { throw 'Khong doc duoc ban Flutter stable hien tai.' }
    $zip = Join-Path $env:TEMP ("flutter_" + $release.version + ".zip")
    if (-not (Test-Path $zip)) {
        Write-Host "[flutter_env] Tai Flutter $($release.version) (~1 GB)..."
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -UseBasicParsing -Uri "$base/$($release.archive)" -OutFile "$zip.part" }
        finally { $ProgressPreference = $old }
        Move-Item -Force "$zip.part" $zip
    }
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($release.sha256 -and $actual -ne $release.sha256.ToLower()) {
        Remove-Item -Force $zip
        throw "Sai SHA-256 cua goi Flutter (tai lai lan sau)."
    }
    Write-Host '[flutter_env] Giai nen...'
    # tar.exe (co san tu Windows 10 1803) giai nen nhanh hon Expand-Archive nhieu.
    $parent = Split-Path $Target -Parent
    & tar.exe -xf $zip -C $parent
    if ($LASTEXITCODE -ne 0) { Expand-Archive -Force -Path $zip -DestinationPath $parent }
    Remove-Item -Force $zip
    if (-not (Test-Path (Join-Path $Target 'bin\flutter.bat'))) { throw 'Giai nen Flutter that bai.' }
}

if (-not (Test-Path (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'))) {
    Install-FlutterSdk -Target $env:FLUTTER_ROOT
}

# Dua cac thu muc bin len dau PATH (chi trong phien nay, khong lap lai).
$prepend = @((Join-Path $env:FLUTTER_ROOT 'bin'), (Join-Path $env:PUB_CACHE 'bin'))
if (Test-Path (Join-Path $env:JAVA_HOME 'bin')) { $prepend += (Join-Path $env:JAVA_HOME 'bin') }
$cmdline = Join-Path $env:ANDROID_SDK_ROOT 'cmdline-tools\latest\bin'
if (Test-Path $cmdline) { $prepend += $cmdline }
$pt = Join-Path $env:ANDROID_SDK_ROOT 'platform-tools'
if (Test-Path $pt) { $prepend += $pt }
$parts = $env:PATH -split ';' | Where-Object { $_ -and ($prepend -notcontains $_) }
$env:PATH = (($prepend + $parts) -join ';')

if (-not $env:FLUTTER_ENV_QUIET) {
    Write-Host "[flutter_env] FLUTTER_ROOT=$($env:FLUTTER_ROOT)"
    Write-Host "[flutter_env] PUB_CACHE=$($env:PUB_CACHE)  GRADLE_USER_HOME=$($env:GRADLE_USER_HOME)"
    Write-Host "[flutter_env] TEMP=$($env:TEMP)"
}
$ErrorActionPreference = 'Continue'
