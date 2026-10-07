// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "MenuBarController.h"

#include "AppBridge.h"
#include "simorg/appmodel/AuthModel.h"
#include "simorg/frontend/BuildInfo.h"
#include "simorg/frontend/Logging.h"

#include <QAction>
#include <QGuiApplication>
#include <QKeySequence>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QStringList>
#include <QWindow>

namespace simorg::app {

bool MenuBarController::isSupported()
{
#ifdef Q_OS_MACOS
    return true;
#else
    return false;
#endif
}

MenuBarController::MenuBarController(AuthModel *auth, AppBridge *bridge, QObject *parent)
    : QObject(parent)
    , m_auth(auth)
    , m_bridge(bridge)
{
    build();
    syncToAuthState();

    connect(m_auth, &AuthModel::stateChanged, this, &MenuBarController::syncToAuthState);
}

MenuBarController::~MenuBarController()
{
    // Parentless by design — see the class comment — so ownership is manual.
    delete m_menuBar;
}

void MenuBarController::build()
{
    m_menuBar = new QMenuBar(nullptr);

    // ---- Account -------------------------------------------------------
    QMenu *account = m_menuBar->addMenu(tr("&Account"));

    m_dashboardAction = account->addAction(tr("Dashboard"));
    m_dashboardAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_D));
    connect(m_dashboardAction, &QAction::triggered, m_bridge, &AppBridge::requestDashboard);

    m_signInAction = account->addAction(tr("Sign In…"));
    connect(m_signInAction, &QAction::triggered, m_bridge, &AppBridge::requestLogin);

    QAction *web = account->addAction(tr("Open Simorg in Browser"));
    web->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_L));
    connect(web, &QAction::triggered, m_bridge, &AppBridge::openWebApp);

    account->addSeparator();

    m_signOutAction = account->addAction(tr("Sign Out"));
    // Through the bridge, which asks first when agents are running here.
    connect(m_signOutAction, &QAction::triggered, m_bridge, &AppBridge::signOut);

    // ---- Window --------------------------------------------------------
    QMenu *window = m_menuBar->addMenu(tr("&Window"));

    QAction *minimise = window->addAction(tr("Minimise"));
    minimise->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_M));
    connect(minimise, &QAction::triggered, this, [] { minimiseActiveWindow(); });

    QAction *close = window->addAction(tr("Close"));
    close->setShortcut(QKeySequence::Close);
    connect(close, &QAction::triggered, this, [] { closeActiveWindow(); });

    // ---- Help ----------------------------------------------------------
    // The two About actions are declared here rather than in a menu of their
    // own: macOS moves anything role-tagged into the application menu, and a
    // menu that ends up empty still leaves its title in the bar. Help keeps
    // the website item, so nothing is left hollow.
    QMenu *help = m_menuBar->addMenu(tr("&Help"));

    QAction *website = help->addAction(tr("Simorg Website"));
    connect(website, &QAction::triggered, m_bridge, &AppBridge::openWebsite);

    QAction *about = help->addAction(tr("About Simorg"));
    about->setMenuRole(QAction::AboutRole);
    connect(about, &QAction::triggered, this, &MenuBarController::showAbout);

    // No "About Qt" item. Nothing in the GPL requires one, and Qt's own terms
    // require attribution and a source offer, not a dialog — both of which the
    // About box below and the README already carry. It is a convention worth
    // dropping when the whole app is three menus wide.

    // Quit is not declared here: Qt's Cocoa plugin already puts a working
    // "Quit Simorg" (⌘Q) in the application menu, and a second one tagged
    // QuitRole would merge into the same place.

    if (lcApp().isDebugEnabled()) {
        const QList<QAction *> menus = m_menuBar->actions();
        QStringList titles;
        for (const QAction *menu : menus)
            titles << menu->text();
        qCDebug(lcApp) << "menu bar:" << titles.join(QStringLiteral(" | "))
                       << "(About Simorg moves into the application menu on macOS)";
    }
}

void MenuBarController::syncToAuthState()
{
    const bool signedIn = m_auth->isSignedIn();

    // Shown and hidden rather than enabled and disabled: "Sign Out" greyed out
    // while signed out says less than not offering it at all.
    m_dashboardAction->setVisible(signedIn);
    m_signOutAction->setVisible(signedIn);
    m_signInAction->setVisible(!signedIn);
}

void MenuBarController::showAbout()
{
    const QString body = tr(
        "<h3>Simorg %1</h3>"
        "<p>Agents, artifacts and machines — from your desktop and your terminal.</p>"
        "<p><small>Build %2</small></p>"
        "<p><small>Copyright © 2026 Simorg.<br>"
        "Free software under the "
        "<a href=\"https://www.gnu.org/licenses/gpl-3.0.html\">GNU General Public License v3</a> "
        "or later. There is no warranty, to the extent permitted by law.</small></p>"
        "<p><small>Built with the "
        "<a href=\"https://www.qt.io\">Qt framework</a> %3, used under the GNU GPL v3.</small></p>")
        .arg(QStringLiteral(SIMORG_VERSION), QStringLiteral(SIMORG_GIT_SHA), QStringLiteral(QT_VERSION_STR));

    QMessageBox::about(nullptr, tr("About Simorg"), body);
}

void MenuBarController::minimiseActiveWindow()
{
    if (QWindow *window = QGuiApplication::focusWindow())
        window->showMinimized();
}

void MenuBarController::closeActiveWindow()
{
    // close() runs the window's own onClosing handler, so ⌘W hides to the tray
    // exactly the way clicking the close button does.
    if (QWindow *window = QGuiApplication::focusWindow())
        window->close();
}

} // namespace simorg::app
