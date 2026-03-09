@echo off
setlocal enabledelayedexpansion

set OPTS=none minimal size speed aggressive

echo Starting odin-mbox local CI (Windows)...

for %%o in (%OPTS%) do (
    echo.
    echo --- opt: %%o ---

    echo   build root lib...
    if "%%o"=="none" (
        odin build . -build-mode:lib -vet -strict-style -o:none -debug
    ) else (
        odin build . -build-mode:lib -vet -strict-style -o:%%o
    )
    if !errorlevel! neq 0 (
        echo [ERROR] root build failed for -o:%%o
        exit /b !errorlevel!
    )

    echo   build examples...
    if "%%o"=="none" (
        odin build ./examples/ -build-mode:lib -vet -strict-style -o:none -debug
    ) else (
        odin build ./examples/ -build-mode:lib -vet -strict-style -o:%%o
    )
    if !errorlevel! neq 0 (
        echo [ERROR] examples build failed for -o:%%o
        exit /b !errorlevel!
    )

    echo   test tests/...
    if "%%o"=="none" (
        odin test ./tests/ -vet -strict-style -disallow-do -o:none -debug
    ) else (
        odin test ./tests/ -vet -strict-style -disallow-do -o:%%o
    )
    if !errorlevel! neq 0 (
        echo [ERROR] tests failed for -o:%%o
        exit /b !errorlevel!
    )

    echo   pass: %%o
)

echo.
echo ALL CHECKS PASSED
