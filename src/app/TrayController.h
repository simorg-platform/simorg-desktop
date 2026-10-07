// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QIcon>
#include <QObject>

class QAction;
class QMenu;
class QSystemTrayIcon;
class QTimer;

namespace simorg::app {

class AuthModel;
class AppBridge;

/**
 * The menu-bar / system-tray presence.
 *
 * This is the app's real front door: it is created before any window and
 * outlives every one of them, which is what lets the app keep running in the
 * background after the last window closes.
 *
 * The menu is rebuilt from the auth state rather than toggled item by item, so
 * "Dashboard" and "Sign in…" can never both be showing.
 */
class TrayController : public QObject
{
    Q_OBJECT

public:
    TrayController(AuthModel *auth, AppBridge *bridge, QObject *parent = nullptr);
    ~TrayController() override;

    /**
     * Puts the icon in the menu bar, retrying while a session is still coming up.
     *
     * On macOS and Windows the answer is immediate and final. On Linux it is
     * not: `isSystemTrayAvailable()` reports false until a status-notifier host
     * registers, and on a freshly-started session that can be several seconds
     * after this app. Asking once and giving up is how a perfectly good desktop
     * ends up with no way to reach a background app.
     */
    void show();

    /** Balloon/notification through the tray, where the platform supports it. */
    void notify(const QString &title, const QString &message);

Q_SIGNALS:
    /**
     * Somebody clicked the last notification.
     *
     * A tray message carries no buttons of its own on macOS, Windows or Linux,
     * so the whole message is the button. Forwarded rather than acted on here,
     * because what a click should open depends on what was last said and this
     * class deliberately knows nothing about that.
     */
    void messageClicked();

private:
    void rebuildMenu();
    /** Dumps the menu under `--verbose`; the quickest answer to "where is Quit?". */
    void logMenu() const;
    void updateTooltip();
    static QIcon loadTrayIcon();

    AuthModel *m_auth;
    AppBridge *m_bridge;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_menu = nullptr;
    /** Linux only: keeps looking for a status-notifier host for a short while. */
    QTimer *m_retry = nullptr;
};

} // namespace simorg::app
