![Simorg](docs/simorg-mark.svg)

# Simorg Desktop

**Run your Simorg agents on your own computer.**

Simorg Desktop turns a Mac, Windows or Linux computer into a machine your agents
run on. Sign in, name the computer, choose the agents it hosts, and follow their
work from the menu bar. For a server with no screen, or anyone who prefers a
terminal, [Simorg CLI](https://simorg.tech/logos/simorg/betsalel/simorg-cli) offers the same controls.

## Features

- **Your hardware, your choice.** Run the agents you pick, stop any of them at any time, and uninstall one from this computer while it stays on your Logos.
- **Agent surfaces in a native window.** Open an agent's Workbench and Brain exactly as they appear in the browser, on macOS, Windows and Linux.
- **Live status and logs.** See which agents are running, what they are doing and what they have written.
- **Application management.** Install, open and remove Simorg applications, and choose which agents may use each one.
- **Private by design.** It reads none of your files and runs only what you place on the computer.
- **A clean sign-out.** Signing out removes the account's session, cache, applications and agent data from the computer.
- **Updates on your terms.** New versions of the app, the machine service, the agent runtime and, where it is installed, Simorg CLI appear in Settings, Updates, within a minute of their release and with what each brings. They download ahead, and each installs when you press Update, here, with Simorg CLI or on the machine's page on simorg.tech, or by itself once you turn on Install updates automatically, with your agents kept running. When an agent you installed has a newer release, a bar says so and its Settings updates it with one press.
- **Leaves nothing behind.** Uninstall in Settings removes Simorg, and your data if you ask, from the computer in one press.

## Usage

1. Download Simorg Desktop for your operating system and open it, or install it with one line in a terminal, for you alone and with no password:

   **macOS and Linux**

   ```bash
   curl -fsSL https://install.simorg.tech/app | sh -s -- @simorg/betsalel/simorg-desktop
   ```

   **Windows** (PowerShell)

   ```powershell
   & ([scriptblock]::Create((irm https://install.simorg.tech/app.ps1))) @simorg/betsalel/simorg-desktop
   ```

2. On first launch it sets up the Simorg machine service by itself; your system asks for your administrator password once.
3. Sign in, name the computer, and drag and drop machine's avatar inside your logos grid and connect it to the agents who need the processing power ;).

## Opening it the first time

Simorg Desktop for macOS and Windows is signed by Simorg Oy, and the Mac
version is notarized by Apple.

**macOS.** Move Simorg into your Applications folder before you open it: macOS
runs an app opened straight from Downloads from a temporary copy, which cannot
update itself. From there it opens like any other app.

**Windows.** A new release can still meet "Windows protected your PC" until
Windows has seen enough people install it: check that the publisher is Simorg
Oy, click More info, then Run anyway. The installer then asks nothing you have to
decide: Next, Install, and Finish, which opens Simorg. It installs for you alone,
with no administrator's password, and from then on Simorg is in the Start menu
and, while it runs, in the notification area next to the clock.

**Linux** asks nothing. The line under Usage adds Simorg to your applications
menu. A downloaded `.AppImage` has to
be marked as a program before it opens, because a browser never marks a download
that way: tick Allow executing file as program in its Properties, or run
`chmod +x` on it.

The machine service Simorg Desktop sets up on first launch installs without
these steps: Simorg fetches and installs it itself.

## Uninstalling

Open Settings, choose Uninstall, and press Uninstall. Simorg signs you out,
removes the machine service, your data if you leave the box ticked, and the
app itself. Your account and your agents on simorg.tech stay. With Simorg CLI,
`sim self uninstall` does the same.

## Requirements

- macOS 13 or later, Windows 10 or 11, or 64-bit Linux with a desktop, on Intel,
  AMD or ARM: Ubuntu 22.04, Debian 12, Fedora 36, Raspberry Pi OS bookworm or
  newer.
- A Simorg account and an agent to run.
- Docker, from any provider — Docker Desktop, OrbStack or Colima. Simorg Desktop uses the Docker you have installed and never installs it for you.

## Building from source

You need CMake 3.21 or later, Ninja, a C++17 compiler and Qt 6.4 or later. Agent
surfaces, the Workbench and the Brain, are drawn with Qt WebEngine 6.8 or later;
without it the app builds and says where they would be.

```bash
cmake --preset release
cmake --build --preset release
```

`./install.sh` builds and installs it from a fresh clone, with the packages your
system's package manager provides; `./install.sh --user` installs it under
`~/.local` with no password.

| Preset | What it builds |
| --- | --- |
| `dev` | Debug, pointed at a local Simorg (`localhost:10000`), warnings as errors |
| `release` | Release, pointed at simorg.tech |
| `package` | Release with Qt's libraries and QML modules copied beside the program |
| `macos-universal` | One macOS build for Apple silicon and Intel |

| CMake option | Default | |
| --- | --- | --- |
| `SIMORG_BUILD_GUI` | `ON` | The desktop app; off builds the libraries alone |
| `SIMORG_BUILD_WEBENGINE` | on when Qt WebEngine 6.8 is found | Draw agent surfaces with Qt WebEngine |
| `SIMORG_DEPLOY_QT` | `OFF` | Copy Qt's libraries and QML modules next to the binary |
| `SIMORG_WARNINGS_AS_ERRORS` | `OFF` | Turn compiler warnings into errors |

An archive that runs on a machine with nothing installed is made by
`scripts/build-targets.sh` on Linux and macOS and `scripts\build-windows.ps1` on
Windows; [docs/packaging.md](docs/packaging.md) and
[docs/windows-builds.md](docs/windows-builds.md) say how.

## Licence

Simorg Desktop is free software, licensed under the
**[GNU General Public License, version 3 or later](LICENSE)**. Every source file
carries an `SPDX-License-Identifier: GPL-3.0-or-later` header.

It uses the **Qt Framework** — Qt Core, Qt Network, Qt Gui, Qt Widgets, Qt Qml,
Qt Quick, Qt Quick Controls, Qt Svg and Qt WebEngine, which is built on Chromium
— under the terms of the **GNU Lesser General Public License, version 3**, linked
dynamically so that the Qt beside the program can be replaced and the program
run with it. Qt is a trademark of The Qt Company Ltd. Qt's own source is
available from [code.qt.io](https://code.qt.io/), and every build carries
`THIRD-PARTY-NOTICES.txt`, which names the exact Qt it links
([docs/packaging.md](docs/packaging.md#third-party-notices)).

The Simorg machine service that Simorg Desktop talks to is a separate program,
shipped separately under its own licence. Neither links the other: they speak
over the service's local API.
