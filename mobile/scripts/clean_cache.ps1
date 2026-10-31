# Don sach cache/tam sau khi lam xong (1 lenh):
#   D:\dev-tools\cache\, D:\dev-tools\temp\, mobile\build\, mobile\.dart_tool\
# Giu nguyen SDK (flutter, jdk-17, android-sdk). Lan build sau se tai lai goi pub/Gradle.
# Dung: powershell -ExecutionPolicy Bypass -File mobile\scripts\clean_cache.ps1

$ErrorActionPreference = 'Continue'
$DevRoot = if ($env:DEV_TOOLS_ROOT) { $env:DEV_TOOLS_ROOT } else { 'D:\dev-tools' }
$Mobile = Split-Path $PSScriptRoot -Parent

# Gradle/Kotlin daemon dang chay se khoa file trong cache: dung chung truoc.
$gradlew = Join-Path $Mobile 'android\gradlew.bat'
if ((Test-Path $gradlew) -and (Test-Path (Join-Path $DevRoot 'jdk-17\bin\java.exe'))) {
    $env:JAVA_HOME = Join-Path $DevRoot 'jdk-17'
    $env:GRADLE_USER_HOME = Join-Path $DevRoot 'cache\gradle'
    Push-Location (Join-Path $Mobile 'android')
    & $gradlew --stop 2>$null | Out-Null
    Pop-Location
}
Get-Process -Name 'dart', 'dartaotruntime' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$DevRoot*" } | Stop-Process -Force -ErrorAction SilentlyContinue

$targets = @(
    (Join-Path $DevRoot 'cache'),
    (Join-Path $DevRoot 'temp'),
    (Join-Path $Mobile 'build'),
    (Join-Path $Mobile '.dart_tool')
)
$freed = 0
foreach ($t in $targets) {
    if (-not (Test-Path $t)) { Write-Host "[clean] Khong co: $t"; continue }
    $size = (Get-ChildItem -LiteralPath $t -Recurse -Force -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    try {
        Remove-Item -LiteralPath $t -Recurse -Force -Confirm:$false -ErrorAction Stop
        $freed += $size
        Write-Host ("[clean] Da xoa {0} ({1:N0} MB)" -f $t, ($size / 1MB))
    } catch {
        Write-Host "[clean] Khong xoa het $t (file dang bi khoa?): $($_.Exception.Message)"
    }
}
Write-Host ("[clean] Giai phong tong cong {0:N0} MB." -f ($freed / 1MB))
