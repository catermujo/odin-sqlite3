@echo off

setlocal

if not defined SQLITE_REPOSITORY set "SQLITE_REPOSITORY=https://github.com/sqlite/sqlite.git"
set "VENDOR_WINDOWS_ARCH=%VSCMD_ARG_TGT_ARCH%"
if not defined VENDOR_WINDOWS_ARCH set "VENDOR_WINDOWS_ARCH=%PROCESSOR_ARCHITECTURE%"
if /I "%VENDOR_WINDOWS_ARCH%"=="AMD64" set "VENDOR_WINDOWS_ARCH=x64"
if /I "%VENDOR_WINDOWS_ARCH%"=="ARM64" set "VENDOR_WINDOWS_ARCH=arm64"
if /I "%VENDOR_WINDOWS_ARCH%"=="X86" set "VENDOR_WINDOWS_ARCH=x64"
if /I not "%VENDOR_WINDOWS_ARCH%"=="x64" if /I not "%VENDOR_WINDOWS_ARCH%"=="arm64" (
    echo Unsupported Windows architecture: %VENDOR_WINDOWS_ARCH% 1>&2
    exit /b 1
)

set "BASE=%~dp0"
set "SOURCE_DIR=%BASE%sqlite"
set "OUTPUT_DIR=%BASE%windows_%VENDOR_WINDOWS_ARCH%"
if exist "%SOURCE_DIR%\.git\" goto source_ready
if exist "%SOURCE_DIR%" (
    echo SQLite source path exists but is not a git checkout: %SOURCE_DIR% 1>&2
    exit /b 1
)

where git >nul 2>&1 || (
    echo Missing required command: git 1>&2
    exit /b 1
)
git clone --depth 1 "%SQLITE_REPOSITORY%" "%SOURCE_DIR%" || exit /b 1

:source_ready
where nmake >nul 2>&1 || (
    echo Missing required command: nmake 1>&2
    exit /b 1
)
where cl >nul 2>&1 || (
    echo Missing required command: cl 1>&2
    exit /b 1
)
set "MSVC_BIN="
for /f "delims=" %%I in ('where cl.exe 2^>nul') do if not defined MSVC_BIN set "MSVC_BIN=%%~dpI"
if not defined MSVC_BIN (
    echo Could not locate MSVC tools beside cl.exe 1>&2
    exit /b 1
)
set "MSVC_LINK=%MSVC_BIN%link.exe"
if not exist "%MSVC_LINK%" (
    echo Missing MSVC linker: %MSVC_LINK% 1>&2
    exit /b 1
)

pushd "%SOURCE_DIR%" || exit /b 1
call make.bat sqlite3.c
if errorlevel 1 (
    popd
    exit /b 1
)
popd

set "BUILD_DIR=%TEMP%\sqlite_shared_%VENDOR_WINDOWS_ARCH%_%RANDOM%"
mkdir "%BUILD_DIR%" || exit /b 1
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

cl /nologo /O2 /D"SQLITE_API=__declspec(dllexport)" /c "%SOURCE_DIR%\sqlite3.c" /Fo"%BUILD_DIR%\sqlite3.obj"
if errorlevel 1 goto failed
"%MSVC_LINK%" /DLL /NOLOGO /OUT:"%OUTPUT_DIR%\sqlite3.dll" /IMPLIB:"%OUTPUT_DIR%\sqlite3_shared.lib" "%BUILD_DIR%\sqlite3.obj"
if errorlevel 1 goto failed

echo SQLite shared build completed successfully!
rmdir /s /q "%BUILD_DIR%"
exit /b 0

:failed
rmdir /s /q "%BUILD_DIR%"
exit /b 1
