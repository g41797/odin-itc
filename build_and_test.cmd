@echo off
setlocal enabledelayedexpansion

set OPTS=debug speed size compat

echo Starting Odin Mailbox Local CI (Windows)...

for %%o in (%OPTS%) do (
    echo.
    echo ------------------------------------------
    echo Testing configuration: -o:%%o
    echo ------------------------------------------
    
    echo Running build check...
    odin build . -no-entrypoint -vet -strict-style -disallow-do -o:%%o
    if !errorlevel! neq 0 (
        echo [ERROR] Build failed for -o:%%o
        exit /b !errorlevel!
    )
    
    echo Running tests...
    odin test . -vet -strict-style -disallow-do -o:%%o
    if !errorlevel! neq 0 (
        echo [ERROR] Tests failed for -o:%%o
        exit /b !errorlevel!
    )
    
    echo Pass: -o:%%o
)

echo.
echo ALL LOCAL CHECKS PASSED
# pause