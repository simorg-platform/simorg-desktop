// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QObject>

class QAction;
class QMenuBar;

namespace simorg::app {

class AuthModel;
class AppBridge;

/**
 * The application menu bar.
 *
 * macOS gives every foreground app a menu bar of its own, next to the Apple
 * menu, and people reasonably expect to find About, Quit and the app's main
 * actions there. Our windows are Qt Quick and have no menu bar to hang this
 * off, so the QMenuBar is created without a parent — which is precisely what
 * Cocoa treats as the application-wide fallback menu bar.
 *
 * That is also why this is macOS-only: Windows and most Linux desktops have no
 * such concept, and a parentless menu bar there would simply never be shown.
 * On those platforms the tray menu is the app's menu.
 */
class MenuBarController : public QObject
{
    Q_OBJECT

public:
    MenuBarController(AuthModel *auth, AppBridge *bridge, QObject *parent = nullptr);
    ~MenuBarController() override;

    /** Whether this platform has an application-wide menu bar to populate. */
    static bool isSupported();

private:
    void build();
    void syncToAuthState();
    void showAbout();

    /** Minimise/close act on whichever window currently has focus. */
    static void minimiseActiveWindow();
    static void closeActiveWindow();

    AuthModel *m_auth;
    AppBridge *m_bridge;

    QMenuBar *m_menuBar = nullptr;
    QAction *m_dashboardAction = nullptr;
    QAction *m_signInAction = nullptr;
    QAction *m_signOutAction = nullptr;
};

} // namespace simorg::app
