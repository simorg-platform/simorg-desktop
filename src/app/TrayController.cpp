// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "TrayController.h"

#include "AppBridge.h"
#include "simorg/appmodel/AuthModel.h"
#include "simorg/frontend/Logging.h"

#include <QAction>
#include <QApplication>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QSvgRenderer>
#include <QStringList>
#include <QSystemTrayIcon>
#include <QTimer>

namespace simorg::app {
namespace {

/** Sizes a menu bar might ask for, at 1x and 2x. */
constexpr int kIconSizes[] = {16, 18, 22, 24, 32, 36, 44, 64};

/**
 * How long to keep looking for a Linux status-notifier host.
 *
 * Long enough for a desktop session to finish starting, short enough that a
 * genuinely tray-less setup — a bare window manager, a kiosk — settles into
 * that answer rather than polling forever.
 */
#ifdef Q_OS_LINUX
constexpr int kTrayRetryIntervalMs = 1'000;
constexpr int kTrayRetryLimit = 30;
#endif

} // namespace

TrayController::TrayController(AuthModel *auth, AppBridge *bridge, QObject *parent)
    : QObject(parent)
    , m_auth(auth)
    , m_bridge(bridge)
{
    // Unparented on purpose: a QMenu needs a QWidget parent and this controller
    // is not one, so ownership is manual — see the destructor.
    m_menu = new QMenu();
    m_tray = new QSystemTrayIcon(loadTrayIcon(), this);
    m_tray->setContextMenu(m_menu);

    connect(m_auth, &AuthModel::stateChanged, this, [this] {
        rebuildMenu();
        updateTooltip();
    });
    connect(m_auth, &AuthModel::userChanged, this, [this] {
        rebuildMenu();
        updateTooltip();
    });

    // Every platform: a notification is clickable wherever it is shown, and what
    // it opens is the caller's business.
    connect(m_tray, &QSystemTrayIcon::messageClicked, this, &TrayController::messageClicked);

    // On Windows and most Linux shells a left click on the tray icon is a
    // shortcut to the app, and the menu is on the right button.
    //
    // Not on macOS. There the click *is* how you open the menu, so opening a
    // window as well would put the interface on screen in front of someone who
    // only wanted to see their options — the menu is the whole interaction, and
    // Dashboard and Sign in are items within it.
#ifndef Q_OS_MACOS
    connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason != QSystemTrayIcon::Trigger && reason != QSystemTrayIcon::DoubleClick)
            return;
        if (m_auth->isSignedIn())
            m_bridge->requestDashboard();
        else
            m_bridge->requestLogin();
    });
#endif

    rebuildMenu();
    updateTooltip();
}

TrayController::~TrayController()
{
    delete m_menu;
}

QIcon TrayController::loadTrayIcon()
{
    // Rendered to pixmaps here rather than handed to QIcon as an SVG path: it
    // guarantees crisp output at every menu-bar size without depending on the
    // SVG icon engine plugin being deployed alongside the binary.
    QSvgRenderer renderer(QStringLiteral(":/simorg/branding/simorg-tray.svg"));
    if (!renderer.isValid()) {
        qCWarning(lcApp) << "tray icon resource missing";
        return {};
    }

    QIcon icon;
    for (const int size : kIconSizes) {
        QPixmap pixmap(size, size);
        pixmap.fill(Qt::transparent);
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        renderer.render(&painter);
        painter.end();
        icon.addPixmap(pixmap);
    }

    // macOS tints template images to match the menu bar, light or dark. Other
    // platforms take the silhouette as-is.
#ifdef Q_OS_MACOS
    icon.setIsMask(true);
#endif

    return icon;
}

void TrayController::rebuildMenu()
{
    m_menu->clear();

    if (m_auth->isSignedIn()) {
        const Profile user = m_auth->user();

        QAction *identity = m_menu->addAction(user.displayName);
        identity->setEnabled(false);
        if (!user.email.isEmpty()) {
            QAction *email = m_menu->addAction(user.email);
            email->setEnabled(false);
        }
        m_menu->addSeparator();

        QAction *dashboard = m_menu->addAction(tr("Dashboard"));
        connect(dashboard, &QAction::triggered, m_bridge, &AppBridge::requestDashboard);
        m_menu->setDefaultAction(dashboard);

        QAction *console = m_menu->addAction(tr("Open Simorg in browser"));
        connect(console, &QAction::triggered, m_bridge, &AppBridge::openWebApp);

        m_menu->addSeparator();

        QAction *signOut = m_menu->addAction(tr("Sign out"));
        // Through the bridge, which asks first when agents are running here.
        connect(signOut, &QAction::triggered, m_bridge, &AppBridge::signOut);
    } else {
        QAction *signIn = m_menu->addAction(tr("Sign in…"));
        connect(signIn, &QAction::triggered, m_bridge, &AppBridge::requestLogin);
        m_menu->setDefaultAction(signIn);
    }

    m_menu->addSeparator();

    QAction *quit = m_menu->addAction(tr("Quit Simorg"));
    // NoRole, emphatically. macOS merges role-tagged actions into the
    // application menu, which for a menu-bar item means this one is moved out
    // of the tray menu and — on a build with no application menu — nowhere at
    // all, leaving no way to quit. The app menu has its own Quit; see
    // MenuBarController.
    quit->setMenuRole(QAction::NoRole);
    connect(quit, &QAction::triggered, m_bridge, &AppBridge::quit);

    logMenu();
}

void TrayController::logMenu() const
{
    if (!lcApp().isDebugEnabled())
        return;

    QStringList entries;
    const QList<QAction *> actions = m_menu->actions();
    for (const QAction *action : actions)
        entries << (action->isSeparator() ? QStringLiteral("--") : action->text());

    qCDebug(lcApp) << "tray menu:" << entries.join(QStringLiteral(" | "));
}

void TrayController::updateTooltip()
{
    if (!m_tray)
        return;

    m_tray->setToolTip(m_auth->isSignedIn()
                           ? tr("Simorg — signed in as %1").arg(m_auth->user().displayName)
                           : tr("Simorg — not signed in"));
}

void TrayController::show()
{
    if (QSystemTrayIcon::isSystemTrayAvailable()) {
        m_tray->show();
        m_bridge->setTrayAvailable(true);
        return;
    }

#ifdef Q_OS_LINUX
    /*
      Not an answer yet, on this platform.

      A GNOME or KDE session brings its status-notifier host up around the same
      time as the applications it autostarts, and losing that race would leave
      an app that is running with no icon and no window — see the close handler
      in DashboardWindow, which offers to quit rather than vanish when this
      never becomes true.
    */
    if (!m_retry) {
        m_retry = new QTimer(this);
        m_retry->setInterval(kTrayRetryIntervalMs);
        int attempts = 0;
        connect(m_retry, &QTimer::timeout, this, [this, attempts]() mutable {
            if (QSystemTrayIcon::isSystemTrayAvailable()) {
                m_retry->stop();
                m_tray->show();
                m_bridge->setTrayAvailable(true);
                return;
            }
            if (++attempts >= kTrayRetryLimit) {
                m_retry->stop();
                qCWarning(lcApp) << "no system tray on this desktop after"
                                 << kTrayRetryLimit << "seconds";
            }
        });
        m_retry->start();
    }
#else
    // Common on a bare Linux session with no status-notifier host running.
    // The app still works; it just has no menu-bar entry to open from.
    qCWarning(lcApp) << "no system tray available on this desktop";
#endif

    m_bridge->setTrayAvailable(false);
}

void TrayController::notify(const QString &title, const QString &message)
{
    if (m_tray && m_tray->isVisible() && QSystemTrayIcon::supportsMessages())
        m_tray->showMessage(title, message, QSystemTrayIcon::Information, 4000);
}

} // namespace simorg::app
