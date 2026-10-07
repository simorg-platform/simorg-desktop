// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>

#include <functional>
#include <optional>

class QNetworkAccessManager;
class QProcess;

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

/**
 * The pure half of installing the Simorg machine service from this app, kept apart
 * so every platform's command line is tested on every host.
 */
namespace serviceinstall {

enum class Platform { MacOS, Linux, Windows };

Platform thisPlatform();

/** `https://install.simorg.tech/simorgm`, or `SIMORG_INSTALL_URL` for a test against a local copy. */
QString installScriptUrl();

/** `https://download.simorg.tech`, or `SIMORG_DOWNLOAD_HOST`, as the install script reads it too. */
QString downloadHost();

/** What a person types into a terminal on macOS or Linux: `curl -fsSL <url> | sh`. */
QString terminalCommand(const QString &scriptUrl);

/**
 * The shell text that fetches the install script to a temporary file and runs it.
 *
 * Not `curl … | sh`: a pipe's status is the shell's, and a shell handed an empty
 * script because the download failed exits 0, which would report an install that
 * never happened. `downloadHost` is passed on to the script only when it is not
 * the default, which is what a test against a local copy needs.
 */
QString fetchAndRunScript(const QString &scriptUrl, const QString &downloadHost);

/**
 * The program and arguments that run `fetchAndRunScript` under the operating
 * system's own administrator prompt: `osascript … with administrator
 * privileges` on macOS, `pkexec /bin/sh -c …` on Linux. Empty on Windows, which
 * has no shell to run the script in, and on Linux without `pkexec`.
 *
 * The same prompts the machine service uses for the steps that need an
 * administrator, so a person meets one
 * kind of dialog from Simorg, and the password never reaches this app.
 */
QStringList scriptUnderPrompt(Platform platform, const QString &script, const QString &pkexecPath);

/** The newest Windows package in the release index, `binaries/simorgm/index.json`. */
struct WindowsPackage {
    QString version;
    QString name;
    QString sha256;
    qint64 size = 0;
    QUrl url;
};

/**
 * The newest version with an `.msi` for `target` — `windows/x64` or
 * `windows/arm64`, as packageTarget() says — from the release index on the
 * download host; nothing when there is none or the document is not an index. The file name is the index's, never guessed.
 */
std::optional<WindowsPackage> newestWindowsPackage(const QByteArray &indexJson, const QString &downloadHost,
                                                   const QString &target);

/**
 * PowerShell running `msiexec /i <msi> /passive /norestart` with `-Verb RunAs`, so
 * Windows shows its own consent prompt, and exiting with msiexec's code.
 */
QStringList msiUnderPrompt(const QString &msiPath);

/**
 * Where this computer's package sits in the release index: `macos/universal`,
 * `linux/arm64` or `linux/x64`, `windows/x64` or `windows/arm64` — the `<os>/<arch>`
 * level of the release index.
 */
QString packageTarget(Platform platform, const QString &cpuArchitecture);

/** Whether the release index names at least one file for `target`, in any version. */
bool publishedFor(const QByteArray &indexJson, const QString &target);

/**
 * The program and arguments that run `argv` — a program and its arguments, never
 * a shell line — under the operating system's own administrator prompt, showing
 * `reason` where the prompt can: `osascript … with administrator privileges with
 * prompt` on macOS, `pkexec` on Linux, Windows' consent prompt through
 * PowerShell's `Start-Process -Verb RunAs`, exiting with the program's own code.
 * Empty on Linux without `pkexec`. What Uninstall Simorg removes the machine
 * service's package with.
 */
QStringList argvUnderPrompt(Platform platform, const QStringList &argv, const QString &reason,
                            const QString &pkexecPath);
/** Whether an msiexec exit code is an install that happened: 0, or 3010 (done, restart pending). */
bool msiSucceeded(int exitCode);

/** macOS's "User canceled" (-128) in osascript's error text, or pkexec's dismissed dialog (126). */
bool promptDismissed(Platform platform, int exitCode, const QString &output);

/**
 * The runner every model here uses unless a test gives its own: the command as a
 * process owned by `owner`, under whatever prompt it opens itself, its output
 * passed on as it arrives and the process deleted once it has ended.
 */
std::function<void(std::function<void(const QString &)> output, std::function<void(int, const QString &)> done,
                   const QStringList &argv)>
processRunner(QObject *owner);
} // namespace serviceinstall

/**
 * Setting up the Simorg machine service when this app finds none, as QML reads it
 * off `ServiceInstall`.
 *
 * Simorg Desktop is a front end of the machine service and does nothing without
 * it, so a computer that has the app and not the service gets the service from
 * here, **by itself**: the moment the session reports the service is not on this
 * computer, the setup starts, and the only question a person meets is the
 * operating system's own administrator prompt. It starts once per launch; after
 * the prompt was closed, or the setup
 * failed, starting it again is the person's press.
 *
 * On macOS and Linux it runs `install.simorg.tech/simorgm`, the same script a
 * terminal runs, under the system's administrator prompt; on Windows, which has
 * no shell for it, it downloads the MSI the release index names, checks its
 * SHA-256 and runs it under Windows' own consent prompt. The service stays a
 * download of its own rather than part of this app. Every step says what it is doing while it happens, what the installer
 * printed is kept for when it fails, and on success the session is asked to
 * reach the service at once.
 *
 * Only a production build sets it up: a development build talks to the service
 * built from simorg-machine (`simorgm service install`), which no published
 * package provides. Linux without `pkexec` cannot show a password prompt, so it
 * gets the terminal command instead.
 */
class ServiceInstallModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ isAvailable CONSTANT)
    /** Why the setup cannot run from here, when it cannot; empty otherwise. */
    Q_PROPERTY(QString unavailableReason READ unavailableReason CONSTANT)
    /**
     * The terminal command that does the same, only where this app cannot: a
     * production build on Linux without `pkexec`. Empty everywhere else, where
     * the setup runs by itself or, in a development build, is not this app's.
     */
    Q_PROPERTY(QString terminalCommand READ terminalCommand CONSTANT)
    Q_PROPERTY(State state READ state NOTIFY changed)
    /** The state as flags, for bindings that read better without the enum. */
    Q_PROPERTY(bool running READ isRunning NOTIFY changed)
    Q_PROPERTY(bool succeeded READ hasSucceeded NOTIFY changed)
    Q_PROPERTY(bool declined READ wasDeclined NOTIFY changed)
    Q_PROPERTY(bool failed READ hasFailed NOTIFY changed)
    /** Whether a setup has started in this launch, so the window keeps its step once it is done. */
    Q_PROPERTY(bool attempted READ wasAttempted NOTIFY changed)
    /** One sentence for what is happening now, or what stopped it. */
    Q_PROPERTY(QString status READ status NOTIFY changed)
    /** A few words for the setup's row in the window's checklist. */
    Q_PROPERTY(QString step READ step NOTIFY changed)
    /** Everything the installer printed, as it arrived; shown, selectable, when it failed. */
    Q_PROPERTY(QString output READ output NOTIFY changed)

public:
    /** `Declined`: the person closed the operating system's prompt, which is an answer, not a failure. */
    enum State { Idle, Running, Succeeded, Declined, Failed };
    Q_ENUM(State)

    /**
     * What runs a command under the operating system's prompt.
     *
     * `output` takes text as it arrives; `done` is called once, with the exit code,
     * or with -1 and a sentence when the command could not be started at all. The
     * default starts a QProcess. A test puts one of its own here, so nothing a test
     * does ever puts an administrator prompt on the screen of whoever runs it.
     */
    struct Launch {
        QStringList argv;
        std::function<void(const QString &text)> output;
        std::function<void(int exitCode, const QString &problem)> done;
    };
    using Runner = std::function<void(Launch launch)>;

    /**
     * What is checked, without any prompt, before the operating system asks for a
     * password on macOS and Linux: that the install script is there and that the
     * release index names a package for this computer. `done` takes an empty
     * reason when both are, and otherwise the reason as the start of a sentence,
     * which the caller finishes with what it means there: after a press, that
     * nothing was installed and no password asked for; on the Updates row, that
     * the service cannot be updated from here yet. Nobody is asked for a password
     * for a setup that cannot succeed. The default reads both over the network; a
     * test puts one of its own here.
     */
    using Preflight = std::function<void(std::function<void(const QString &problem)> done)>;

    ServiceInstallModel(client::ServiceSession *session, const QString &environment, QObject *parent = nullptr);

    bool isAvailable() const { return m_unavailableReason.isEmpty(); }
    QString unavailableReason() const { return m_unavailableReason; }
    QString terminalCommand() const;
    State state() const { return m_state; }
    bool isRunning() const { return m_state == Running; }
    bool hasSucceeded() const { return m_state == Succeeded; }
    bool wasDeclined() const { return m_state == Declined; }
    bool hasFailed() const { return m_state == Failed; }
    bool wasAttempted() const { return m_attempted; }
    QString status() const { return m_status; }
    QString step() const;
    QString output() const { return m_output; }

    /** Replaces what runs the command under the prompt; see `Launch`. */
    void setRunner(Runner runner);
    /** Replaces the check made before the prompt; see `Preflight`. */
    void setPreflight(Preflight preflight);
    /**
     * The same check, for somebody deciding whether to offer the setup at all (the
     * Updates row for a service too old to update itself). Windows needs no
     * script, so there it passes.
     */
    void checkPublished(const std::function<void(const QString &problem)> &done);
    /** How long the window is on screen before the prompt covers it; shortened by tests. */
    void setLead(int milliseconds) { m_leadMs = milliseconds; }

public Q_SLOTS:
    /**
     * Starts the setup: once per launch, and only where it is this app's to do.
     * Called when the session finds no service, so a person never presses
     * anything for the ordinary case.
     */
    void setUp();
    /** Starts it again, after the prompt was closed or the setup failed; the button's action. */
    void install();
    /**
     * Simorg is being uninstalled: the
     * service's disappearing is the point, so the setup never starts by itself
     * again in this launch. A press of Install still works, which is what Keep
     * Simorg on the uninstall window relies on when the person changes their mind.
     */
    void hold();

Q_SIGNALS:
    void changed();

private:
    void start(int leadMs);
    void begin();
    QString askingSentence() const;
    void runUnderPrompt(const QStringList &argv);
    void installOnWindows();
    void finished(int exitCode);
    void fail(const QString &status);
    void append(const QString &text);
    void setState(State state, const QString &status);

    client::ServiceSession *m_session;
    serviceinstall::Platform m_platform;
    QString m_environment;
    QString m_pkexec;
    QString m_unavailableReason;
    State m_state = Idle;
    bool m_attempted = false;
    bool m_held = false;
    bool m_downloading = false;
    int m_leadMs = 1200;
    QElapsedTimer m_succeededAt;
    QString m_status;
    QString m_output;
    Runner m_runner;
    Preflight m_preflight;
    QNetworkAccessManager *m_network = nullptr;
};

} // namespace simorg::app
