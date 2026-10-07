// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/UninstallModel.h"

#include "simorg/client/Discovery.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QFileInfo>
#include <QJsonArray>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>

namespace simorg::app {

using client::ServiceSession;

namespace uninstall {

namespace {

struct Reason {
    const char *code;
    const char *label;
};

// The platform's uninstall reasons and their labels, in the platform's order.
constexpr Reason kReasons[] = {
    {"no_longer_needed", QT_TRANSLATE_NOOP("Uninstall", "I don't need it anymore")},
    {"reinstalling", QT_TRANSLATE_NOOP("Uninstall", "I'm reinstalling or moving to another computer")},
    {"hard_to_set_up", QT_TRANSLATE_NOOP("Uninstall", "It was hard to set up")},
    {"did_not_work", QT_TRANSLATE_NOOP("Uninstall", "Something didn't work")},
    {"slows_computer", QT_TRANSLATE_NOOP("Uninstall", "It slows my computer down")},
    {"docker", QT_TRANSLATE_NOOP("Uninstall", "I'd rather not run Docker")},
    {"missing_feature", QT_TRANSLATE_NOOP("Uninstall", "Something I need is missing")},
    {"privacy_security", QT_TRANSLATE_NOOP("Uninstall", "Privacy or security concerns")},
    {"switching_product", QT_TRANSLATE_NOOP("Uninstall", "I'm switching to another product")},
    {"other", QT_TRANSLATE_NOOP("Uninstall", "Other")},
};

constexpr Step kSteps[] = {Step::Report, Step::SignOut, Step::Images, Step::Service,
                           Step::Data,   Step::LoginItems, Step::App};

/** Paths compared the way the file system does: without regard to case on Windows. */
QString comparable(const QString &path)
{
#ifdef Q_OS_WIN
    return QDir::cleanPath(QDir::fromNativeSeparators(path)).toLower();
#else
    return QDir::cleanPath(path);
#endif
}

} // namespace

QStringList reasonCodes()
{
    QStringList codes;
    for (const Reason &reason : kReasons)
        codes << QString::fromLatin1(reason.code);
    return codes;
}

QString reasonLabel(const QString &code)
{
    for (const Reason &reason : kReasons) {
        if (code == QLatin1String(reason.code))
            return QCoreApplication::translate("Uninstall", reason.label);
    }
    return code;
}

QJsonObject requestBody(const QString &source, const QString &desktopVersion, const QStringList &reasons,
                        const QString &comment, bool removeData)
{
    const QStringList known = reasonCodes();
    QJsonArray codes;
    // In the form's order, each once, whatever order they were ticked in.
    for (const QString &code : known) {
        if (reasons.contains(code))
            codes.append(code);
    }
    const QString written = comment.trimmed().left(commentLimit);
    QJsonObject body{
        {QStringLiteral("source"), source},
        {QStringLiteral("reasons"), codes},
        {QStringLiteral("remove_data"), removeData},
    };
    body.insert(QStringLiteral("comment"), written.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(written));
    body.insert(QStringLiteral("desktop_version"),
                source == QLatin1String("desktop") && !desktopVersion.isEmpty() ? QJsonValue(desktopVersion)
                                                                                 : QJsonValue(QJsonValue::Null));
    return body;
}

bool deletable(const QString &path, const QString &home)
{
    if (path.trimmed().isEmpty() || QDir::isRelativePath(path))
        return false;
    const QString cleaned = comparable(path);
    const QString name = QFileInfo(cleaned).fileName();
    // The root of a drive or of the file system has no name.
    if (name.isEmpty() || !name.contains(QLatin1String("simorg"), Qt::CaseInsensitive))
        return false;
    if (!home.isEmpty()) {
        const QString ownHome = comparable(home);
        if (cleaned == ownHome || ownHome.startsWith(cleaned + QLatin1Char('/')))
            return false;
    }
    return true;
}

bool insideDeletable(const QString &path, const QStringList &folders, const QString &home)
{
    const QString cleaned = comparable(path);
    return std::any_of(folders.cbegin(), folders.cend(), [&cleaned, &home](const QString &folder) {
        return cleaned.startsWith(comparable(folder) + QLatin1Char('/')) && deletable(folder, home);
    });
}

QStringList desktopDataPaths()
{
    QStringList paths;
    const auto add = [&paths](const QString &path) {
        if (!path.isEmpty() && !paths.contains(QDir::cleanPath(path)))
            paths << QDir::cleanPath(path);
    };
    // The hand-over note and the update's staging folder (DesktopUpdateModel), then Qt's own places for this app.
    add(QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)).filePath(QStringLiteral("Simorg")));
    add(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    add(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation));
    add(QStandardPaths::writableLocation(QStandardPaths::CacheLocation));
    const QString home = QDir::homePath();
    paths.erase(std::remove_if(paths.begin(), paths.end(), [&home](const QString &path) { return !deletable(path, home); }),
                paths.end());
    return paths;
}

QString stepKey(Step step)
{
    switch (step) {
    case Step::Report:
        return QStringLiteral("report");
    case Step::SignOut:
        return QStringLiteral("sign_out");
    case Step::Images:
        return QStringLiteral("images");
    case Step::Service:
        return QStringLiteral("service");
    case Step::Data:
        return QStringLiteral("data");
    case Step::LoginItems:
        return QStringLiteral("login_items");
    case Step::App:
        return QStringLiteral("app");
    }
    return {};
}

QString stepLabel(Step step)
{
    switch (step) {
    case Step::Report:
        return QCoreApplication::translate("Uninstall", "Telling Simorg why");
    case Step::SignOut:
        return QCoreApplication::translate("Uninstall", "Signing out and removing your agents");
    case Step::Images:
        return QCoreApplication::translate("Uninstall", "Removing the agent runtime");
    case Step::Service:
        return QCoreApplication::translate("Uninstall", "Removing the Simorg machine service");
    case Step::Data:
        return QCoreApplication::translate("Uninstall", "Deleting Simorg's data");
    case Step::LoginItems:
        return QCoreApplication::translate("Uninstall", "Removing Simorg's login items");
    case Step::App:
        return QCoreApplication::translate("Uninstall", "Removing Simorg Desktop");
    }
    return {};
}

QString windowsUpgradeCode()
{
    return QStringLiteral("{C307B93B-59EA-4BCE-B1B9-AF66E6EE343C}");
}

QString windowsSelfRemovalScript(qint64 pid, const QString &upgradeCode, const QStringList &dataPaths)
{
    // RelatedProducts is Windows Installer's own answer to "what is installed with this upgrade code".
    QString script =
        QStringLiteral(
            "$ErrorActionPreference = 'SilentlyContinue'; "
            "Wait-Process -Id %1 -Timeout 120; "
            "$installer = New-Object -ComObject WindowsInstaller.Installer; "
            "foreach ($product in $installer.RelatedProducts('%2')) { "
            "Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $product, '/qn', '/norestart') -Wait }")
            .arg(pid)
            .arg(upgradeCode);
    if (!dataPaths.isEmpty()) {
        QStringList quoted;
        for (const QString &path : dataPaths) {
            // Windows' separators whichever system wrote the script, and every ' doubled in PowerShell's quotes.
            QString native = path;
            native.replace(QLatin1Char('/'), QLatin1Char('\\'));
            native.replace(QLatin1Char('\''), QStringLiteral("''"));
            quoted << QLatin1Char('\'') + native + QLatin1Char('\'');
        }
        script += QStringLiteral("; foreach ($path in @(%1)) { Remove-Item -LiteralPath $path -Recurse -Force }")
                      .arg(quoted.join(QStringLiteral(", ")));
    }
    return script;
}

QString removeThisCopy(desktopupdate::System system, const desktopupdate::Install &install, qint64 pid,
                       const QStringList &dataPaths)
{
    switch (system) {
    case desktopupdate::System::MacOS: {
        if (install.appName.isEmpty())
            return QCoreApplication::translate("Uninstall", "This copy of Simorg Desktop was not installed from its "
                                                            "disk image, so it stays: move it to the Trash yourself.");
        const QString bundle = QDir(install.parent).filePath(install.appName);
        if (QFile::moveToTrash(bundle))
            return {};
        return QCoreApplication::translate("Uninstall", "Simorg Desktop could not move itself to the Trash, because "
                                                        "its folder is not yours to change. Drag %1 to the Trash to "
                                                        "finish.")
            .arg(bundle);
    }
    case desktopupdate::System::Linux: {
        if (install.appName.isEmpty())
            return QCoreApplication::translate("Uninstall", "This copy of Simorg Desktop was not started from its "
                                                            "AppImage, so it stays: delete it yourself.");
        // The AppImage runs from a mount of itself, which stays until this process ends.
        const QString image = QDir(install.parent).filePath(install.appName);
        if (QFile::remove(image)) {
            removeScriptInstall(scriptInstallRecord(), QDir::homePath());
            return {};
        }
        return QCoreApplication::translate("Uninstall", "Simorg Desktop could not delete %1. Delete it to finish.")
            .arg(image);
    }
    case desktopupdate::System::Windows: {
        if (!install.reason.isEmpty())
            return QCoreApplication::translate("Uninstall", "This copy of Simorg Desktop was not installed from its "
                                                            "installer, so it stays: delete its folder yourself.");
        // Started from the home folder: the shortcut starts this app in its own folder, and Windows does not remove a
        // folder that a running process stands in, so the removal it starts would leave that folder behind, empty.
        const bool started = QProcess::startDetached(
            QStringLiteral("powershell"),
            {QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"), QStringLiteral("-WindowStyle"),
             QStringLiteral("Hidden"), QStringLiteral("-Command"),
             windowsSelfRemovalScript(pid, windowsUpgradeCode(), dataPaths)},
            QDir::homePath());
        if (!started)
            return QCoreApplication::translate("Uninstall", "Simorg Desktop could not remove itself. Remove it from "
                                                            "Settings, Apps to finish.");
        return QCoreApplication::translate("Uninstall", "Windows finishes removing it once this window closes, "
                                                        "because a running program's files cannot be removed.");
    }
    }
    return {};
}

QString removeInstalledCopy(const DesktopUpdateModel::Options &options, const QStringList &dataPaths)
{
    const desktopupdate::Install install =
        desktopupdate::locate(options.system, options.applicationDirPath, options.archiveBuild, options.appImagePath);
    return removeThisCopy(options.system, install, options.processId, dataPaths);
}

QString scriptInstallRecord()
{
    // GenericDataLocation is $XDG_DATA_HOME, or ~/.local/share without it: where the script writes.
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
        .filePath(QStringLiteral("simorg/applications/simorg-desktop.installed"));
}

void removeScriptInstall(const QString &record, const QString &home)
{
    QFile file(record);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QStringList paths = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    file.close();
    const QString inside = QDir::cleanPath(home) + QLatin1Char('/');
    for (const QString &line : paths) {
        const QString path = QDir::cleanPath(line.trimmed());
        if (!path.startsWith(inside))
            continue;
        // A link to the AppImage dangles by now, and a dangling link is still one to remove.
        const QFileInfo info(path);
        if (info.isSymLink() || info.isFile())
            QFile::remove(path);
    }
    QFile::remove(record);
}

} // namespace uninstall

using uninstall::Step;

UninstallModel::UninstallModel(ServiceSession *session, Parts parts, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_parts(std::move(parts))
{
    for (const Step step : uninstall::kSteps) {
        m_steps.append(QVariantMap{{QStringLiteral("key"), uninstall::stepKey(step)},
                                   {QStringLiteral("label"), uninstall::stepLabel(step)},
                                   {QStringLiteral("state"), QStringLiteral("pending")},
                                   {QStringLiteral("detail"), QString()}});
    }
    setParts(std::move(m_parts));
}

void UninstallModel::setParts(Parts parts)
{
    m_parts = std::move(parts);
    if (!m_parts.runner) {
        m_parts.runner = [run = serviceinstall::processRunner(this)](ServiceInstallModel::Launch launch) {
            run(launch.output, launch.done, launch.argv);
        };
    }
    if (!m_parts.elevate) {
        const serviceinstall::Platform platform = m_parts.platform;
        const QString pkexec = m_parts.pkexecPath;
        m_parts.elevate = [platform, pkexec](const QStringList &argv, const QString &reason) {
            return serviceinstall::argvUnderPrompt(platform, argv, reason, pkexec);
        };
    }
}

UninstallModel::Parts UninstallModel::defaultParts(const QString &environment)
{
    Parts parts;
    parts.environment = environment;
    parts.platform = serviceinstall::thisPlatform();
    parts.pkexecPath = QStandardPaths::findExecutable(QStringLiteral("pkexec"));
    parts.home = QDir::homePath();
    parts.desktopDataPaths = uninstall::desktopDataPaths();
    parts.serviceGone = [environment] {
        return client::Discovery::read(environment).status != client::Discovery::Status::Found;
    };
    const QString home = parts.home;
    parts.deletePath = [home](const QString &path) -> QString {
        if (!uninstall::deletable(path, home))
            return QCoreApplication::translate("Uninstall", "%1 was kept, because it does not look like Simorg's own "
                                                            "folder.")
                .arg(QDir::toNativeSeparators(path));
        QDir directory(path);
        if (!directory.exists() || directory.removeRecursively())
            return {};
        return QCoreApplication::translate("Uninstall", "Some of %1 could not be deleted.")
            .arg(QDir::toNativeSeparators(path));
    };
    return parts;
}

QVariantList UninstallModel::reasons() const
{
    QVariantList list;
    for (const QString &code : uninstall::reasonCodes())
        list << QVariantMap{{QStringLiteral("code"), code}, {QStringLiteral("label"), uninstall::reasonLabel(code)}};
    return list;
}

QVariantList UninstallModel::steps() const
{
    QVariantList list;
    for (const QVariantMap &step : m_steps)
        list << step;
    return list;
}

void UninstallModel::setStep(Step step, const QString &state, const QString &detail)
{
    const QString key = uninstall::stepKey(step);
    for (QVariantMap &row : m_steps) {
        if (row.value(QStringLiteral("key")).toString() != key)
            continue;
        row.insert(QStringLiteral("state"), state);
        row.insert(QStringLiteral("detail"), detail);
    }
    Q_EMIT changed();
}

void UninstallModel::setState(State state, const QString &status)
{
    m_state = state;
    m_status = status;
    Q_EMIT changed();
}

void UninstallModel::fail(const QString &status)
{
    setState(Failed, status);
}

void UninstallModel::start(const QStringList &reasons, const QString &comment, bool removeData)
{
    if (m_started)
        return;
    m_started = true;
    m_removeData = removeData;
    if (!removeData) {
        setStep(Step::Images, QStringLiteral("skipped"), tr("Kept, as you asked."));
        setStep(Step::Data, QStringLiteral("skipped"), tr("Kept, as you asked."));
    }
    if (!m_parts.removeApp)
        setStep(Step::App, QStringLiteral("skipped"));
    // From here the service disappearing is the point, so this app must not set it up again.
    if (m_parts.holdServiceSetup)
        m_parts.holdServiceSetup();

    if (!m_session || !m_session->isConnected()) {
        setStep(Step::Report, QStringLiteral("failed"));
        fail(tr("Simorg cannot reach the Simorg machine service on this computer, so nothing was removed. Start "
                "Simorg again and uninstall from there, or remove the service with the command in the Simorg "
                "documentation."));
        return;
    }
    // Uninstall arrived in API 1.2; an older service has none.
    const QString api = m_session->version().value(QStringLiteral("api_version")).toString();
    if (api.section(QLatin1Char('.'), 0, 0) == QLatin1String("1") && api.section(QLatin1Char('.'), 1, 1).toInt() < 2) {
        setStep(Step::Report, QStringLiteral("failed"));
        fail(tr("This Simorg machine service is too old to uninstall itself, so nothing was removed. Update it "
                "in Settings, Updates, then uninstall again."));
        return;
    }
    // From here the service is asked, and leaves with a stopped marker that names the uninstall, which no client
    // starts again on its own (ServiceClient::Options::startWhenUninstalled).
    m_asked = true;

    setState(Running, tr("Sending your answers, with no name, account or address on them."));
    setStep(Step::Report, QStringLiteral("running"));
    // Subscribed before asking, so `ready` cannot be missed.
    m_subscription = m_session->subscribe(QStringLiteral("uninstall.state"));
    connect(m_subscription, &client::TopicSubscription::received, this, &UninstallModel::received);
    connect(m_session, &ServiceSession::disconnected, this, [this] {
        if (m_ready && m_state == Running)
            waitForServiceToGo();
    });

    client::ServiceReply *reply = m_session->post(
        QStringLiteral("/v1/uninstall"),
        uninstall::requestBody(m_parts.source, m_parts.desktopVersion, reasons, comment, removeData));
    connect(reply, &client::ServiceReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->isError()) {
            setStep(Step::Report, QStringLiteral("failed"));
            fail(tr("The Simorg machine service did not start the uninstall, so nothing was removed: %1")
                     .arg(reply->problem().message()));
            return;
        }
        received(reply->object());
    });
}

void UninstallModel::received(const QJsonObject &uninstall)
{
    if (m_state != Running || m_ready)
        return;
    const QString phase = uninstall.value(QStringLiteral("phase")).toString();
    if (phase == QLatin1String("reporting")) {
        setStep(Step::Report, QStringLiteral("running"));
    } else if (phase == QLatin1String("signing_out")) {
        m_status = tr("Signing out, which stops and removes every agent running on this computer.");
        setStep(Step::Report, QStringLiteral("done"));
        setStep(Step::SignOut, QStringLiteral("running"));
    } else if (phase == QLatin1String("removing_data")) {
        m_status = tr("Removing the agent runtime image, which only Simorg uses.");
        setStep(Step::Report, QStringLiteral("done"));
        setStep(Step::SignOut, QStringLiteral("done"));
        setStep(Step::Images, QStringLiteral("running"));
    } else if (phase == QLatin1String("ready")) {
        m_status = tr("Waiting for the Simorg machine service to stop, so that it can be removed.");
        m_ready = true;
        setStep(Step::Report, QStringLiteral("done"));
        setStep(Step::SignOut, QStringLiteral("done"));
        if (m_removeData) {
            const QString message = uninstall.value(QStringLiteral("message")).toString();
            // The service says so when Docker kept the images.
            setStep(Step::Images, QStringLiteral("done"),
                    message.contains(QLatin1String("images stay")) ? message : QString());
        }
        const QJsonObject removal = uninstall.value(QStringLiteral("removal")).toObject();
        m_removal.clear();
        for (const QJsonValue &argument : removal.value(QStringLiteral("argv")).toArray())
            m_removal << argument.toString();
        m_removalReason = removal.value(QStringLiteral("reason")).toString();
        m_removalUnavailable = uninstall.value(QStringLiteral("removal_unavailable_reason")).toString();
        m_dataPaths.clear();
        for (const QJsonValue &path : uninstall.value(QStringLiteral("data_paths")).toArray())
            m_dataPaths << path.toString();
        setStep(Step::Service, QStringLiteral("running"), tr("Waiting for it to stop."));
        waitForServiceToGo();
    }
}

void UninstallModel::waitForServiceToGo()
{
    if (m_goneTimer)
        return;
    m_goneTimer = new QTimer(this);
    m_goneTimer->setInterval(250);
    m_goneWaitedMs = 0;
    connect(m_goneTimer, &QTimer::timeout, this, [this] {
        m_goneWaitedMs += m_goneTimer->interval();
        const bool gone = m_parts.serviceGone ? m_parts.serviceGone() : true;
        if (!gone && m_goneWaitedMs < m_parts.goneWithinMs)
            return;
        m_goneTimer->stop();
        if (!gone) {
            setStep(Step::Service, QStringLiteral("failed"));
            fail(tr("The Simorg machine service did not stop, so it was not removed. Try again in a moment."));
            return;
        }
        if (m_subscription && m_session) {
            m_session->release(m_subscription);
            m_subscription = nullptr;
        }
        removeService();
    });
    m_goneTimer->start();
}

void UninstallModel::removeService()
{
    if (m_removal.isEmpty()) {
        // A build tree, or a package without its uninstaller: nothing of ours to run, and the reason says what to do.
        setStep(Step::Service, QStringLiteral("skipped"), m_removalUnavailable);
        finishRemoval();
        return;
    }
    const QStringList argv = m_parts.elevate(m_removal, m_removalReason);
    if (argv.isEmpty()) {
        setStep(Step::Service, QStringLiteral("failed"));
        fail(tr("Simorg cannot ask for your password on this computer, so the Simorg machine service is stopped but "
                "still installed. Remove it by running this in a terminal: sudo %1")
                 .arg(m_removal.join(QLatin1Char(' '))));
        return;
    }
    m_output.clear();
    setState(Running, tr("Your computer is asking for an administrator's password to remove the Simorg machine "
                         "service, because it is installed for everybody on this computer."));
    setStep(Step::Service, QStringLiteral("running"), tr("Waiting for your password."));
    m_parts.runner(ServiceInstallModel::Launch{
        argv,
        [this](const QString &text) {
            m_output += text;
            Q_EMIT changed();
        },
        [this](int exitCode, const QString &problem) {
            if (!problem.isEmpty()) {
                setStep(Step::Service, QStringLiteral("failed"));
                fail(tr("The password prompt could not be opened: %1").arg(problem));
                return;
            }
            if (serviceinstall::promptDismissed(m_parts.platform, exitCode, m_output)) {
                setStep(Step::Service, QStringLiteral("pending"), tr("Stopped, still installed."));
                setState(Declined, m_parts.source == QLatin1String("cli")
                                       ? tr("The Simorg machine service is stopped but still installed, because the "
                                            "password prompt was closed. Run simorg uninstall again to remove it; "
                                            "it starts again the next time Simorg is opened.")
                                       : tr("The Simorg machine service is stopped but still installed, because the "
                                            "password prompt was closed. Try again to remove it, or close Simorg: "
                                            "it starts again the next time you open it."));
                return;
            }
            const bool msi = m_parts.platform == serviceinstall::Platform::Windows;
            // 1605: Windows no longer knows the product, which is the removal already done.
            const bool removed = msi ? serviceinstall::msiSucceeded(exitCode) || exitCode == 1605 : exitCode == 0;
            if (!removed) {
                setStep(Step::Service, QStringLiteral("failed"));
                fail(tr("The Simorg machine service could not be removed. What the removal printed is below."));
                return;
            }
            setStep(Step::Service, QStringLiteral("done"));
            finishRemoval();
        }});
}

void UninstallModel::finishRemoval()
{
    setState(Running, tr("Removing what is left."));
    // What the app's removal deletes again once the app has gone: only what may be deleted at all.
    QStringList afterwards;
    if (m_removeData) {
        setStep(Step::Data, QStringLiteral("running"));
        QStringList all = m_dataPaths;
        for (const QString &path : std::as_const(m_parts.desktopDataPaths)) {
            if (!all.contains(path))
                all << path;
        }
        QStringList problems;
        for (const QString &path : std::as_const(all)) {
            // Inside a folder that goes as a whole: nothing to do for it, and nothing to say.
            if (uninstall::insideDeletable(path, all, m_parts.home))
                continue;
            const QString problem = m_parts.deletePath ? m_parts.deletePath(path) : QString();
            if (!problem.isEmpty())
                problems << problem;
            if (uninstall::deletable(path, m_parts.home))
                afterwards << path;
        }
        setStep(Step::Data, QStringLiteral("done"), problems.join(QLatin1Char(' ')));
    }

    setStep(Step::LoginItems, QStringLiteral("running"));
    const QString loginItems = m_parts.removeLoginItems ? m_parts.removeLoginItems() : QString();
    setStep(Step::LoginItems, QStringLiteral("done"), loginItems);

    if (m_parts.removeApp) {
        setStep(Step::App, QStringLiteral("running"));
        const QString app = m_parts.removeApp(afterwards);
        setStep(Step::App, QStringLiteral("done"), app);
    }

    setState(Done, tr("Simorg is removed from this computer. Your account and your agents on simorg.tech stay, and "
                      "you can install Simorg again at any time."));
    Q_EMIT finished();
}

void UninstallModel::retry()
{
    if (m_state != Declined && m_state != Failed)
        return;
    if (!m_ready) {
        // Nothing reached the service; the uninstall starts from the beginning with the next press.
        m_started = false;
        setState(Idle, {});
        return;
    }
    removeService();
}

void UninstallModel::close()
{
    if (m_state != Declined && m_state != Failed)
        return;
    if (m_asked) {
        // The service signed out, removed the agents and stopped, and is still installed: nothing is left for this
        // app to show, so it closes. Opening Simorg again starts the service.
        Q_EMIT closed();
        return;
    }
    // Nothing reached the service, so nothing changed: the window goes, and Simorg is as it was.
    m_started = false;
    m_ready = false;
    for (QVariantMap &row : m_steps) {
        row.insert(QStringLiteral("state"), QStringLiteral("pending"));
        row.insert(QStringLiteral("detail"), QString());
    }
    setState(Idle, {});
}

} // namespace simorg::app
