# Simorg Desktop — documentation

The [project README](../README.md) is the short page a reader meets first: what
the app does, how to install it, and how to build it from source. The terminal
command is Simorg CLI's, documented with it.

These pages are the things that are too detailed to live there.

| | |
|---|---|
| [**packaging.md**](packaging.md) | How a build becomes an archive somebody can run on a machine that has nothing installed — the bundlers, where the line between the bundle and the host is drawn, and how each platform's claim is proved rather than asserted. Also the third-party notices every build carries. |
| [**windows-builds.md**](windows-builds.md) | Building for Windows, including how one Intel machine produces both the x64 and the ARM64 build. |

## The short version

```bash
./scripts/build-targets.sh --config dev linux-arm64    # Linux, macOS
```
```powershell
.\scripts\build-windows.ps1 -Config dev                 # Windows, both architectures
```

Each produces one archive under `build/dist/<target>/` that is unpacked and run.
Qt, Qt's plugins, Qt's QML modules and everything underneath them travel inside
it, so the machine receiving it does not have to install a single library.

On the machine that receives it there is nothing else to do: the Simorg machine
service, which Simorg Desktop sets up on first launch, prepares the computer,
and the app itself writes only its own start-at-login entry.
