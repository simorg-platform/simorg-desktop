// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/frontend/AutostartService.h"
#include "simorg/frontend/GetDocker.h"
#include "simorg/frontend/SimorgCli.h"

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QUrl>

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

class AvatarCache;

/**
 * The QML layer's window onto the process.
 *
 * Exposed as the `App` singleton. QML never touches QDesktopServices, the tray
 * or the event loop directly — everything the interface can do to the outside
 * world goes through here, which keeps the surface small enough to reason
 * about and lets the whole UI be exercised with this one object stubbed.
 */
class AppBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString serviceVersion READ serviceVersion NOTIFY serviceChanged)
    Q_PROPERTY(bool cliChecked READ cliChecked NOTIFY cliChanged)
    Q_PROPERTY(QString cliVersion READ cliVersion NOTIFY cliChanged)
    Q_PROPERTY(QString agentImage READ agentImage NOTIFY serviceChanged)
    Q_PROPERTY(QString engineVersion READ engineVersion NOTIFY serviceChanged)
    Q_PROPERTY(QString agentImageDigest READ agentImageDigest NOTIFY serviceChanged)
    Q_PROPERTY(QString environment READ environment CONSTANT)
    Q_PROPERTY(QString apiEndpoint READ apiEndpoint NOTIFY serviceChanged)
    Q_PROPERTY(QString websiteUrl READ websiteUrl NOTIFY serviceChanged)
    Q_PROPERTY(QUrl getDockerUrl READ getDockerUrl CONSTANT)
    Q_PROPERTY(bool devMode READ devMode CONSTANT)
    Q_PROPERTY(bool trayAvailable READ trayAvailable NOTIFY trayAvailableChanged)
    Q_PROPERTY(bool autostartSupported READ autostartSupported CONSTANT)
    Q_PROPERTY(bool autostartEnabled READ autostartEnabled NOTIFY autostartChanged)
    Q_PROPERTY(QString autostartLocation READ autostartLocation CONSTANT)
    Q_PROPERTY(QString autostartError READ autostartError NOTIFY autostartChanged)
    Q_PROPERTY(QString hubEndpoint READ hubEndpoint NOTIFY serviceChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion CONSTANT)
    Q_PROPERTY(QUrl accountAvatar READ accountAvatar NOTIFY accountAvatarChanged)
    Q_PROPERTY(bool quitting READ isQuitting NOTIFY quittingChanged)
    Q_PROPERTY(QString leaveQuestion READ leaveQuestion NOTIFY leaveQuestionChanged)
    Q_PROPERTY(bool leaveStopsAgents READ leaveStopsAgents NOTIFY leaveQuestionChanged)

public:
    /**
     * @param environment this build's environment, `dev` or `prod`. The addresses,
     *   links and the agent image come from the Simorg machine service it talks to,
     *   read on every connection.
     */
    AppBridge(client::ServiceSession *session, QString environment, QObject *parent = nullptr);

    QString version() const;
    /**
     * Simorg CLI's version on this computer, or empty: not installed, or not
     * looked for yet, which {@link cliChecked} tells apart. Found by asking the
     * program itself (SimorgCli), not the service, which hears of a copy only
     * once it has registered.
     */
    QString cliVersion() const { return m_cli->version(); }
    bool cliChecked() const { return m_cli->isChecked(); }
    /** Looks for Simorg CLI again; Settings → Overview asks each time it is shown, so one installed since is found. */
    Q_INVOKABLE void checkCli() { m_cli->check(); }
    /**
     * The agent runtime image this build ships with, and the engine inside it.
     *
     * Shown with {@link version}, {@link cliVersion} and {@link serviceVersion}
     * in Settings → Overview, because each moves separately: this program,
     * Simorg CLI, the service, the container an agent runs in, and the engine
     * inside that container. These two are what the service was built with
     * (`GET /v1/version`) rather than what Docker holds, so the panel says the
     * same thing whether or not the daemon is running.
     *
     * What an agent is *actually* running in is the platform's decision and
     * belongs to the Docker section, not to a version screen.
     */
    /**
     * The Simorg machine service's own version, as it reports it (`GET /v1/version`), read again on every
     * connection: it is updated separately from this app, so the two can differ. Empty until it answers.
     */
    QString serviceVersion() const;
    QString agentImage() const;
    QString engineVersion() const;
    /**
     * The digest {@link agentImage} is checked against, shortened for reading.
     *
     * A tag is a name and a name is not a thing: anybody who can reach this
     * computer's Docker daemon can build an image and call it
     * `simorg/agent-runtime:0.1.1`. This is the content address of the image
     * this build was actually made against, and the version screen is where
     * somebody comparing two machines, or reading a "not verified" error, needs
     * to see it.
     *
     * Shortened to twelve hex characters, which is what the error message the
     * reader is likely holding also shows, and which is far past the point of
     * an accidental collision. Empty when this build ships no pin, and the
     * interface omits the row rather than showing an empty one.
     */
    QString agentImageDigest() const;
    QString environment() const;
    QString apiEndpoint() const;
    /**
     * The Simorg website for this estate — what the wordmark opens.
     *
     * Exposed as well as opened so the interface can show where a click will
     * land before it is clicked, the way a browser shows a link target. It
     * follows the environment: the local Next.js server in development, the
     * public site in production.
     */
    QString websiteUrl() const;
    /** Docker's own page for getting Docker, which Simorg never installs itself. */
    QUrl getDockerUrl() const { return QUrl(simorg::getDockerUrl()); }
    /** True when pointed at a development estate — the UI shows a badge for it. */
    bool devMode() const { return m_environment == QLatin1String("dev"); }
    bool trayAvailable() const;
    /** Set by the tray controller once it knows; see {@link trayAvailableChanged}. */
    void setTrayAvailable(bool available);

    /**
     * Whether this build can put Simorg in the computer's startup list.
     *
     * False when there is no mechanism for the platform, and false when the
     * binary the entry would point at cannot be found — the Settings checkbox
     * is disabled rather than offered and then quietly ineffective.
     */
    bool autostartSupported() const;
    bool autostartEnabled() const;
    /** Where the entry lives, shown under the checkbox so it can be undone by hand. */
    QString autostartLocation() const;
    QString autostartError() const;
    /** Returns false and leaves {@link autostartError} set when it did not work. */
    Q_INVOKABLE bool setAutostartEnabled(bool enabled);

    QString hubEndpoint() const;
    /**
     * True when SIMORG_REDUCED_MOTION is set to anything but 0/false.
     *
     * Neither Qt nor any of the three platforms exposes the system's
     * reduce-motion setting to Qt Quick, so this is the escape hatch until one
     * of them does. Theme.motion reads it, and every animation reads Theme.
     */
    bool reducedMotion() const;

    /**
     * The signed-in account's picture, as a round PNG on this disk.
     *
     * Empty until there is one, which is most of the time: an account with no
     * picture, a first run before the file has been fetched, and every moment
     * before anybody signs in. {@link Avatar} falls back to initials on the
     * brand gradient, so empty is a finished state rather than a missing one.
     *
     * Here rather than on `Auth.user` because fetching it and cutting it to a
     * circle both need Qt Gui, and the core library is limited to Core, Network
     * and WebSockets so the CLI can run in a container with no GUI stack
     * installed — the same reason {@link revealPath} is here.
     */
    /** Not const: asking the cache for a face it does not have is what starts fetching it. */
    QUrl accountAvatar();

    /**
     * Whether this app is on its way out.
     *
     * True from the moment Quit is chosen, which is **earlier** than the
     * service's shutdown run appears on `shutdown.state`: asking it to stop is a
     * request over a socket, and on a service that is busy or gone that request
     * can take its time. The window that reports the quit reads this as well as
     * the run, so the seconds before the first frame arrives are not spent
     * looking like a dashboard nobody is leaving.
     */
    bool isQuitting() const { return m_quitting; }
    /** Called by `DesktopApplication` when it starts leaving; there is no way back from it. */
    void setQuitting();

    /**
     * Every picture this app draws, which QML reaches as the `Avatars`
     * singleton: an agent's face on its card is the same cache as the account's
     * in the toolbar. Owned here because this is where the service's addresses
     * and cache directory are already known.
     */
    AvatarCache *avatars() const { return m_avatar; }
    /** Points the cache at whoever is signed in. Driven by `AuthService`. */
    void setAccountAvatar(const QString &url);

    /** Sign-up and password recovery live on the web; open the system browser. */
    Q_INVOKABLE void openSignUp();
    Q_INVOKABLE void openForgotPassword();
    /** The Simorg web application, in the system browser. */
    Q_INVOKABLE void openWebApp();
    /**
     * The third-party notices installed beside this program, for Settings →
     * Licences: the LGPL asks for a prominent notice and the licence text, and
     * this is where both are read from. Empty when the file is not beside the
     * program, which a development build that skipped configure can be.
     */
    Q_INVOKABLE QString thirdPartyNotices() const;
    /** Where that file is, so the person can find it without the app. */
    Q_INVOKABLE QString thirdPartyNoticesPath() const;
    /** The GNU General Public License the program itself is under, from LICENSE beside it. */
    Q_INVOKABLE QString licenceText() const;
    /** Where the source code is published, as the GPL asks. */
    Q_INVOKABLE QUrl sourceRepositoryUrl() const;
    /**
     * The signed-in person's public profile on the web — `/catalogue/<username>`.
     *
     * The handle is passed in rather than read from a session here, because
     * this class deliberately knows nothing about authentication; QML hands it
     * `Auth.user.username`.
     *
     * Nothing about the browser's own session is knowable from this process, so
     * this opens the destination and lets the web application decide: a page
     * that needs a session sends the visitor to `/login?redirect=<path>` and
     * brings them back here once they are in.
     */
    Q_INVOKABLE void openProfile(const QString &username);
    /**
     * The person's Logos with their Machines tab open — where **+** beside a
     * machine puts it on the sheet. The address is the Logos's own
     * (`/in/<username>/logos?account=<username>&tab=machines`); a desktop's
     * machine is its user's, so it is on
     * that tab. Without a username it is `/in`, which the web application answers
     * with whoever is signed in there. The handle comes from QML, as for
     * {@link openProfile}.
     */
    Q_INVOKABLE void openLogosMachines(const QString &username);
    /** The marketing site — the Help menu's "Simorg Website". */
    Q_INVOKABLE void openWebsite();

    /**
     * Opens the terms and privacy window on one of its documents.
     *
     * Routed through the bridge rather than called on the window directly,
     * because the two callers cannot reach it: the tick box lives inside the
     * sign-in window and the Legal panel lives four components deep inside the
     * dashboard, while the window itself is a sibling of both in Main.qml.
     * Every other "show me that window" in this app is a signal from here, and
     * this is one more of them.
     *
     * @param documentId `terms` or `privacy`; anything else opens the first.
     */
    Q_INVOKABLE void openLegal(const QString &documentId = QString());
    Q_INVOKABLE void openExternal(const QUrl &url);

    /**
     * Puts text on the system clipboard.
     *
     * Here rather than in QML because Qt Quick has no clipboard of its own, and
     * because this is the sort of thing that should be countable: everything
     * the interface can push out of the process goes through this one class.
     */
    Q_INVOKABLE void copyToClipboard(const QString &text);

    /**
     * Shows a folder Simorg owns in the platform's file manager.
     *
     * Deliberately narrow: only a directory **inside** Simorg's own cache or
     * work root is opened, and only after being created. A general "open this
     * path" from QML would be a way to launch anything on the disk, and this
     * exists to answer one question — "where did it put my things?" — which
     * never needs more than that.
     *
     * Here rather than on WorkspaceUsage because opening a folder needs Qt Gui,
     * and the core library is limited to Core, Network and WebSockets so the
     * CLI can run in a container with no GUI stack installed.
     */
    Q_INVOKABLE void revealPath(const QString &path);

    /**
     * Asks somebody to point at a folder, using the operating system's own
     * picker.
     *
     * Returns the absolute path, or an empty string when they cancelled —
     * which is an ordinary answer and not an error.
     *
     * The native dialog rather than one drawn in QML, and the reason is trust
     * rather than effort. This is the control through which an agent is given
     * part of somebody's disk, and the window that appears should be the one
     * their operating system shows them for every other program that asks the
     * same thing: their own sidebar, their own recent places, and no chance
     * that a list of folders drawn by Simorg is a list Simorg chose.
     *
     * @param title what the dialog says it is for; the purpose the agent gave
     * @param startAt where to open. Their home folder when empty or gone
     */
    Q_INVOKABLE QString chooseFolder(const QString &title, const QString &startAt = QString());

    /** Closes the windows but leaves the app running behind the tray icon. */
    Q_INVOKABLE void hideToTray();
    /**
     * Asks to quit, rather than quitting.
     *
     * A request rather than an exit because leaving is not instant: the agents'
     * containers have to be stopped first, and somebody has to be told that is
     * what the pause is. `DesktopApplication` turns this into the shutdown
     * sequence, and the process ends when that finishes — after
     * {@link leaveQuestion} when agents are running on this computer.
     */
    Q_INVOKABLE void quit();
    /**
     * {@link quit}, with the question asked whether or not any agent is running:
     * Settings' Quit Simorg, which has always asked first.
     */
    Q_INVOKABLE void askToQuit();
    /**
     * Asks to sign out, from any window, the tray or the menu bar.
     *
     * Here rather than `Auth.signOut` for the same reason {@link quit} is: signing
     * out stops every agent on this computer, and `DesktopApplication` asks first
     * when any is running.
     */
    Q_INVOKABLE void signOut();
    /**
     * Asks to uninstall Simorg with what the person chose on Settings → Uninstall.
     * A request rather than the start,
     * like {@link quit}: uninstalling signs out, which stops every agent here, so
     * `DesktopApplication` asks first when any is running.
     */
    Q_INVOKABLE void uninstall(const QStringList &reasons, const QString &comment, bool removeData);

    /**
     * What leaving is being asked about: `quit`, `signOut`, `uninstall`, or empty when nothing is.
     *
     * Put here by `DesktopApplication` when a Quit, a Sign out or an Uninstall would
     * stop agents on this computer, and read by the dashboard, which asks. The three
     * words are this property's whole vocabulary on both sides of the seam.
     */
    QString leaveQuestion() const { return m_leaveQuestion; }
    /** Whether the question is about agents it would stop, or Settings' plain "Quit Simorg?". */
    bool leaveStopsAgents() const { return m_leaveStopsAgents; }
    /** Called by `DesktopApplication`; a second question replaces the first. */
    void askToLeave(const QString &action, bool stopsAgents);
    /** Takes the question down unanswered, when what it asked about has already happened. */
    void withdrawLeaveQuestion();
    /** The dashboard's answer: yes goes on with {@link leaveConfirmed}, no leaves everything as it was. */
    Q_INVOKABLE void answerLeave(bool confirmed);

    // Called from C++ (tray, single-instance guard) to steer the QML windows.
    /**
     * Puts the environment check in front of everything else.
     *
     * The one window that can appear before there is a session, and the only
     * one that outranks the sign-in window: whether this computer can run an
     * agent is a fact about the computer, and it is settled before anybody is
     * asked for a password. See PreflightModel.
     */
    void requestPreflight();
    /**
     * Puts the window that says Simorg is starting on the screen.
     *
     * What a launch shows while the service is still being reached and the
     * session is still unknown. Neither the sign-in window nor the dashboard can
     * be right yet, and showing one of them anyway is what made a signed-in
     * launch flash a login form; see `DesktopApplication::surfaceWindow` and
     * StartingWindow.qml.
     */
    void requestStarting();
    void requestLogin();
    /**
     * Puts this computer's setup wizard on the screen.
     *
     * Between the sign-in window and the dashboard, and only ever on a machine
     * that owes one: a computer enrols itself the moment somebody signs in on
     * it, and until they have named it the platform will not list it. See
     * MachineSetupModel.
     */
    void requestSetup();
    void requestDashboard();
    /**
     * Opens the dashboard on the screen where permissions are answered.
     *
     * Its own entry point rather than "open the dashboard, then navigate":
     * clicking a notification that says an agent is asking for something has to
     * land on the question, and a window that opened on the last tab somebody
     * happened to be looking at is a click that did nothing.
     */
    void requestAccessManagement();

    /**
     * The same, but for **one agent's** own access screen.
     *
     * Where a permission notification goes. The machine-wide screen sets rules
     * that apply to everything; a request from a particular agent is answered
     * on that agent's page, and landing somebody on the rules instead would be
     * landing them somewhere they have to navigate away from.
     *
     * Falls back to the machine-wide screen when the agent is not known, which
     * happens if the model moved between the notification and the click.
     */
    void requestAgentAccess(int agentId);

Q_SIGNALS:
    /** Somebody chose Quit; `alwaysAsk` from {@link askToQuit}. See {@link quit}. */
    void quitRequested(bool alwaysAsk);
    /** Somebody chose Sign out. See {@link signOut}. */
    void signOutRequested();
    /** Somebody pressed Uninstall on Settings → Uninstall. See {@link uninstall}. */
    void uninstallRequested(const QStringList &reasons, const QString &comment, bool removeData);
    /** The question was answered yes: `quit`, `signOut` or `uninstall` goes ahead. */
    void leaveConfirmed(const QString &action);
    void leaveQuestionChanged();
    /** The service's addresses, links or agent image were read. */
    void serviceChanged();
    /** A look for Simorg CLI finished. See {@link checkCli}. */
    void cliChanged();
    void trayAvailableChanged();
    void autostartChanged();
    void accountAvatarChanged();
    void quittingChanged();
    void showPreflightRequested();
    void showStartingRequested();
    void showLoginRequested();
    void showSetupRequested();
    void showDashboardRequested();
    /** Show the dashboard *and* put it on Settings → Access management. */
    void showAccessManagementRequested();
    /** Show the dashboard *and* open that agent's own access screen. */
    void showAgentAccessRequested(int agentId);
    void hideAllRequested();
    /** Show the terms window, on the document named. */
    void showLegalRequested(const QString &documentId);

private:
    void loadService();
    QJsonObject endpoints() const;
    QString link(const char *key) const;

    client::ServiceSession *m_session;
    bool m_quitting = false;
    QString m_leaveQuestion;
    bool m_leaveStopsAgents = false;
    const QString m_environment;
    /** `GET /v1/config` and `GET /v1/version`, as last read. */
    QJsonObject m_config;
    QJsonObject m_version;
    /**
     * The startup entry for the tray app.
     *
     * Owned here because this is the object QML already talks to for everything
     * that reaches outside the process, and a checkbox that starts a program at
     * login is squarely that.
     */
    AutostartService *m_autostart;
    /** Simorg CLI, looked for on this computer; owned here because running a program is reaching outside. */
    SimorgCli *m_cli;
    /**
     * The signed-in account's picture on this disk.
     *
     * Owned here for the same reason the startup entry is: this is the object
     * the interface already talks to for everything that reaches outside the
     * process, and downloading somebody's photograph is squarely that.
     */
    AvatarCache *m_avatar;
    /** The address of the signed-in account's picture; the cache holds the file. */
    QString m_accountAvatarUrl;
    /**
     * Cached rather than asked each time.
     *
     * `QSystemTrayIcon::isSystemTrayAvailable()` can answer false early in a
     * Linux session and true a moment later, once a status-notifier host is up
     * — so this is what the tray controller has actually observed, and it has a
     * change signal because the interface has to react when it flips.
     */
    bool m_trayAvailable = false;
};

} // namespace simorg::app
