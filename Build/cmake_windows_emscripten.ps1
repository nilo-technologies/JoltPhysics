<#
.SYNOPSIS
    Configure and build Jolt Physics for WebAssembly (Emscripten) on Windows.

.DESCRIPTION
    Mirrors Build/cmake_linux_emscripten.sh for PowerShell. Default is Debug WASM
    (asserts on, suitable for C++ debugging in Chrome via DWARF — see JPH_DEBUG_SYMBOL_FORMAT).

    Prerequisites:
    - CMake 3.20+ on PATH
    - Ninja on PATH (recommended), or install via: winget install Ninja-build.Ninja
    - Emscripten SDK: clone https://github.com/emscripten-core/emsdk and run
        .\emsdk install latest
        .\emsdk activate latest

    Usage (run from this Build folder in PowerShell):
        $env:EMSDK = 'C:\dev\emsdk'
        .\cmake_windows_emscripten.ps1

    From Command Prompt (cmd.exe), use set + powershell (no $env: syntax in cmd):
        set EMSDK=C:\dev\emsdk
        powershell -NoProfile -ExecutionPolicy Bypass -File cmake_windows_emscripten.ps1

    Or pass the path without any env var (works from cmd or PowerShell):
        powershell -NoProfile -ExecutionPolicy Bypass -File cmake_windows_emscripten.ps1 -EmsdkRoot C:\dev\emsdk

    Other examples:
        .\cmake_windows_emscripten.ps1 -Configuration Distribution
        .\cmake_windows_emscripten.ps1 -EmsdkRoot C:\emsdk -SkipBuild
        .\cmake_windows_emscripten.ps1 -CMakeExtra @('-DUSE_WASM_SIMD=ON')

    After a successful build, outputs live under .\WASM_<Configuration>\ (e.g. UnitTests.js).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Debug', 'Release', 'Distribution')]
    [string] $Configuration = 'Debug',

    [Parameter()]
    [string] $EmsdkRoot = $(if ($env:EMSDK) { $env:EMSDK } else { '' }),

    [Parameter()]
    [switch] $SkipConfigure,

    [Parameter()]
    [switch] $SkipBuild,

    [Parameter()]
    [string[]] $CMakeExtra = @('-DTARGET_HELLO_WORLD=OFF', '-DTARGET_PERFORMANCE_TEST=OFF')
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$buildDirName = "WASM_$Configuration"
$buildDir = Join-Path $here $buildDirName

function Resolve-EmsdkRoot {
    param([string] $Root)
    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $null
    }
    if (Test-Path (Join-Path $Root 'emsdk_env.ps1')) {
        return (Resolve-Path $Root).Path
    }
    return $null
}

$resolved = Resolve-EmsdkRoot -Root $EmsdkRoot
if (-not $resolved) {
    Write-Error @"
Emscripten SDK root not found. Set EMSDK or pass -EmsdkRoot to your emsdk clone (directory containing emsdk_env.ps1).

PowerShell:
  `$env:EMSDK = 'C:\emsdk'
  .\cmake_windows_emscripten.ps1

Command Prompt (cmd.exe):
  set EMSDK=C:\emsdk
  powershell -NoProfile -File cmake_windows_emscripten.ps1

Or from either shell:
  powershell -NoProfile -File cmake_windows_emscripten.ps1 -EmsdkRoot C:\emsdk
"@
}

$emsdkEnv = Join-Path $resolved 'emsdk_env.ps1'
Write-Host "Sourcing: $emsdkEnv"
. $emsdkEnv

if (-not (Get-Command emcmake -ErrorAction SilentlyContinue)) {
    Write-Error 'emcmake not on PATH after emsdk_env. Check your Emscripten install.'
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error 'cmake not on PATH. Install CMake 3.20+ and add it to PATH.'
}

$generator = $null
if (Get-Command ninja -ErrorAction SilentlyContinue) {
    $generator = 'Ninja'
    Write-Host 'Using generator: Ninja'
}
else {
    Write-Error @"
Ninja not found on PATH. Install Ninja (winget install Ninja-build.Ninja) and re-run.

Unix Makefiles + make are not used on Windows by this script to avoid fragile setups.
"@
}

Push-Location $here
try {
    if (-not $SkipConfigure) {
        Write-Host "Configuring $buildDirName (CMAKE_BUILD_TYPE=$Configuration)..."
        $cmakeArgs = @(
            '-S', '.',
            '-B', $buildDirName,
            '-G', $generator,
            "-DCMAKE_BUILD_TYPE=$Configuration"
        ) + $CMakeExtra
        & emcmake cmake @cmakeArgs
    }
    else {
        Write-Host "Skipping configure (-SkipConfigure)."
    }

    if (-not $SkipBuild) {
        Write-Host "Building $buildDirName..."
        cmake --build $buildDirName --parallel
        Write-Host ""
        Write-Host "Done. Key outputs under: $buildDir"
        Write-Host "  Run unit tests: node UnitTests.js   (cwd: $buildDir)"
    }
    else {
        Write-Host "Skipping build (-SkipBuild)."
    }
}
finally {
    Pop-Location
}
