// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QObject>
#include <QString>

class QLocalServer;

namespace simorg {

/**
 * Keeps one window of the desktop app per user per environment.
 *
 * Launching the app again from the dock, the app menu or a terminal should bring
 * forward what is already there rather than start a second tray icon. The second
 * process hands its request to the first over a local socket and exits.
 *
 * Only the windows: which Simorg runs on the computer is the Simorg machine
 * service's to keep, by its own socket.
 */
class SingleInstanceGuard : public QObject
{
    Q_OBJECT

public:
    explicit SingleInstanceGuard(const QString &key, QObject *parent = nullptr);

    /**
     * Tries to become the primary instance.
     *
     * Returns false when another instance already holds the socket, in which
     * case it has been asked to show itself and this process should exit.
     */
    bool tryBecomePrimary();

Q_SIGNALS:
    /** Another launch happened; bring the app to the front. */
    void activationRequested();

private:
    QString m_key;
    QLocalServer *m_server = nullptr;
};

} // namespace simorg
