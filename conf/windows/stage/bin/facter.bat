@echo off
SETLOCAL

call "%~dp0environment.bat" %0 %*

"%FACTERDIR%\bin\facter.exe" %*
