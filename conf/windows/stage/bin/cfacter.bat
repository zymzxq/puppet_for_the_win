@echo off
SETLOCAL

call "%~dp0environment.bat" %0 %*

"%CFACTER_DIR%\bin\cfacter.exe" %*
