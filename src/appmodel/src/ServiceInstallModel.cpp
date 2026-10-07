// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/ServiceInstallModel.h"

#include "simorg/client/ServiceSession.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimer>
#include <QVersionNumber>

namespace simorg::app {

namespace serviceinstall {

namespace {

const QString kInstallScriptUrl = QStringLiteral("https://install.simorg.tech/simorgm");
const QString kDownloadHost = QStringLiteral("https://download.simorg.tech");

/** One word for a POSIX shell: single-quoted, each `'` written as `'\''`. */
QString shellQuoted(const QString &word)
{
    QString quoted = word;
    quoted.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + quoted + QLatin1Char('\'');
}

/** Text for the inside of an AppleScript string literal. */
QString appleScriptEscaped(const QString &text)
{
    QString escaped = text;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    return escaped;
}

/** Text as a single-quoted PowerShell string: each `'` doubled. */
QString powerShellQuoted(const QString &text)
{
    QString quoted = text;
    quoted.replace(QLatin1Char('\''), QStringLiteral("''"));
    return QLatin1Char('\'') + quoted + QLatin1Char('\'');
}

/**
 * One argument of a Windows command line as the C runtime reads it back, quoted
 * only when it must be: empty, or holding a space, a tab, a line break or a
 * quote. msiexec reads its own command line and takes no quoted switch: given
 * "/x" it opens its usage window and removes nothing.
 */
QString windowsArgument(const QString &argument)
{
    static const QRegularExpression needsQuotes(QStringLiteral("[ \\t\\n\\v\"]"));
    if (!argument.isEmpty() && !argument.contains(needsQuotes))
        return argument;
    // Backslashes are literal unless a quote follows them: those before a quote, and before the closing one, double.
    QString quoted(QLatin1Char('"'));
    qsizetype backslashes = 0;
    for (const QChar character : argument) {
        if (character == QLatin1Char('\\')) {
            ++backslashes;
            continue;
        }
        quoted += QString(character == QLatin1Char('"') ? (backslashes * 2) + 1 : backslashes, QLatin1Char('\\'));
        quoted += character;
        backslashes = 0;
    }
    quoted += QString(backslashes * 2, QLatin1Char('\\'));
    quoted += QLatin1Char('"');
    return quoted;
}

QString trimmedHost(const QString &host)
{
    QString trimmed = host;
    while (trimmed.endsWith(QLatin1Char('/')))
        trimmed.chop(1);
    return trimmed;
}

} // namespace

Platform thisPlatform()
{
#if defined(Q_OS_MACOS)
    return Platform::MacOS;
#elif defined(Q_OS_WIN)
    return Platform::Windows;
#else
    return Platform::Linux;
#endif
}

QString installScriptUrl()
{
    const QString overridden = qEnvironmentVariable("SIMORG_INSTALL_URL");
    return overridden.isEmpty() ? kInstallScriptUrl : overridden;
}

QString downloadHost()
{
    const QString overridden = qEnvironmentVariable("SIMORG_DOWNLOAD_HOST");
    return trimmedHost(overridden.isEmpty() ? kDownloadHost : overridden);
}

QString terminalCommand(const QString &scriptUrl)
{
    return QStringLiteral("curl -fsSL %1 | sh").arg(scriptUrl);
}

QString fetchAndRunScript(const QString &scriptUrl, const QString &host)
{
    /*
      Everything the script prints goes to a log, and the log is replayed on
      stdout when it succeeds and on stderr when it does not. macOS's `do shell
      script` keeps only stderr of a command that fails, so without this the
      reason an install stopped is exactly the text that would be lost.
    */
    const QString tls = scriptUrl.startsWith(QLatin1String("https://"))
                            ? QStringLiteral(" --proto '=https' --tlsv1.2")
                            : QString();
    const QString env = trimmedHost(host) == kDownloadHost
                            ? QString()
                            : QStringLiteral("SIMORG_DOWNLOAD_HOST=%1 ").arg(shellQuoted(trimmedHost(host)));
    return QStringLiteral("f=$(mktemp) || exit 1; l=$(mktemp) || exit 1; "
                          "if curl -fsSL%1 %2 -o \"$f\" >\"$l\" 2>&1; "
                          "then %3sh \"$f\" >>\"$l\" 2>&1; s=$?; "
                          "else echo 'Could not download the install script from %4' >>\"$l\"; s=1; fi; "
                          "if [ \"$s\" -eq 0 ]; then cat \"$l\"; else cat \"$l\" >&2; fi; "
                          "rm -f \"$f\" \"$l\"; exit \"$s\"")
        .arg(tls, shellQuoted(scriptUrl), env, QString(scriptUrl).remove(QLatin1Char('\'')));
}

QStringList scriptUnderPrompt(Platform platform, const QString &script, const QString &pkexecPath)
{
    switch (platform) {
    case Platform::MacOS:
        // `without altering line endings`, or AppleScript hands the output back with \r for \n.
        return {QStringLiteral("/usr/bin/osascript"), QStringLiteral("-e"),
                QStringLiteral("do shell script \"%1\" with administrator privileges without altering line endings")
                    .arg(appleScriptEscaped(script))};
    case Platform::Linux:
        if (pkexecPath.isEmpty())
            return {};
        // An absolute program: pkexec refuses to look one up on PATH.
        return {pkexecPath, QStringLiteral("/bin/sh"), QStringLiteral("-c"), script};
    case Platform::Windows:
        return {};
    }
    return {};
}

std::optional<WindowsPackage> newestWindowsPackage(const QByteArray &indexJson, const QString &host,
                                                   const QString &target)
{
    const QJsonDocument document = QJsonDocument::fromJson(indexJson);
    if (!document.isObject())
        return std::nullopt;
    const QJsonObject versions = document.object().value(QStringLiteral("versions")).toObject();
    static const QRegularExpression kVersion(QStringLiteral("^\\d+\\.\\d+\\.\\d+$"));
    static const QRegularExpression kSha256(QStringLiteral("^[0-9a-f]{64}$"));
    static const QRegularExpression kName(QStringLiteral("^[\\w.+-]+\\.msi$"));

    std::optional<WindowsPackage> newest;
    for (auto it = versions.constBegin(); it != versions.constEnd(); ++it) {
        if (!kVersion.match(it.key()).hasMatch())
            continue;
        const QJsonArray files = it.value().toObject().value(target).toObject().value(QStringLiteral("files")).toArray();
        for (const QJsonValue &value : files) {
            const QJsonObject file = value.toObject();
            const QString name = file.value(QStringLiteral("name")).toString();
            const QString sha256 = file.value(QStringLiteral("sha256")).toString();
            const qint64 size = file.value(QStringLiteral("size")).toInteger();
            if (!kName.match(name).hasMatch() || !kSha256.match(sha256).hasMatch() || size <= 0)
                continue;
            if (newest && QVersionNumber::fromString(it.key()) <= QVersionNumber::fromString(newest->version))
                continue;
            newest = WindowsPackage{it.key(), name, sha256, size,
                                    QUrl(QStringLiteral("%1/binaries/simorgm/%2/%3/%4")
                                             .arg(trimmedHost(host), it.key(), target, name))};
        }
    }
    return newest;
}

QStringList msiUnderPrompt(const QString &msiPath)
{
    /*
      Start-Process joins its arguments with spaces and quotes none of them, so a
      path under a user folder with a space in it would reach msiexec in pieces.
      The path is wrapped in double quotes inside the PowerShell string for that.
    */
    const QString path = QDir::toNativeSeparators(msiPath);
    const QString script =
        QStringLiteral("$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', %1, '/passive', '/norestart') "
                       "-Verb RunAs -Wait -PassThru; exit $p.ExitCode")
            .arg(powerShellQuoted(QLatin1Char('"') + path + QLatin1Char('"')));
    return {QStringLiteral("powershell"), QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"),
            QStringLiteral("-Command"), script};
}

QString packageTarget(Platform platform, const QString &cpuArchitecture)
{
    const bool arm = cpuArchitecture.startsWith(QLatin1String("arm")) || cpuArchitecture == QLatin1String("aarch64");
    switch (platform) {
    case Platform::MacOS:
        // One universal package, whichever chip.
        return QStringLiteral("macos/universal");
    case Platform::Linux:
        return arm ? QStringLiteral("linux/arm64") : QStringLiteral("linux/x64");
    case Platform::Windows:
        return arm ? QStringLiteral("windows/arm64") : QStringLiteral("windows/x64");
    }
    return {};
}

bool publishedFor(const QByteArray &indexJson, const QString &target)
{
    const QJsonDocument document = QJsonDocument::fromJson(indexJson);
    if (!document.isObject())
        return false;
    const QJsonObject versions = document.object().value(QStringLiteral("versions")).toObject();
    for (auto it = versions.constBegin(); it != versions.constEnd(); ++it) {
        const QJsonArray files =
            it.value().toObject().value(target).toObject().value(QStringLiteral("files")).toArray();
        for (const QJsonValue &file : files) {
            if (!file.toObject().value(QStringLiteral("name")).toString().isEmpty())
                return true;
        }
    }
    return false;
}

bool msiSucceeded(int exitCode)
{
    // 3010: installed, a restart is pending; 1641: installed, and the installer started the restart.
    return exitCode == 0 || exitCode == 3010 || exitCode == 1641;
}

QStringList argvUnderPrompt(Platform platform, const QStringList &argv, const QString &reason,
                            const QString &pkexecPath)
{
    if (argv.isEmpty())
        return {};
    switch (platform) {
    case Platform::MacOS: {
        QStringList words;
        for (const QString &word : argv)
            words << shellQuoted(word);
        return {QStringLiteral("/usr/bin/osascript"), QStringLiteral("-e"),
                QStringLiteral("do shell script \"%1\" with prompt \"%2\" with administrator privileges "
                               "without altering line endings")
                    .arg(appleScriptEscaped(words.join(QLatin1Char(' '))), appleScriptEscaped(reason))};
    }
    case Platform::Linux:
        if (pkexecPath.isEmpty())
            return {};
        // The program is absolute already: every uninstaller the service names is.
        return QStringList{pkexecPath} + argv;
    case Platform::Windows: {
        // Start-Process joins its arguments with spaces and quotes none of them, so an argument that needs quotes
        // carries them inside the PowerShell string; a switch such as /x must not, or msiexec will not read it.
        QStringList arguments;
        for (qsizetype index = 1; index < argv.size(); ++index)
            arguments << powerShellQuoted(windowsArgument(argv.at(index)));
        const QString script =
            QStringLiteral("$p = Start-Process -FilePath %1 -ArgumentList @(%2) -Verb RunAs -Wait -PassThru; "
                           "exit $p.ExitCode")
                .arg(powerShellQuoted(argv.first()), arguments.join(QStringLiteral(", ")));
        return {QStringLiteral("powershell"), QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"),
                QStringLiteral("-Command"), script};
    }
    }
    return {};
}

bool promptDismissed(Platform platform, int exitCode, const QString &output)
{
    switch (platform) {
    case Platform::MacOS:
        return exitCode != 0 && output.contains(QLatin1String("(-128)"));
    case Platform::Linux:
        return exitCode == 126;
    case Platform::Windows:
        return exitCode == 1602 || output.contains(QLatin1String("canceled by the user"), Qt::CaseInsensitive);
    }
    return false;
}

std::function<void(std::function<void(const QString &)> output, std::function<void(int, const QString &)> done,
                   const QStringList &argv)>
processRunner(QObject *owner)
{
    QPointer<QObject> guard(owner);
    return [guard](std::function<void(const QString &)> output, std::function<void(int, const QString &)> done,
                   const QStringList &argv) {
        if (!guard || argv.isEmpty()) {
            done(-1, QStringLiteral("There is nothing to run."));
            return;
        }
        auto *process = new QProcess(guard);
        process->setProcessChannelMode(QProcess::MergedChannels);
        QObject::connect(process, &QProcess::readyRead, process,
                         [process, output] { output(QString::fromUtf8(process->readAll())); });
        QObject::connect(process, &QProcess::finished, process,
                         [process, output, done](int exitCode, QProcess::ExitStatus status) {
                             output(QString::fromUtf8(process->readAll()));
                             done(status == QProcess::NormalExit ? exitCode : -1, {});
                             process->deleteLater();
                         });
        QObject::connect(process, &QProcess::errorOccurred, process, [process, done](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                done(-1, process->errorString());
                process->deleteLater();
            }
        });
        process->start(argv.first(), argv.mid(1));
    };
}

} // namespace serviceinstall

namespace {

/** How much of what the installer printed is kept: plenty for apt, not a log file. */
constexpr qsizetype kOutputCap = 64 * 1024;

} // namespace

ServiceInstallModel::ServiceInstallModel(client::ServiceSession *session, const QString &environment, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_platform(serviceinstall::thisPlatform())
    , m_environment(environment)
    , m_pkexec(QStandardPaths::findExecutable(QStringLiteral("pkexec")))
{
    if (environment != QLatin1String("prod")) {
        m_unavailableReason =
            tr("This development build uses the machine service built from simorg-machine, which no published package "
               "sets up. Register that one with simorgm service install.");
    } else if (m_platform == serviceinstall::Platform::Linux && m_pkexec.isEmpty()) {
        m_unavailableReason = tr("Simorg cannot ask for your password here, because this computer has no pkexec. "
                                 "Running this in a terminal adds the Simorg machine service:");
    }

    // The default: the command as a process, under the prompt it opens itself.
    m_runner = [run = serviceinstall::processRunner(this)](Launch launch) {
        run(launch.output, launch.done, launch.argv);
    };

    // The default check: the script, then the index, as anybody could read them, before anything asks for a password.
    m_preflight = [this](std::function<void(const QString &problem)> done) {
        if (!m_network)
            m_network = new QNetworkAccessManager(this);
        const QUrl script(serviceinstall::installScriptUrl());
        const QString host = serviceinstall::downloadHost();
        const auto unreachable = [](QNetworkReply *reply, const QString &where) {
            const QNetworkReply::NetworkError error = reply->error();
            // What S3 and CloudFront answer for a key nobody has published.
            if (error == QNetworkReply::ContentNotFoundError || error == QNetworkReply::ContentAccessDenied)
                return tr("The Simorg machine service is not published for download yet");
            return tr("Simorg could not reach %1 (%2)").arg(where, reply->errorString());
        };
        QNetworkReply *fetched = m_network->get(QNetworkRequest(script));
        connect(fetched, &QNetworkReply::finished, this, [this, fetched, host, script, done, unreachable] {
            fetched->deleteLater();
            const QNetworkReply::NetworkError error = fetched->error();
            // The packages can be up without it: said as what is missing, which is the installer, not the service.
            if (error == QNetworkReply::ContentNotFoundError || error == QNetworkReply::ContentAccessDenied) {
                done(tr("The installer that sets up the Simorg machine service is not published yet"));
                return;
            }
            if (error != QNetworkReply::NoError) {
                done(unreachable(fetched, script.host()));
                return;
            }
            QNetworkReply *index =
                m_network->get(QNetworkRequest(QUrl(host + QStringLiteral("/binaries/simorgm/index.json"))));
            connect(index, &QNetworkReply::finished, this, [this, index, done, unreachable] {
                index->deleteLater();
                if (index->error() != QNetworkReply::NoError) {
                    done(unreachable(index, index->url().host()));
                    return;
                }
                const QString target = serviceinstall::packageTarget(m_platform, QSysInfo::currentCpuArchitecture());
                if (!serviceinstall::publishedFor(index->readAll(), target)) {
                    done(tr("No version of the Simorg machine service is published for this computer (%1) yet")
                             .arg(target));
                    return;
                }
                done({});
            });
        });
    };

    // Nothing to press: the session finding no service is what starts the setup.
    if (m_session) {
        connect(m_session, &client::ServiceSession::unavailable, this,
                [this](client::ServiceClient::Unavailable reason, const QString &) {
                    if (reason != client::ServiceClient::Unavailable::NotInstalled)
                        return;
                    /*
                      Still not there well after a setup that said it finished: a
                      package that put nothing where the service is looked for. Said,
                      rather than "Connecting…" forever. The margin lets a check that
                      was already under way when the setup finished report its old news.
                    */
                    if (m_state == Succeeded && m_succeededAt.isValid() && m_succeededAt.elapsed() > 5000) {
                        fail(tr("The setup finished, but the machine service is still not on this computer. What "
                                "the setup printed is below."));
                        return;
                    }
                    setUp();
                });
    }
}

QString ServiceInstallModel::terminalCommand() const
{
    // Only where this app cannot run it: anywhere else a command to copy is noise beside a setup already under way.
    if (m_environment != QLatin1String("prod") || m_platform != serviceinstall::Platform::Linux || !m_pkexec.isEmpty())
        return {};
    return serviceinstall::terminalCommand(serviceinstall::installScriptUrl());
}

QString ServiceInstallModel::step() const
{
    switch (m_state) {
    case Idle:
        return {};
    case Running:
        return m_downloading ? tr("Downloading…") : tr("Setting up…");
    case Succeeded:
        return tr("Added");
    case Declined:
        return tr("Not added");
    case Failed:
        return tr("Did not finish");
    }
    return {};
}

void ServiceInstallModel::setRunner(Runner runner)
{
    m_runner = std::move(runner);
}

void ServiceInstallModel::checkPublished(const std::function<void(const QString &problem)> &done)
{
    if (m_platform == serviceinstall::Platform::Windows || !m_preflight) {
        done({});
        return;
    }
    m_preflight(done);
}

void ServiceInstallModel::setPreflight(Preflight preflight)
{
    m_preflight = std::move(preflight);
}

void ServiceInstallModel::setUp()
{
    // Once per launch. A closed prompt is an answer, and asking again is the person's press, never a loop.
    if (m_attempted || m_held || !isAvailable() || m_state == Running)
        return;
    // A moment first, so the window that says what is happening is on screen before the prompt covers it.
    start(m_leadMs);
}

void ServiceInstallModel::hold()
{
    m_held = true;
}

void ServiceInstallModel::install()
{
    if (!isAvailable() || m_state == Running)
        return;
    start(0);
}

void ServiceInstallModel::start(int leadMs)
{
    m_attempted = true;
    m_downloading = false;
    m_output.clear();
    setState(Running, tr("Finding the newest Simorg machine service for this computer."));
    if (leadMs > 0)
        QTimer::singleShot(leadMs, this, &ServiceInstallModel::begin);
    else
        begin();
}

QString ServiceInstallModel::askingSentence() const
{
    return m_platform == serviceinstall::Platform::MacOS
               ? tr("macOS asks for your password once to add it. It takes about a minute.")
               : tr("Your system asks for your password once to add it. It takes about a minute.");
}

void ServiceInstallModel::begin()
{
    // Windows reads the index and checks the package itself before its own prompt.
    if (m_platform == serviceinstall::Platform::Windows) {
        installOnWindows();
        return;
    }
    /*
      Checked first, as anybody could, so nobody types a password for a setup that
      cannot succeed. The download that is run stays inside the privileged shell:
      a script fetched here would sit in a file this user can write, and be run as
      root after whatever else runs as this user had its chance to change it.
    */
    m_preflight([this](const QString &problem) {
        if (m_state != Running)
            return;
        if (!problem.isEmpty()) {
            fail(tr("%1, so nothing was installed and no password was asked for.").arg(problem));
            return;
        }
        setState(Running, askingSentence());
        runUnderPrompt(serviceinstall::scriptUnderPrompt(
            m_platform,
            serviceinstall::fetchAndRunScript(serviceinstall::installScriptUrl(), serviceinstall::downloadHost()),
            m_pkexec));
    });
}

void ServiceInstallModel::runUnderPrompt(const QStringList &argv)
{
    if (argv.isEmpty()) {
        fail(tr("This computer has no way for Simorg to ask for your password."));
        return;
    }
    m_runner(Launch{argv, [this](const QString &text) { append(text); },
                    [this](int exitCode, const QString &problem) {
                        if (!problem.isEmpty()) {
                            fail(tr("The password prompt could not be opened: %1").arg(problem));
                            return;
                        }
                        finished(exitCode);
                    }});
}

void ServiceInstallModel::installOnWindows()
{
    if (!m_network)
        m_network = new QNetworkAccessManager(this);
    const QString host = serviceinstall::downloadHost();

    QNetworkReply *index = m_network->get(QNetworkRequest(QUrl(host + QStringLiteral("/binaries/simorgm/index.json"))));
    // windows/arm64 on an ARM PC: its own build, never the x64 one run under emulation.
    const QString target = serviceinstall::packageTarget(m_platform, QSysInfo::currentCpuArchitecture());
    connect(index, &QNetworkReply::finished, this, [this, index, host, target] {
        index->deleteLater();
        const auto package = index->error() == QNetworkReply::NoError
                                 ? serviceinstall::newestWindowsPackage(index->readAll(), host, target)
                                 : std::nullopt;
        if (!package) {
            fail(index->error() == QNetworkReply::NoError || index->error() == QNetworkReply::ContentAccessDenied ||
                         index->error() == QNetworkReply::ContentNotFoundError
                     ? tr("No version of the Simorg machine service is published for this computer (%1) yet.")
                           .arg(target)
                     : tr("Could not reach %1: %2").arg(host, index->errorString()));
            return;
        }

        m_downloading = true;
        setState(Running, tr("Downloading it (%1 MB).").arg(double(package->size) / 1e6, 0, 'f', 1));
        QNetworkReply *download = m_network->get(QNetworkRequest(package->url));
        connect(download, &QNetworkReply::finished, this, [this, download, msi = *package] {
            download->deleteLater();
            m_downloading = false;
            if (download->error() != QNetworkReply::NoError) {
                fail(tr("Could not download %1: %2").arg(msi.name, download->errorString()));
                return;
            }
            const QByteArray bytes = download->readAll();
            const QString actual = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
            if (actual != msi.sha256) {
                fail(tr("%1 does not match its published checksum, so nothing was added.").arg(msi.name));
                return;
            }
            const QString path = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(msi.name);
            QFile file(path);
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) || file.write(bytes) != bytes.size()) {
                fail(tr("Could not save %1 to %2.").arg(msi.name, QDir::toNativeSeparators(path)));
                return;
            }
            file.close();
            append(tr("Downloaded %1, SHA-256 %2, checksum verified.\n").arg(msi.name, msi.sha256));
            setState(Running, tr("Windows asks for your permission once to add it."));
            runUnderPrompt(serviceinstall::msiUnderPrompt(path));
        });
    });
}

void ServiceInstallModel::finished(int exitCode)
{
    const bool succeeded = m_platform == serviceinstall::Platform::Windows ? serviceinstall::msiSucceeded(exitCode)
                                                                           : exitCode == 0;
    if (succeeded) {
        m_succeededAt.start();
        setState(Succeeded, tr("Added. Connecting to it now."));
        // The person let Simorg add it, which is also what may start a service this app finds stopped.
        if (m_session)
            m_session->resumeService();
        return;
    }
    if (serviceinstall::promptDismissed(m_platform, exitCode, m_output)) {
        setState(Declined, m_platform == serviceinstall::Platform::Windows
                               ? tr("The permission prompt was closed, so nothing was added. Simorg Desktop needs "
                                    "the machine service to run your agents.")
                               : tr("The password prompt was closed, so nothing was added. Simorg Desktop needs the "
                                    "machine service to run your agents."));
        return;
    }
    fail(tr("Setting it up did not finish. What it printed is below."));
}

void ServiceInstallModel::fail(const QString &status)
{
    setState(Failed, status);
}

void ServiceInstallModel::append(const QString &text)
{
    if (text.isEmpty())
        return;
    m_output += text;
    if (m_output.size() > kOutputCap)
        m_output = m_output.right(kOutputCap);
    Q_EMIT changed();
}

void ServiceInstallModel::setState(State state, const QString &status)
{
    m_state = state;
    m_status = status;
    Q_EMIT changed();
}

} // namespace simorg::app
