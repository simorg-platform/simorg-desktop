// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DesktopUpdateModel.h"
#include "simorg/appmodel/ServiceInstallModel.h"

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include <functional>

class QTimer;

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The pure half of taking Simorg off a computer, kept apart so every rule is
 * tested on every host.
 */
namespace uninstall {

/**
 * The reason codes, in the order the form lists them: the list the platform
 * stores them against. The machine service passes them on untouched.
 */
QStringList reasonCodes();

/** Each reason as the person reads it. */
QString reasonLabel(const QString &code);

/** The longest comment kept (`UNINSTALL_COMMENT_MAX`). */
inline constexpr int commentLimit = 2000;

/** The body of the machine service's `POST /v1/uninstall`. Unknown reason codes are left out. */
QJsonObject requestBody(const QString &source, const QString &desktopVersion, const QStringList &reasons,
                        const QString &comment, bool removeData);

/**
 * Whether a directory may be deleted as Simorg's own: absolute, not the
 * file system's root, not `home` or anything above it, and its last part naming
 * Simorg. A service configured with `SIMORG_CONFIG_DIR=$HOME` names a directory
 * that holds far more than Simorg, and nothing it reports is deleted on trust.
 */
bool deletable(const QString &path, const QString &home);

/**
 * Whether `path` lies inside one of `folders` that may be deleted, and so goes
 * with it: it is neither deleted on its own nor said to be kept. On Windows the
 * service names `…\Simorg\cache` and `…\Simorg\logs`, which `deletable` keeps
 * for their names, inside the `…\Simorg` this app deletes as its own, so they
 * go with it and are not reported as kept.
 */
bool insideDeletable(const QString &path, const QStringList &folders, const QString &home);

/** The directories Simorg Desktop keeps of its own beside the service's, on this computer. */
QStringList desktopDataPaths();

/** One step of the uninstall, in the order it runs. */
enum class Step { Report, SignOut, Images, Service, Data, LoginItems, App };

/** A few words for a step's row. */
QString stepLabel(Step step);

/** The step key a row carries: `report`, `sign_out`, … */
QString stepKey(Step step);

/**
 * The PowerShell that removes Simorg Desktop on Windows once process `pid` has
 * ended: it finds the installed product by `upgradeCode` through Windows
 * Installer's own `RelatedProducts` and runs `msiexec /x` on it, quietly — the
 * package is installed for the person, so no prompt is needed. A running
 * program's files cannot be removed on Windows, which is why this waits. Then it
 * deletes `dataPaths` once more, the folders the person asked to delete: what the
 * running app held or wrote on its way out, Qt's pipeline cache among them, goes
 * with it.
 */
QString windowsSelfRemovalScript(qint64 pid, const QString &upgradeCode, const QStringList &dataPaths = {});

/** Simorg Desktop's Windows installer's upgrade code (`packaging/windows/simorg-desktop.wxs`). */
QString windowsUpgradeCode();

/**
 * Removes this copy of Simorg Desktop, found where `install` says it is: the
 * bundle moved to the Trash on macOS, where it can be taken out again; the
 * AppImage deleted on Linux; and on Windows, whose running program cannot be
 * deleted, the removal handed to `windowsSelfRemovalScript` to run once process
 * `pid` has closed, with `dataPaths` to delete after it. Answers a sentence for
 * the row — what the person still has to do, or when Windows finishes — or
 * nothing when it is done.
 */
QString removeThisCopy(desktopupdate::System system, const desktopupdate::Install &install, qint64 pid,
                       const QStringList &dataPaths = {});

/** {@link removeThisCopy} for the copy of the app `options` describes. */
QString removeInstalledCopy(const DesktopUpdateModel::Options &options, const QStringList &dataPaths = {});

/**
 * Where the Linux install script (`curl -fsSL https://install.simorg.tech/app | sh`)
 * records what it put in place for Simorg Desktop:
 * `$XDG_DATA_HOME/simorg/applications/simorg-desktop.installed`, one path per
 * line — the AppImage, its desktop entry, its icon, and from an older script,
 * the `simorg` and `sim` links of a release before Simorg CLI.
 */
QString scriptInstallRecord();

/**
 * Removes what `record` lists besides the AppImage, which `removeThisCopy` has
 * already deleted, and then the record: the menu entry would otherwise outlive
 * the app it opens. Only files and links inside `home` are touched, whatever the
 * record says, and a missing record removes nothing.
 */
void removeScriptInstall(const QString &record, const QString &home);

} // namespace uninstall

/**
 * Taking Simorg off this computer, as QML reads it off `Uninstall`;
 * Simorg CLI's `sim self uninstall` asks
 * the service for the same steps.
 *
 * Seven steps, each a row that says what it is doing while it does it:
 *
 * 1. **Report** — the reasons ticked and what was written, sent anonymously by
 *    the machine service.
 * 2. **Sign out** — the sweep a person's own sign-out runs, which removes every
 *    agent container.
 * 3. **Agent runtime** — its images, when the person asked for their data to go.
 * 4. **Machine service** — once the service has stopped, the one command it
 *    handed back, run under the system's own password prompt.
 * 5. **Data** — the service's directories and this app's own, each checked with
 *    `uninstall::deletable` first, when the person asked.
 * 6. **Login items** — every one of Simorg's name, and the terminal commands an
 *    older release put in place. Simorg CLI's `sim` is its own and stays.
 * 7. **Simorg Desktop** — the app itself: to the Trash on macOS, the AppImage
 *    deleted on Linux, its own installer's removal on Windows once it has closed.
 *
 * A closed password prompt is an answer, not a failure (`Declined`): the service
 * is stopped but still installed, and the window says so and offers to try
 * again or to close Simorg, which starts the service again when it is next
 * opened. Every other step that cannot finish says why on its
 * row and the uninstall carries on, because half an uninstall that stops at the
 * first leftover is worse than one that removes everything it can and names
 * what it could not.
 *
 * Everything that would change the computer is a part, so a test never shows a
 * password prompt, never deletes a real directory and never trashes the app.
 */
class UninstallModel : public QObject
{
    Q_OBJECT
    /** `[{code, label}]`, in the form's order. */
    Q_PROPERTY(QVariantList reasons READ reasons CONSTANT)
    Q_PROPERTY(int commentLimit READ commentLimit CONSTANT)
    Q_PROPERTY(State state READ state NOTIFY changed)
    /** Whether an uninstall has begun in this launch: the uninstall window stays up from then on. */
    Q_PROPERTY(bool started READ hasStarted NOTIFY changed)
    Q_PROPERTY(bool running READ isRunning NOTIFY changed)
    Q_PROPERTY(bool declined READ wasDeclined NOTIFY changed)
    Q_PROPERTY(bool failed READ hasFailed NOTIFY changed)
    Q_PROPERTY(bool done READ isDone NOTIFY changed)
    /** `[{key, label, state, detail}]`; `state` is `pending`, `running`, `done`, `skipped` or `failed`. */
    Q_PROPERTY(QVariantList steps READ steps NOTIFY changed)
    /** One sentence for what is happening now, or what stopped it. */
    Q_PROPERTY(QString status READ status NOTIFY changed)
    /** What the removal printed, shown, selectable, when it failed. */
    Q_PROPERTY(QString output READ output NOTIFY changed)

public:
    enum State { Idle, Running, Declined, Failed, Done };
    Q_ENUM(State)

    /** What an uninstall needs from the program it runs in, every part replaceable by a test. */
    struct Parts {
        /** `desktop` for the app; Simorg CLI's `sim self uninstall` says `cli`. */
        QString source = QStringLiteral("desktop");
        QString desktopVersion;
        /** `dev` or `prod`: which service's discovery file says whether it has gone. */
        QString environment = QStringLiteral("prod");
        serviceinstall::Platform platform = serviceinstall::thisPlatform();
        QString pkexecPath;
        /** What runs the removal. The app's opens the system's prompt; the command line's runs `sudo`. */
        ServiceInstallModel::Runner runner;
        /** Wraps the service's argv for the runner: the system's prompt by default. */
        std::function<QStringList(const QStringList &argv, const QString &reason)> elevate;
        /** Keeps this app from setting the service up again once it has gone (`ServiceInstallModel::hold`). */
        std::function<void()> holdServiceSetup;
        /** Whether the service has gone: no discovery file naming a live process. */
        std::function<bool()> serviceGone;
        /** Deletes one directory; answers why it could not, or nothing. */
        std::function<QString(const QString &path)> deletePath;
        /** Where the person's home is, which `uninstall::deletable` never lets anything reach. */
        QString home;
        /** This app's own directories, deleted with the service's when the person asks. */
        QStringList desktopDataPaths;
        /** Removes the login items and an older release's terminal commands; answers why not, or nothing. */
        std::function<QString()> removeLoginItems;
        /**
         * Removes this copy of Simorg Desktop; answers why not, or nothing. Absent:
         * nothing to remove. `dataPaths` are the folders the data step deleted, to
         * delete again once the app has gone where only then can they all go
         * (Windows); empty when the data stays.
         */
        std::function<QString(const QStringList &dataPaths)> removeApp;
        /** How long to wait for the service to go once it said `ready`. */
        int goneWithinMs = 30'000;
    };

    UninstallModel(client::ServiceSession *session, Parts parts, QObject *parent = nullptr);

    /** The defaults every program shares: the system's prompt, the discovery file, deletion guarded by `deletable`. */
    static Parts defaultParts(const QString &environment);

    /**
     * Replaces everything the uninstall changes the computer with. A test puts its
     * own here before anything is pressed, so no prompt reaches the screen and
     * nothing real is deleted, unlinked or moved to the Trash.
     */
    void setParts(Parts parts);

    QVariantList reasons() const;
    int commentLimit() const { return uninstall::commentLimit; }
    State state() const { return m_state; }
    bool hasStarted() const { return m_started; }
    bool isRunning() const { return m_state == Running; }
    bool wasDeclined() const { return m_state == Declined; }
    bool hasFailed() const { return m_state == Failed; }
    bool isDone() const { return m_state == Done; }
    QVariantList steps() const;
    QString status() const { return m_status; }
    QString output() const { return m_output; }

public Q_SLOTS:
    /** The person pressed Uninstall, with what they chose. Once. */
    void start(const QStringList &reasons, const QString &comment, bool removeData);
    /** Runs the removal again, after the prompt was closed or the removal failed. */
    void retry();
    /**
     * The person stops after a closed prompt or a removal that failed. Once the
     * service was asked, it has signed out and stopped, still installed, and the
     * app has nothing left to show: `closed` follows, and opening Simorg again
     * starts the service. Before that nothing changed, and the window just goes.
     */
    void close();

Q_SIGNALS:
    void changed();
    /** Everything that could be removed was; the app closes itself. */
    void finished();
    /** The person closed an uninstall that did not finish; the app closes now. */
    void closed();

private:
    void received(const QJsonObject &uninstall);
    void waitForServiceToGo();
    void removeService();
    void finishRemoval();
    void setStep(uninstall::Step step, const QString &state, const QString &detail = {});
    void setState(State state, const QString &status);
    void fail(const QString &status);

    QPointer<client::ServiceSession> m_session;
    Parts m_parts;
    State m_state = Idle;
    bool m_started = false;
    /** The service was asked to uninstall: from then on it signs out and stops, so closing ends the app. */
    bool m_asked = false;
    bool m_removeData = false;
    bool m_ready = false;
    QString m_status;
    QString m_output;
    QStringList m_removal;
    QString m_removalReason;
    QString m_removalUnavailable;
    QStringList m_dataPaths;
    QList<QVariantMap> m_steps;
    QPointer<client::TopicSubscription> m_subscription;
    QTimer *m_goneTimer = nullptr;
    int m_goneWaitedMs = 0;
};

} // namespace simorg::app
