@setlocal
@rem Windows runs Node scripts by extension (spawn "npm.cmd"), but the Node install dir is off PATH (see windows\powershell\profile.ps1); forward to the mise shim.
@if exist "%LOCALAPPDATA%\mise\shims\corepack.exe" goto run
@echo corepack.exe was not found in %LOCALAPPDATA%\mise\shims. Run: mise install 1>&2
@exit /b 1
:run
@"%LOCALAPPDATA%\mise\shims\corepack.exe" %*
@exit /b %ERRORLEVEL%
