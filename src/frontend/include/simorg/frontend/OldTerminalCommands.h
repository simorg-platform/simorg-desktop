// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>
#include <QStringList>

namespace simorg {

/**
 * What releases of Simorg Desktop before Simorg CLI put on PATH, taken away.
 *
 * Until Simorg CLI became an application of its own, Simorg Desktop carried the
 * `simorg` command and, from Settings → Execution, put `simorg` and `sim` on
 * PATH: links in `~/.local/bin`, `~/bin` or `/usr/local/bin` to the command
 * inside the bundle or to the AppImage itself, and on Windows `.cmd` shims in a
 * folder of its own that it added to the person's PATH. This release carries no
 * command, so those would answer with a file that is gone or, on Linux, open
 * the app: each start takes them away, and once they are gone it has nothing to
 * do.
 *
 * Only what an older Simorg Desktop made is taken: a link to a bundle's
 * `Contents/Helpers/simorg` or to the AppImage this app runs as, a shim running
 * the `simorg.exe` of the folder this app is in. Simorg CLI's own `simorg` and
 * `sim`, which `install.simorg.tech/app` puts in `~/.local/bin`, are a program
 * and a link beside it, and stay, with the PATH block they rely on: a block goes
 * only when nothing of Simorg is left in its folder.
 */
namespace oldterminalcommands {

/** The names an older release put on PATH: `simorg` and `sim`. */
QStringList names();

/** Where it looked for a folder for them: `~/.local/bin`, `~/bin`, `/usr/local/bin`; on Windows its own `bin`. */
QStringList candidateDirectories(const QString &home);

/** The profile a new terminal of `shell` reads, where an older release added its PATH block. */
QString profileFileFor(const QString &shell, const QString &home);

/** `text` without the guarded `# >>> simorg >>>` block that names `directory`; as it was otherwise. */
QString withoutBlockFor(const QString &text, const QString &directory);

/**
 * Whether a link called `simorg` or `sim` that points at `target` is one an older
 * release made: to a bundle's `Contents/Helpers/simorg`, or to `appImage`, the
 * AppImage this app runs as (empty when it is not one).
 */
bool madeByOlderDesktop(const QString &target, const QString &appImage);

/** Whether a Windows shim reading `text` runs the `simorg.exe` of `installFolder`, as an older release's did. */
bool shimMadeByOlderDesktop(const QString &text, const QString &installFolder);

/**
 * Takes them away from `home` for a person whose shell is `shell`, and the PATH
 * an older release added for their folder once nothing of Simorg is left in it.
 * `appImage` and `installFolder` are this app's. Answers the files removed.
 */
QStringList removeFrom(const QString &home, const QString &shell, const QString &appImage,
                       const QString &installFolder);

/** removeFrom for the person running this app, as each start runs it. */
QStringList removeFromThisComputer();

} // namespace oldterminalcommands

/**
 * What Settings → Uninstall takes away that is the app's own rather than the
 * service's: an older release's terminal commands, and every login item of
 * Simorg's name. Answers what could not be removed, as one sentence, or empty.
 */
QString removeCommandsAndLoginItems();

} // namespace simorg
