@echo off
setlocal
title Nap firmware THIET BI GIAM SAT K230 - ESP32-S3
cd /d "%~dp0\.."

REM ==========================================================================
REM flash_bridge.bat - Nap chuong trinh cho THIET BI GIAM SAT dau voi cam K230
REM --------------------------------------------------------------------------
REM Bo mach   : ESP32-S3-DevKitC-1 N16R8 (16MB flash, 8MB Octal PSRAM)
REM Moi truong: camera_bridge  (xem platformio.ini)
REM
REM Cach dung:
REM     scripts\flash_bridge.bat        -> tu tim cong COM
REM     scripts\flash_bridge.bat COM3   -> chi dinh dung cong COM3
REM
REM Cam CA HAI bo mach vao may cung luc thi PHAI ghi ro cong.
REM
REM LUU Y VE CONG USB TREN DEVKITC-1: bo mach nay co HAI cong micro-USB.
REM Cau hinh dang dung xuat Serial qua cong ghi "UART", KHONG phai cong ghi
REM "USB". Cam nham cong thi may van co dien nhung khong nap duoc.
REM ==========================================================================

set "MOI_TRUONG=camera_bridge"

echo ==========================================================
echo   NAP FIRMWARE THIET BI GIAM SAT K230  ^(ESP32-S3^)
echo   Moi truong build: %MOI_TRUONG%
echo ==========================================================
echo.

REM ---- Tim lenh pio: uu tien moi truong ao chuan cua PlatformIO ----
set "PIO=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if not exist "%PIO%" set "PIO=pio"

REM ---- Cong COM: lay tu tham so dong lenh neu co ----
set "THAM_SO_CONG="
set "THAM_SO_MONITOR="
if not "%~1"=="" set "THAM_SO_CONG=--upload-port %~1"
if not "%~1"=="" set "THAM_SO_MONITOR=--monitor-port %~1"

if "%~1"=="" (
    echo [i] Khong chi dinh cong COM - de PlatformIO tu tim.
) else (
    echo [i] Nap qua cong %~1
)
echo [i] Nho cam day vao cong ghi "UART" tren bo mach.
echo.

"%PIO%" run -e %MOI_TRUONG% -t upload %THAM_SO_CONG%
if errorlevel 1 goto loi

echo.
echo ==========================================================
echo   [OK] Da nap xong firmware thiet bi giam sat.
echo ==========================================================
echo.
set /p XEM_LOG="Mo Serial Monitor de xem log khoi dong? (c/k): "
if /i "%XEM_LOG%"=="c" (
    echo.
    echo [i] Dang mo Serial Monitor - nhan Ctrl+C de thoat.
    echo.
    "%PIO%" run -e %MOI_TRUONG% -t monitor %THAM_SO_MONITOR%
)
goto ket_thuc

:loi
echo.
echo ==========================================================
echo   [LOI] Nap that bai.
echo ==========================================================
echo.
echo Cac nguyen nhan thuong gap voi ESP32-S3-DevKitC-1:
echo.
echo  1. Cam nham cong USB.
echo     Bo mach co hai cong. Cau hinh nay can cong ghi "UART".
echo.
echo  2. May khong vao che do nap.
echo     GIU nut BOOT, bam nhanh nut RESET, tha nut BOOT ra, roi chay lai.
echo.
echo  3. Sai cong COM.
echo     Cam ca hai bo mach cung luc thi phai ghi ro, vi du:
echo         scripts\flash_bridge.bat COM3
echo     Xem cong nao la cong nao trong Device Manager ^> Ports.
echo.
echo  4. Toc do nap qua cao.
echo     Ha upload_speed trong platformio.ini tu 460800 xuong 115200.
echo.

:ket_thuc
echo.
pause
endlocal
