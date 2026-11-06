@setlocal
@call "%~dp0..\gitbash-lib.cmd" || exit /b 1
@"%GITBASH%" "%~dp0..\posix\run" handoff %*
@exit /b %ERRORLEVEL%
