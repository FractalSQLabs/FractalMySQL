@echo off
REM scripts/windows/build.bat
REM
REM Builds fractalsql.dll on Windows with the MSVC toolchain using
REM static CRT (/MT) and whole-program optimization (/GL), matching
REM the Linux posture — zero runtime dependency on the Visual C++
REM Redistributable, and zero dependency on libluajit at load time.
REM
REM One DLL per (MySQL major, arch) cell: the UDF ABI is stable
REM across 8.0 / 8.4 LTS / 9.x, but we still build per-major on
REM Windows because the install target path differs per server
REM installation (C:\Program Files\MySQL\MySQL Server ^<VER^>\lib\plugin\).
REM
REM Prerequisites
REM   * Visual Studio Build Tools (cl.exe on PATH — invoke from a
REM     Developer Command Prompt, or `call vcvarsall.bat ^<arch^>` first).
REM   * A static LuaJIT archive (lua51.lib) built with msvcbuild.bat
REM     static against the same host arch as cl.exe.
REM   * A MySQL Windows binaries tree (mysql-^<VER^>-winx64.zip from
REM     dev.mysql.com / downloads.mysql.com/archives), unpacked so
REM     that:
REM         %MYSQL_DIR%\include\mysql.h
REM     exists. Only headers are needed — UDFs don't link against a
REM     server import lib.
REM
REM Environment overrides
REM   LUAJIT_DIR    directory with lua.h / lualib.h / lauxlib.h + lua51.lib
REM   MYSQL_DIR     directory with MySQL binaries tree
REM                 (the "mysql-^<VER^>-winx64" root from the ZIP)
REM   MYSQL_MAJOR   MySQL major version being targeted (e.g. 8.0, 8.4, 9.1)
REM   OUT_DIR       output directory for fractalsql.dll
REM
REM Invocation
REM   set LUAJIT_DIR=%CD%\deps\LuaJIT\src
REM   set MYSQL_DIR=%CD%\deps\mysql\root
REM   set MYSQL_MAJOR=8.4
REM   set OUT_DIR=dist\windows\my8.4
REM   scripts\windows\build.bat

setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

if "%LUAJIT_DIR%"=="" set LUAJIT_DIR=%CD%\deps\LuaJIT\src
if "%MYSQL_DIR%"=="" (
    echo ==^> ERROR: MYSQL_DIR must point at an unpacked MySQL binaries tree
    exit /b 1
)
if "%MYSQL_MAJOR%"==""   (
    echo ==^> ERROR: MYSQL_MAJOR must be set ^(8.0 ^| 8.4 ^| 9.1^)
    exit /b 1
)
if "%OUT_DIR%"==""    set OUT_DIR=dist\windows\my%MYSQL_MAJOR%

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo ==^> LUAJIT_DIR    = %LUAJIT_DIR%
echo ==^> MYSQL_DIR     = %MYSQL_DIR%
echo ==^> MYSQL_MAJOR   = %MYSQL_MAJOR%
echo ==^> OUT_DIR       = %OUT_DIR%

REM LuaJIT's msvcbuild.bat static emits lua51.lib; accept the
REM Makefile-style libluajit-5.1.lib name too if present.
set LUAJIT_LIB=%LUAJIT_DIR%\libluajit-5.1.lib
if not exist "%LUAJIT_LIB%" (
    if exist "%LUAJIT_DIR%\lua51.lib" set LUAJIT_LIB=%LUAJIT_DIR%\lua51.lib
)
if not exist "%LUAJIT_LIB%" (
    echo ==^> ERROR: no LuaJIT static library in %LUAJIT_DIR%
    echo         ^(expected libluajit-5.1.lib or lua51.lib^)
    exit /b 1
)
echo ==^> LUAJIT_LIB    = %LUAJIT_LIB%

REM MySQL header tree. A UDF doesn't call server-exported symbols,
REM so no server import lib is needed — the server loads this DLL and
REM calls the exported UDF entry points by name via GetProcAddress.
REM The Oracle MySQL winx64 zip lays headers at include\mysql.h
REM (unlike MariaDB which uses include\mysql\mysql.h).
set MYSQL_INC=%MYSQL_DIR%\include
if not exist "%MYSQL_INC%\mysql.h" (
    echo ==^> ERROR: %MYSQL_INC%\mysql.h not found — check MYSQL_DIR layout
    exit /b 1
)
echo ==^> MYSQL_INC     = %MYSQL_INC%

REM cl.exe flags:
REM   /MT     static CRT (no MSVC runtime DLL dependency)
REM   /GL     whole-program optimization (paired with /LTCG at link)
REM   /O2     optimize for speed
REM   /LD     build a DLL
REM   /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS
REM
REM The UDF entry points (fractal_search / fractalsql_edition /
REM fractalsql_version plus their _init/_deinit) carry
REM __declspec(dllexport) via the FRACTAL_EXPORT macro in
REM src/fractalsql.c, so no .def file is needed and candle/light
REM downstream won't need to play with export tables.
cl.exe /nologo /MT /GL /O2 ^
    /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS ^
    /I"%LUAJIT_DIR%" ^
    /I"%MYSQL_INC%" ^
    /Iinclude ^
    /LD src\fractalsql.c ^
    /Fo"%OUT_DIR%\\" ^
    /Fe"%OUT_DIR%\fractalsql.dll" ^
    /link /LTCG ^
        "%LUAJIT_LIB%"

if errorlevel 1 (
    echo.
    echo ==^> BUILD FAILED for MySQL %MYSQL_MAJOR%
    exit /b 1
)

echo.
echo ==^> Built %OUT_DIR%\fractalsql.dll ^(MySQL %MYSQL_MAJOR%^)
dir "%OUT_DIR%\fractalsql.dll"

endlocal
