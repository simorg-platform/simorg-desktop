// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "AppBridge.h"

#include "AvatarCache.h"

#include "simorg/client/ServiceSession.h"
#include "simorg/frontend/BuildInfo.h"
#include "simorg/frontend/Logging.h"

#include <QCoreApplication>
#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QGuiApplication>
#include <QSystemTrayIcon>

#include <utility>

namespace simorg::app {

using client::ServiceReply;

AppBridge::AppBridge(client::ServiceSession *session, QString environment, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_environment(std::move(environment))
    , m_autostart(new AutostartService(AutostartTarget::DesktopApp, {}, this))
    , m_cli(new SimorgCli(m_environment, this))
    , m_avatar(new AvatarCache(this))
{
    // The account's own face is one row of the cache like any other; this is the
    // binding QML already had, kept pointing at it.
    connect(m_avatar, &AvatarCache::arrived, this, [this](const QString &url) {
        if (url == m_accountAvatarUrl)
            Q_EMIT accountAvatarChanged();
    });
    connect(m_cli, &SimorgCli::changed, this, &AppBridge::cliChanged);
    connect(m_session, &client::ServiceSession::connected, this, &AppBridge::loadService);
    if (m_session->isConnected())
        loadService();

    // The tray icon is created after this object, so the first answer is
    // whatever the platform says now; TrayController corrects it once it has
    // actually managed to show one.
    m_trayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
}

void AppBridge::loadService()
{
    // Read again on every connection: an upgraded service may have been built with another agent image.
    ServiceReply *config = m_session->get(QStringLiteral("/v1/config"));
    connect(config, &ServiceReply::finished, this, [this, config] {
        if (config->isError() || config->object() == m_config)
            return;
        m_config = config->object();
        m_avatar->configure(endpoints().value(QStringLiteral("api_endpoint")).toString(),
                            m_config.value(QStringLiteral("directories"))
                                .toObject()
                                .value(QStringLiteral("cache_root"))
                                .toString());
        Q_EMIT serviceChanged();
    });
    ServiceReply *version = m_session->get(QStringLiteral("/v1/version"));
    connect(version, &ServiceReply::finished, this, [this, version] {
        if (version->isError() || version->object() == m_version)
            return;
        m_version = version->object();
        Q_EMIT serviceChanged();
    });
}

QJsonObject AppBridge::endpoints() const
{
    return m_config.value(QStringLiteral("endpoints")).toObject();
}

QString AppBridge::link(const char *key) const
{
    return m_config.value(QStringLiteral("links")).toObject().value(QLatin1String(key)).toString();
}

QString AppBridge::version() const
{
    return QStringLiteral(SIMORG_VERSION);
}

QString AppBridge::agentImage() const
{
    return m_version.value(QStringLiteral("agent_image")).toObject().value(QStringLiteral("reference")).toString();
}

QString AppBridge::serviceVersion() const
{
    return m_version.value(QStringLiteral("version")).toString();
}

QString AppBridge::engineVersion() const
{
    return m_version.value(QStringLiteral("agent_image")).toObject().value(QStringLiteral("engine_version")).toString();
}

QString AppBridge::agentImageDigest() const
{
    // Twelve hex characters, which is what an error about an unverified image shows too.
    QString digest =
        m_version.value(QStringLiteral("agent_image")).toObject().value(QStringLiteral("digest")).toString();
    const qsizetype colon = digest.indexOf(QLatin1Char(':'));
    if (colon >= 0)
        digest = digest.mid(colon + 1);
    return digest.left(12);
}

QString AppBridge::apiEndpoint() const
{
    return endpoints().value(QStringLiteral("api_endpoint")).toString();
}

QString AppBridge::hubEndpoint() const
{
    return endpoints().value(QStringLiteral("hub_endpoint")).toString();
}

QString AppBridge::websiteUrl() const
{
    return endpoints().value(QStringLiteral("landing_url")).toString();
}

QUrl AppBridge::accountAvatar()
{
    return m_accountAvatarUrl.isEmpty() ? QUrl() : m_avatar->fileFor(m_accountAvatarUrl);
}

void AppBridge::setAccountAvatar(const QString &url)
{
    const QString wanted = url.trimmed();
    if (wanted == m_accountAvatarUrl)
        return;
    /*
      Cleared rather than left on the last account's picture, which on a shared
      computer would be somebody else's face beside this person's name. The new
      one is asked for at once and arrives when it arrives.
    */
    m_accountAvatarUrl = wanted;
    Q_EMIT accountAvatarChanged();
    if (!wanted.isEmpty())
        m_avatar->fileFor(wanted);
}

QString AppBridge::environment() const
{
    return m_environment;
}

bool AppBridge::trayAvailable() const
{
    return m_trayAvailable;
}

void AppBridge::setTrayAvailable(bool available)
{
    if (m_trayAvailable == available)
        return;
    m_trayAvailable = available;
    qCInfo(lcApp) << "system tray" << (available ? "available" : "unavailable");
    Q_EMIT trayAvailableChanged();
}

bool AppBridge::autostartSupported() const
{
    return m_autostart->isSupported();
}

bool AppBridge::autostartEnabled() const
{
    return m_autostart->isEnabled();
}

QString AppBridge::autostartLocation() const
{
    return m_autostart->location();
}

QString AppBridge::autostartError() const
{
    return m_autostart->lastError();
}

bool AppBridge::setAutostartEnabled(bool enabled)
{
    const bool ok = m_autostart->setEnabled(enabled);
    // Emitted either way: a refused change has to put the checkbox back where
    // it was, and the reason beside it.
    Q_EMIT autostartChanged();
    return ok;
}

bool AppBridge::reducedMotion() const
{
    const QString value = qEnvironmentVariable("SIMORG_REDUCED_MOTION").trimmed().toLower();
    if (value.isEmpty())
        return false;
    return value != QLatin1String("0") && value != QLatin1String("false") && value != QLatin1String("no");
}

void AppBridge::openSignUp()
{
    openExternal(QUrl(link("sign_up_url")));
}

void AppBridge::openForgotPassword()
{
    openExternal(QUrl(link("forgot_password_url")));
}

void AppBridge::openWebApp()
{
    openExternal(QUrl(endpoints().value(QStringLiteral("web_url")).toString()));
}

namespace {

/*
  Where cmake/SimorgNotices.cmake puts the file on each platform, and the build
  tree's bin/ for a development build, which is applicationDirPath there.
*/
QStringList noticeDirectories()
{
    const QDir bin(QCoreApplication::applicationDirPath());
    return {
        bin.absolutePath(),
        bin.absoluteFilePath(QStringLiteral("../Resources")),
        bin.absoluteFilePath(QStringLiteral("../share/licenses/simorg")),
    };
}

QString findBesideProgram(const QString &fileName)
{
    for (const QString &directory : noticeDirectories()) {
        const QFileInfo candidate(QDir(directory).absoluteFilePath(fileName));
        if (candidate.isFile())
            return candidate.absoluteFilePath();
    }
    return {};
}

QString readWholeFile(const QString &path)
{
    if (path.isEmpty())
        return {};
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(file.readAll());
}

} // namespace

QString AppBridge::thirdPartyNoticesPath() const
{
    return findBesideProgram(QStringLiteral("THIRD-PARTY-NOTICES.txt"));
}

QString AppBridge::thirdPartyNotices() const
{
    return readWholeFile(thirdPartyNoticesPath());
}

QString AppBridge::licenceText() const
{
    return readWholeFile(findBesideProgram(QStringLiteral("LICENSE")));
}

QUrl AppBridge::sourceRepositoryUrl() const
{
    return QUrl(QStringLiteral("https://github.com/simorg-platform/simorg-desktop"));
}

void AppBridge::openProfile(const QString &username)
{
    const QString web = endpoints().value(QStringLiteral("web_url")).toString();
    const QString handle = username.trimmed();
    // `/in` resolves to whichever account the browser is signed in as; a handle is encoded, since it arrived in a
    // response and a URL built by concatenation is where that stops being free.
    openExternal(QUrl(handle.isEmpty()
                          ? web + QStringLiteral("/in")
                          : web + QStringLiteral("/catalogue/") + QString::fromUtf8(QUrl::toPercentEncoding(handle))));
}

void AppBridge::openLogosMachines(const QString &username)
{
    const QString web = endpoints().value(QStringLiteral("web_url")).toString();
    const QString handle = username.trimmed();
    if (handle.isEmpty()) {
        openExternal(QUrl(web + QStringLiteral("/in")));
        return;
    }
    const QString owner = QString::fromUtf8(QUrl::toPercentEncoding(handle));
    openExternal(QUrl(web + QStringLiteral("/in/%1/logos?account=%1&tab=machines").arg(owner)));
}

void AppBridge::openWebsite()
{
    openExternal(QUrl(websiteUrl()));
}

void AppBridge::openLegal(const QString &documentId)
{
    Q_EMIT showLegalRequested(documentId.isEmpty() ? QStringLiteral("terms") : documentId);
}

void AppBridge::openExternal(const QUrl &url)
{
    // Only ever open the estate this build is configured for. QML passes URLs
    // built from AppConfig, but this is the one place that reaches outside the
    // process, so it is worth refusing anything unexpected outright.
    if (!url.isValid() || (url.scheme() != QLatin1String("https") && url.scheme() != QLatin1String("http"))) {
        qCWarning(lcApp) << "refusing to open" << url;
        return;
    }

    qCInfo(lcApp) << "opening" << url.toString() << "in the system browser";
    QDesktopServices::openUrl(url);
}

void AppBridge::copyToClipboard(const QString &text)
{
    if (text.isEmpty())
        return;
    QGuiApplication::clipboard()->setText(text);
    qCDebug(lcApp) << "copied" << text.size() << "characters to the clipboard";
}

void AppBridge::revealPath(const QString &path)
{
    const QString wanted = QDir::cleanPath(path);
    if (wanted.isEmpty())
        return;

    /*
      Inside Simorg's own root, or nowhere.

      This is reachable from QML, and QML is a text file inside the application
      bundle — so treating it as a general "open anything" would make one
      writable file into a way to launch whatever is on the disk. Every caller
      wants the cache root or a folder under it, and that is what it opens.
    */
    const QString cacheRoot =
        QDir::cleanPath(m_config.value(QStringLiteral("directories")).toObject().value(QStringLiteral("cache_root")).toString());
    const bool ours = !cacheRoot.isEmpty()
                      && (wanted == cacheRoot || wanted.startsWith(cacheRoot + QLatin1Char('/')));
    if (!ours) {
        qCWarning(lcApp) << "refusing to open" << wanted << "— not a folder Simorg owns";
        return;
    }

    // Created on the way out rather than refused. The natural moment to go and
    // look at the cache folder is before anything has put something in it.
    if (!QDir().mkpath(wanted)) {
        qCWarning(lcApp) << "cannot open" << wanted;
        return;
    }

    QDesktopServices::openUrl(QUrl::fromLocalFile(wanted));
}

QString AppBridge::chooseFolder(const QString &title, const QString &startAt)
{
    QString start = startAt.trimmed();
    if (start.isEmpty() || !QFileInfo(start).isDir())
        start = QDir::homePath();

    /*
      `DontResolveSymlinks` is deliberate.

      A person who picks a link expects the folder they clicked, and resolving
      it would silently share the target instead — which on a Mac is how
      somebody picks a shortcut to their Desktop and shares a volume. What
      Docker eventually does with a link is a separate question and is settled
      by the request's own `followSymlinks`, not here.
    */
    const QString chosen = QFileDialog::getExistingDirectory(
        nullptr, title.isEmpty() ? tr("Choose a folder") : title, start,
        QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);

    // Empty is cancelled, which is a real answer: nothing is chosen and nothing
    // is granted.
    return chosen;
}

void AppBridge::hideToTray()
{
    /*
      Hidden, and nothing is said about it.

      No tray notification saying "Simorg is still running, find it in your menu
      bar": it would be worth saying once, to somebody who had never used the app
      before, and would interrupt the same person every time they closed a
      window, forever, to tell them something they learned the first time.

      A notification is an interruption, and this one would have nothing for
      anybody to do about it. Closing a window is not an event; it is what somebody just
      decided. The menu-bar icon is the answer and it is on screen already.
    */
    Q_EMIT hideAllRequested();
}

void AppBridge::quit()
{
    /*
      Announced, not done.

      `DesktopApplication` listens for this and decides what leaving means: it
      asks the Simorg machine service to stop, shows the run, and leaves when it
      is over.
    */
    Q_EMIT quitRequested(false);
}

void AppBridge::askToQuit()
{
    Q_EMIT quitRequested(true);
}

void AppBridge::signOut()
{
    Q_EMIT signOutRequested();
}

void AppBridge::uninstall(const QStringList &reasons, const QString &comment, bool removeData)
{
    Q_EMIT uninstallRequested(reasons, comment, removeData);
}

void AppBridge::askToLeave(const QString &action, bool stopsAgents)
{
    if (m_leaveQuestion == action && m_leaveStopsAgents == stopsAgents)
        return;
    m_leaveQuestion = action;
    m_leaveStopsAgents = stopsAgents;
    Q_EMIT leaveQuestionChanged();
}

void AppBridge::withdrawLeaveQuestion()
{
    if (m_leaveQuestion.isEmpty())
        return;
    m_leaveQuestion.clear();
    m_leaveStopsAgents = false;
    Q_EMIT leaveQuestionChanged();
}

void AppBridge::answerLeave(bool confirmed)
{
    // Taken down before it is acted on, so the window is already clear when the quitting window or the sign-out
    // strip replaces it.
    const QString action = std::exchange(m_leaveQuestion, QString());
    m_leaveStopsAgents = false;
    if (action.isEmpty())
        return; // a second press on a dialog already fading out
    Q_EMIT leaveQuestionChanged();
    if (confirmed)
        Q_EMIT leaveConfirmed(action);
}

void AppBridge::requestPreflight()
{
    Q_EMIT showPreflightRequested();
}

void AppBridge::setQuitting()
{
    if (std::exchange(m_quitting, true))
        return;
    Q_EMIT quittingChanged();
}

void AppBridge::requestStarting()
{
    qCDebug(lcApp) << "window requested: starting";
    // Somebody opening the app is somebody wanting Simorg, which is what may start a service a client stopped
    // — and the reason this window has a Try again on it at all.
    m_session->resumeService();
    Q_EMIT showStartingRequested();
}

void AppBridge::requestLogin()
{
    // Every route to a window passes through here, so `--verbose` answers
    // "why did the interface just appear?" in one line.
    qCDebug(lcApp) << "window requested: login";
    // A window asked for is somebody wanting Simorg, which starts a service another app stopped.
    m_session->resumeService();
    Q_EMIT showLoginRequested();
}

void AppBridge::requestSetup()
{
    qCDebug(lcApp) << "window requested: machine setup";
    Q_EMIT showSetupRequested();
}

void AppBridge::requestDashboard()
{
    qCDebug(lcApp) << "window requested: dashboard";
    m_session->resumeService();
    Q_EMIT showDashboardRequested();
}

void AppBridge::requestAccessManagement()
{
    qCDebug(lcApp) << "window requested: dashboard (access management)";
    // Both, in this order: the window has to exist before it can be steered, and
    // QML acts on the second by switching tabs on the window the first opened.
    Q_EMIT showDashboardRequested();
    Q_EMIT showAccessManagementRequested();
}

void AppBridge::requestAgentAccess(int agentId)
{
    if (agentId <= 0) {
        // The agent moved between the notification and the click. The rules
        // screen is the honest fallback: it is the other place an answer lives.
        requestAccessManagement();
        return;
    }

    qCDebug(lcApp) << "window requested: agent" << agentId << "(access)";
    Q_EMIT showDashboardRequested();
    Q_EMIT showAgentAccessRequested(agentId);
}

} // namespace simorg::app
