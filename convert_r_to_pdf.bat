@echo off
cd /d "%~dp0"
if "%~1"=="" (
  echo Drag an .r file onto this file, or run:
  echo convert_r_to_pdf.bat "path\to\homework.r"
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_r_pdf_service.ps1" -Once -InputFile "%~1"
pause
