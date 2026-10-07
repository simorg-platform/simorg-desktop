// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QIcon>
#include <QString>

namespace simorg::app {

/**
 * The desktop entry the Linux desktop knows Simorg by, without `.desktop`:
 * packaging/linux/tech.simorg.desktop.desktop, and the icon installed under the
 * same name.
 */
inline constexpr const char *desktopFileId = "tech.simorg.desktop";

/**
 * Simorg Desktop's Linux application icon, every size scripts/make-icons.sh draws
 * for a window: the white plate with the raised mark, as the title bar, the dock
 * and the window switcher show it. Not the tray's, which stays the bare mark: a
 * status icon is a glyph on the panel, not an application.
 */
QIcon applicationIcon();

/**
 * Who this process is, to the operating system. Called once, straight after the
 * application object exists and before any window.
 *
 * - The organisation and application names the CLI shares, which settle where
 *   QSettings and QStandardPaths put things.
 * - The desktop file name. On Wayland it is the window's app id, which is the
 *   only way GNOME, KDE and the Raspberry Pi's panel match a window to its menu
 *   entry and icon: left unset, Qt makes one up from the domain and the program's
 *   file name (`tech.simorg.simorg-desktop`), no desktop entry has that name, and
 *   the running app appears as a second, iconless entry in the dock.
 * - The window icon, on Linux only. On Windows every window is given the
 *   program's own icon resource (`IDI_ICON1`, packaging/windows/simorg.ico, drawn
 *   the Windows 11 way), which Windows reads at each size it needs, so the title
 *   bar, the taskbar, Alt+Tab, Explorer and the Start menu show one icon. On
 *   macOS a window icon would replace the Dock icon the bundle's Simorg.icns
 *   provides — macOS draws that one, with the system's own shadow and at every
 *   size, better than any image the process hands it at run time.
 */
void applyApplicationIdentity(const QString &version);

} // namespace simorg::app
