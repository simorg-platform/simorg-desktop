# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Builds Simorg for Windows -- x64 and ARM64, both from one Intel machine.
#
#   .\scripts\build-windows.ps1                    both architectures
#   .\scripts\build-windows.ps1 x64                just one
#   .\scripts\build-windows.ps1 -Config dev        point the build at localhost
#   .\scripts\build-windows.ps1 -InstallQt         fetch Qt first, then build
#   .\scripts\build-windows.ps1 -List              what the targets are
#
# The Unix half of this is scripts/build-targets.sh; the two produce the same
# shape of output under build\dist\<target>\ and are deliberately separate
# rather than one script with branches, because nothing in a Windows build
# resembles a Linux one past "run cmake".
#
# --- ARM64 from an Intel machine ----------------------------------------------
#
# Cross-compiled, not emulated. MSVC has shipped an ARM64 backend that runs on
# x64 for years, and Qt publishes a matching ARM64 build; what the arrangement
# needs is for CMake to be told that the *tools* (moc, rcc, qmlcachegen) come
# from the x64 Qt while everything linked comes from the ARM64 one. That is
# QT_HOST_PATH, and it is the only unusual line in here.
#
# --- Everything the app needs travels with it ---------------------------------
#
# windeployqt copies Qt, its plugins and its QML modules next to the binary, and
# the Visual C++ runtime is copied in beside them from the toolchain's own
# redistributable directory -- app-local deployment, which is what that directory
# is published for. The result is a folder somebody unzips and runs: no Qt, no
# "VCRUNTIME140.dll was not found", nothing to install.

[CmdletBinding()]
param(
    # x64, arm64, or all. Positional so `build-windows.ps1 x64` reads naturally.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Targets = @('all'),

    # dev is a Debug build pointed at localhost; prod is optimised and points at
    # the public estate. Same meaning as --config on the Unix script.
    [ValidateSet('dev', 'prod')]
    [string] $Config = 'prod',

    # Where Qt is. Defaults to $env:SIMORG_QT_ROOT, then C:\Qt.
    [string] $QtRoot = '',

    # Which Qt to use out of what is installed. Newest by default.
    [string] $QtVersion = '',

    # Install the pinned Qt with the official Qt Online Installer before building.
    [switch] $InstallQt,

    # The Qt Online Installer -InstallQt runs, when it is already downloaded.
    # Without it, -InstallQt downloads it first.
    [string] $QtInstaller = '',

    # Delete each target's build tree first.
    [switch] $Clean,

    # Parallel compile jobs. Default: every core.
    [int] $Jobs = 0,

    [switch] $List,
    [switch] $Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DistDir   = Join-Path $SourceDir 'build\dist'
$WorkDir   = Join-Path $SourceDir 'build\targets'

# The Qt a release is built against: the same pinned version as the macOS and
# Linux builds (scripts/build-targets.sh, QT_VERSION), and one Qt publishes for
# x64 and ARM64 Windows alike, Qt WebEngine included, so the Workbench and the
# Brain are in both. A prod build uses exactly this; -QtVersion picks another.
$DefaultQtVersion = '6.11.2'

# ------------------------------------------------------------------- output ---
function Write-Step($text)  { Write-Host ''; Write-Host "> $text" -ForegroundColor Cyan }
function Write-Info($text)  { Write-Host "  $text" }
function Write-Muted($text) { Write-Host "  $text" -ForegroundColor DarkGray }
function Write-Ok($text)    { Write-Host "  [ok] $text" -ForegroundColor Green }
function Write-Warn($text)  { Write-Host "warning: $text" -ForegroundColor Yellow }
function Die($text) { Write-Host "error: $text" -ForegroundColor Red; exit 1 }

function Show-Usage {
@"
Simorg release builds for Windows

  .\scripts\build-windows.ps1 [options] [target ...]

TARGETS
  x64               Windows on x86-64. Built natively on an Intel or AMD machine.
  arm64             Windows on ARM64. Cross-compiled; an Intel machine can make it.
  all               Both. The default.

OPTIONS
  -Config dev|prod   dev is a Debug build pointed at localhost; prod is
                     optimised and points at the public estate. Default: prod.
  -QtRoot <dir>      Where Qt is installed. Default: `$env:SIMORG_QT_ROOT, then C:\Qt.
  -QtVersion <v>     Which installed Qt to build against. Default: $DefaultQtVersion
                     for a prod build, the newest for a dev one.
  -InstallQt         Install Qt $DefaultQtVersion first, with the official Qt
                     Online Installer. It asks you to sign in to a Qt account.
  -QtInstaller <exe> The installer -InstallQt runs, if already downloaded.
  -Clean             Delete each target's build tree first.
  -Jobs <n>          Parallel compile jobs. Default: every core.
  -List              Print the targets and what each one produces.
  -Help              This.

OUTPUT
  build\dist\windows-<arch>\   a .zip and its checksum, one folder per target
  build\targets\<target>\      intermediate build trees, safe to delete

REQUIREMENTS
  Visual Studio 2022 with "Desktop development with C++", and -- for the arm64
  target -- its "MSVC v143 ARM64 build tools" component. CMake and Ninja come
  with that workload. Qt is either already installed or installed by -InstallQt.
"@ | Write-Host
}

function Show-Targets {
@"
x64
  simorg-desktop.exe       the desktop app
  Qt, its plugins, its QML modules and the Visual C++ runtime, beside them

arm64
  the same, cross-compiled from this machine for ARM64 Windows

Each target produces one .zip under build\dist\windows-<arch>\ that is unzipped
and run. Nothing in it is installed and nothing is required on the other end.
"@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }
if ($List) { Show-Targets; exit 0 }

if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }

# A release is always the pinned Qt, whatever else is installed beside it.
if (-not $QtVersion -and $Config -eq 'prod') { $QtVersion = $DefaultQtVersion }

switch ($Config) {
    'dev'  { $BuildType = 'Debug';   $SimorgEnv = 'dev' }
    'prod' { $BuildType = 'Release'; $SimorgEnv = 'prod' }
}

# `x86_64`, `amd64` and friends all mean x64; accept what people type.
$Wanted = [System.Collections.Generic.List[string]]::new()
foreach ($target in $Targets) {
    switch -Regex ($target.ToLowerInvariant()) {
        '^(all)$'                              { $Wanted.Add('x64'); $Wanted.Add('arm64') }
        '^(x64|amd64|x86_64|intel|windows-x64)$' { $Wanted.Add('x64') }
        '^(arm64|aarch64|windows-arm64)$'      { $Wanted.Add('arm64') }
        default { Die "unknown target '$target' -- try -List" }
    }
}
$Wanted = $Wanted | Select-Object -Unique

# ---------------------------------------------------------------- Visual C++ --
#
# The compiler environment comes from VsDevCmd.bat, which is a batch file and
# therefore cannot set variables in this process. It is run in a child cmd that
# prints its environment afterwards, and the difference is imported here -- the
# standard way to get a developer prompt's settings into a PowerShell session
# that was not started from one.

# Captured before anything touches it, and restored before each target's own
# developer environment is imported. Without this the second architecture in a
# run inherits VSCMD_VER from the first, VsDevCmd sees an initialised prompt and
# refuses to set anything up -- so the arm64 build silently compiles with the
# x64 toolchain's INCLUDE and LIB and fails at link with errors about machine
# type mismatch that name no cause.
$PristineEnvironment = @{}
Get-ChildItem Env: | ForEach-Object { $PristineEnvironment[$_.Name] = $_.Value }

function Reset-Environment {
    Get-ChildItem Env: | ForEach-Object {
        if (-not $PristineEnvironment.ContainsKey($_.Name)) { Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue }
    }
    foreach ($name in $PristineEnvironment.Keys) {
        Set-Item -Path "Env:$name" -Value $PristineEnvironment[$name] -ErrorAction SilentlyContinue
    }
}

function Import-VisualStudioEnvironment {
    param([string] $HostArch, [string] $TargetArch)

    Reset-Environment

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        Die "Visual Studio is not installed (no vswhere.exe). Install VS 2022 with the ""Desktop development with C++"" workload."
    }

    $installation = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $installation) { Die "no Visual Studio installation with the C++ tools was found" }

    $devcmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path $devcmd)) { Die "VsDevCmd.bat not found under $installation" }

    $before = @{}
    Get-ChildItem Env: | ForEach-Object { $before[$_.Name] = $_.Value }

    # stderr is merged inside cmd, not with PowerShell's 2>&1: Windows
    # PowerShell 5.1 -- what build-driver.sh runs this with -- turns each stderr
    # line into an error record, and under ErrorActionPreference Stop the first
    # one ends the build. VsDevCmd prints a harmless "'vswhere.exe' is not
    # recognized" whenever the Visual Studio Installer is not on PATH.
    $lines = & cmd /c "call `"$devcmd`" -arch=$TargetArch -host_arch=$HostArch -no_logo 2>&1 && set"
    if ($LASTEXITCODE -ne 0) {
        Die "VsDevCmd.bat failed for target $TargetArch. Is the ""MSVC v143 - VS 2022 C++ $TargetArch build tools"" component installed?"
    }

    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $matches[1]; $value = $matches[2]
            if ($before[$name] -ne $value) { Set-Item -Path "Env:$name" -Value $value }
        }
    }
}

# --------------------------------------------------------------------- Qt -----
function Resolve-QtRoot {
    if ($QtRoot) { return $QtRoot }
    if ($env:SIMORG_QT_ROOT) { return $env:SIMORG_QT_ROOT }
    return 'C:\Qt'
}

# Qt names its Windows kits msvc2022_64 and msvc2022_arm64_cross_compiled, with
# msvc2019_64 still around on older installs. Both spellings are accepted so an
# existing installation does not have to be redone.
function Get-QtKit {
    param([string] $Root, [string] $Arch)

    if (-not (Test-Path $Root)) { return $null }

    $versions = Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^6\.\d+' } |
        Sort-Object { [version]($_.Name) } -Descending
    if ($QtVersion) { $versions = $versions | Where-Object { $_.Name -eq $QtVersion } }

    $names = if ($Arch -eq 'arm64') {
        @('msvc2022_arm64_cross_compiled', 'msvc2022_arm64', 'msvc2019_arm64')
    } else {
        @('msvc2022_64', 'msvc2019_64')
    }

    foreach ($version in $versions) {
        foreach ($name in $names) {
            $kit = Join-Path $version.FullName $name
            if (Test-Path (Join-Path $kit 'lib\cmake\Qt6')) {
                return [pscustomobject]@{ Path = $kit; Version = $version.Name }
            }
        }
    }
    return $null
}

# The add-ons this application links beyond each kit's own (Qt Base,
# Declarative, SVG): the image-format and shader plugins, and what Qt
# WebEngine stands on. WebEngine itself is an extension, installed beside them.
# Listed rather than fetching all of Qt because the difference is gigabytes.
$QtAddons = @('qtimageformats', 'qtshadertools', 'qtpositioning', 'qtwebchannel', 'qtserialport')

function Install-Qt {
    param([string] $Root)

    # aqtinstall cannot install Qt 6.11 or later for Windows: Qt split the
    # repository into one folder per compiler and aqt still asks for the old
    # combined Updates.xml (github.com/miurahr/aqtinstall issue 959). So this
    # runs Qt's own installer, from its command line, with the exact components.
    $v = $DefaultQtVersion -replace '\.', ''
    $components = @()
    foreach ($kit in @('win64_msvc2022_64', 'win64_msvc2022_arm64_cross_compiled')) {
        $components += "qt.qt6.$v.$kit"
        foreach ($addon in $QtAddons) { $components += "qt.qt6.$v.addons.$addon.$kit" }
        $components += "extensions.qtwebengine.$v.$kit"
    }

    $installer = $QtInstaller
    if (-not $installer) {
        $installer = Join-Path $WorkDir 'qt-online-installer-windows-x64-online.exe'
        if (-not (Test-Path $installer)) {
            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
            Write-Step "Downloading the Qt Online Installer"
            Invoke-WebRequest -UseBasicParsing -OutFile $installer `
                -Uri 'https://download.qt.io/official_releases/online_installers/qt-online-installer-windows-x64-online.exe'
        }
    }
    if (-not (Test-Path $installer)) { Die "no Qt Online Installer at $installer" }

    Write-Step "Installing Qt $DefaultQtVersion into $Root"
    Write-Muted "it asks you to sign in with your Qt account"
    & $installer --root $Root --accept-licenses --accept-obligations --default-answer --confirm-command install @components
    if ($LASTEXITCODE -ne 0) { Die "the Qt installer failed ($LASTEXITCODE)" }
    Write-Ok "Qt $DefaultQtVersion installed"
}

# ------------------------------------------------------- the Visual C++ runtime --
#
# windeployqt brings Qt; nothing brings the compiler's own runtime, and a
# machine without the redistributable installed answers a double-click with a
# dialog about VCRUNTIME140.dll. Copying these three beside the executable is
# app-local deployment, which is exactly what Microsoft publishes the Redist
# directory for.
function Copy-VisualCppRuntime {
    param([string] $Destination, [string] $Arch)

    $redistRoot = $env:VCToolsRedistDir
    if (-not $redistRoot -or -not (Test-Path $redistRoot)) {
        Write-Warn "VCToolsRedistDir is not set; the Visual C++ runtime was not bundled"
        Write-Muted "the target machine will need the Visual C++ Redistributable installed"
        return
    }

    $folder = Get-ChildItem (Join-Path $redistRoot $Arch) -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.CRT' } | Select-Object -First 1
    if (-not $folder) {
        Write-Warn "no CRT redistributable for $Arch under $redistRoot"
        return
    }

    Copy-Item (Join-Path $folder.FullName '*.dll') $Destination -Force
    Write-Ok "Visual C++ runtime  $($folder.Name)"
}

# ------------------------------------------------------------------ one build --
function Build-Target {
    param([string] $Arch)

    $root = Resolve-QtRoot
    $kit = Get-QtKit -Root $root -Arch $Arch
    if (-not $kit) {
        Die @"
no Qt kit for $Arch under $root

Install one with:
    .\scripts\build-windows.ps1 -InstallQt $Arch

or point at an existing installation:
    `$env:SIMORG_QT_ROOT = 'D:\Qt'
"@
    }

    $hostKit = if ($Arch -eq 'arm64') { Get-QtKit -Root $root -Arch 'x64' } else { $kit }
    if ($Arch -eq 'arm64' -and -not $hostKit) {
        Die "the arm64 build needs an x64 Qt as well -- it is where moc, rcc and qmlcachegen come from. Run with -InstallQt."
    }

    Write-Step "windows-$Arch  ($($kit.Version), $BuildType)"
    Write-Muted "qt    $($kit.Path)"
    if ($Arch -eq 'arm64') { Write-Muted "host  $($hostKit.Path)" }

    Import-VisualStudioEnvironment -HostArch 'amd64' -TargetArch $(if ($Arch -eq 'arm64') { 'arm64' } else { 'amd64' })

    $buildDir = Join-Path $WorkDir "windows-$Arch-$Config"
    $outDir   = Join-Path $DistDir "windows-$Arch"
    $stageDir = Join-Path $buildDir 'stage'

    if ($Clean -and (Test-Path $buildDir)) { Remove-Item $buildDir -Recurse -Force }
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $cmakeArgs = @(
        '-S', $SourceDir, '-B', $buildDir, '-G', 'Ninja',
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DCMAKE_PREFIX_PATH=$($kit.Path)",
        # What this makes is a driver archive, so it may replace itself with a newer release.
        '-DSIMORG_ARCHIVE_BUILD=ON',
        '-DSIMORG_BUILD_GUI=ON',
        # Said, not inherited. Left to its default the option is whether Qt
        # WebEngine was found the first time this build folder was configured,
        # and CMake keeps that answer for good: a folder first configured before
        # WebEngine was installed would ship the WebEngine DLLs beside the
        # program and no Workbench or Brain in it. ON here makes a missing
        # WebEngine stop the configure instead (src/app/CMakeLists.txt).
        '-DSIMORG_BUILD_WEBENGINE=ON'
    )
    if ($Arch -eq 'arm64') {
        # Cross-compiling: the target is ARM64 Windows, and the tools that run
        # during the build are the x64 ones.
        $cmakeArgs += @(
            '-DCMAKE_SYSTEM_NAME=Windows',
            '-DCMAKE_SYSTEM_PROCESSOR=ARM64',
            "-DQT_HOST_PATH=$($hostKit.Path)"
        )
    }

    & cmake @cmakeArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "cmake configure failed for windows-$Arch" }

    & cmake --build $buildDir --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { Die "build failed for windows-$Arch" }

    if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    # What this build makes, by name: the folder is reused, and bin\ keeps every
    # program an earlier build made, such as the simorg.exe of before Simorg CLI
    # was an application of its own, which went on into every installer.
    foreach ($made in 'simorg-desktop.exe', 'THIRD-PARTY-NOTICES.txt') {
        $path = Join-Path $buildDir "bin\$made"
        if (-not (Test-Path $path)) { Die "the build left no bin\$made" }
        Copy-Item $path $stageDir -Force
    }

    # --- Qt, beside the binaries ---------------------------------------------
    #
    # Run from the *host* kit even for the ARM64 build: windeployqt is a program
    # that has to run on this machine, and the one in the ARM64 kit is an ARM64
    # binary. `--qtpaths` is how it is told which installation to copy from.
    $windeployqt = Join-Path $hostKit.Path 'bin\windeployqt.exe'
    if (-not (Test-Path $windeployqt)) { Die "windeployqt.exe not found in $($hostKit.Path)" }

    $deployArgs = @(
        "--$($BuildType.ToLowerInvariant())",
        '--compiler-runtime',
        '--no-opengl-sw',
        '--no-system-d3d-compiler',
        '--qmldir', (Join-Path $SourceDir 'src\app\qml')
    )
    if ($Arch -eq 'arm64') {
        # The ARM64 kit's own qtpaths.exe is, like its windeployqt, an ARM64
        # binary that cannot run here. host-qtpaths.bat is the kit's answer:
        # the x64 qtpaths reading the ARM64 kit's target_qt.conf, so what it
        # reports is the ARM64 installation. The .exe is the last resort, for a
        # kit that has no wrapper.
        $qtpaths = @('host-qtpaths.bat', 'host-qtpaths6.bat', 'qtpaths.bat', 'qtpaths.exe', 'qtpaths6.exe') |
            ForEach-Object { Join-Path $kit.Path "bin\$_" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($qtpaths) { $deployArgs += @('--qtpaths', $qtpaths) }
        else { Write-Warn "no qtpaths in the arm64 kit; windeployqt may copy x64 libraries" }
    }

    & $windeployqt @deployArgs (Join-Path $stageDir 'simorg-desktop.exe') | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "windeployqt failed for simorg-desktop.exe" }
    Write-Ok "Qt libraries, plugins and QML modules"

    Copy-VisualCppRuntime -Destination $stageDir -Arch $(if ($Arch -eq 'arm64') { 'arm64' } else { 'x64' })

    # --- Workbench and Brain can be drawn -------------------------------------
    #
    # They are drawn in Qt WebEngine, and a build without it still starts, still
    # carries the WebEngine DLLs (windeployqt copies them for the QML that names
    # them) and shows a spinner where the surfaces should be. So before anything
    # is packed: the executable must import Qt WebEngine, which only a build
    # with it does -- read, for either processor -- and, on the processor it is
    # built for, must start Chromium, load a page and run its script.
    $desktopExe = Join-Path $stageDir 'simorg-desktop.exe'
    $imports = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($desktopExe))
    if ($imports.IndexOf('Qt6WebEngineQuick') -lt 0) {
        Die "simorg-desktop.exe was built without Qt WebEngine, so it cannot draw a Workbench or a Brain"
    }
    $hostIsArm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
    if (($Arch -eq 'x64' -and -not $hostIsArm) -or ($Arch -eq 'arm64' -and $hostIsArm)) {
        $check = Start-Process -FilePath $desktopExe -ArgumentList '--check-web-engine' -PassThru
        if (-not $check.WaitForExit(90000)) {
            $check.Kill()
            Die "simorg-desktop.exe --check-web-engine did not finish in 90 seconds"
        }
        if ($check.ExitCode -ne 0) {
            Die "simorg-desktop.exe --check-web-engine failed (exit $($check.ExitCode)): Chromium did not draw a page"
        }
        Write-Ok "Qt WebEngine: linked, and it draws a page"
    } else {
        Write-Ok "Qt WebEngine: linked (not run: this is a $Arch build on a $(if ($hostIsArm) { 'arm64' } else { 'x64' }) machine)"
    }

    # --- The archive ----------------------------------------------------------
    $version = Get-ArchiveVersion
    $name = "simorg-$version-windows-$Arch"
    $folder = Join-Path $buildDir $name
    # Every earlier bundle, not just this version's: build-driver.sh packs the
    # first simorg-*-windows-<arch> folder it finds here, and after a version
    # bump that would be the old one.
    Get-ChildItem -LiteralPath $buildDir -Directory |
        Where-Object { $_.Name -like "simorg-*-windows-$Arch" } |
        Remove-Item -Recurse -Force
    Move-Item $stageDir $folder

    Write-BundleReadme -Folder $folder
    Write-Manifest -Folder $folder -Arch $Arch -QtVersion $kit.Version

    $archive = Join-Path $outDir "$name.zip"
    Compress-Archive -Path $folder -DestinationPath $archive -CompressionLevel Optimal -Force

    $hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $name.zip" | Set-Content (Join-Path $outDir 'SHA256SUMS') -Encoding ascii
    Copy-Item (Join-Path $folder 'MANIFEST.txt') $outDir -Force

    Write-BuildInfo -OutDir $outDir -Target "windows-$Arch" -Arch $Arch -QtVersion $kit.Version
    # And inside the folder the driver archive is packed from, as on macOS and
    # Linux: it is how a release tells a prod build from a dev one.
    Copy-Item (Join-Path $outDir 'BUILD-INFO.txt') $folder -Force

    Write-Ok "windows-$Arch -> build\dist\windows-$Arch\$name.zip"
}

function Get-ProjectVersion {
    # The release tag simorg.toml publishes, which CMakeLists.txt reads as the
    # version too. The equivalent sed is in scripts/build-targets.sh; the two have
    # to agree or the same commit produces differently named archives per platform.
    $text = Get-Content (Join-Path $SourceDir 'simorg.toml') -Raw
    if ($text -match '(?m)^tag = "(\d+\.\d+\.\d+)"') { return $matches[1] }
    return '0.0.0'
}

function Get-ArchiveVersion {
    # The version in the archive's name, which says -dev for a dev build so two
    # archives of one version are never mistaken for each other. BUILD-INFO.txt
    # carries the plain version the binary reports.
    $version = Get-ProjectVersion
    if ($Config -eq 'dev') { return "$version-dev" }
    return $version
}

function Write-BundleReadme {
    param([string] $Folder)
@"
Simorg for Windows
==================

Unzip anywhere and run. Nothing is installed and nothing has to be added to
this machine first -- Qt, its plugins, its QML modules and the Visual C++
runtime are all in this folder.

    simorg-desktop.exe          the desktop app

To work from a terminal instead, Simorg CLI is an application of its own, with
an install line on its page on simorg.tech.

To remove it, delete this folder.

MANIFEST.txt lists what is carried in here.
"@ | Set-Content (Join-Path $Folder 'README.txt') -Encoding utf8
}

function Write-Manifest {
    param([string] $Folder, [string] $Arch, [string] $QtVersion)

    $dlls = Get-ChildItem $Folder -Filter *.dll -File | Sort-Object Name
    $plugins = Get-ChildItem $Folder -Directory | Where-Object { $_.Name -ne 'qml' } | Sort-Object Name
    $qml = if (Test-Path (Join-Path $Folder 'qml')) {
        Get-ChildItem (Join-Path $Folder 'qml') -Directory | Sort-Object Name
    } else { @() }

@"
Simorg -- bundled Windows build

Architecture   $Arch
Built against  Qt $QtVersion
Contents       simorg-desktop.exe

BUNDLED LIBRARIES ($($dlls.Count))
  Nothing below has to be installed on the machine that runs this -- including
  the Visual C++ runtime, which is the one people forget.

$($dlls | ForEach-Object { "  $($_.Name)" } | Out-String)
QT PLUGIN DIRECTORIES
$($plugins | ForEach-Object { "  $($_.Name)\" } | Out-String)
QML MODULES
$($qml | ForEach-Object { "  $($_.Name)\" } | Out-String)
PROVIDED BY WINDOWS
  The system DLLs in System32 -- kernel32, user32, d3d11, and the rest. Every
  Windows 10 and 11 machine has them.
"@ | Set-Content (Join-Path $Folder 'MANIFEST.txt') -Encoding utf8
}

function Write-BuildInfo {
    param([string] $OutDir, [string] $Target, [string] $Arch, [string] $QtVersion)

    $commit = try { (& git -C $SourceDir rev-parse --short HEAD 2>$null) } catch { 'unknown' }
    if (-not $commit) { $commit = 'unknown' }
    $built = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + 'Z'

@"
Simorg -- $Target

  configuration   $Config ($BuildType)
  endpoints       $SimorgEnv
  architecture    $Arch
  contents        desktop app
  version         $(Get-ProjectVersion)
  qt              $QtVersion
  built           $built
  commit          $commit

The endpoint set is chosen at run time, not baked in: this build carries both
and picks with SIMORG_ENV, --env, or the build type. A dev build defaults to
localhost; a prod build defaults to the public estate.

Everything the application needs is inside the .zip, including the Visual C++
runtime. Unzip it and run simorg-desktop.exe.
"@ | Set-Content (Join-Path $OutDir 'BUILD-INFO.txt') -Encoding utf8
}

# -------------------------------------------------------------------- main ----
New-Item -ItemType Directory -Path $DistDir, $WorkDir -Force | Out-Null

foreach ($tool in @('cmake', 'ninja')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Muted "$tool is not on PATH yet; it comes with the Visual Studio C++ workload and is picked up below"
    }
}

if ($InstallQt) { Install-Qt -Root (Resolve-QtRoot) }

Write-Host ''
Write-Host "Simorg build" -ForegroundColor White -NoNewline
Write-Host "  $Config - $BuildType - $Jobs jobs" -ForegroundColor DarkGray

foreach ($arch in $Wanted) { Build-Target -Arch $arch }

Write-Step 'Done'
Get-ChildItem $DistDir -Directory | ForEach-Object {
    # An empty folder (another platform's build that stopped early) measures as
    # nothing at all, and reading .Sum off nothing is an error under StrictMode.
    $files = @(Get-ChildItem $_.FullName -Recurse -File)
    $size = if ($files.Count -gt 0) { ($files | Measure-Object Length -Sum).Sum } else { 0 }
    Write-Info ("{0}  {1:N0} MB" -f $_.Name, ($size / 1MB))
}
Write-Muted "artifacts in build\dist"
