// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#include "simorg/appmodel/DesktopUpdateModel.h"

#include "EmbeddedHandover.h"
#include "simorg/appmodel/ServiceInstallModel.h"
#include "simorg/appmodel/UpdatesModel.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>
#include <QUrlQuery>

#include <chrono>

#ifndef Q_OS_WIN
#include <unistd.h>
#endif

namespace simorg::app {

using client::ServiceReply;
using client::ServiceSession;

namespace desktopupdate {

namespace {

/** The id the platform writes as a string, or as a number in an older answer. */
QString idOf(const QJsonValue &value)
{
    return value.isString() ? value.toString() : QString::number(value.toInteger());
}

QString installUnknown()
{
    return QObject::tr("Simorg Desktop cannot tell where it was installed, so it cannot replace itself. "
                       "Download the new version from its page and install it over this one.");
}

/** One dot-separated part of a pre-release, compared as Semantic Versioning §11 compares them. */
int compareIdentifiers(const QString &left, const QString &right)
{
    bool leftNumber = false;
    bool rightNumber = false;
    const qulonglong leftValue = left.toULongLong(&leftNumber);
    const qulonglong rightValue = right.toULongLong(&rightNumber);
    if (leftNumber && rightNumber)
        return leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : 0;
    if (leftNumber != rightNumber)
        return leftNumber ? -1 : 1;
    return QString::compare(left, right, Qt::CaseSensitive) < 0 ? -1 : left == right ? 0 : 1;
}

struct Parsed {
    bool valid = false;
    qulonglong core[3] = {0, 0, 0};
    QStringList preRelease;
};

Parsed parse(const QString &text)
{
    static const QRegularExpression kVersion(
        QStringLiteral("^v?(\\d+)\\.(\\d+)\\.(\\d+)(?:-([0-9A-Za-z.-]+))?(?:\\+[0-9A-Za-z.-]+)?$"));
    const QRegularExpressionMatch match = kVersion.match(text.trimmed());
    Parsed parsed;
    if (!match.hasMatch())
        return parsed;
    for (int part = 0; part < 3; ++part)
        parsed.core[part] = match.captured(part + 1).toULongLong();
    if (match.hasCaptured(4))
        parsed.preRelease = match.captured(4).split(QLatin1Char('.'));
    parsed.valid = true;
    return parsed;
}

} // namespace

System thisSystem()
{
#if defined(Q_OS_MACOS)
    return System::MacOS;
#elif defined(Q_OS_WIN)
    return System::Windows;
#else
    return System::Linux;
#endif
}

QString driverCode(System system, const QString &cpuArchitecture)
{
    const bool arm = cpuArchitecture.startsWith(QLatin1String("arm")) || cpuArchitecture == QLatin1String("aarch64");
    switch (system) {
    case System::MacOS:
        return arm ? QStringLiteral("BINARY_MAC_APPLE_SILICON") : QStringLiteral("BINARY_MAC_X64");
    case System::Linux:
        return arm ? QStringLiteral("BINARY_LINUX_ARM") : QStringLiteral("BINARY_LINUX_X64");
    case System::Windows:
        return arm ? QStringLiteral("BINARY_WINDOWS_ARM") : QStringLiteral("BINARY_WINDOWS_X64");
    }
    return {};
}

Install locate(System system, const QString &applicationDirPath, bool archiveBuild, const QString &appImagePath)
{
    Install install;
    if (!archiveBuild) {
        install.reason = QObject::tr("This copy of Simorg Desktop was built from source, so it is updated the way it "
                                     "was built: from the new source, built again.");
        return install;
    }
    const QString folder = QDir::cleanPath(QDir::fromNativeSeparators(applicationDirPath));

    if (system == System::MacOS) {
        if (folder.contains(QLatin1String("/AppTranslocation/"))) {
            install.reason = QObject::tr("Move Simorg into your Applications folder and open it from there to update "
                                         "it, because macOS runs an app opened straight from a download from a "
                                         "temporary copy that cannot be changed.");
            return install;
        }
        // …/Name.app/Contents/MacOS: the app, open or updating itself with no window.
        QDir bundle(folder);
        if (bundle.dirName() != QLatin1String("MacOS") || !bundle.cdUp() ||
            bundle.dirName() != QLatin1String("Contents") || !bundle.cdUp() ||
            !bundle.dirName().endsWith(QLatin1String(".app"))) {
            install.reason = installUnknown();
            return install;
        }
        // The bundle alone, under whatever name the person gave it, and nothing else in its folder.
        install.appName = bundle.dirName();
        QDir parent = bundle;
        parent.cdUp();
        install.parent = parent.absolutePath();
        return install;
    }

    if (system == System::Linux) {
        // The AppImage it was started from: the program itself runs from a mount that goes when it ends.
        const QFileInfo image(appImagePath);
        if (appImagePath.isEmpty() || !image.isAbsolute() || !image.isFile()) {
            install.reason = QObject::tr("This copy of Simorg Desktop was not started from its AppImage, so it cannot "
                                         "replace itself. Download the new version from its page and open that.");
            return install;
        }
        install.parent = image.absolutePath();
        install.appName = image.fileName();
        return install;
    }

    // Windows: the folder its installer put it in, which carries the build's note beside the program.
    if (!QFileInfo::exists(QDir(folder).filePath(QStringLiteral("BUILD-INFO.txt")))) {
        install.reason = installUnknown();
        return install;
    }
    install.parent = QDir(folder).absolutePath();
    return install;
}

std::optional<Release> releaseFor(const QJsonObject &artifact, const QString &code, QString *why)
{
    const QString tag = artifact.value(QStringLiteral("version")).toObject().value(QStringLiteral("tag")).toString();
    if (tag.isEmpty()) {
        if (why)
            *why = QObject::tr("Simorg Desktop is not published on this Simorg yet, so there is nothing to update to.");
        return std::nullopt;
    }
    static const QRegularExpression kSha256(QStringLiteral("^[0-9a-f]{64}$"));
    for (const QJsonValue &value : artifact.value(QStringLiteral("drivers")).toArray()) {
        const QJsonObject driver = value.toObject();
        if (driver.value(QStringLiteral("category_codename")).toString() != code)
            continue;
        const QJsonObject file = driver.value(QStringLiteral("file")).toObject();
        const QString sha256 = file.value(QStringLiteral("sha256")).toString().toLower();
        if (!kSha256.match(sha256).hasMatch()) {
            if (why)
                *why = QObject::tr("Version %1 carries no checksum for this computer's download, so Simorg Desktop "
                                   "will not install it: a download it cannot check could be anything.")
                           .arg(tag);
            return std::nullopt;
        }
        Release release;
        release.tag = tag;
        release.artifactId = idOf(artifact.value(QStringLiteral("id")));
        release.driverId = idOf(driver.value(QStringLiteral("id")));
        release.sha256 = sha256;
        const QJsonValue size = file.value(QStringLiteral("size_bytes"));
        release.size = size.isDouble() ? qint64(size.toDouble()) : -1;
        return release;
    }
    if (why)
        *why = QObject::tr("Version %1 has no download for this computer (%2) yet, so there is nothing to install here.")
                   .arg(tag, code);
    return std::nullopt;
}

QString buildInfoVersion(const QByteArray &buildInfo)
{
    static const QRegularExpression kLine(QStringLiteral("^\\s*version\\s+(\\S+)\\s*$"),
                                          QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = kLine.match(QString::fromUtf8(buildInfo));
    return match.hasMatch() ? match.captured(1) : QString();
}

int compareVersions(const QString &left, const QString &right)
{
    const Parsed a = parse(left);
    const Parsed b = parse(right);
    if (a.valid != b.valid)
        return a.valid ? 1 : -1;
    if (!a.valid)
        return 0;
    for (int part = 0; part < 3; ++part) {
        if (a.core[part] != b.core[part])
            return a.core[part] < b.core[part] ? -1 : 1;
    }
    // A release outranks any pre-release of it.
    if (a.preRelease.isEmpty() || b.preRelease.isEmpty())
        return a.preRelease.isEmpty() == b.preRelease.isEmpty() ? 0 : a.preRelease.isEmpty() ? 1 : -1;
    for (qsizetype index = 0; index < qMin(a.preRelease.size(), b.preRelease.size()); ++index) {
        if (const int order = compareIdentifiers(a.preRelease.at(index), b.preRelease.at(index)); order != 0)
            return order;
    }
    return a.preRelease.size() < b.preRelease.size() ? -1 : a.preRelease.size() > b.preRelease.size() ? 1 : 0;
}

QString shellQuoted(const QString &word)
{
    QString quoted = word;
    quoted.replace(QLatin1Char('\''), QLatin1String("'\\''"));
    return QLatin1Char('\'') + quoted + QLatin1Char('\'');
}

QByteArray handoverScript(System system)
{
    return system == System::Windows ? embeddedHandoverPowerShell() : embeddedHandoverShell();
}

bool desktopRunning(System system, const Install &install)
{
    if (install.parent.isEmpty())
        return false;
    const QDir parent(install.parent);
    // The update with no window runs as the app's own program (HeadlessUpdate.h): that process, and on Linux the
    // AppImage runtime it was started through, are this update, not an open app.
    const qint64 self = QCoreApplication::applicationPid();
    if (system == System::Windows) {
        const QString prefix = QDir::toNativeSeparators(parent.absolutePath()) + QLatin1Char('\\');
        QProcess powershell;
        powershell.start(QStringLiteral("powershell.exe"),
                         {QStringLiteral("-NoProfile"), QStringLiteral("-Command"),
                          QStringLiteral("@(Get-Process simorg-desktop -ErrorAction SilentlyContinue | "
                                         "Where-Object { $_.Id -ne %2 -and $_.Path -and $_.Path.StartsWith('%1', "
                                         "[StringComparison]::OrdinalIgnoreCase) }).Count")
                              .arg(QString(prefix).replace(QLatin1Char('\''), QLatin1String("''")))
                              .arg(self)});
        return powershell.waitForFinished(15'000) && powershell.readAllStandardOutput().trimmed().toInt() > 0;
    }
    // On Linux the AppImage itself: its runtime is the process that holds the path, the program runs from a mount.
    const QString program = system == System::MacOS
                                ? parent.filePath(install.appName + QStringLiteral("/Contents/MacOS/Simorg"))
                                : parent.filePath(install.appName);
    // pgrep reads a pattern, and a path is taken as it is written.
    QString pattern = QRegularExpression::escape(program);
    QProcess pgrep;
    pgrep.start(QStringLiteral("pgrep"), {QStringLiteral("-f"), QStringLiteral("^") + pattern + QStringLiteral("( |$)")});
    if (!pgrep.waitForFinished(10'000) || pgrep.exitStatus() != QProcess::NormalExit || pgrep.exitCode() != 0)
        return false;
    QSet<qint64> ours{self};
    for (qint64 pid = self; pid > 1;) {
        QProcess ps;
        ps.start(QStringLiteral("ps"), {QStringLiteral("-o"), QStringLiteral("ppid="), QStringLiteral("-p"),
                                        QString::number(pid)});
        if (!ps.waitForFinished(5'000))
            break;
        bool ok = false;
        pid = ps.readAllStandardOutput().trimmed().toLongLong(&ok);
        if (!ok)
            break;
        ours.insert(pid);
    }
    for (const QByteArray &line : pgrep.readAllStandardOutput().split('\n')) {
        bool ok = false;
        const qint64 pid = line.trimmed().toLongLong(&ok);
        if (ok && !ours.contains(pid))
            return true;
    }
    return false;
}

QString defaultNotePath()
{
    // Not the app's own data folder: a release before Simorg CLI, whose `simorg update desktop` read and wrote it, may
    // have left the note an update reads.
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
        .filePath(QStringLiteral("Simorg/desktop-update.json"));
}

QString installLocation(System system, const Install &install, const QString &applicationDirPath)
{
    if (install.parent.isEmpty())
        return QDir::toNativeSeparators(QDir::cleanPath(applicationDirPath));
    if (system == System::Windows || install.appName.isEmpty())
        return QDir::toNativeSeparators(install.parent);
    return QDir::toNativeSeparators(QDir(install.parent).filePath(install.appName));
}

QStringList commandLine(System system, const Install &install)
{
    if (!install.reason.isEmpty() || install.parent.isEmpty())
        return {};
    const QDir parent(install.parent);
    // The app's own program, which the service runs followed by `update desktop --json` (HeadlessUpdate.h).
    switch (system) {
    case System::MacOS:
        return {parent.filePath(install.appName + QStringLiteral("/Contents/MacOS/Simorg"))};
    case System::Linux:
        return {parent.filePath(install.appName)};
    case System::Windows:
        return {QDir::toNativeSeparators(parent.filePath(QStringLiteral("simorg-desktop.exe")))};
    }
    return {};
}

} // namespace desktopupdate

namespace {

using namespace std::chrono_literals;

/** How often the app looks for a newer version of itself without being asked. */
constexpr auto kCheckEvery = 6h;

/** A note older than this that no update is still working on is left over, and removed. */
constexpr qint64 kStaleNoteSeconds = 10 * 60;

QString phaseName(int phase)
{
    switch (phase) {
    case 1:
        return QStringLiteral("downloading");
    case 2:
        return QStringLiteral("verifying");
    case 3:
        return QStringLiteral("unpacking");
    case 4:
        return QStringLiteral("handing_over");
    case 5:
        return QStringLiteral("ready_to_restart");
    default:
        return {};
    }
}

bool writeWhole(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}

QString readText(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
}

QString megabytes(qint64 bytes)
{
    return QString::number(double(bytes) / 1e6, 'f', bytes < 10'000'000 ? 1 : 0);
}

} // namespace

DesktopUpdateModel::Options DesktopUpdateModel::defaults()
{
    Options options;
    options.applicationDirPath = QCoreApplication::applicationDirPath();
    options.appImagePath = qEnvironmentVariable("APPIMAGE");
    options.executableName = QFileInfo(QCoreApplication::applicationFilePath()).fileName();
    // SIMORG_VERSION, as the app and the command line both set it.
    options.version = QCoreApplication::applicationVersion();
    options.system = desktopupdate::thisSystem();
    options.cpuArchitecture = QSysInfo::currentCpuArchitecture();
    options.notePath = desktopupdate::defaultNotePath();
    options.processId = QCoreApplication::applicationPid();
    options.fallbackStaging = QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
                                  .filePath(QStringLiteral("Simorg/desktop-update"));
    return options;
}

DesktopUpdateModel::DesktopUpdateModel(ServiceSession *session, UpdatesModel *updates, Options options,
                                       QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_updates(updates)
    , m_options(std::move(options))
    , m_install(desktopupdate::locate(m_options.system, m_options.applicationDirPath, m_options.archiveBuild,
                                      m_options.appImagePath))
    , m_network(new QNetworkAccessManager(this))
{
    // Given up on after half a minute with nothing arriving, so a platform that does not answer is said to be so.
    m_network->setTransferTimeout(30'000);
    // Only a copy that can replace itself was ever handed over to, or left anything behind to clear.
    if (m_install.reason.isEmpty())
        readNote();
    if (m_updates) {
        connect(m_updates, &UpdatesModel::desktopUpdateRequested, this, &DesktopUpdateModel::start);
        connect(m_updates, &UpdatesModel::desktopCancelRequested, this, &DesktopUpdateModel::cancel);
        connect(m_updates, &UpdatesModel::desktopCheckRequested, this, &DesktopUpdateModel::check);
        connect(m_updates, &UpdatesModel::desktopRestartRequested, this, &DesktopUpdateModel::restartToFinish);
        // The service checks this copy's release, and says what it found in its `desktop` item.
        connect(m_updates, &UpdatesModel::serviceDesktopChanged, this, &DesktopUpdateModel::applyServiceItem);
        // Opened by its own update: the window shows how it went, where the person pressed it.
        connect(this, &DesktopUpdateModel::finishedUpdate, m_updates, &UpdatesModel::requestReview);
    }
    if (m_session) {
        // This copy, told to the service on every connection, so it survives the service's restarts.
        connect(m_session, &ServiceSession::connected, this, &DesktopUpdateModel::registerInstallation);
        if (m_session->isConnected())
            QTimer::singleShot(0, this, &DesktopUpdateModel::registerInstallation);
        // The open app is the one subscribed here, which is also how the service knows it is open.
        if (m_options.announceOpen) {
            m_requests = m_session->subscribe(QStringLiteral("updates.desktop_requested"));
            connect(m_requests, &client::TopicSubscription::received, this, &DesktopUpdateModel::onRequested);
        }
    }
    // An update somebody asked for and this copy prepared is applied as it starts: it was accepted, and the
    // restart that finishes it is this one.
    if (m_options.applyPreparedAtStart && m_install.reason.isEmpty()) {
        const QJsonObject kept = readPrepared();
        const QString tag = kept.value(QStringLiteral("tag")).toString();
        if (kept.value(QStringLiteral("accepted")).toBool() && desktopupdate::compareVersions(tag, m_options.version) > 0 &&
            prepared()) {
            desktopupdate::Release release;
            release.tag = tag;
            m_release = release;
            if (m_options.system == desktopupdate::System::Windows)
                m_archive.setFileName(QDir(stagingFolder()).filePath(QStringLiteral("Simorg.msi")));
            QTimer::singleShot(0, this, &DesktopUpdateModel::handOver);
        }
    }
    if (m_options.checkOnItsOwn) {
        // Only for a service older than API 1.3: a newer one checks this copy's release and says so in its
        // `desktop` item, and `check()` then does nothing. The registration's answer says which (registerInstallation).
        m_every.setInterval(kCheckEvery);
        connect(&m_every, &QTimer::timeout, this, &DesktopUpdateModel::check);
        m_every.start();
        if (!m_session && !m_options.platformApi.isEmpty())
            QTimer::singleShot(0, this, &DesktopUpdateModel::check);
    }
    publish();
}

DesktopUpdateModel::~DesktopUpdateModel()
{
    if (m_download)
        m_download->abort();
    if (m_opening)
        m_opening->kill();
}

void DesktopUpdateModel::readNote()
{
    const QString text = readText(m_options.notePath);
    if (text.isEmpty()) {
        // Nothing in hand: a staging folder still here is what an interrupted update left, unless it holds a version
        // newer than this one, prepared ahead.
        const QString tag = readPrepared().value(QStringLiteral("tag")).toString();
        if (tag.isEmpty() || desktopupdate::compareVersions(tag, m_options.version) <= 0)
            clearStaging();
        return;
    }
    const QJsonObject note = QJsonDocument::fromJson(text.toUtf8()).object();
    const QString state = note.value(QStringLiteral("state")).toString();
    const QString from = note.value(QStringLiteral("from")).toString();
    const QString to = note.value(QStringLiteral("to")).toString();
    const QString log = QDir::cleanPath(m_options.notePath.chopped(5) + QStringLiteral(".log"));
    const auto forget = [this, &log] {
        QFile::remove(m_options.notePath);
        QFile::remove(log);
    };

    if (state == QLatin1String("handing_over") && to == m_options.version) {
        // This version was just opened by the hand-over: said to the script, which then clears up, and to the person.
        QJsonObject started = note;
        started.insert(QStringLiteral("state"), QStringLiteral("started"));
        started.insert(QStringLiteral("at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        writeWhole(m_options.notePath, QJsonDocument(started).toJson(QJsonDocument::Compact));
        m_lastUpdate = QJsonObject{{QStringLiteral("from"), from},
                                   {QStringLiteral("to"), to},
                                   {QStringLiteral("outcome"), QStringLiteral("succeeded")}};
        QTimer::singleShot(0, this, &DesktopUpdateModel::finishedUpdate);
        return;
    }
    if (state == QLatin1String("finished")) {
        // Moved into place by the command line, which opened nothing: the version that reads it is the new one.
        m_lastUpdate = QJsonObject{{QStringLiteral("from"), from},
                                   {QStringLiteral("to"), to},
                                   {QStringLiteral("outcome"), QStringLiteral("succeeded")}};
        forget();
        return;
    }
    if (state == QLatin1String("failed") || state == QLatin1String("rolled_back")) {
        // The script's sentence, and what it did, on this version's row; the Update stays on offer.
        m_failure = note.value(QStringLiteral("reason")).toString();
        m_output = readText(log).trimmed().right(8000);
        forget();
        clearStaging();
        return;
    }
    const QDateTime at = QDateTime::fromString(note.value(QStringLiteral("at")).toString(), Qt::ISODate);
    if (!at.isValid() || at.secsTo(QDateTime::currentDateTimeUtc()) > kStaleNoteSeconds) {
        forget();
        clearStaging();
    }
}

void DesktopUpdateModel::withPlatform(const std::function<void(const QString &)> &then)
{
    if (!m_options.platformApi.isEmpty()) {
        then(m_options.platformApi);
        return;
    }
    if (!m_session || !m_session->isConnected())
        return; // asked again when the service answers
    ServiceReply *config = m_session->get(QStringLiteral("/v1/config"));
    connect(config, &ServiceReply::finished, this, [config, then] {
        const QString api = config->object()
                                .value(QStringLiteral("endpoints"))
                                .toObject()
                                .value(QStringLiteral("api_endpoint"))
                                .toString();
        if (config->isError() || api.isEmpty())
            return;
        then(api);
    });
}

void DesktopUpdateModel::registerInstallation()
{
    const QStringList words = desktopupdate::commandLine(m_options.system, m_install);
    QJsonArray cli;
    for (const QString &word : words)
        cli.append(word);
    const QJsonObject body{
        {QStringLiteral("version"), m_options.version},
        {QStringLiteral("client"), m_options.client},
        {QStringLiteral("location"),
         desktopupdate::installLocation(m_options.system, m_install, m_options.applicationDirPath)},
        {QStringLiteral("cli"), words.isEmpty() ? QJsonValue() : QJsonValue(cli)},
        {QStringLiteral("driver"), desktopupdate::driverCode(m_options.system, m_options.cpuArchitecture)},
        {QStringLiteral("can_self_update"), m_install.reason.isEmpty()},
        {QStringLiteral("unavailable_reason"), m_install.reason.isEmpty() ? QJsonValue() : QJsonValue(m_install.reason)},
    };
    ServiceReply *reply = toService("PUT", QStringLiteral("/v1/updates/desktop/installation"), body);
    if (!reply) {
        Q_EMIT registered(false);
        return;
    }
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        // A service older than API 1.3 has no such operation: this copy checks for itself, as it always did.
        const bool supported = !reply->isError();
        m_serviceChecks = supported;
        if (supported) {
            // The answer is the whole list; the desktop row in it is this copy's, as the service sees it.
            for (const QJsonValue &value : reply->object().value(QStringLiteral("items")).toArray()) {
                if (value.toObject().value(QStringLiteral("item")).toString() == QLatin1String("desktop"))
                    applyServiceItem(value.toObject());
            }
        } else if (m_options.checkOnItsOwn && !m_checked) {
            check();
        }
        Q_EMIT registered(supported);
    });
}

void DesktopUpdateModel::applyServiceItem(const QJsonObject &item)
{
    if (item.isEmpty())
        return;
    m_serviceChecks = true;
    m_checked = true;
    const QJsonObject release = item.value(QStringLiteral("release")).toObject();
    if (!release.isEmpty()) {
        desktopupdate::Release found;
        found.tag = release.value(QStringLiteral("tag")).toString();
        found.artifactId = release.value(QStringLiteral("artifact_id")).toString();
        found.driverId = release.value(QStringLiteral("driver_id")).toString();
        found.sha256 = release.value(QStringLiteral("sha256")).toString();
        const QJsonValue size = release.value(QStringLiteral("size"));
        found.size = size.isDouble() ? qint64(size.toDouble()) : -1;
        // Another release while one is prepared ahead in the background: that one is dropped for this.
        if (m_release && m_release->tag != found.tag && m_background && m_phase != Phase::Idle)
            cancel();
        if (m_phase == Phase::Idle || !m_release)
            m_release = found;
        m_reason.clear();
    } else if (m_phase == Phase::Idle) {
        m_release.reset();
        m_reason = item.value(QStringLiteral("unavailable_reason")).toString();
    }
    m_notes = item.value(QStringLiteral("notes")).toArray();
    m_required = item.value(QStringLiteral("required")).toBool();
    m_minimum = item.value(QStringLiteral("minimum")).toString();
    publish();

    // Downloaded and unpacked as soon as found, so Update, here or from elsewhere, only hands over.
    const bool newer = m_release && desktopupdate::compareVersions(m_release->tag, m_options.version) > 0;
    if (m_options.prepareAhead && newer && m_install.reason.isEmpty() && m_phase == Phase::Idle && !prepared() &&
        m_aheadFailedTag != m_release->tag)
        prepare(true);
}

void DesktopUpdateModel::check()
{
    // A service of API 1.3 checks this copy's release itself; asking it is UpdatesModel::check's.
    if (m_serviceChecks)
        return;
    if (m_phase != Phase::Idle)
        return;
    withPlatform([this](const QString &api) {
        m_api = api;
        QNetworkReply *config = m_network->get(QNetworkRequest(QUrl(api + QStringLiteral("/api/v1/platform/config"))));
        connect(config, &QNetworkReply::finished, this, [this, config, api] {
            config->deleteLater();
            if (config->error() != QNetworkReply::NoError) {
                m_reason = tr("Simorg Desktop could not reach Simorg to look for a newer version of itself: %1")
                               .arg(config->errorString());
                publish();
                return;
            }
            const QString specifier = QJsonDocument::fromJson(config->readAll())
                                          .object()
                                          .value(QStringLiteral("simorg_desktop_artifact_specifier"))
                                          .toString();
            if (specifier.isEmpty()) {
                m_release.reset();
                m_checked = true;
                m_reason = tr("This Simorg names no Simorg Desktop release, so there is nothing to update to.");
                publish();
                return;
            }
            QUrl url(api + QStringLiteral("/api/v1/machine/artifact"));
            url.setQuery(QUrlQuery{{QStringLiteral("packageSpecifier"), specifier}});
            QNetworkReply *artifact = m_network->get(QNetworkRequest(url));
            connect(artifact, &QNetworkReply::finished, this, [this, artifact] {
                artifact->deleteLater();
                if (artifact->error() != QNetworkReply::NoError) {
                    m_reason = tr("Simorg Desktop could not reach Simorg to look for a newer version of itself: %1")
                                   .arg(artifact->errorString());
                    publish();
                    return;
                }
                // The platform answers an artifact nobody may see, or none, with an empty body.
                const QJsonObject answer = QJsonDocument::fromJson(artifact->readAll()).object();
                QString why;
                m_release = desktopupdate::releaseFor(
                    answer, desktopupdate::driverCode(m_options.system, m_options.cpuArchitecture), &why);
                m_reason = m_release ? QString() : why;
                m_checked = true;
                publish();
            });
        });
    });
}

QString DesktopUpdateModel::stagingFolder() const
{
    // Beside the install, so the new version moves into place without a copy; elsewhere when that folder is
    // an administrator's.
    if (!m_install.parent.isEmpty() && QFileInfo(m_install.parent).isWritable())
        return QDir(m_install.parent).filePath(QStringLiteral(".simorg-update"));
    return m_options.fallbackStaging;
}

void DesktopUpdateModel::clearStaging()
{
    for (const QString &folder : {m_install.parent.isEmpty()
                                      ? QString()
                                      : QDir(m_install.parent).filePath(QStringLiteral(".simorg-update")),
                                  m_options.fallbackStaging}) {
        if (!folder.isEmpty() && QFileInfo::exists(folder))
            QDir(folder).removeRecursively();
    }
}

bool DesktopUpdateModel::prepared() const
{
    const QJsonObject kept = readPrepared();
    const QString tag = kept.value(QStringLiteral("tag")).toString();
    if (tag.isEmpty() || (m_release && m_release->tag != tag))
        return false;
    const QDir staging(stagingFolder());
    switch (m_options.system) {
    case desktopupdate::System::MacOS:
        return QFileInfo::exists(staging.filePath(QStringLiteral("new/Simorg.app"))) ||
               (!m_install.appName.isEmpty() && QFileInfo::exists(staging.filePath(QStringLiteral("new/") + m_install.appName)));
    case desktopupdate::System::Linux:
        return QFileInfo::exists(staging.filePath(QStringLiteral("new/Simorg.AppImage"))) ||
               (!m_install.appName.isEmpty() && QFileInfo::exists(staging.filePath(QStringLiteral("new/") + m_install.appName)));
    case desktopupdate::System::Windows:
        return QFileInfo::exists(staging.filePath(QStringLiteral("Simorg.msi")));
    }
    return false;
}

QJsonObject DesktopUpdateModel::readPrepared() const
{
    return QJsonDocument::fromJson(readText(QDir(stagingFolder()).filePath(QStringLiteral("prepared.json"))).toUtf8())
        .object();
}

void DesktopUpdateModel::writePrepared(bool accepted)
{
    if (!m_release)
        return;
    writeWhole(QDir(stagingFolder()).filePath(QStringLiteral("prepared.json")),
               QJsonDocument(QJsonObject{{QStringLiteral("tag"), m_release->tag}, {QStringLiteral("accepted"), accepted}})
                   .toJson(QJsonDocument::Compact));
}

void DesktopUpdateModel::start()
{
    if (!m_release || !m_install.reason.isEmpty() || desktopupdate::compareVersions(m_release->tag, m_options.version) <= 0)
        return;
    m_accepted = true;
    // Prepared already, ahead or on a request from elsewhere: the press is the restart that finishes it.
    if (m_phase == Phase::ReadyToRestart || (m_phase == Phase::Idle && prepared())) {
        handOver();
        return;
    }
    m_applyWhenPrepared = true;
    if (m_phase != Phase::Idle) {
        // A download ahead already on its way becomes the update, shown as one.
        m_background = false;
        publish();
        return;
    }
    prepare(false);
}

void DesktopUpdateModel::onRequested(const QJsonObject &request)
{
    // Asked for elsewhere, so prepared and offered as a restart. This window is never closed from outside.
    m_requestId = request.value(QStringLiteral("id")).toString();
    m_lastReport = {};
    m_accepted = true;
    m_applyWhenPrepared = false;
    if (!m_release || !m_install.reason.isEmpty()) {
        report();
        return;
    }
    if (m_phase == Phase::Idle && prepared()) {
        writePrepared(true);
        preparedNow();
        return;
    }
    if (m_phase != Phase::Idle) {
        m_background = false;
        publish();
        return;
    }
    prepare(false);
}

void DesktopUpdateModel::restartToFinish()
{
    if (m_phase == Phase::ReadyToRestart || (m_phase == Phase::Idle && prepared()))
        handOver();
}

void DesktopUpdateModel::preparedNow()
{
    writePrepared(m_accepted);
    m_downloadState = QStringLiteral("ready");
    if (m_applyWhenPrepared) {
        handOver();
        return;
    }
    if (m_accepted) {
        m_background = false;
        setPhase(Phase::ReadyToRestart, tr("Simorg Desktop %1 is ready. Restart it to finish updating; your agents "
                                           "keep running.")
                                            .arg(m_release->tag));
        return;
    }
    // Downloaded ahead: it waits for Update, which then only hands over.
    m_background = false;
    m_phase = Phase::Idle;
    m_message.clear();
    m_progress = -1;
    publish();
}

void DesktopUpdateModel::prepare(bool background)
{
    if (m_phase != Phase::Idle || !m_release || !m_install.reason.isEmpty() ||
        desktopupdate::compareVersions(m_release->tag, m_options.version) <= 0)
        return;
    m_background = background;
    m_downloadState = QStringLiteral("downloading");
    m_failure.clear();
    m_output.clear();
    if (m_api.isEmpty() && !m_options.platformApi.isEmpty())
        m_api = m_options.platformApi;
    if (m_api.isEmpty()) {
        // The service found the release, so where Simorg is was never asked here; it is now.
        const QString unknown = tr("Simorg Desktop could not ask the machine service where Simorg is, so nothing was "
                                   "downloaded.");
        if (!m_session || !m_session->isConnected()) {
            fail(unknown);
            return;
        }
        ServiceReply *config = m_session->get(QStringLiteral("/v1/config"));
        connect(config, &ServiceReply::finished, this, [this, config, background, unknown] {
            const QString api = config->object()
                                    .value(QStringLiteral("endpoints"))
                                    .toObject()
                                    .value(QStringLiteral("api_endpoint"))
                                    .toString();
            if (config->isError() || api.isEmpty()) {
                fail(unknown);
                return;
            }
            m_api = api;
            // Update pressed meanwhile makes the download ahead the update itself.
            prepare(background && !m_applyWhenPrepared);
        });
        return;
    }
    clearStaging();
    const QString staging = stagingFolder();
    if (!QDir().mkpath(staging)) {
        fail(tr("Simorg Desktop could not make a folder for the download in %1, so nothing was changed.")
                 .arg(QDir::toNativeSeparators(staging)));
        return;
    }
    // Named for what it is, this system's own installer: hdiutil and the Windows Installer both read the name.
    m_archive.setFileName(QDir(staging).filePath(m_options.system == desktopupdate::System::MacOS   ? QStringLiteral("Simorg.dmg")
                                                 : m_options.system == desktopupdate::System::Windows ? QStringLiteral("Simorg.msi")
                                                                                                    : QStringLiteral("Simorg.AppImage")));
    if (!m_archive.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        fail(tr("Simorg Desktop could not save the download in %1, so nothing was changed.")
                 .arg(QDir::toNativeSeparators(staging)));
        return;
    }
    m_hash.reset();
    m_received = 0;
    // Measured when the platform says how big it is; the bar sweeps when it does not.
    m_progress = m_release->size > 0 ? 0 : -1;
    const QUrl url(m_api + QStringLiteral("/api/v1/machine/artifact/%1/drivers/%2/download")
                               .arg(m_release->artifactId, m_release->driverId));
    m_download = m_network->get(QNetworkRequest(url));
    connect(m_download, &QNetworkReply::readyRead, this, &DesktopUpdateModel::onDownloadChunk);
    connect(m_download, &QNetworkReply::finished, this, &DesktopUpdateModel::onDownloaded);
    setPhase(Phase::Downloading, tr("Downloading Simorg Desktop %1.").arg(m_release->tag));
}

void DesktopUpdateModel::onDownloadChunk()
{
    if (!m_download)
        return;
    const QByteArray chunk = m_download->readAll();
    m_hash.addData(chunk);
    m_received += chunk.size();
    if (m_archive.write(chunk) != chunk.size()) {
        m_download->abort();
        return;
    }
    if (m_release->size <= 0)
        return;
    // A whole percent at a time: the row changes value in place, and a hundred changes are plenty.
    const double progress = qMin(1.0, double(m_received) / double(m_release->size));
    if (int(progress * 100) == int(m_progress * 100))
        return;
    m_progress = progress;
    m_message = tr("Downloading Simorg Desktop %1: %2 of %3 MB.")
                    .arg(m_release->tag, megabytes(m_received), megabytes(m_release->size));
    publish();
}

void DesktopUpdateModel::onDownloaded()
{
    if (!m_download)
        return;
    if (m_phase == Phase::Downloading)
        onDownloadChunk(); // whatever arrived with the end
    QNetworkReply *reply = m_download;
    m_download = nullptr;
    reply->deleteLater();
    if (m_phase != Phase::Downloading)
        return; // cancelled
    const bool written = m_archive.error() == QFileDevice::NoError;
    const QString writeError = m_archive.errorString();
    m_archive.close();
    if (!written) {
        fail(tr("Simorg Desktop could not save the download, so nothing was changed: %1").arg(writeError));
        return;
    }
    if (reply->error() != QNetworkReply::NoError) {
        fail(tr("The download stopped before it finished, so nothing was changed: %1").arg(reply->errorString()));
        return;
    }

    setPhase(Phase::Verifying, tr("Checking the download against the checksum Simorg published for it."));
    if (m_release->size >= 0 && m_received != m_release->size) {
        fail(tr("The download is %1 bytes where Simorg published %2, so it was not installed.")
                 .arg(m_received)
                 .arg(m_release->size));
        return;
    }
    if (QString::fromLatin1(m_hash.result().toHex()) != m_release->sha256) {
        fail(tr("The download does not match the checksum Simorg published for it, so it was not installed."));
        return;
    }
    openDownload();
}

void DesktopUpdateModel::openDownload()
{
    setPhase(Phase::Unpacking, tr("Opening Simorg Desktop %1.").arg(m_release->tag));
    const QDir staging(stagingFolder());

    if (m_options.system == desktopupdate::System::Windows) {
        // Nothing to take out: the installer is what the hand-over runs, and upgrades the copy in place. The
        // checksum has said it is the file Simorg published; this says it is an installer at all.
        QFile installer(m_archive.fileName());
        static const QByteArray kOle = QByteArray::fromHex("d0cf11e0a1b11ae1");
        if (!installer.open(QIODevice::ReadOnly) || installer.read(8) != kOle) {
            fail(tr("The download is not a Windows Installer package, so it was not installed."));
            return;
        }
        preparedNow();
        return;
    }

    const QString into = staging.filePath(QStringLiteral("new"));
    QDir(into).removeRecursively();
    QDir().mkpath(into);
    // One small script: the new version out of its download and into new/, with the note on how it was built beside
    // it. A disk image is attached where nobody sees it and detached again whatever happens; an AppImage is made
    // runnable and asked for its note, which it hands out without being mounted.
    const QByteArray script =
        m_options.system == desktopupdate::System::MacOS
            ? QByteArrayLiteral("set -e\n"
                                "mount=\"$2/mount\"; mkdir -p \"$mount\"\n"
                                "/usr/bin/hdiutil attach -nobrowse -readonly -noautoopen -mountpoint \"$mount\" \"$1\" "
                                ">/dev/null\n"
                                "trap '/usr/bin/hdiutil detach -force \"$mount\" >/dev/null 2>&1; rmdir \"$mount\" "
                                "2>/dev/null' EXIT\n"
                                "/usr/bin/ditto \"$mount/Simorg.app\" \"$2/new/Simorg.app\"\n"
                                "cp \"$mount/BUILD-INFO.txt\" \"$2/new/BUILD-INFO.txt\"\n")
            : QByteArrayLiteral("set -e\n"
                                "cp \"$1\" \"$2/new/Simorg.AppImage\"\n"
                                "chmod 755 \"$2/new/Simorg.AppImage\"\n"
                                "cd \"$2\"\n"
                                "rm -rf squashfs-root\n"
                                "\"$2/new/Simorg.AppImage\" --appimage-extract BUILD-INFO.txt >/dev/null\n"
                                "mv squashfs-root/BUILD-INFO.txt new/BUILD-INFO.txt\n"
                                "rm -rf squashfs-root\n");

    m_opening = new QProcess(this);
    m_opening->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_opening, &QProcess::finished, this, [this, into](int exitCode, QProcess::ExitStatus status) {
        const QString printed = QString::fromUtf8(m_opening->readAll()).trimmed();
        m_opening->deleteLater();
        m_opening = nullptr;
        if (m_phase != Phase::Unpacking)
            return; // cancelled
        if (status != QProcess::NormalExit || exitCode != 0) {
            fail(tr("The download could not be opened, so nothing was changed."), printed);
            return;
        }
        QFile buildInfo(QDir(into).filePath(QStringLiteral("BUILD-INFO.txt")));
        const QString version =
            buildInfo.open(QIODevice::ReadOnly) ? desktopupdate::buildInfoVersion(buildInfo.readAll()) : QString();
        if (version != m_release->tag) {
            fail(tr("The download says it is version %1 where Simorg published %2, so it was not installed.")
                     .arg(version.isEmpty() ? tr("unknown") : version, m_release->tag));
            return;
        }
        const QString entry = m_options.system == desktopupdate::System::MacOS ? QStringLiteral("Simorg.app")
                                                                                : QStringLiteral("Simorg.AppImage");
        if (!QFileInfo::exists(QDir(into).filePath(entry))) {
            fail(tr("The download has no %1 in it, so it was not installed.").arg(entry));
            return;
        }
        preparedNow();
    });
    connect(m_opening, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !m_opening)
            return;
        m_opening->deleteLater();
        m_opening = nullptr;
        fail(tr("Simorg Desktop could not open the download, so nothing was changed."));
    });
    m_opening->start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), QString::fromUtf8(script), QStringLiteral("sh"),
                                                  m_archive.fileName(), staging.absolutePath()});
}

void DesktopUpdateModel::handOver()
{
    // Windows cannot replace a running program, so its hand-over always waits for this process to close.
    const bool detached = m_options.detached || m_options.system == desktopupdate::System::Windows;
    setPhase(Phase::HandingOver,
             m_options.reopen
                 ? tr("Closing Simorg Desktop to open version %1. Your agents keep running.").arg(m_release->tag)
                 : tr("Moving Simorg Desktop %1 into place.").arg(m_release->tag));
    const QDir staging(stagingFolder());
    const QDir unpacked(staging.filePath(QStringLiteral("new")));

    // What the download brought, under the name the copy it replaces has: Simorg.app or Simorg.AppImage as it
    // was published, and whatever the person called theirs. Nothing on Windows, whose installer is run whole.
    QStringList entries;
    if (m_options.system != desktopupdate::System::Windows) {
        const QString published = m_options.system == desktopupdate::System::MacOS ? QStringLiteral("Simorg.app")
                                                                                    : QStringLiteral("Simorg.AppImage");
        if (m_install.appName != published && !QDir(unpacked).rename(published, m_install.appName)) {
            fail(tr("Simorg Desktop could not prepare the new version, so nothing was changed."));
            return;
        }
        entries = {m_install.appName};
    }
    const bool elevate = !QFileInfo(m_install.parent).isWritable();
    const QString script = staging.filePath(m_options.system == desktopupdate::System::Windows
                                                ? QStringLiteral("desktop-handover.ps1")
                                                : QStringLiteral("desktop-handover.sh"));
    bool prepared = writeWhole(staging.filePath(QStringLiteral("entries")), entries.join(QLatin1Char('\n')).toUtf8() + '\n') &&
                    writeWhole(script, desktopupdate::handoverScript(m_options.system));

    QString program;
    QStringList arguments;
    if (m_options.system == desktopupdate::System::Windows) {
        const QString user = qEnvironmentVariable("USERDOMAIN").isEmpty()
                                 ? qEnvironmentVariable("USERNAME")
                                 : qEnvironmentVariable("USERDOMAIN") + QLatin1Char('\\') + qEnvironmentVariable("USERNAME");
        const QJsonObject settings{
            {QStringLiteral("app_pid"), m_options.processId},
            {QStringLiteral("parent"), QDir::toNativeSeparators(m_install.parent)},
            {QStringLiteral("app_exe"), m_options.executableName},
            {QStringLiteral("installer"), QDir::toNativeSeparators(QFileInfo(m_archive.fileName()).absoluteFilePath())},
            {QStringLiteral("note"), QDir::toNativeSeparators(m_options.notePath)},
            {QStringLiteral("from"), m_options.version},
            {QStringLiteral("to"), m_release->tag},
            {QStringLiteral("started_within"), m_options.startedWithinSeconds},
            {QStringLiteral("reopen"), m_options.reopen},
            {QStringLiteral("elevate"), elevate},
            {QStringLiteral("owner"), user},
        };
        prepared = prepared && writeWhole(staging.filePath(QStringLiteral("handover.json")),
                                          QJsonDocument(settings).toJson(QJsonDocument::Compact));
        program = QStringLiteral("powershell.exe");
        arguments = {QStringLiteral("-NoProfile"),       QStringLiteral("-ExecutionPolicy"),
                     QStringLiteral("Bypass"),           QStringLiteral("-WindowStyle"),
                     QStringLiteral("Hidden"),           QStringLiteral("-File"),
                     QDir::toNativeSeparators(script),   QStringLiteral("-Staging"),
                     QDir::toNativeSeparators(staging.absolutePath())};
    } else {
        using desktopupdate::shellQuoted;
        const bool mac = m_options.system == desktopupdate::System::MacOS;
#ifndef Q_OS_WIN
        const QString owner = QStringLiteral("%1:%2").arg(::getuid()).arg(::getgid());
#else
        const QString owner;
#endif
        const QStringList variables{
            // Nothing to wait for when this process waits for the script instead.
            QStringLiteral("APP_PID=%1").arg(detached ? m_options.processId : 0),
            QStringLiteral("PARENT=") + shellQuoted(m_install.parent),
            QStringLiteral("APP_ENTRY=") + shellQuoted(m_install.appName),
            QStringLiteral("NOTE=") + shellQuoted(m_options.notePath),
            QStringLiteral("FROM=") + shellQuoted(m_options.version),
            QStringLiteral("TO=") + shellQuoted(m_release->tag),
            QStringLiteral("SYSTEM=") + (mac ? QStringLiteral("macos") : QStringLiteral("linux")),
            QStringLiteral("STARTED_WITHIN=%1").arg(m_options.startedWithinSeconds),
            QStringLiteral("ELEVATE=%1").arg(elevate ? 1 : 0),
            QStringLiteral("REOPEN=%1").arg(m_options.reopen ? 1 : 0),
            QStringLiteral("OWNER=") + shellQuoted(owner),
        };
        prepared = prepared && writeWhole(staging.filePath(QStringLiteral("handover.env")),
                                          variables.join(QLatin1Char('\n')).toUtf8() + '\n');
        if (elevate) {
            // The move alone under the operating system's own prompt, as the service's install is.
            const auto underPrompt = [&](const char *mode) {
                const QStringList argv = serviceinstall::scriptUnderPrompt(
                    mac ? serviceinstall::Platform::MacOS : serviceinstall::Platform::Linux,
                    QStringLiteral("/bin/sh %1 %2 %3")
                        .arg(shellQuoted(script), QLatin1String(mode), shellQuoted(staging.absolutePath())),
                    QStandardPaths::findExecutable(QStringLiteral("pkexec")));
                QStringList words;
                for (const QString &word : argv)
                    words.append(shellQuoted(word));
                return words.isEmpty() ? QByteArray() : ("exec " + words.join(QLatin1Char(' ')).toUtf8() + '\n');
            };
            const QByteArray swap = underPrompt("--swap");
            if (swap.isEmpty()) {
                fail(tr("Simorg Desktop is in %1, which only an administrator can change, and this computer has no "
                        "way for Simorg to ask for the password, so nothing was changed.")
                         .arg(QDir::toNativeSeparators(m_install.parent)));
                return;
            }
            prepared = prepared && writeWhole(staging.filePath(QStringLiteral("swap-elevated.sh")), swap) &&
                       writeWhole(staging.filePath(QStringLiteral("restore-elevated.sh")), underPrompt("--restore"));
        }
        program = QStringLiteral("/bin/sh");
        arguments = {script, staging.absolutePath()};
    }

    // The note first: the version that opens next reads it.
    const QJsonObject note{{QStringLiteral("state"), QStringLiteral("handing_over")},
                           {QStringLiteral("from"), m_options.version},
                           {QStringLiteral("to"), m_release->tag},
                           {QStringLiteral("at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}};
    QDir().mkpath(QFileInfo(m_options.notePath).absolutePath());
    prepared = prepared && writeWhole(m_options.notePath, QJsonDocument(note).toJson(QJsonDocument::Compact));
    // Started outside the staging folder, which it deletes when it is done: Windows keeps a folder that is a
    // process's working directory.
    const QString workingDirectory = QFileInfo(m_options.notePath).absolutePath();
    if (prepared && !detached) {
        auto *running = new QProcess(this);
        running->setProcessChannelMode(QProcess::MergedChannels);
        running->setWorkingDirectory(workingDirectory);
        const auto ended = [this, running] {
            running->deleteLater();
            m_phase = Phase::Idle;
            m_message.clear();
            m_progress = -1;
            // The script's note says how it went, as it says it to a version that opens after a detached one.
            readNote();
            if (m_lastUpdate.isEmpty() && m_failure.isEmpty())
                m_failure = tr("The hand-over stopped without saying how it went, so check the version with "
                               "simorg version.");
            publish();
            Q_EMIT handedOver(m_failure.isEmpty());
        };
        connect(running, &QProcess::finished, this, ended);
        connect(running, &QProcess::errorOccurred, this, [this, running](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            running->deleteLater();
            QFile::remove(m_options.notePath);
            fail(tr("Simorg Desktop could not start the hand-over to the new version, so nothing was changed."));
            Q_EMIT handedOver(false);
        });
        running->start(program, arguments);
        return;
    }
    if (!prepared || !QProcess::startDetached(program, arguments, workingDirectory)) {
        QFile::remove(m_options.notePath);
        fail(tr("Simorg Desktop could not start the hand-over to the new version, so nothing was changed."));
        return;
    }
    // A moment for the row to say so, then this process alone closes; the service and the agents stay.
    QTimer::singleShot(750, this, &DesktopUpdateModel::exitRequested);
}

void DesktopUpdateModel::cancel()
{
    if (m_phase == Phase::Idle || m_phase == Phase::HandingOver)
        return;
    if (m_phase == Phase::ReadyToRestart) {
        // Not now: the prepared version stays for the next Update, and is no longer applied at the next start.
        m_accepted = false;
        writePrepared(false);
        m_phase = Phase::Idle;
        m_message.clear();
        publish();
        return;
    }
    m_background = false;
    m_downloadState = QStringLiteral("idle");
    const Phase was = m_phase;
    m_phase = Phase::Idle;
    if (was == Phase::Downloading && m_download)
        m_download->abort();
    if (was == Phase::Unpacking && m_opening)
        m_opening->kill();
    if (m_archive.isOpen())
        m_archive.close();
    clearStaging();
    m_message.clear();
    m_progress = -1;
    publish();
}

void DesktopUpdateModel::fail(const QString &message, const QString &output)
{
    m_phase = Phase::Idle;
    if (m_background) {
        // A download ahead that did not work is not an update that failed: Update downloads it again.
        m_background = false;
        m_downloadState = QStringLiteral("failed");
        if (m_release)
            m_aheadFailedTag = m_release->tag;
        m_message.clear();
        m_progress = -1;
        if (m_archive.isOpen())
            m_archive.close();
        clearStaging();
        publish();
        return;
    }
    m_downloadState = QStringLiteral("idle");
    m_failure = message;
    m_output = output;
    m_message.clear();
    m_progress = -1;
    if (m_archive.isOpen())
        m_archive.close();
    clearStaging();
    publish();
}

void DesktopUpdateModel::setPhase(Phase phase, const QString &message)
{
    m_phase = phase;
    m_message = message;
    if (phase != Phase::Downloading)
        m_progress = -1;
    publish();
}

QJsonObject DesktopUpdateModel::row() const
{
    const bool newer = m_release && desktopupdate::compareVersions(m_release->tag, m_options.version) > 0;
    // A download ahead is not an update: the row stays on offer, and says so in `download`.
    const bool running = m_phase != Phase::Idle && !m_background;
    QString state = QStringLiteral("unknown");
    if (running)
        state = QStringLiteral("updating");
    else if (newer && !m_failure.isEmpty())
        state = QStringLiteral("failed");
    else if (newer)
        state = QStringLiteral("available");
    else if (m_checked)
        state = QStringLiteral("up_to_date");

    // Why it cannot be pressed: this copy's own reason once there is something to update to, else the check's.
    QString reason = m_reason;
    if (newer && !m_install.reason.isEmpty())
        reason = m_install.reason;

    QJsonValue operation;
    if (running) {
        operation = QJsonObject{{QStringLiteral("phase"), phaseName(int(m_phase))},
                                {QStringLiteral("progress"), m_progress < 0 ? QJsonValue() : QJsonValue(m_progress)},
                                {QStringLiteral("message"), m_message},
                                {QStringLiteral("outcome"), QJsonValue()}};
    } else if (!m_failure.isEmpty()) {
        operation = QJsonObject{{QStringLiteral("phase"), QString()},
                                {QStringLiteral("progress"), QJsonValue()},
                                {QStringLiteral("message"), m_failure},
                                {QStringLiteral("outcome"), QStringLiteral("failed")},
                                {QStringLiteral("problem"), QJsonObject{{QStringLiteral("detail"), m_failure}}},
                                {QStringLiteral("output"), m_output}};
    }

    return QJsonObject{
        {QStringLiteral("item"), QStringLiteral("desktop")},
        {QStringLiteral("installed"), m_options.version},
        {QStringLiteral("available"), newer ? QJsonValue(m_release->tag) : QJsonValue()},
        {QStringLiteral("state"), state},
        {QStringLiteral("can_update"), newer && !running && m_install.reason.isEmpty()},
        {QStringLiteral("unavailable_reason"), reason.isEmpty() ? QJsonValue() : QJsonValue(reason)},
        {QStringLiteral("operation"), operation.isUndefined() ? QJsonValue() : operation},
        {QStringLiteral("last_update"), m_lastUpdate.isEmpty() ? QJsonValue() : QJsonValue(m_lastUpdate)},
        {QStringLiteral("notes"), newer ? QJsonValue(m_notes) : QJsonValue(QJsonArray())},
        {QStringLiteral("required"), newer && m_required},
        {QStringLiteral("minimum"), m_minimum.isEmpty() ? QJsonValue() : QJsonValue(m_minimum)},
        {QStringLiteral("download"),
         newer ? QJsonValue(QJsonObject{
                     {QStringLiteral("state"), prepared() && m_phase == Phase::Idle ? QStringLiteral("ready") : m_downloadState},
                     {QStringLiteral("progress"), m_background && m_progress >= 0 ? QJsonValue(m_progress) : QJsonValue()}})
               : QJsonValue()},
    };
}

void DesktopUpdateModel::publish()
{
    if (m_updates)
        m_updates->setDesktopRow(row());
    report();
    Q_EMIT changed();
}

client::ServiceReply *DesktopUpdateModel::toService(const QByteArray &method, const QString &path, const QJsonObject &body)
{
    if (m_session) {
        if (!m_session->isConnected())
            return nullptr;
        return m_session->request(method, path, QJsonDocument(body));
    }
    return m_options.serviceRequest ? m_options.serviceRequest(method, path, body) : nullptr;
}

void DesktopUpdateModel::report()
{
    // Only an update, not a download ahead, and only to a service that keeps this copy's row.
    if (!m_serviceChecks || m_background)
        return;
    QJsonObject body;
    if (!m_requestId.isEmpty())
        body.insert(QStringLiteral("id"), m_requestId);
    if (m_phase != Phase::Idle) {
        body.insert(QStringLiteral("phase"), phaseName(int(m_phase)));
        body.insert(QStringLiteral("progress"), m_progress < 0 ? QJsonValue() : QJsonValue(m_progress));
        body.insert(QStringLiteral("message"), m_message);
    } else if (!m_failure.isEmpty() && !m_lastReport.contains(QStringLiteral("outcome"))) {
        body.insert(QStringLiteral("outcome"), QStringLiteral("failed"));
        body.insert(QStringLiteral("detail"), m_failure);
        if (!m_output.isEmpty())
            body.insert(QStringLiteral("output"), m_output.right(8000));
    } else if (m_lastReport.contains(QStringLiteral("phase")) && !m_lastReport.contains(QStringLiteral("outcome")) &&
               m_lastUpdate.value(QStringLiteral("outcome")).toString() == QLatin1String("succeeded") &&
               m_lastUpdate.value(QStringLiteral("to")).toString() == (m_release ? m_release->tag : QString())) {
        // The command line's hand-over, which it waited for, put the new version in place.
        body.insert(QStringLiteral("outcome"), QStringLiteral("succeeded"));
        body.insert(QStringLiteral("message"), tr("Simorg Desktop %1 is in place.").arg(m_release->tag));
    } else if (m_lastReport.contains(QStringLiteral("phase")) && !m_lastReport.contains(QStringLiteral("outcome"))) {
        // It was running and stopped with nothing wrong: cancelled here, or prepared and put off.
        body.insert(QStringLiteral("outcome"), QStringLiteral("cancelled"));
    } else if (!m_requestId.isEmpty() && (!m_release || !m_install.reason.isEmpty())) {
        // Asked for elsewhere, and this copy cannot: said at once, in its own words.
        body.insert(QStringLiteral("outcome"), QStringLiteral("failed"));
        body.insert(QStringLiteral("detail"), m_install.reason.isEmpty() ? m_reason : m_install.reason);
    } else {
        return;
    }
    // Only what moved: a phase, an outcome, or five points of progress.
    const auto progressOf = [](const QJsonObject &object) {
        const QJsonValue value = object.value(QStringLiteral("progress"));
        return value.isDouble() ? value.toDouble() : -1.0;
    };
    if (body.value(QStringLiteral("phase")) == m_lastReport.value(QStringLiteral("phase")) &&
        body.value(QStringLiteral("outcome")) == m_lastReport.value(QStringLiteral("outcome")) &&
        qAbs(progressOf(body) - progressOf(m_lastReport)) < 0.05)
        return;
    m_lastReport = body;
    // Fire and forget: a reply deletes itself once finished, and a report that did not land is overtaken by the next.
    (void)toService("POST", QStringLiteral("/v1/updates/desktop/progress"), body);
    if (body.contains(QStringLiteral("outcome")))
        m_requestId.clear();
}

} // namespace simorg::app
