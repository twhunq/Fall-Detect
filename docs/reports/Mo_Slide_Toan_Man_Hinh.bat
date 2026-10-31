@echo off
rem Mo slide thuyet trinh toan man hinh ngay khi mo (Microsoft Edge, che do app).
rem Thoat: Alt+F4. Khong co Edge thi mo bang trinh duyet mac dinh, bam F de toan man hinh.
set "SLIDE=%~dp0Slide_Thuyet_Trinh_Nhom_1.html"
set "URL=file:///%SLIDE:\=/%"
set "PROFILE=%TEMP%\baonga-slide"
if exist "D:\dev-tools\temp" set "PROFILE=D:\dev-tools\temp\baonga-slide"
set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if exist "%EDGE%" (
  start "" "%EDGE%" --app="%URL%" --start-fullscreen --user-data-dir="%PROFILE%" --no-first-run --disable-features=Translate
) else (
  start "" "%SLIDE%"
)
