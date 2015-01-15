@echo off
echo Running CFacter on demand ...
cd "%~dp0"
call .\cfacter.bat %*
PAUSE
