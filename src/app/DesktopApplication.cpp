// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "DesktopApplication.h"

#ifdef SIMORG_WITH_WEBENGINE
#include "SurfaceSchemeHandler.h"

#include "simorg/appmodel/SurfaceRouter.h"

#include <QWebEngineProfile>
#endif

#include "AppBridge.h"
#include "AvatarCache.h"
#include "CrashMarker.h"
#include "MenuBarController.h"
#include "TrayController.h"
#include "simorg/appmodel/AgentModels.h"
#include "simorg/appmodel/AuthModel.h"
#include "simorg/appmodel/DesktopUpdateModel.h"
#include "simorg/appmodel/HubModel.h"
#include "simorg/appmodel/MachineSetupModel.h"
#include "simorg/appmodel/PeersModel.h"
#include "simorg/appmodel/PreflightModel.h"
#include "simorg/appmodel/ShutdownModel.h"
#include "simorg/appmodel/UninstallModel.h"
#include "simorg/appmodel/SurfaceModels.h"
#include "simorg/appmodel/TelemetryModel.h"
#include "simorg/client/ServiceSession.h"
#include "simorg/frontend/OldTerminalCommands.h"
#include "simorg/frontend/BuildInfo.h"
#include "simorg/frontend/Logging.h"
#include "simorg/frontend/SingleInstanceGuard.h"

#include <QEvent>
#include <QGuiApplication>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QSysInfo>
#include <QTimer>
#include <QWindow>
#include <QtQml>

#include <algorithm>
#include <optional>
#include <utility>

namespace simorg::app {

namespace {

/** `dev` or `prod` from what somebody typed; empty when neither. */
QString environmentFrom(const QString &text)
{
    const QString value = text.trimmed().toLower();
    if (value == QLatin1String("dev") || value == QLatin1String("development"))
        return QStringLiteral("dev");
    if (value == QLatin1String("prod") || value == QLatin1String("production"))
        return QStringLiteral("prod");
    return {};
}

} // namespace

DesktopApplication::DesktopApplication(Options options, QObject *parent)
    : QObject(parent)
    , m_options(std::move(options))
{
}

DesktopApplication::~DesktopApplication()
{
    /*
      The interface first.

      Everything here is a child of this object, and children go in the order
      they were made: the session and the models long before the QML engine,
      which is made last. The windows' bindings then read models that had
      already gone, and every exit ended with a dozen TypeErrors in the log.
      Destroyed first, the engine takes its windows down while what they read
      is still there.
    */
    delete m_engine;
    m_engine = nullptr;
}

bool DesktopApplication::start()
{
    // `--env`, else `SIMORG_ENV`, else the build, the order the service itself follows.
    m_environment = environmentFrom(m_options.environment);
    if (m_environment.isEmpty())
        m_environment = environmentFrom(qEnvironmentVariable("SIMORG_ENV"));
    if (m_environment.isEmpty())
#ifdef QT_DEBUG
        m_environment = QStringLiteral("dev");
#else
        m_environment = QStringLiteral("prod");
#endif

    /*
      One window per person per environment.

      Only the windows: the service's own socket is what keeps one Simorg agent on
      this computer, and a second launch of this app is somebody asking for the
      window they already have.
    */
    m_guard = new SingleInstanceGuard(QStringLiteral("simorg-desktop-%1").arg(m_environment), this);
    if (!m_guard->tryBecomePrimary())
        return false;

    /*
      The previous launch's crash marker is read and deleted before this launch
      installs its own, so one crash is reported once. The report itself waits
      for the service: it goes out with the other telemetry, on the first
      connection.
    */
    const QString marker = crash::markerPath(m_environment);
    m_crash = crash::take(marker);
    if (!crash::install(marker, QStringLiteral(SIMORG_VERSION)))
        qCWarning(lcApp) << "the crash marker could not be installed; a crash of this app will not be reported";

    // `simorg` and `sim` as an older release put them on PATH, now Simorg CLI's to provide: nothing once they are gone.
    oldterminalcommands::removeFromThisComputer();

    client::ServiceSession::Options session;
    session.environment = m_environment;
    session.clientName = QStringLiteral("simorg-desktop/%1 (%2 %3; %4)")
                             .arg(QStringLiteral(SIMORG_VERSION), QSysInfo::productType(), QSysInfo::productVersion(),
                                  QSysInfo::currentCpuArchitecture())
                             .toUtf8();
    m_session = new client::ServiceSession(session, this);

    /*
      The models first, and the reporter first among them: what goes wrong while the
      rest starts is what is most worth hearing about.
    */
    m_models = AppModels::build(m_session, m_environment, this, SIMORG_ARCHIVE_BUILD != 0);
    m_models.telemetry->installMessageHandler();
    m_bridge = new AppBridge(m_session, m_environment, this);

    // Up before any window: from here on the app has somewhere to live with every window closed.
    m_tray = new TrayController(m_models.auth, m_bridge, this);
    m_tray->show();
    if (MenuBarController::isSupported())
        m_menuBar = new MenuBarController(m_models.auth, m_bridge, this);

    connectSignals();
    qApp->installEventFilter(this);
    loadQml();

    // Connecting is what has the service prepare this computer; the windows are already listening.
    m_session->start();

    if (!m_options.background)
        surfaceWindow();
    else
        qCInfo(lcApp) << "started in the background";
    return true;
}

void DesktopApplication::connectSignals()
{
    // A second launch, from the Dock, the app menu or a terminal, brings forward the window this state owes.
    connect(m_guard, &SingleInstanceGuard::activationRequested, this, [this] { surfaceWindow(); });

    connect(m_session, &client::ServiceSession::connected, this, [this] {
        if (std::exchange(m_launchReported, true))
            return;
        if (m_crash) {
            // The app cannot report its own death, so this launch does it.
            const QString signal = crash::signalName(m_crash->signal);
            m_models.telemetry->reportError(
                QStringLiteral("crash"),
                QStringLiteral("The previous launch of Simorg Desktop crashed with %1.").arg(signal),
                {{QStringLiteral("signal"), signal},
                 {QStringLiteral("crashed_version"),
                  m_crash->version.isEmpty() ? QStringLiteral("unknown") : m_crash->version}});
            m_crash.reset();
        }
        m_models.telemetry->track(QStringLiteral("session_started"));
        m_models.telemetry->track(QStringLiteral("app_launched"),
                                  {{QStringLiteral("background"), m_options.background},
                                   {QStringLiteral("version"), QStringLiteral(SIMORG_VERSION)},
                                   {QStringLiteral("os"), QSysInfo::productType()},
                                   {QStringLiteral("arch"), QSysInfo::currentCpuArchitecture()},
                                   {QStringLiteral("qt"), QStringLiteral(QT_VERSION_STR)}});
    });

    /*
      No service to talk to: not installed, refused to start, or not the one this
      build trusts. Said once per reason, in the service client's own sentence; the
      session goes on trying, and the windows show what they can without it.
    */
    connect(m_session, &client::ServiceSession::unavailable, this,
            [this, last = QString()](client::ServiceClient::Unavailable, const QString &detail) mutable {
                qCWarning(lcApp).noquote() << "the Simorg machine service is not available:" << detail;
                if (detail == std::exchange(last, detail))
                    return;
                m_tray->notify(tr("Simorg is not running"), detail);
            });

    /*
      One topic refused while the rest of the socket works.

      Worth a line of its own, because the shape of it is a screen that waits for
      something that is never coming — the session above all. The session asks
      again on the next connection, and the launch window's *Try again* asks now.
    */
    connect(m_session, &client::ServiceSession::subscriptionRefused, this,
            [](const QString &topic, const client::ServiceProblem &problem) {
                qCWarning(lcApp).noquote()
                    << "the Simorg machine service refused the topic" << topic << ":" << problem.message();
            });

    // The environment check putting its window up or taking it down; a tray app started at login stays in the tray.
    connect(m_models.preflight, &PreflightModel::holdingChanged, this, &DesktopApplication::surfaceIfWindowOpen);

    // Whether this computer owes its owner the setup wizard, and whether that is decided yet.
    connect(m_models.machineSetup, &MachineSetupModel::stateChanged, this, &DesktopApplication::surfaceIfWindowOpen);

    /*
      The answer the launch window is waiting for, and the session afterwards.

      `surfaceWindow` shows neither the sign-in window nor the dashboard until the
      service has said what this computer's session is; this is what moves the
      launch on the moment it does. It follows the session from then on as well,
      which closes a hole the `signedOut` signal cannot: a restore that fails goes
      Restoring → SignedOut without ever having been signed in, and would leave
      a dashboard on screen with no session behind it.

      The states in the middle of a sign-in or a sign-out are skipped, and each
      for the same reason: the window they happen on is already saying so. The
      sign-in window draws its own two steps, and taking the dashboard away the
      moment somebody presses Sign out would replace the sweep this app just
      started — agents stopped, containers stopped, this computer's cache and
      journal cleared — with a sign-in form, which reads as though it had already
      finished. `signedOut` moves the window when it actually has.
    */
    connect(m_models.auth, &AuthModel::stateChanged, this,
            [this, last = std::optional<AuthModel::State>()]() mutable {
                const AuthModel::State state = m_models.auth->state();
                if (last && *last == state)
                    return; // busy toggling, which changes no window
                last = state;
                if (state == AuthModel::State::SigningIn || state == AuthModel::State::AwaitingSecondFactor
                    || state == AuthModel::State::SigningOut) {
                    return;
                }
                // Following what is on screen, never conjuring a window: a sign-in or a sign-out
                // in a terminal leaves an app sitting in the tray where it is.
                if (anyWindowVisible())
                    surfaceWindow();
            });

    connect(m_models.auth, &AuthModel::signInSucceeded, this, [this] {
        // Following a sign-in on screen rather than interrupting with one: a sign-in in a terminal leaves the
        // background alone. The tray still says it happened.
        if (anyWindowVisible())
            surfaceWindow();
        m_tray->notify(tr("Signed in"), tr("Welcome back, %1.").arg(m_models.auth->user().displayName));
    });

    connect(m_models.auth, &AuthModel::signedOut, this, [this] {
        // Signed out from a terminal while the question was up: it has happened, and there is nothing left to ask.
        if (m_bridge->leaveQuestion() == QLatin1String("signOut"))
            m_bridge->withdrawLeaveQuestion();
        // An open Workbench or Brain is a connection into an agent as that account, and it goes with the account.
        // The service sweeps the rest: the containers, the cache and the journal.
        m_models.surfaceSessions->closeAll();
        if (anyWindowVisible())
            m_bridge->requestLogin();
    });

    // The account's picture, followed: a restored session, a sign-in, a refreshed profile, and nothing on sign-out.
    connect(m_models.auth, &AuthModel::userChanged, this,
            [this] { m_bridge->setAccountAvatar(m_models.auth->user().avatarUrl); });

    // A computer that just appeared on somebody's account is worth saying out loud, once per sign-in.
    connect(m_models.hub, &HubModel::machineChanged, this, [this, announced = false]() mutable {
        if (!m_models.hub->isNewlyRegistered()) {
            announced = false;
            return;
        }
        if (!std::exchange(announced, true))
            m_tray->notify(tr("Machine added"),
                           tr("%1 is now on your account and online.").arg(m_models.hub->machineTitle()));
    });

    // The session ended somewhere this app has no view of: the machine removed, the account blocked.
    client::TopicSubscription *const revoked = m_session->subscribe(QStringLiteral("hub.revoked"));
    connect(revoked, &client::TopicSubscription::received, this, [this](const QJsonObject &event) {
        const QString reason = event.value(QStringLiteral("reason")).toString();
        m_tray->notify(reason == QLatin1String("machine_removed") ? tr("This machine was removed") : tr("Signed out"),
                       event.value(QStringLiteral("message")).toString());
        if (anyWindowVisible())
            m_bridge->requestLogin();
    });

    /*
      The one notification about permissions, and a way in. The service decides when
      an agent's unanswered requests are worth announcing and remembers that it did,
      so this is said once per agent, not every morning; the message is the button,
      and it opens that agent's page.
    */
    client::TopicSubscription *const pending = m_session->subscribe(QStringLiteral("access.pending"));
    connect(pending, &client::TopicSubscription::received, this, [this](const QJsonObject &announcement) {
        m_pendingAccessAgentId = announcement.value(QStringLiteral("agent_id")).toInt();
        m_noticeIsApplication = false;
        const QString title = announcement.value(QStringLiteral("agent_title")).toString();
        const int count = announcement.value(QStringLiteral("pending_count")).toInt();
        m_tray->notify(tr("%1 cannot start until you decide").arg(title),
                       count == 1 ? tr("It is waiting on one permission. Open Simorg to answer it.")
                                  : tr("It is waiting on %1 permissions. Open Simorg to answer them.").arg(count));
    });
    /*
      An application on this computer asking to attach. The sheet in the window asks the question; the
      notification is the way to it when the window is closed.
    */
    connect(m_models.peers, &PeersModel::consentRequested, this, [this](const QString &title) {
        m_noticeIsApplication = true;
        m_tray->notify(tr("%1 wants to connect to Simorg").arg(title),
                       tr("Open Simorg to allow or refuse it."));
    });
    connect(m_tray, &TrayController::messageClicked, this, [this] {
        if (m_noticeIsApplication)
            m_bridge->requestDashboard();
        else
            m_bridge->requestAgentAccess(m_pendingAccessAgentId);
    });

    /*
      Leaving. Quit Simorg asks the service to stop:
      the agents are asked to finish, their containers stop, and the quitting window
      shows it to this app and every other one connected. The app goes when the run
      is over. With no service to ask there is nothing running to stop, and it goes
      at once.
    */
    connect(m_bridge, &AppBridge::quitRequested, this,
            [this](bool alwaysAsk) { requestLeave(QStringLiteral("quit"), alwaysAsk); });
    connect(m_bridge, &AppBridge::signOutRequested, this, [this] { requestLeave(QStringLiteral("signOut")); });
    // Uninstall Simorg: asked first when it would stop agents, as a sign-out is.
    connect(m_bridge, &AppBridge::uninstallRequested, this,
            [this](const QStringList &reasons, const QString &comment, bool removeData) {
                m_pendingUninstall = PendingUninstall{reasons, comment, removeData};
                requestLeave(QStringLiteral("uninstall"));
            });
    /*
      Everything that could be removed was. The window says so on a visible five-second countdown, and then this
      process goes, and nothing else: the service is already gone, so Quit Simorg would have nothing to stop.
    */
    connect(m_models.uninstall, &UninstallModel::finished, this, [this] {
        QTimer::singleShot(5'000, this, [this] { exitNow(); });
    });
    // Closed before it finished, once the service had signed out and stopped: nothing is left to show.
    connect(m_models.uninstall, &UninstallModel::closed, this, [this] { exitNow(); });
    connect(m_bridge, &AppBridge::leaveConfirmed, this, &DesktopApplication::proceed);
    connect(m_models.shutdown, &ShutdownModel::changed, this, [this] {
        // A terminal or another app stopping the service has already done what the question asks about.
        if (m_models.shutdown->isActive())
            m_bridge->withdrawLeaveQuestion();
        // The last frame held a third of a second, so the window does not flicker out.
        if (m_leaving && m_models.shutdown->isComplete())
            QTimer::singleShot(333, this, [this] { exitNow(); });
    });
    connect(m_session, &client::ServiceSession::disconnected, this, [this] {
        if (m_leaving)
            exitNow();
    });
    /*
      Updating itself. The new version is in place the moment this
      process is gone, so this process goes and nothing else does: never Quit Simorg, which would stop the
      service and every agent with it.
    */
    connect(m_models.desktopUpdate, &DesktopUpdateModel::exitRequested, this, [this] {
        m_models.telemetry->track(QStringLiteral("app_quit"), {{QStringLiteral("reason"), QStringLiteral("update")}});
        m_models.telemetry->flush();
        exitNow();
    });
    connect(m_models.shutdown, &ShutdownModel::beginFailed, this, [this](const QString &message) {
        // Refused: the person still asked to leave, and the service goes on without this window.
        qCWarning(lcApp).noquote() << "the Simorg machine service would not stop:" << message;
        exitNow();
    });
}

void DesktopApplication::requestLeave(const QString &action, bool alwaysAsk)
{
    if (m_leaving)
        return; // already going, and the quitting window is saying so
    /*
      Asked first when it would stop agents.

      Quitting stops the service and every agent it runs, and signing
      out stops the account's agents before it clears this computer. Either is a
      moment's press in a tray menu that takes work away from people who may be
      relying on it, so it is said out loud before it happens, in the dashboard,
      whichever menu it was chosen from. With nothing running there is nothing
      to warn about and it goes straight through, as it always has.
    */
    const bool stopsAgents = leavingStopsAgents();
    if (!stopsAgents && !alwaysAsk) {
        proceed(action);
        return;
    }
    m_bridge->askToLeave(action, stopsAgents);
}

bool DesktopApplication::leavingStopsAgents() const
{
    /*
      Running or starting, the two states the service stops. Not while this app
      cannot reach the service, since quitting then stops nothing and signing
      out cannot happen; and not while a sign-out is already stopping them,
      when a second Sign out is the same request.
    */
    if (!m_session->isConnected() || m_models.auth->state() == AuthModel::State::SigningOut)
        return false;
    return !m_models.hub->agents()->busyAgentIds().isEmpty();
}

void DesktopApplication::proceed(const QString &action)
{
    if (action == QLatin1String("quit"))
        leave();
    else if (action == QLatin1String("signOut"))
        m_models.auth->signOut();
    else if (action == QLatin1String("uninstall"))
        m_models.uninstall->start(m_pendingUninstall.reasons, m_pendingUninstall.comment, m_pendingUninstall.removeData);
}

void DesktopApplication::leave()
{
    if (std::exchange(m_leaving, true))
        return; // a second press while the service stops is the same request
    m_bridge->withdrawLeaveQuestion();
    /*
      Said on the screen before it is asked for.

      Asking the service to stop is a request over a socket, and a service that
      is busy — or gone — can take seconds to answer or never answer at all. The
      quitting window reads this, so those seconds show the window that says
      Simorg is leaving rather than the dashboard somebody just pressed Quit on.
    */
    m_bridge->setQuitting();
    m_models.telemetry->track(QStringLiteral("app_quit"), {{QStringLiteral("reason"), QStringLiteral("quit")}});
    m_models.telemetry->flush();
    if (!m_session->isConnected()) {
        /*
          Nobody to ask over the API, so the system's service manager is asked
          instead: a service that was started and never answered — the launch
          window sitting on "Reaching the Simorg machine service" — can stay
          like that until the computer restarts, and Quit Simorg is somebody
          asking for it to stop. The next launch starts it afresh.
        */
        if (m_session->stopUnreachedService())
            qCInfo(lcApp) << "asked the system to stop the Simorg machine service, which was not answering";
        exitNow();
        return;
    }
    m_models.shutdown->begin();
}

void DesktopApplication::exitNow()
{
    /*
      `exit`, not `quit`. `QCoreApplication::quit()` asks the platform to end the
      application, and on macOS that is Cocoa's terminate handshake, which ends in
      another `QEvent::Quit` arriving at the filter below. `exit` leaves the event
      loop directly.
    */
    m_exiting = true;
    QCoreApplication::exit(0);
}

bool DesktopApplication::eventFilter(QObject *watched, QEvent *event)
{
    /*
      A platform quit: ⌘Q and Quit Simorg in the macOS application menu, which Qt's
      Cocoa plugin puts there without passing through the tray, or the Dock.

      It is Quit Simorg, so it asks the service to stop like the tray's,
      and it is swallowed for as long as that stop runs: letting it through would end
      the app with the quitting window half drawn and the person believing Simorg
      had stopped. Once the app is exiting, a `Quit` is the exit in progress rather
      than a request, and is let through — swallowing that one too is what once made
      Simorg impossible to quit, the window reappearing several times a second.
      With agents running it asks first, like every other Quit.
    */
    if (event->type() == QEvent::Quit && !m_exiting) {
        requestLeave(QStringLiteral("quit"));
        return true;
    }
    return QObject::eventFilter(watched, event);
}

void DesktopApplication::surfaceWindow()
{
    // The environment check first, and it is the whole screen while it has something to say.
    if (m_models.preflight->isHolding()) {
        m_bridge->requestPreflight();
        return;
    }
    /*
      Nobody knows yet whether this computer has a session.

      The session is the service's, and until it answers this app cannot tell a
      signed-out computer from a signed-in one. Showing the sign-in window in
      the meantime would flash a login form past for half a second on every
      signed-in machine before the dashboard replaced it, so the launch window
      says what is actually happening instead, and the state
      arriving brings the launch on — see the `stateChanged` connection above.
    */
    if (!m_models.auth->isKnown()) {
        m_bridge->requestStarting();
        return;
    }
    // Restoring counts as signed in: the stored profile is on screen while the service confirms it.
    if (!m_models.auth->isSignedIn() && m_models.auth->state() != AuthModel::State::Restoring) {
        m_bridge->requestLogin();
        return;
    }
    // A computer nobody has named is not listed anywhere, so the wizard comes before a dashboard for it.
    if (m_models.machineSetup->isRequired()) {
        m_bridge->requestSetup();
        return;
    }
    // Signed in, and not yet known whether a wizard is owed: whatever is on screen stays, rather than a dashboard
    // taken away a moment later. With nothing on screen, the dashboard's own first-connection screen waits.
    if (m_models.machineSetup->isUndecided() && anyWindowVisible())
        return;
    m_bridge->requestDashboard();
}

void DesktopApplication::surfaceIfWindowOpen()
{
    // Re-decides the window without conjuring one for a tray app in the background.
    if (m_options.background && !anyWindowVisible())
        return;
    surfaceWindow();
}

bool DesktopApplication::anyWindowVisible()
{
    const QList<QWindow *> windows = QGuiApplication::topLevelWindows();
    return std::any_of(windows.cbegin(), windows.cend(), [](const QWindow *window) { return window->isVisible(); });
}

void DesktopApplication::loadQml()
{
    m_engine = new QQmlApplicationEngine(this);

#ifdef SIMORG_WITH_WEBENGINE
    /*
      The scheme an agent's rooms are served over, on the profile every web view
      shares. Installed here because it needs the renderer it reads from; the scheme
      itself was registered in `main`, before the application object existed.
    */
    m_surfaceScheme = new SurfaceSchemeHandler(m_models.surfaces, this);
    QWebEngineProfile::defaultProfile()->installUrlSchemeHandler(SurfaceRouter::scheme().toUtf8(), m_surfaceScheme);
#endif

    qmlRegisterSingletonInstance("Simorg", 1, 0, "App", m_bridge);
    // Every face the windows draw — the account's and every agent's — out of one cache.
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Avatars", m_bridge->avatars());
    m_models.registerQml();

    connect(
        m_engine, &QQmlApplicationEngine::objectCreationFailed, this,
        [this] {
            qCCritical(lcApp) << "the interface failed to load";
            m_exiting = true; // a broken interface is not somebody asking Simorg to stop
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    m_engine->load(QUrl(QStringLiteral("qrc:/qt/qml/Simorg/Main.qml")));
}

} // namespace simorg::app
