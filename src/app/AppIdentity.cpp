// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "AppIdentity.h"

#include "simorg/frontend/BuildInfo.h"

#include <QCoreApplication>
#include <QGuiApplication>

namespace simorg::app {

QIcon applicationIcon()
{
    QIcon icon;
    // Each size as drawn for it, rather than one image scaled: the small ones
    // give the mark more of the plate and leave the soft shadows out.
    for (const int size : {16, 22, 24, 32, 48, 64, 128, 256})
        icon.addFile(QStringLiteral(":/simorg/branding/app-icon/simorg-%1.png").arg(size), QSize(size, size));
    return icon;
}

void applyApplicationIdentity(const QString &version)
{
    // Shared with the CLI so both report the same identity to the OS. The
    // session file's location is resolved independently of these — see
    // SessionStore::configDirectory.
    QCoreApplication::setOrganizationName(QStringLiteral(SIMORG_ORGANIZATION));
    QCoreApplication::setOrganizationDomain(QStringLiteral(SIMORG_ORGANIZATION_DOMAIN));
    QCoreApplication::setApplicationName(QStringLiteral(SIMORG_ORGANIZATION));
    QCoreApplication::setApplicationVersion(version);
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Simorg"));
    QGuiApplication::setDesktopFileName(QString::fromLatin1(desktopFileId));
    // Linux only: Windows gives every window the program's icon resource, and
    // macOS takes the Dock icon from the bundle (AppIdentity.h).
#if !defined(Q_OS_MACOS) && !defined(Q_OS_WIN)
    QGuiApplication::setWindowIcon(applicationIcon());
#endif
}

} // namespace simorg::app
