// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>

#include <functional>
#include <optional>

class QNetworkAccessManager;
class QNetworkReply;
class QProcess;

namespace simorg::client {
class ServiceReply;
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

class UpdatesModel;

/**
 * The pure half of Simorg Desktop updating itself, kept apart so every rule is
 * tested on every host.
 */
namespace desktopupdate {

enum class System { MacOS, Linux, Windows };

System thisSystem();

/** The `[[driver]]` code simorg.toml publishes for `system` on `cpuArchitecture`, as `QSysInfo` names it. */
QString driverCode(System system, const QString &cpuArchitecture);

/**
 * What an update replaces, found from where the running copy is.
 *
 * Simorg Desktop is published as each system's own installer — a `.dmg`, an
 * `.AppImage`, an `.msi` — and replaces what that installer left: on macOS the
 * app bundle alone, wherever it was dragged and whatever it is called; on Linux
 * the AppImage it was started from; on Windows the folder its installer put it
 * in, which the next installer upgrades in place. Nothing else in the folder is
 * ever touched.
 */
struct Install {
    /** The folder the app is in. */
    QString parent;
    /** What is replaced inside `parent`: the bundle's name (macOS) or the AppImage's (Linux); empty on Windows. */
    QString appName;
    /** Why this copy cannot replace itself, said to the person with its reason; empty when it can. */
    QString reason;
};

/**
 * Where this copy is installed, and whether it may replace itself.
 *
 * `archiveBuild` is `SIMORG_ARCHIVE_BUILD`: only a build made for a published
 * driver replaces itself. A development build and one installed from source by
 * `install.sh` are updated the way they were built. `appImagePath` is the
 * AppImage a Linux copy was started from, which the AppImage itself sets as
 * `APPIMAGE`; a Linux copy without one was not installed from its driver.
 */
Install locate(System system, const QString &applicationDirPath, bool archiveBuild,
               const QString &appImagePath = QString());

/** The latest release's driver for one computer, from the platform's artifact answer. */
struct Release {
    QString tag;
    QString artifactId;
    QString driverId;
    QString sha256;
    qint64 size = -1;
};

/**
 * The driver for `code` in a `GET /api/v1/machine/artifact` answer. Nothing when
 * the answer names no release or no driver for `code`; `why` then says which, for
 * the row.
 */
std::optional<Release> releaseFor(const QJsonObject &artifact, const QString &code, QString *why);

/** The `version` line of a `BUILD-INFO.txt`, or empty. */
QString buildInfoVersion(const QByteArray &buildInfo);

/** Semantic Versioning precedence of two versions: negative, zero or positive. Unparsable text sorts first. */
int compareVersions(const QString &left, const QString &right);

/** A word as POSIX `sh` reads it back unchanged: in single quotes, each quote closed and escaped. */
QString shellQuoted(const QString &word);

/** The hand-over script this system runs (`desktop-handover.sh`, or `.ps1` on Windows), as text. */
QByteArray handoverScript(System system);

/** Where the hand-over note is: both versions read it, the script writes it. */
QString defaultNotePath();

/**
 * Where `install` is, as the person would recognise it: the bundle, the AppImage, or the folder on Windows;
 * `applicationDirPath` when the copy cannot say.
 */
QString installLocation(System system, const Install &install, const QString &applicationDirPath);

/**
 * The words that start `install`'s own program, which the machine service runs followed by `update desktop --json`
 * to update the app while it is closed (HeadlessUpdate.h): `Simorg.app/Contents/MacOS/Simorg`, the
 * AppImage, or `simorg-desktop.exe` in the app's folder. Empty for a copy that cannot replace itself.
 */
QStringList commandLine(System system, const Install &install);

/**
 * Whether Simorg Desktop from `install` is open: its own program, other than this process and what started it, which
 * is the update with no window when that asks (HeadlessUpdate.h). That update refuses to replace an app that is open,
 * because replacing a running app's files would break it.
 */
bool desktopRunning(System system, const Install &install);

} // namespace desktopupdate

/**
 * Simorg Desktop updating itself:
 * the app's own row in Settings → Updates, fed to `UpdatesModel::setDesktopRow`.
 *
 * **Check.** The platform's address comes from the service (`GET /v1/config`), the
 * artifact from the platform (`simorg_desktop_artifact_specifier`), and the
 * release and its checksum from the artifact's public answer; nothing about which
 * artifact the app is is compiled in. At start, every six hours, and whenever the
 * Updates view opens.
 *
 * **Update**, on the person's press only. The driver — this system's own
 * installer — is downloaded beside the install and its size and SHA-256
 * compared with the platform's. On macOS the new bundle is copied out of the
 * disk image, and on Linux the AppImage made runnable, and the `BUILD-INFO.txt`
 * each carries must name the tag. A small script is then started on its own: it
 * waits for this process to end, moves the old copy aside and the new one into
 * place (on Windows, runs the new installer, which upgrades the old one), and
 * opens it. The app then **closes its own process only** (`exitRequested`),
 * never Quit Simorg, which would stop the service and every agent.
 *
 * **Result.** The new version writes `started` in the hand-over note as it opens;
 * without that within 30 seconds the script puts the old version back — on
 * Windows, where the installer has already replaced it, says so instead — and
 * says why in the note. Whichever version opens reads the note and shows the
 * outcome on its row.
 */
class DesktopUpdateModel : public QObject
{
    Q_OBJECT

public:
    struct Options {
        QString applicationDirPath;
        /** The AppImage a Linux copy was started from (`APPIMAGE`); empty anywhere else. */
        QString appImagePath;
        /** The file the app runs as, which Windows opens again once the new version is in place. */
        QString executableName;
        desktopupdate::System system = desktopupdate::System::MacOS;
        QString cpuArchitecture;
        bool archiveBuild = false;
        QString version;
        QString notePath;
        qint64 processId = 0;
        /** The platform's API, when a test sets it; otherwise the service's `api_endpoint`. */
        QString platformApi;
        /** Where the download is staged when the install's own folder cannot be written. */
        QString fallbackStaging;
        /** How long the script waits for the new version to say it started, in seconds. */
        int startedWithinSeconds = 30;
        /** Whether a check runs by itself (at start and every six hours); tests call `check()` themselves. */
        bool checkOnItsOwn = true;
        /**
         * Whether the new version is opened once it is in place, and the old one put back if it does not start.
         * The command line says no: it may run where nobody sees a window, and nothing was open to reopen.
         */
        bool reopen = true;
        /**
         * Whether the hand-over runs on its own after this process closes (`exitRequested`). The command line on
         * macOS and Linux says no: it waits for the move and says how it went (`handedOver`), because a file
         * that is running there can be replaced. Windows cannot replace a running program, so there it is
         * always on its own.
         */
        bool detached = true;
        /**
         * `app` or `cli`: what this copy registers itself as with the machine service, which then checks
         * its release for every screen.
         */
        QString client = QStringLiteral("app");
        /**
         * Whether this is the open app, subscribed to `updates.desktop_requested`: the service knows the app is open
         * by that subscription, so the command line never takes it.
         */
        bool announceOpen = true;
        /** Whether an update somebody asked for and this copy prepared is applied as this copy starts. */
        bool applyPreparedAtStart = true;
        /** Whether a release found is downloaded and unpacked ahead of any Update; the command line says no. */
        bool prepareAhead = true;
        /**
         * How the command line, which holds no ServiceSession, sends the service a request: the registration and the
         * progress reports. Unused while a session is given.
         */
        std::function<client::ServiceReply *(const QByteArray &method, const QString &path, const QJsonObject &body)>
            serviceRequest;
    };

    /** This process, as it runs: `archiveBuild` stays for the caller, which can read `SIMORG_ARCHIVE_BUILD`. */
    static Options defaults();

    DesktopUpdateModel(client::ServiceSession *session, UpdatesModel *updates, Options options,
                       QObject *parent = nullptr);
    ~DesktopUpdateModel() override;

    /** The row as `UpdatesModel` shows it; exposed for tests. */
    QJsonObject row() const;

    /** The hand-over note's result this version read as it started, for tests. */
    QJsonObject lastUpdate() const { return m_lastUpdate; }

    /** Where this copy is, and why it cannot replace itself when it cannot. */
    const desktopupdate::Install &install() const { return m_install; }

    /** Whether a check has answered, found a release or said why there is none. */
    bool checked() const { return m_checked || !m_reason.isEmpty(); }

    /** Whether the machine service checks this copy's release (API 1.3), rather than the copy itself. */
    bool serviceChecks() const { return m_serviceChecks; }

    /** Whether the update is downloaded, checked and unpacked, waiting only for the hand-over. */
    bool prepared() const;

public Q_SLOTS:
    void check();
    void start();
    void cancel();
    /** Tells the machine service which copy this is; `registered` says whether it takes it. */
    void registerInstallation();
    /** The service's `desktop` item: the release on offer, its notes, and whether it is required. */
    void applyServiceItem(const QJsonObject &item);
    /** The person pressed Restart to finish updating: the prepared update is handed over now. */
    void restartToFinish();

Q_SIGNALS:
    /** Everything is handed over: close this process now, and only this process. */
    void exitRequested();
    /** This version has just been opened by an update, to show the person how it went. */
    void finishedUpdate();
    /** The row changed. */
    void changed();
    /** A hand-over that was not detached has ended; `lastUpdate()` or the row's failure says how. */
    void handedOver(bool succeeded);
    /** The service answered the registration: `supported` when it checks this copy's release. */
    void registered(bool supported);

private:
    enum class Phase { Idle, Downloading, Verifying, Unpacking, HandingOver, ReadyToRestart };

    /** Downloads, checks and unpacks the release: in the background, or as the update somebody asked for. */
    void prepare(bool background);
    /** The download is unpacked and checked: handed over, offered as a restart, or kept for later. */
    void preparedNow();
    /** Somebody asked for the update elsewhere; it is prepared and offered as a restart, never forced. */
    void onRequested(const QJsonObject &request);
    /** Says how the update is going to the service, so every screen shows it. */
    void report();
    void writePrepared(bool accepted);
    QJsonObject readPrepared() const;
    /** A request to the service, through the session or the command line's own client; nothing without either. */
    client::ServiceReply *toService(const QByteArray &method, const QString &path, const QJsonObject &body);

    void readNote();
    void withPlatform(const std::function<void(const QString &api)> &then);
    void onDownloadChunk();
    void onDownloaded();
    void openDownload();
    void handOver();
    void fail(const QString &message, const QString &output = {});
    void setPhase(Phase phase, const QString &message);
    void publish();
    QString stagingFolder() const;
    void clearStaging();

    client::ServiceSession *m_session;
    QPointer<UpdatesModel> m_updates;
    Options m_options;
    desktopupdate::Install m_install;
    QNetworkAccessManager *m_network;
    QTimer m_every;

    std::optional<desktopupdate::Release> m_release;
    QString m_api;
    QString m_reason;
    bool m_checked = false;

    Phase m_phase = Phase::Idle;
    QString m_message;
    double m_progress = -1;
    QString m_failure;
    QString m_output;
    QJsonObject m_lastUpdate;

    /** The service checks this copy's release; the copy's own check is only for an older service. */
    bool m_serviceChecks = false;
    QJsonArray m_notes;
    bool m_required = false;
    QString m_minimum;
    /** A download ahead of any Update, shown as the row's `download` rather than as an update. */
    bool m_background = false;
    QString m_downloadState = QStringLiteral("idle");
    /** Once prepared, hand over at once (the person pressed Update here) rather than offer a restart. */
    bool m_applyWhenPrepared = false;
    /** Somebody asked for this update, here or elsewhere, so it is applied at the next start at the latest. */
    bool m_accepted = false;
    /** The operation id the service named in `updates.desktop_requested`; empty for a press here. */
    QString m_requestId;
    QJsonObject m_lastReport;
    /** A release whose download ahead failed: not tried again until another is on offer, or Update is pressed. */
    QString m_aheadFailedTag;
    client::TopicSubscription *m_requests = nullptr;

    QPointer<QNetworkReply> m_download;
    /** The downloaded installer. */
    QFile m_archive;
    QCryptographicHash m_hash{QCryptographicHash::Sha256};
    qint64 m_received = 0;
    QPointer<QProcess> m_opening;
};

} // namespace simorg::app
