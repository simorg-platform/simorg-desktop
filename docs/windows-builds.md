# Windows builds

One Intel machine produces both the x64 and the ARM64 build.

```powershell
.\scripts\build-windows.ps1 -Config dev
```

From an ordinary Command Prompt, or by double-clicking it in Explorer, use the
wrapper instead — same arguments:

```
scripts\build-windows.bat -Config dev
```

The wrapper exists for one reason: a freshly installed Windows refuses to run an
unsigned `.ps1` at all, and the alternative to `-ExecutionPolicy Bypass` is
telling everybody to change a machine-wide security setting before they can build
anything.

## Contents

- [What you need installed](#what-you-need-installed)
- [Getting Qt](#getting-qt)
- [Building](#building)
- [What comes out](#what-comes-out)
- [How ARM64 is built on an Intel machine](#how-arm64-is-built-on-an-intel-machine)
- [The Visual C++ runtime](#the-visual-c-runtime)
- [The icon, the name and the installer](#the-icon-the-name-and-the-installer)
- [When something goes wrong](#when-something-goes-wrong)

## What you need installed

| | Where it comes from |
|---|---|
| **Visual Studio 2022**, "Desktop development with C++" workload | [visualstudio.microsoft.com](https://visualstudio.microsoft.com/downloads/) — the free Community edition is enough |
| **MSVC v143 ARM64 build tools** (for the `arm64` target only) | The same installer, under *Individual components* |
| **CMake** and **Ninja** | Included in that workload; nothing to do |
| **Qt 6** | Either already installed, or fetched by `-InstallQt` — see below |

You do **not** need a developer command prompt. The script finds Visual Studio
with `vswhere`, runs `VsDevCmd.bat` in a child `cmd` for the architecture being
built and imports the difference into its own environment — which is what a
developer prompt is.

PowerShell 5.1, the one Windows ships with, is enough. PowerShell 7 is used
where it is installed, simply because it makes the `.zip` faster.

## Getting Qt

If Qt is already installed, the script finds it. It looks in
`$env:SIMORG_QT_ROOT`, then `C:\Qt`, for the newest `6.x` with a kit named
`msvc2022_64` (or `msvc2022_arm64_cross_compiled` for the ARM64 target);
`msvc2019_*` is accepted too, so an older installation does not have to be redone.

```powershell
$env:SIMORG_QT_ROOT = 'D:\Qt'         # if it is somewhere else
.\scripts\build-windows.ps1 -QtVersion 6.11.2   # if there are several
```

Otherwise, let the script fetch it:

```powershell
.\scripts\build-windows.ps1 -InstallQt
```

That runs Qt's own online installer, which asks you to sign in with your Qt
account, to put Qt 6.11.2 into `C:\Qt` — the pinned one every platform's release
uses — with both kits (`msvc2022_64` and `msvc2022_arm64_cross_compiled`) and
only the add-ons this application links, Qt WebEngine among them. Listing them
rather than taking all of Qt is the difference of gigabytes. aqtinstall cannot
install Qt 6.11 for Windows
([aqtinstall issue 959](https://github.com/miurahr/aqtinstall/issues/959)).

## Building

```powershell
.\scripts\build-windows.ps1                    # both architectures
.\scripts\build-windows.ps1 x64                # just one
.\scripts\build-windows.ps1 -Config dev        # point the build at localhost
.\scripts\build-windows.ps1 -List              # what each target produces
.\scripts\build-windows.ps1 -Help
```

`-Config` means the same thing it does on the Unix script: `dev` is a Debug
build defaulting to `localhost:10000`, `prod` is optimised and defaults to the
public estate. The endpoint set is never baked in — every build carries both and
picks at startup from `SIMORG_ENV`, `--env`, or the build type.

Run it from PowerShell, Command Prompt or Git Bash, which can all reach
`powershell.exe`, MSVC and the Windows Qt. **WSL cannot**: it is a Linux
machine, with no MSVC and no Windows Qt.

## What comes out

```
build\dist\windows-x64\
├── simorg-0.1.0-windows-x64.zip
├── BUILD-INFO.txt
├── MANIFEST.txt
└── SHA256SUMS
```

Inside the `.zip`, one folder:

```
simorg-0.1.0-windows-x64\
├── simorg-desktop.exe
├── Qt6Core.dll, Qt6Gui.dll, Qt6Quick.dll, …
├── msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll
├── platforms\, styles\, tls\, imageformats\, iconengines\, …
├── qml\
├── MANIFEST.txt
└── README.txt
```

Unzip it and run it. Nothing is installed, nothing is registered, and nothing
has to be added to the machine first — which is the same promise the Linux and
macOS archives make, and the reason the Visual C++ runtime is in that list.

The build for the machine's own processor is run before it is called finished,
as below. The ARM64 build cannot be run on an Intel machine, so it is not run,
and the script says so rather than implying it was checked.

Every build with a window is also checked to draw an agent's Workbench and Brain,
before anything is packed. The script configures with
`-DSIMORG_BUILD_WEBENGINE=ON`, so a missing Qt WebEngine stops the configure;
then `simorg-desktop.exe` has to import `Qt6WebEngineQuick`, read from the file
for either processor; and on a machine of its own processor it has to pass
`simorg-desktop.exe --check-web-engine` — start Chromium, load a page and run
its script — within 90 seconds. A build folder configured before Qt WebEngine
was installed keeps that answer in CMake's cache, and without these checks would
produce a program whose Workbench and Brain never draw.

## How ARM64 is built on an Intel machine

Cross-compiled, not emulated. MSVC has shipped an ARM64 backend that runs on x64
for years, and Qt publishes a matching ARM64 build. What the arrangement needs is
for CMake to be told that the *tools* come from the x64 Qt while everything
linked comes from the ARM64 one — `moc`, `rcc` and `qmlcachegen` are programs
that have to run on this machine, and the ARM64 kit's copies are ARM64 binaries.

That is `QT_HOST_PATH`, and it is the only unusual line in the script:

```powershell
cmake -G Ninja `
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=ARM64 `
    -DCMAKE_PREFIX_PATH=C:\Qt\6.11.2\msvc2022_arm64_cross_compiled `
    -DQT_HOST_PATH=C:\Qt\6.11.2\msvc2022_64
```

from a `VsDevCmd.bat -arch=arm64 -host_arch=amd64` environment. The same applies
to `windeployqt`: it is run from the *host* kit with `--qtpaths` pointing at the
ARM64 one, because it too is a program that has to run here.

So an ARM64 build needs **both** kits installed. `-InstallQt` fetches both when
the ARM64 target is among the ones asked for.

One consequence worth knowing about: building both architectures in one run
means `VsDevCmd.bat` has to be set up twice, and it refuses to run a second time
in an environment it has already initialised. The script therefore snapshots the
environment before it touches anything and restores that snapshot before each
target. Without it the second architecture silently compiles with the first
one's `INCLUDE` and `LIB` and fails at link with machine-type errors that name no
cause.

## The Visual C++ runtime

`windeployqt` brings Qt. Nothing brings the compiler's own runtime, and a machine
without the redistributable installed answers a double-click with a dialog about
`VCRUNTIME140.dll`.

So `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll` are copied from
`%VCToolsRedistDir%` beside the executables. This is *app-local deployment*,
which is exactly what Microsoft publishes that directory for, and it is the only
way to keep the promise that nothing has to be installed on the other end.

If `VCToolsRedistDir` is not set — which happens with some partial Visual Studio
installations — the script warns rather than failing, and says that the target
will need the redistributable. It is worth fixing when it happens.

## The icon, the name and the installer

The program is built with a resource file
([`packaging/windows/program.rc.in`](../packaging/windows/program.rc.in), through
[`cmake/SimorgWindowsResources.cmake`](../cmake/SimorgWindowsResources.cmake)):
the application icon, `packaging/windows/simorg.ico`, and a version resource. So
Explorer and the Start menu show the icon, every window has it without the app
asking, and Task Manager lists `simorg-desktop.exe` as **Simorg**. The icon is
drawn by `scripts/make-icons.sh`, never by hand; see
[packaging.md](packaging.md#application-icons).

The `.msi` Simorg publishes is made from a build like this one with
[`packaging/windows/simorg-desktop.wxs`](../packaging/windows/simorg-desktop.wxs):
a wizard — Welcome, Ready to install, and a last page with **Open Simorg now**
ticked — built with WiX's UI extension. Opened by Simorg's own update (`/qb!`)
or unpacked by the machine service (`/a`) it shows no page and opens nothing.
[packaging.md](packaging.md#the-installer-a-person-opens) has the pages and why.

## When something goes wrong

**"no Visual Studio installation with the C++ tools was found."** The Desktop
development with C++ workload is not installed. Open the Visual Studio Installer
and add it.

**"VsDevCmd.bat failed for target arm64."** The ARM64 cross tools are a separate
component. Visual Studio Installer → Modify → Individual components → *MSVC
v143 – VS 2022 C++ ARM64 build tools*.

**"no Qt kit for arm64 under C:\Qt."** Either install one with
`.\scripts\build-windows.ps1 -InstallQt arm64`, or point `SIMORG_QT_ROOT` at
where yours is. Remember that an ARM64 build also needs the x64 kit.

**"the arm64 build needs an x64 Qt as well."** See above — the host tools come
from it.

**The script will not start at all.** Windows blocks unsigned scripts by
default. Use `scripts\build-windows.bat`, which passes `-ExecutionPolicy Bypass`
for this one invocation and changes nothing about the machine.

**Everything else.** The build itself is the same CMake project as on every other
platform; see [packaging.md](packaging.md) for what the archives contain and
[../README.md](../README.md#building-from-source) for the project's own build
options.
