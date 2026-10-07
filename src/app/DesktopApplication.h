// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "AppModels.h"
#include "CrashMarker.h"

#include <QObject>
#include <QString>

#include <optional>

class QEvent;
class QQmlApplicationEngine;

namespace simorg {
class SingleInstanceGuard;
} // namespace simorg

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

class AppBridge;
class MenuBarController;
class SurfaceSchemeHandler;
class TrayController;

/**
 * The desktop app: the windows, the tray and the menu bar, on the Simorg machine
 * service.
 *
 * Everything this computer does for Simorg — the Hub connection, Docker, the agents'
 * containers, the journal, sign-in — happens in `simorgm`.
 * This process holds one `ServiceSession` to it and one object per QML singleton,
 * each reading the service's topics and asking it to act, and decides only what a
 * front end decides: which window is owed, what the tray says, and when to say it.
 *
 * The app going any other way than Quit Simorg stops nothing: the agents go
 * on running under the service with every window closed and this process gone.
 * Quit Simorg, ⌘Q and the application menu ask the service to stop, and
 * so, for the account's agents, does Sign out: each of them asks first when an
 * agent is running here. A Quit with no connection to ask over — a service that
 * never answered — asks the system's service manager to stop it instead
 * (`ServiceSession::stopUnreachedService`).
 */
class DesktopApplication : public QObject
{
    Q_OBJECT

public:
    struct Options
    {
        /** `dev` or `prod`; empty for `SIMORG_ENV`, then the build. */
        QString environment;
        bool background = false;
    };

    explicit DesktopApplication(Options options, QObject *parent = nullptr);
    /** The interface goes first, while everything it reads is still there. */
    ~DesktopApplication() override;

    /** False when another window of this app is already open, which has been asked to come forward. */
    bool start();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void loadQml();
    void connectSignals();
    /**
     * Quit (`quit`) or Sign out (`signOut`), from wherever it was chosen: done at once, or asked about first
     * when it would stop agents running on this computer. `alwaysAsk` asks either way.
     */
    void requestLeave(const QString &action, bool alwaysAsk = false);
    /** Whether leaving now would stop an agent: the service is reached and a container runs or is starting. */
    bool leavingStopsAgents() const;
    /** What {@link requestLeave} goes on to, straight away or once the question is answered yes. */
    void proceed(const QString &action);
    /** Quit Simorg, once decided: the service is asked to stop, and the app goes after it. */
    void leave();
    /** Ends the event loop; a platform quit arriving after this is the exit itself, and is let through. */
    void exitNow();
    void surfaceWindow();
    void surfaceIfWindowOpen();
    static bool anyWindowVisible();

    Options m_options;
    QString m_environment;
    SingleInstanceGuard *m_guard = nullptr;
    client::ServiceSession *m_session = nullptr;
    AppModels m_models;
#ifdef SIMORG_WITH_WEBENGINE
    SurfaceSchemeHandler *m_surfaceScheme = nullptr;
#endif

    AppBridge *m_bridge = nullptr;
    TrayController *m_tray = nullptr;
    MenuBarController *m_menuBar = nullptr;
    QQmlApplicationEngine *m_engine = nullptr;

    /** The agent the last permission notification named, for its click, which carries nothing. */
    int m_pendingAccessAgentId = 0;
    /** The last notification was an application asking to attach, so a click opens the window rather than an agent. */
    bool m_noticeIsApplication = false;
    bool m_launchReported = false;
    /** What the previous launch's crash marker said, until the service is there to be told. */
    std::optional<crash::Marker> m_crash;
    /** Quit was chosen: the app goes when the service's run is over. */
    bool m_leaving = false;
    /** What Settings → Uninstall asked with, held while the question about running agents is on screen. */
    struct PendingUninstall {
        QStringList reasons;
        QString comment;
        bool removeData = true;
    };
    PendingUninstall m_pendingUninstall;
    /** The event loop was told to end. */
    bool m_exiting = false;
};

} // namespace simorg::app
