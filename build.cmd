@echo off
REM TimeCapsule - offline build entry (Windows)
REM Usage: build.cmd         build
REM        build.cmd clean   clean then build
REM
REM Note: on this machine DevEco Studio's ohpm / hvigor / java are not on PATH,
REM and libimage_transcoder_shared.dll needs libcjson / libhilog /
REM libskia_canvaskit, which live in other SDK folders. Those folders must be on
REM PATH, otherwise resource compilation fails with
REM "An Application Control policy has blocked this file"
REM (in reality: a missing dependent DLL).

setlocal
set "DEVECO=D:\DevEco Studio"
set "DEVECO_SDK_HOME=%DEVECO%\sdk"
set "PATH=%DEVECO%\tools\node;%DEVECO%\jbr\bin;%DEVECO_SDK_HOME%\default\hms\toolchains\lib;%DEVECO_SDK_HOME%\default\openharmony\previewer\common\bin;%DEVECO_SDK_HOME%\default\openharmony\toolchains;%PATH%"

if not exist "%DEVECO%\tools\hvigor\bin\hvigorw.bat" (
    echo [ERROR] hvigorw not found: %DEVECO%\tools\hvigor\bin\hvigorw.bat
    exit /b 1
)

if /i "%~1"=="clean" (
    echo "==> clean"
    call "%DEVECO%\tools\hvigor\bin\hvigorw.bat" clean --no-daemon
    if errorlevel 1 exit /b 1
)

echo "==> assembleHap"
REM remove stale artifacts first, so a failed build cannot be mistaken for success
if exist "%~dp0entry\build\default\outputs\default\*.hap" del /q "%~dp0entry\build\default\outputs\default\*.hap"
call "%DEVECO%\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
set "HVG_EXIT=%ERRORLEVEL%"

REM hvigor prints an unsigned-hap warning to stderr, so the exit code is not a
REM reliable success signal here; check the artifact instead.
set "HAP="
for /f "delims=" %%f in ('dir /b /s /o-d "%~dp0entry\build\*.hap" 2^>nul') do if not defined HAP set "HAP=%%f"
if not defined HAP (
    echo [ERROR] build failed - no .hap artifact was produced ^(hvigor exit %HVG_EXIT%^)
    exit /b 1
)
echo "==> artifact: %HAP%"
endlocal
