@echo off
title Nap TinyML - ESP32-S3 Super Mini
cd /d "%~dp0"
rem Bam dup: tu build va nap vao ESP32-S3 duy nhat dang cam (tu tim cong COM).
rem Van truyen tham so duoc, vi du: flash.bat --port COM3
echo Dang build va nap firmware... Khong rut USB.
echo.
python flash.py %*
if errorlevel 1 (
  echo.
  echo [LOI] Build/nap that bai. Xem thong bao ben tren.
  echo Neu khong thay cong: giu BOOT, bam RESET, tha BOOT roi chay lai.
) else (
  echo.
  echo [OK] Hoan tat. Mo monitor.bat de xem log.
)
pause
