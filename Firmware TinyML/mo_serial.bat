@echo off
title Serial - ESP32-S3 Super Mini
cd /d "%~dp0"
python serial_monitor.py %*
pause
