# Packaging

How a Simorg build becomes something you can hand to somebody.

The rule this whole directory of scripts exists to keep: **a build must run on
the machine it is given to without that machine installing anything.** Not Qt,
not a runtime, not one library. Unpack it and run it.

That is not what Qt gives you for free. An archive holding the program and
nothing else, handed to another machine, answers with

```
./simorg-desktop: error while loading shared libraries: libQt6WebSockets.so.6:
cannot open shared object file: No such file or directory
```

and the same is true on macOS and Windows under a different message.

## Contents

- [What each target produces](#what-each-target-produces)
- [The line between the bundle and the machine](#the-line-between-the-bundle-and-the-machine)
- [Linux](#linux)
  - [Which systems each archive reaches](#which-systems-each-archive-reaches)
  - [The oldest system it runs on](#the-oldest-system-it-runs-on)
  - [What the bundler does](#what-the-bundler-does)
  - [How the binaries find their libraries](#how-the-binaries-find-their-libraries)
  - [The check that runs before the artifacts are allowed out](#the-check-that-runs-before-the-artifacts-are-allowed-out)
  - [A computer that cannot run it says why](#a-computer-that-cannot-run-it-says-why)
- [macOS](#macos)
  - [A dev build skips all of it](#a-dev-build-skips-all-of-it)
  - [Two things macdeployqt does not do](#two-things-macdeployqt-does-not-do)
  - [The disk image a person opens](#the-disk-image-a-person-opens)
  - [Signed as Simorg Oy, and notarized](#signed-as-simorg-oy-and-notarized)
- [Windows](#windows)
  - [The installer a person opens](#the-installer-a-person-opens)
  - [Signed as Simorg Oy](#signed-as-simorg-oy)
- [Application icons](#application-icons)
  - [One drawing, a geometry per platform](#one-drawing-a-geometry-per-platform)
  - [Where each system reads it](#where-each-system-reads-it)
  - [Drawing them again](#drawing-them-again)
- [Qt 6.4 is the declared floor](#qt-64-is-the-declared-floor)
- [Third-party notices](#third-party-notices)
- [When something is missing](#when-something-is-missing)

## What each target produces

Everything lands in `build/dist/<target>/`, one directory per target, so which
build is for which machine is a question you answer by reading a directory name.

| Target | Made by | Archive |
|---|---|---|
| `macos` | `scripts/build-targets.sh macos` | `simorg-<version>-macos-<arch>.zip` |
| `linux-x64` | `scripts/build-targets.sh linux-x64` | `simorg-<version>-linux-amd64.tar.gz` |
| `linux-arm64` | `scripts/build-targets.sh linux-arm64` | `simorg-<version>-linux-arm64.tar.gz` |
| `windows-x64` | `scripts\build-windows.ps1 x64` | `simorg-<version>-windows-x64.zip` |
| `windows-arm64` | `scripts\build-windows.ps1 arm64` | `simorg-<version>-windows-arm64.zip` |

Beside each archive:

| File | What it is |
|---|---|
| `BUILD-INFO.txt` | Which configuration, which commit, which architecture, which Qt. Nobody remembers three weeks later which of two archives was the Debug one. |
| `MANIFEST.txt` | Every library carried inside, and the short list the target is still expected to have. |
| `SHA256SUMS` | The archive's checksum. |

A `dev` build says so in the file name — `simorg-0.1.0-dev-linux-arm64.tar.gz` —
because two archives called the same thing, one pointed at `localhost` and one at
the public estate, is a mistake that costs an afternoon.

The installers Simorg publishes — a `.dmg`, an `.AppImage` and an `.msi` — are
made from these builds by Simorg's release tooling, which is not part of this
repository. What is Simorg Desktop's own in them is here: the WiX source in
`packaging/windows/`, the disk image's picture in `packaging/macos/`, and the
desktop entry and icons under `packaging/linux/` and `resources/branding/`.

## The line between the bundle and the machine

A bundle cannot carry *everything*, and the interesting question is where the
line is. It is written down once, in
[`scripts/linux-host-libraries.txt`](../scripts/linux-host-libraries.txt), read
by both the bundler and the verifier so the two can never come to disagree.

A library belongs to the host only when one of two things is true:

1. **The host loads its own copy into this process anyway.** Then two copies
   under one soname is the problem, not a missing one, and the copy that has to
   win is the host's. The clearest case is `libstdc++`: Mesa's drivers are
   loaded into this process and link it, so a bundled copy older than the one
   the driver needs breaks the driver.
2. **It is the kernel-, driver- or policy-facing side of something.** `libGL`
   dispatches into a vendor library compiled against this kernel's DRM. A
   bundled one would dispatch into nothing.

That comes to about thirty sonames: the loader and the C library family, the C++
runtime, the graphics stack, the X11 and Wayland client libraries, the sound
servers, and `libsystemd`/`libudev`/`libselinux`. Every one of them is present on
any Linux machine with a graphical session — with one exception, below.

Everything else is carried — including several libraries other projects leave
out. ICU, PCRE2, OpenSSL, glib, fontconfig, FreeType, HarfBuzz, D-Bus, zlib and
libpng are all bundled here, because nothing on a target loads its own copy of
those into a Qt process, and each one is a package somebody would otherwise have
had to install before the application would start.

**xcb is split down the middle.** `libxcb` and the eight extensions Mesa links —
`dri2`, `dri3`, `glx`, `present`, `randr`, `shm`, `sync` and `xfixes`, measured
from Mesa's GL, EGL, GBM, DRI and Vulkan libraries on Ubuntu 22.04 and 24.04
and Debian 12 and 13 — are the host's. The rest of the family is carried: the
xcb-util libraries (`cursor`, `icccm`, `image`, `keysyms`, `render-util`, `util`)
and the extensions only a toolkit uses (`render`, `shape`, `xkb`). No driver
loads those, so they are Qt's alone, and a desktop does not bring them: Ubuntu
22.04 does not install `libxcb-cursor0`, and without it Qt 6.5 and later refuse
to open a window on X11 — the session Ubuntu 22.04 gives an NVIDIA card, and the
one WSL gives.

**ALSA is the host's, with a fallback.** Only `libQt6WebEngineCore` links
`libasound`, and it links it for sound — Qt's Chromium plays through ALSA and
nothing else — which reaches PulseAudio and PipeWire through plugins the sound
server installs, built against the machine's own `libasound`, in a directory
compiled into it. A copy from the Debian build image looks in
`/usr/lib/x86_64-linux-gnu/alsa-lib`; on Fedora that directory does not exist,
the PipeWire plugin is not found and every page plays nothing (measured on
Fedora 42). So the machine's copy has to win. But a machine without one — WSL, a
server reached over `ssh -X`, a minimal install — could not start the app at
all. A line in the list can therefore say `fallback`: the bundler also carries
the library, in `lib/fallback/<soname>/`, and the launcher puts that directory
in front of the loader (`LD_LIBRARY_PATH`) only when `ldconfig -p` knows no
copy for this architecture. Where the machine has one, nothing changes.

## Linux

```bash
./scripts/build-targets.sh linux-arm64
./scripts/build-targets.sh linux-x64
```

A prod build always goes through Docker — `docker/Dockerfile.linux-build`, which
installs the pinned Qt 6.11.2 with Qt WebEngine from Qt's own servers (aqtinstall,
pinned too) and exports an archive without a container ever starting. Only a dev
build on a Linux host of the same architecture is built natively, against
whatever Qt that host has.

Build each architecture on its own kind of processor where you can. Docker
builds the other one under QEMU, and under QEMU GCC crashes compiling this
project for x86-64 on an Apple silicon Mac. Simorg's own repository has a
`scripts/native-docker.sh` that `build-targets.sh` uses when it is there (or
when `SIMORG_NATIVE_DOCKER` points at it): on an Apple silicon Mac it builds
x86-64 in a Colima VM of its own that runs x86-64 code through Rosetta. Without
it, the active Docker builds both platforms.

### Which systems each archive reaches

A program asks for the C library by version, and a system whose glibc is older
than the newest version any of its files names refuses it before a line runs —
silently, when it was opened from a file manager. The C library is the one
library a program cannot bring with it. So each architecture is built on the
oldest system Qt's own build for it allows, and then made to reach further:

| Archive | Built on | Runs on | Reaches |
|---|---|---|---|
| `linux-amd64` | `debian:12-slim`, pinned by digest | glibc 2.35, GLIBCXX 3.4.30 | Ubuntu 22.04, Debian 12, Fedora 36 and everything later — **not** RHEL 9 (2.34) |
| `linux-arm64` | `ubuntu:24.04`, pinned by digest | glibc 2.35, GLIBCXX 3.4.30 | Ubuntu 22.04, Debian 12, Raspberry Pi OS bookworm (64-bit), Fedora 36 and everything later |

The two are built on different systems because Qt's two builds are: the x86-64
one is made on Red Hat Enterprise Linux 9 and needs glibc 2.34, the arm64 one on
Ubuntu 24.04, where its WebEngine names glibc 2.38 and takes four libraries —
snappy, WebP, minizip and Little CMS — from the system, which the bundle then
carries.

Left there, the arm64 archive would need glibc 2.38 — Ubuntu 24.04 and Debian 13
on — and would do nothing on the Raspberry Pi OS most Pis run (bookworm, glibc
2.36). Measured, the whole bundle asks for glibc 2.37 and later for three
things only — the C23 number parsers (`__isoc23_strtol` and its kin),
`strlcpy`/`strlcat`, and a second version of `fmod` — and GCC 13's C++ runtime
for one marker nothing calls, `std::ios_base_library_init`. So the bundler's last
step, `--glibc-floor` (see [its section](#the-oldest-system-it-runs-on)),
rewrites those references with
[polyfill-glibc](https://github.com/corsix/polyfill-glibc), and both
architectures run on Ubuntu 22.04's glibc 2.35 and GCC 12's C++ runtime.

The floor is `GLIBC_FLOOR` and `GLIBCXX_FLOOR` in
[`docker/Dockerfile.linux-build`](../docker/Dockerfile.linux-build), and its
first verify stage runs on `FLOOR_IMAGE`, Ubuntu 22.04 itself, so no archive
leaves that does not start there. `--base-image` overrides where it is
compiled; the floor stays where it is.

### The oldest system it runs on

`scripts/bundle-linux.sh --glibc-floor 2.35 --glibcxx-floor 3.4.30` runs after
the RUNPATH rewrite and the strip, over every ELF file that names a newer glibc:

| What the file asks for | What it gets instead | What changes |
|---|---|---|
| `__isoc23_strtol`, `__isoc23_sscanf` and their kin (glibc 2.38) | the classic `strtol`, `__isoc99_sscanf`, … at the version this libc gives them | a string starting `0b` is read as 0 rather than as binary |
| `strlcpy`, `strlcat` (2.38) | a copy of their code inside the file | nothing |
| `fmod@GLIBC_2.38`, `fmodf@GLIBC_2.38` | their first version | nothing |
| `std::ios_base_library_init` (GLIBCXX 3.4.32) | an unversioned one, from `lib/libsimorg-cxx-compat.so` | nothing |

The last one needs its own library. GCC 13 names the marker in every file that
includes `<iostream>` purely to demand its own C++ runtime, which sets
`std::cout` up by itself; GCC 12's does not, and Qt Positioning writes to
`std::cout`. The compatibility library, compiled by the bundler, exports the
marker and constructs `std::ios_base::Init` once, which is what sets `std::cout`
up on GCC 12's runtime and is one more reference to an object already there on
a newer one.

Nothing is compiled differently, so a system at or above the floor runs exactly
the code it would run without the step. The step refuses to finish when any
file still asks for more than the floor, and the verify stage then proves it on
the floor system.

### What the bundler does

[`scripts/bundle-linux.sh`](../scripts/bundle-linux.sh) turns a staged install
tree into a self-contained directory. Qt has no supported way to do this —
`qt_generate_deploy_qml_app_script` covers macOS and Windows and is a no-op on
Linux — so it walks the graph itself.

```
simorg-0.1.0-linux-arm64/
├── simorg-desktop       launcher: clears stray Qt environment variables, execs bin/
├── bin/
│   ├── simorg-desktop
│   └── qt.conf          where plugins/, qml/ and the WebEngine parts are
├── lib/                 Qt and everything underneath it, NSS's modules too
│   └── fallback/        libasound, loaded only on a system without its own
├── libexec/
│   ├── QtWebEngineProcess   the process every web page runs in
│   └── qt.conf          the same answers, for it
├── plugins/             platforms, tls, imageformats, iconengines, wayland, …
├── qml/                 QtQuick, QtQml and their submodules
├── resources/           Chromium's .pak files, ICU's data, V8's snapshot
├── translations/        qtwebengine_locales, Chromium's own strings
├── share/               the .desktop entry, the icon, the licence
├── MANIFEST.txt
└── README.txt
```

Three separate problems, three separate answers:

**Plugins are chosen by category**, not discovered. Every Qt plugin is loaded by
name at run time, so none of them is reachable from the dependency graph — a
bundle that walked dependencies alone would start and then have no way to draw a
window, open a TLS connection or decode a PNG. The `tls` category in particular:
without `libqopensslbackend.so` every HTTPS request and the Hub's own `wss://`
socket fail with *TLS initialization failed*, on a machine that plainly has
OpenSSL installed, which is what makes it such a puzzling one.

**QML modules come from `qmlimportscanner`**, Qt's own tool, so the list stays
right as the interface grows — then widened to the whole top-level directory of
each hit. That widening is deliberate: `QtQuick.Controls` resolves its *style* at
run time, so `QtQuick/Controls/Basic` is never an import anybody wrote and is
exactly what the application will not start without.

**Libraries come from `DT_NEEDED`**, not from `ldd`. `ldd` prints the whole
transitive closure, so walking it means walking *through* the host libraries
too: `libdbus-1` is bundled and links `libsystemd`, which is not, and following
`ldd` from there would drag lz4, lzma, zstd, gcrypt and libcap into the bundle
for the sole benefit of a library the host is providing anyway.

Two sets of libraries are named explicitly rather than discovered, and they have
to be. Qt 6 opens `libssl` and `libcrypto` by soname at run time rather than
linking them. And NSS, which Chromium keeps its keys and certificates in, opens
its software token (`libsoftokn3`, with `libfreeblpriv3` behind it) and its root
certificates (`libnssckbi`) by file name from the directory `libnss3` was loaded
from — without the token Chromium cannot start NSS and no page loads over HTTPS.
No walk of any kind finds either set.

**Qt WebEngine is three things found by path**, not linked: `QtWebEngineProcess`,
the process every page runs in; `resources/`; and `translations/qtwebengine_locales`.
They are copied beside the libraries and both `qt.conf` files point at them. The
launcher clears `QTWEBENGINEPROCESS_PATH`, `QTWEBENGINE_RESOURCES_PATH` and
`QTWEBENGINE_LOCALES_PATH`, which would otherwise send it to another Qt's.

**One plugin is left out on purpose.** Qt's GTK 3 platform theme links the whole
of GTK, which cannot be carried — GTK loads the desktop's own themes and modules
into the process — and cannot be asked for, or a machine without GTK would not
start. Qt uses the desktop portal's theme or its own instead.

**Chromium's sandbox needs user namespaces**, and Ubuntu 23.10 and later refuse
them to a program AppArmor has no profile for; so do containers and some
hardened kernels. At start-up the app tries what the sandbox does first, in a
child process it throws away, and where that fails it starts the web engine
without the sandbox and says why in its log — otherwise every agent surface
would stay blank with nothing on screen to say why. The pages still run in their
own processes; what is lost is the sandbox around them. A package that installs
an AppArmor profile for the renderer would keep it; an archive a person unpacks
cannot.

### How the binaries find their libraries

Two mechanisms, both relative, so the directory can be unpacked anywhere.

`patchelf` rewrites every file's `DT_RUNPATH` to `$ORIGIN` plus the hops back to
`lib/`. This is applied to every file rather than only to the executable,
because `DT_RUNPATH` — unlike the older `DT_RPATH` — is not inherited by
dependencies: each library resolves its own.

`bin/qt.conf` tells Qt where `plugins/`, `qml/`, `libexec/`, `resources/` and
`translations/` are, relative to the executable. That is also why this is a
directory rather than a tree to unpack over `/usr`: Qt reads `qt.conf` from
beside the executable, and a `qt.conf` in `/usr/bin` would answer for every Qt
application on the machine, not only ours.

The launcher at the top level is not necessary — `bin/simorg-desktop` runs
perfectly well on its own. It exists to clear `QT_PLUGIN_PATH`,
`QML_IMPORT_PATH`, `QML2_IMPORT_PATH` and `QT_QPA_PLATFORM_PLUGIN_PATH`, which on
a developer's machine point into a *different* Qt and produce a crash inside a
library nobody in this bundle shipped — and to offer `lib/fallback/` to a
machine that has no `libasound` of its own. `DT_RUNPATH` cannot do that: it is
searched before the machine's libraries, so it can only ever make the bundle's
copy win. Started from `bin/` directly on such a machine, the app fails to load;
the AppImage, the menu entry and the login item all go through the launcher.

### The check that runs before the artifacts are allowed out

This is the part that matters, and it is the reason the Linux claim can be made
at all. [`scripts/verify-linux-bundle.sh`](../scripts/verify-linux-bundle.sh)
runs in a second container, on the floor system — Ubuntu 22.04, the oldest the
archive claims to run on — with **no Qt and no development packages** in it:
only the libraries `scripts/linux-host-libraries.txt` says a target provides, a
virtual display and fonts. That makes it the barest machine with a graphical
session, the way WSL's Ubuntu is: Mesa and the X11 and Wayland client libraries,
no sound library and none of the xcb-util family, and the step that builds the
image refuses to go on if a package pulled one of those in. It runs as an
ordinary user, and then again in a third container, on Ubuntu 24.04, which adds
the sound library every desktop has.

| # | Check | What it catches |
|---|---|---|
| 1 | No file has an unresolved `NEEDED` | A library that should have been bundled and was not |
| 2 | No file resolves a Qt library outside the bundle | A bundle that quietly half-resolves against a system Qt |
| 3 | `simorg-desktop update desktop --json` answers with no display | Core, Network and the whole loader path, the way the machine service runs the app while it is closed |
| 4 | `simorg-desktop --version` runs under the offscreen platform plugin, then on X11 under `xvfb-run`, and the loader's trace shows which `libasound` it took | Gui, Widgets and the platform plugins; the xcb-util libraries X11 needs; the launcher taking the carried `libasound` on the floor, which has none, and the system's on Ubuntu 24.04, which does |
| 5 | The app starts for real and loads its interface | A missing QML module — which is a run-time warning and an empty window, not a link error, so nothing above would see it |
| 6 | `simorg-desktop --check-web-engine` draws its built-in page and runs its script, then loads `https://simorg.tech/robots.txt`, under `xvfb-run` | Everything the Workbench and the Brain need and no link error reveals: `QtWebEngineProcess`, `resources/`, a library only the renderer opens, NSS and its certificates, a sandbox that kills every renderer |

The `export` stage of the Dockerfile pulls from the Ubuntu check, which pulls
from the first, which pulls from the build — so there is no way to produce
artifacts that skipped either.

Running the same script on a developer's machine — which the native build path
does — is a weaker check and says so: this machine has Qt installed, so a library
the bundle forgot can still be found. What it does catch is a file missing
outright.

### A computer that cannot run it says why

The AppImage Simorg publishes checks the computer before it starts the app: the
architecture, and the newest glibc and C++ runtime any file inside names,
measured when the AppImage was made. A computer that falls short gets the reason
and what would make it run — a 32-bit Raspberry Pi OS, a glibc older than 2.35,
a musl system — in the terminal, or in a dialog (zenity, kdialog, notify-send or
xmessage, whichever is there) when it was opened from a file manager.

`SIMORG_PREFLIGHT=1` runs the check alone, which is how the Linux install line
(`curl -fsSL https://install.simorg.tech/app | sh -s -- @simorg/betsalel/simorg-desktop`)
asks before it puts anything in place.

## macOS

```bash
./scripts/build-targets.sh --config dev macos
```

Apple silicon first, Intel as the fallback, and a universal binary when the
toolchain can produce one — which needs a universal Qt, and Homebrew ships one
architecture per bottle. The script checks whether the installed `QtCore`
actually carries both slices and says which build you got, rather than failing at
link time with an error about a missing slice that reads like a compiler bug.

### A dev build skips all of it

`--config dev` builds the bundle **without Qt inside it**, and that is the
difference between a five-second macOS build and a five-minute one.

| | |
|---|---|
| `cmake --install` with deployment | **290 s**, 343 MB — 204 MB of it `QtWebEngineCore` |
| the same install without it | **0.2 s**, 31 MB |

Measured, not estimated. The cost is not compilation: it is copying Chromium and
then signing it, which is why it is I/O bound and why no amount of parallelism
helps. An undeployed bundle links the Qt that built it at the absolute paths
Homebrew keeps it at, so it runs on that Mac and starts on no other — which is
exactly what a dev build is for, and `build/dist/macos/README.txt` says so rather
than leaving somebody to find out by sending it to a colleague.

`--portable` turns the deployment back on for a dev build; `--config prod` always
deploys. Everything below describes that path.

The deployment runs during `cmake --install`, not during the build.
`qt_generate_deploy_qml_app_script` writes a script and hands it to
`install(SCRIPT)`, so the frameworks are copied into the bundle when somebody
installs it and at no other moment. A `Simorg.app` copied straight out of
`build/bin/` has no `Contents/Frameworks` at all: it runs on the Mac that
compiled it, because Homebrew's Qt is still at the absolute path baked into it,
and dies everywhere else with
`Library not loaded: /opt/homebrew/opt/qt/lib/QtCore.framework`.

### Two things macdeployqt does not do

[`scripts/bundle-macos.sh`](../scripts/bundle-macos.sh) finishes the job.

**It does not descend into a framework that contains an executable of its own**,
and Qt ships exactly one that does: `QtWebEngineCore` carries
`QtWebEngineProcess.app`, the separate process Chromium renders in. Homebrew
builds that helper with absolute install names, so a deployed bundle points at
`/opt/homebrew/...` from seven directories down. On any other Mac the app opens,
the agent Workbench stays blank, and nothing anywhere says why — the main process
is fine, it is the child that cannot start. So every Mach-O file in the bundle is
walked and any absolute dependency outside `/usr/lib` and `/System/Library` is
pointed back at the copy in `Contents/Frameworks`, bringing it in first if it is
not already there. `@loader_path` rather than `@executable_path`, because it
resolves against the file doing the loading and so is right for the app binary,
for a framework loaded by it, and for a helper executable seven directories down
alike.

There is no clean-machine container to prove this on, so it is proved by reading:
any dependency that is neither inside the bundle nor part of the operating system
fails the build. There is also a real `CMAKE_INSTALL_RPATH` subtlety recorded in
[`CMakeLists.txt`](../CMakeLists.txt) — `CMAKE_INSTALL_RPATH_USE_LINK_PATH` has
to stay on, or macdeployqt cannot resolve the `@rpath` install names Homebrew's
Qt uses and silently deploys nothing.

A build made here is signed ad hoc, so macOS asks once, under Privacy &
Security, before it opens it.

### The disk image a person opens

Opened, the `.dmg` Simorg publishes shows one window: Simorg on the left, the
Applications folder on the right, and behind them a picture with **Drag and
drop** between the two and an arrow from one to the other — the way Docker
Desktop's disk image says it.

The window is written into the image's `.DS_Store` by
[`dmgbuild`](https://dmgbuild.readthedocs.io), from a layout every Simorg
application's disk image shares, so no Finder is scripted: it needs no logged-in
session and asks for no permission. The picture,
`packaging/macos/dmg-background.png` and its `@2x` for Retina screens, is drawn
by the same script as the icons, to that layout's geometry.

- **The window's size is Finder's whole window**, title bar included, and the
  picture starts under the title bar. So the picture is as big as the window and
  its bottom strip is never seen, rather than smaller with a band of white below.
- **Finder's path and status bars** belong to the person (View menu), and when
  they are on, Finder shows them on this window too and they take 56 points off
  the bottom. Everything that matters — the icons, their labels, the words and
  the arrow — sits above the bottom 90 points.
- **Dark Mode** leaves the picture as it is and Finder draws the labels dark on
  it, so they read. Checked by opening the image on macOS 26.4 in Dark Mode with
  both bars on.
- **`BUILD-INFO.txt` stays at the top of the image**, where the updater reads it,
  with the hidden flag set, so the window shows only the two things to drag.

### Signed as Simorg Oy, and notarized

A release image is signed with Simorg Oy's Developer ID, and so is everything in
it: every program and library (the Qt frameworks and plug-ins, about 150
pieces), then each nested bundle, then `Simorg.app`, from the inside out, with
the hardened runtime and Apple's timestamp. Qt's browser helper,
`QtWebEngineProcess.app`, is signed with the entitlements Qt ships beside it
(`Contents/Resources/QtWebEngineProcess.entitlements`: JIT and unsigned
executable memory, which Chromium needs). The image is then signed, opened again
to check the app inside it, and sent to Apple's notary service, and Apple's
ticket is stapled to it. Simorg's release tooling does this; it is not part of
this repository.

## Windows

See [**windows-builds.md**](windows-builds.md) — one Intel machine produces both
the x64 and the ARM64 build, and the prerequisites are worth their own page.

The program carries its own resources, compiled in by
[`cmake/SimorgWindowsResources.cmake`](../cmake/SimorgWindowsResources.cmake)
from [`packaging/windows/program.rc.in`](../packaging/windows/program.rc.in): the
application icon (`IDI_ICON1`, which Qt also gives every window that has none of
its own) and a version resource, so Explorer shows the icon, Task Manager lists
`simorg-desktop.exe` as **Simorg**, and the file's Properties say Simorg Desktop,
its version and its licence. Without them a Windows install is a blank page in
the Start menu, in Explorer and in Apps & Features.

### The installer a person opens

The `.msi` ([`packaging/windows/simorg-desktop.wxs`](../packaging/windows/simorg-desktop.wxs))
is a small wizard built on WiX's own pages (the `WixToolset.UI.wixext`
extension):

| Page | What it says |
|---|---|
| Welcome | *Welcome to the Simorg Desktop Setup Wizard*, over the application icon |
| Ready to install | **Install**, with no shield: it is installed for the person, under `%LocalAppData%\Programs\Simorg` |
| Files in use | Only when a Simorg Desktop is running: Windows' Restart Manager offers to close it |
| Completed | Where Simorg is — the Start menu, and the notification area once it is open — and **Open Simorg now**, ticked |

There is no licence page and no folder to choose: GPL-3.0 asks for no acceptance,
and a per-person install has one right place.

**Open Simorg now** runs the program from the wizard's own process — the person's
session and account, and it does not wait — and only for an install or an
upgrade, never after a repair or an uninstall. The pages exist only when the
installer is opened with its full interface: Simorg Desktop updating itself runs
it with `/qb!` and opens the new version itself (`config/update/desktop-handover.ps1`),
and the machine service unpacks it with `/a`, so neither sees a page nor starts a
second copy.

The Start menu shortcut and Apps & Features take the icon from the package's own
`simorg.ico` (`ARPPRODUCTICON` and the shortcut's `Icon`) rather than from the
program: that is a new icon file per product code, so an upgrade from a version
whose program had no icon is not shown Windows' cached blank one.

The page pictures, `installer-dialog.bmp` (493 × 312, behind Welcome and
Completed) and `installer-banner.bmp` (493 × 58, across the others), are drawn
from the icon by the same script as the icons. Windows Installer stretches them
at high DPI; that is a limit of its dialogs, not of the pictures. The dialog
picture's text area is the system button face, `#f0f0f0`, because Windows
Installer paints the check box on that colour whatever is behind it.

### Signed as Simorg Oy

A release installer is signed, and so is everything in it: every program and
library that carries no signature yet is signed as Simorg Oy before WiX packs
them — Windows 11's Smart App Control checks each one it loads, not only the
installer — and then the package is signed. Libraries their makers already
signed, and Microsoft's runtime installer, keep their own signatures. The
signing is Microsoft's Artifact Signing, in Simorg's release tooling. A build
from `scripts/build-windows.ps1` is not signed.

## Application icons

The icon every system shows for Simorg Desktop is the Simorg mark, extruded
towards the bottom and lit from above: on macOS and Linux raised on a white plate
with continuous ("squircle") corners, the way macOS draws its own applications,
and on Windows standing on its own, the way Windows 11 draws its. It is drawn,
not painted: [`scripts/icons/make_icons.py`](../scripts/icons/make_icons.py)
builds it as SVG from [`resources/branding/simorg-logo.svg`](../resources/branding/simorg-logo.svg)
and has librsvg rasterise it, so changing the mark and running one command is the
whole of a rebrand.

The tray icon is not this. A status icon is a glyph on a panel, so it stays the
bare mark (`simorg-tray.svg`), a template image on macOS.

### One drawing, a geometry per platform

| | Shape | Why |
|---|---|---|
| **macOS** | A plate of 824 units on a 1024 canvas, 100 clear all round, corner radius 185.4 with 60 % corner smoothing | Apple's app icon grid since macOS 11. The margin is where the system's shadow and the Dock's magnification go; a plate that fills the canvas looks a size too big beside every other app |
| **Linux** | A plate filling almost the whole canvas: a little room at the sides and more below for the shadow | freedesktop desktops neither mask nor pad icons, and draw them at 16 to 48 pixels far more often than at 256, where a macOS margin would only make the mark smaller |
| **Windows** | No plate: the mark itself, 86 % of the canvas from 64 pixels up and all but half a pixel of it at 16, with a soft two-layer shadow from 48 pixels up | Microsoft's guidance for Windows 11 app icons: one front-facing shape lit from the top, no backplate, using the whole canvas, with a shadow only where it has room to be soft. The brand blue has the contrast Windows asks for against both the light and the dark taskbar, so it needs no outline |

And a drawing per size, rather than one picture scaled down: at 32 pixels and
below the mark takes more of the plate (78 % at 24 and under, against 66 % from
64 up) or, on Windows, of the canvas, where its strokes are also thickened by
half a pixel so the wings stay lines; the extrusion stays at least half a pixel
deep so the raised edge still reads; the plate's outline is darker so it holds
against a light background; and the soft shadows, which at that size would only
blur the edge, are left out. The installer's page pictures carry the Windows
drawing.

### Where each system reads it

| System | File | Read by |
|---|---|---|
| macOS | `packaging/macos/Simorg.icns` (16 pt to 512 pt @2x) | Finder and the Dock, from the bundle (`CFBundleIconFile`) |
| Windows | `packaging/windows/simorg.ico` (15 sizes, 16 to 256) | The program's resources, and so every window: Qt gives `IDI_ICON1` to a window with no icon of its own, and Windows picks the size it needs for the title bar, the taskbar and Alt+Tab. Also the installer's Start menu entry and Apps & Features |
| Linux | `resources/branding/app-icon/simorg-<N>.png` (16 to 512) and `simorg-app-icon.svg` | Installed as `hicolor/<N>x<N>/apps/tech.simorg.desktop.png` and `scalable`; in the AppImage, its top-level `tech.simorg.desktop.svg` and `.png`, and `.DirIcon`; and, 16 to 256 in the program's resources, the window icon ([`src/app/AppIdentity.cpp`](../src/app/AppIdentity.cpp)) |

Three things decide whether a desktop actually shows it:

- **macOS and Windows: no window icon.** `QGuiApplication::setWindowIcon` on
  macOS *replaces the Dock icon* with whatever image it is handed, so the Dock
  would show that instead of the bundle's icon. On Windows the program's own
  icon resource is the one to show, so it is left to that. It is set on Linux
  only.
- **Linux: the desktop file name.** On Wayland a window is matched to its menu
  entry, and so to its icon, by its app id, and Qt makes one up when the app
  names none: `tech.simorg.simorg-desktop`, from the organisation's domain and the
  program's file name, which no desktop entry is called — and the running app
  would get a second, generic entry in GNOME's dock and on the Raspberry Pi's
  panel. So it sets `tech.simorg.desktop`, the name of its desktop entry, and on
  X11 the entry's `StartupWMClass=simorg-desktop` matches the window's class.
- **The install script takes the SVG.** The Linux install line copies
  `<Icon>.svg` from the top of the AppImage before `<Icon>.png`, so the scalable
  icon is the one the menu shows.

macOS 26 draws app icons from an Icon Composer `.icon` compiled into
`Assets.car` when an app has one, and fits any other icon into its own shape. The
`.icns` follows Apple's grid exactly, so it is shown as drawn; an `.icon` made
from the same layers would need Xcode's `actool` in the Mac build.

### Drawing them again

```bash
./scripts/make-icons.sh                  # write every icon that is not current
./scripts/make-icons.sh --check          # write nothing; fail when one is stale
./scripts/make-icons.sh --preview /tmp/i # also every size of both geometries, to look at
```

It runs the generator in a throwaway `alpine:3.20` container with librsvg 2.58
and the Inter typeface (for the words on the disk image's picture), so a Mac, a
Windows computer and a Linux machine write byte-for-byte the same files;
`--local` uses this computer's `rsvg-convert`, `python3` and Inter instead. The
generator needs only the Python standard library: it decodes PNG and writes the
ICO (32-bit images below 64 pixels, PNG from 64 up), ICNS and BMP containers
itself. The files are committed, and nothing in a build runs it.

## Qt 6.4 is the declared floor

The project declares Qt 6.4 as its minimum, the Qt the current Ubuntu LTS ships.
Release builds use the pinned Qt 6.11.2 on every platform, so none of them
compiles against 6.4; a dev build on Debian 12 with its own Qt (`qt6-base-dev`
and friends) is the way to check it.

Two kinds of line load on a newer Qt and break on 6.4, and the interface keeps
both out:

| Where | What 6.4 refuses | How it is kept out |
|---|---|---|
| `src/app/qml/TipLayer.qml` | `onTargetChanged` inside a `Connections` block, which has a `target` of its own: 6.4 calls it a duplicate method and refuses to load the file | the values are mirrored onto local properties rather than watched with a `Connections` |
| `src/app/qml/CountdownPill.qml`, `OsLogo.qml`, `Sparkline.qml` | `font.features` and `Shape.CurveRenderer`, both 6.6 | assigned from `Component.onCompleted` behind a check that the property or value exists |

A property that does not exist is a *hard load failure* of the file that names
it, not a warning, and it takes every file that instantiates that one down with
it — `OsLogo` is drawn on every machine card, so a one-line renderer hint could
remove the entire dashboard. Where a newer Qt's property is genuinely wanted,
assign it from `Component.onCompleted` behind a `typeof` check: an older Qt gets
the older behaviour and everything else works.

## Third-party notices

The LGPL asks that a program built on Qt carry Qt's licence text and a prominent
notice, that the source of that exact Qt be available, and that Chromium's own
attributions travel with Qt WebEngine. Every build therefore ships a
`THIRD-PARTY-NOTICES.txt`:

| Where it comes from | What it holds |
| --- | --- |
| `packaging/notices/THIRD-PARTY-NOTICES.txt.in` | The template: the GPL statement, the Qt modules used with the version substituted at configure time, the source archive's address, and the LGPL text |
| `packaging/notices/qtwebengine-third-party.txt` | The components inside Qt WebEngine, as The Qt Company lists them, appended when the build has WebEngine |
| `packaging/notices/LGPL-3.0.txt` | The licence text itself |
| `scripts/bundle-linux.sh` | On Linux, the Debian `copyright` file of every library the bundle carries, appended at the end |

`cmake/SimorgNotices.cmake` writes it into the build tree's `bin/` and installs it
beside the program: `Simorg.app/Contents/Resources/` with the `LICENSE` on macOS,
next to the executable on Windows, and `share/licenses/simorg/` on Linux.
**Settings → Licences** in the app shows the same file, selectable, with the
licence and the source repository named above it, which is the "prominent
notice" the LGPL asks for.

## When something is missing

**A library is missing on the target.** Run the verifier against the unpacked
bundle on the machine that fails:

```bash
./scripts/verify-linux-bundle.sh /path/to/simorg-0.1.0-linux-arm64
```

Its last section prints every library the bundle resolves outside itself. If the
missing one is in `scripts/linux-host-libraries.txt`, the target genuinely lacks
something a Linux desktop has. Ask first whether anything on the host really
loads it into the process (measure, as was done for xcb): if nothing does, the
line is too wide and it should be bundled; if something does and machines still
go without it, give the line `fallback`, as `libasound` has. If it is not in the
list at all, it should have been bundled: find out which file names it, and
whether it is opened by soname at run time rather than linked — that is the only
way for one to escape the walk, and the fix is to name it beside `libssl` in
`bundle-linux.sh`.

**An agent's Workbench or Brain stays blank.** Ask the app itself, on the
machine that fails:

```bash
./simorg-desktop --check-web-engine
./simorg-desktop --check-web-engine https://simorg.tech
```

The first draws a built-in page and runs its script, the second loads one over
the network; each says what it saw and exits non-zero when the page did not
draw. The app's log says whether the web engine runs without Chromium's sandbox
and why.

**A QML module is missing.** The symptom is an empty window and
`module "…" is not installed` on stderr; check #5 catches it before release. The
bundler copies whole top-level module directories, so this means a new top-level
module — add it to the always-present list in `bundle-linux.sh` if
`qmlimportscanner` does not see it, which happens when the import is constructed
at run time rather than written at the top of a file.

**A new Qt module is linked.** Nothing needs doing for its shared library; the
walk finds it. Its *plugins* may need a new category in `PLUGIN_CATEGORIES`, and
if it is an add-on module, the Qt installs need it too: the `-m` list in
`docker/Dockerfile.linux-build` and `QT_MAC_MODULES` in `build-targets.sh`.

**The archive is enormous.** It is mostly Chromium, in Qt WebEngine — its
library alone is 182 MB of the 421 MB an arm64 bundle unpacks to, 171 MB as a
download — and then ICU, which `libQt6Core` links and which carries about 30 MB
of locale data. `--config prod` strips the binaries. A server wants Simorg CLI,
which carries no Qt at all.
