@echo off
rem Finds Git for Windows bash.exe and sets GITBASH (windows\bin\*.cmd call this; exit code 1 if not found).
rem Same lookup as gitbash-lib.ps1: one and two levels above each git.exe on PATH
rem (cmd\git.exe, bin\git.exe, mingw64\bin\git.exe, ucrt64\bin\git.exe), then the standard install locations.
rem ASCII only: cmd.exe reads this file in the console code page.
set "GITBASH="
for /f "delims=" %%G in ('where git.exe 2^>nul') do (call :try "%%~dpG.." & call :try "%%~dpG..\..")
call :try "%ProgramFiles%\Git"
call :try "%ProgramFiles(x86)%\Git"
call :try "%LocalAppData%\Programs\Git"
if defined GITBASH exit /b 0
echo bash.exe of Git for Windows was not found. Put git.exe on PATH or install Git for Windows. 1>&2
exit /b 1

:try
if defined GITBASH exit /b 0
if exist "%~1\bin\bash.exe" for %%P in ("%~1\bin\bash.exe") do set "GITBASH=%%~fP"
exit /b 0
