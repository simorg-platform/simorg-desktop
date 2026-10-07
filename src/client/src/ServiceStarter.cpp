// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "ServiceStarter.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>
#include <QtGlobal>

#ifdef Q_OS_WIN
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace simorg::client::detail {
namespace {

constexpr int toolTimeoutMs = 10'000;

struct ToolResult
{
    /** The tool is on PATH. */
    bool found = false;
    /** It ran to an exit of its own; `exitCode` is that exit. */
    bool exited = false;
    int exitCode = -1;
    QString output;
};

/** Runs a system tool to completion, with its output kept for a message. */
ToolResult runTool(const QString &program, const QStringList &arguments)
{
    ToolResult result;
    const QString path = QStandardPaths::findExecutable(program);
    if (path.isEmpty())
        return result;
    result.found = true;

    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.setStandardInputFile(QProcess::nullDevice());
    process.start(path, arguments);
    if (!process.waitForFinished(toolTimeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        result.output = QStringLiteral("%1 did not finish").arg(program);
        return result;
    }
    result.exited = process.exitStatus() == QProcess::NormalExit;
    result.exitCode = process.exitCode();
    result.output = QString::fromUtf8(process.readAll()).trimmed();
    return result;
}

/** `<binary> run --env <environment>`, detached so that the caller ending does not end it. */
StartOutcome launchBinary(const QString &binary, const QString &environment)
{
    const QFileInfo info(binary);
    if (!info.isFile() || !info.isExecutable())
        return {StartOutcome::Kind::NotInstalled, QStringLiteral("%1 is not an executable file").arg(binary)};

    QProcess process;
    process.setProgram(info.absoluteFilePath());
    process.setArguments({QStringLiteral("run"), QStringLiteral("--env"), environment});
    process.setWorkingDirectory(QDir::homePath());

#ifdef Q_OS_WIN
    const auto launch = [&process](bool breakAway) {
        process.setCreateProcessArgumentsModifier([breakAway](QProcess::CreateProcessArguments *arguments) {
            arguments->flags &= ~DWORD(CREATE_NEW_CONSOLE | DETACHED_PROCESS);
            arguments->flags |= CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP;
            if (breakAway)
                arguments->flags |= CREATE_BREAKAWAY_FROM_JOB;
            arguments->inheritHandles = FALSE;
        });
        return process.startDetached();
    };
    // A job that does not allow breaking away refuses the flag; the service then lives in the job.
    if (launch(true) || launch(false))
        return {StartOutcome::Kind::Asked, {}};
#else
    // Its own session, so a Ctrl-C in the terminal that started it never reaches it.
    process.setStandardInputFile(QProcess::nullDevice());
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
    process.setUnixProcessParameters(QProcess::UnixProcessFlag::CreateNewSession
                                     | QProcess::UnixProcessFlag::CloseFileDescriptors
                                     | QProcess::UnixProcessFlag::ResetSignalHandlers);
#else
    process.setChildProcessModifier([] { setsid(); });
#endif
    if (process.startDetached())
        return {StartOutcome::Kind::Asked, {}};
#endif
    return {StartOutcome::Kind::Failed,
            QStringLiteral("%1 could not be started: %2").arg(binary, process.errorString())};
}

#if defined(Q_OS_MACOS)

QString launchdLabel(const QString &environment)
{
    return environment == QLatin1String("dev") ? QStringLiteral("tech.simorg.machine.dev")
                                               : QStringLiteral("tech.simorg.machine");
}

StartOutcome startWithLaunchd(const QString &environment)
{
    const QString label = launchdLabel(environment);
    const QString domain = QStringLiteral("gui/%1").arg(getuid());

    const ToolResult kicked =
        runTool(QStringLiteral("launchctl"), {QStringLiteral("kickstart"), domain + QLatin1Char('/') + label});
    if (kicked.exited && kicked.exitCode == 0)
        return {StartOutcome::Kind::Asked, {}};

    // Not loaded, which a person booting it out leaves behind: load it again from its file.
    const QString file = label + QStringLiteral(".plist");
    for (const QString &directory :
         {QDir::homePath() + QStringLiteral("/Library/LaunchAgents"), QStringLiteral("/Library/LaunchAgents")}) {
        const QString plist = directory + QLatin1Char('/') + file;
        if (!QFileInfo(plist).isFile())
            continue;
        const ToolResult loaded = runTool(QStringLiteral("launchctl"), {QStringLiteral("bootstrap"), domain, plist});
        if (loaded.exited && loaded.exitCode == 0)
            return {StartOutcome::Kind::Asked, {}};
        return {StartOutcome::Kind::Failed,
                QStringLiteral("launchd could not start %1: %2").arg(plist, loaded.output)};
    }
    return {StartOutcome::Kind::NotInstalled, {}};
}

#elif defined(Q_OS_LINUX)

QString systemdUnit(const QString &environment)
{
    return environment == QLatin1String("dev") ? QStringLiteral("simorgm-dev.service")
                                               : QStringLiteral("simorgm.service");
}

StartOutcome startWithSystemd(const QString &environment)
{
    const QString unit = systemdUnit(environment);
    const ToolResult started =
        runTool(QStringLiteral("systemctl"),
                {QStringLiteral("--user"), QStringLiteral("start"), QStringLiteral("--no-block"), unit});
    if (!started.found)
        return {StartOutcome::Kind::NotInstalled, QStringLiteral("this computer has no systemctl")};
    if (started.exited && started.exitCode == 0)
        return {StartOutcome::Kind::Asked, {}};
    // 5 is systemctl's "no such unit" (LSB "program is not installed").
    if (started.exited && started.exitCode == 5)
        return {StartOutcome::Kind::NotInstalled, {}};
    return {StartOutcome::Kind::Failed, QStringLiteral("systemd could not start %1: %2").arg(unit, started.output)};
}

#endif

} // namespace

StartOutcome startService(const QString &environment)
{
    const QString binary = qEnvironmentVariable("SIMORGM_BINARY");
    if (!binary.isEmpty())
        return launchBinary(binary, environment);

#if defined(Q_OS_MACOS)
    return startWithLaunchd(environment);
#elif defined(Q_OS_LINUX)
    return startWithSystemd(environment);
#elif defined(Q_OS_WIN)
    QString programFiles = qEnvironmentVariable("ProgramW6432");
    if (programFiles.isEmpty())
        programFiles = qEnvironmentVariable("ProgramFiles");
    const QString installed = QDir::cleanPath(programFiles + QStringLiteral("/Simorg/simorgm.exe"));
    if (programFiles.isEmpty() || !QFileInfo(installed).isFile())
        return {StartOutcome::Kind::NotInstalled, {}};
    return launchBinary(QDir::toNativeSeparators(installed), environment);
#else
    return {StartOutcome::Kind::NotInstalled, {}};
#endif
}

bool stopService(const QString &environment)
{
    if (!qEnvironmentVariable("SIMORGM_BINARY").isEmpty())
        return false;

#if defined(Q_OS_MACOS)
    /*
      `bootout` rather than `launchctl kill SIGTERM`, tried against a job that
      ignores the signal: the signal alone left it running, where
      `bootout` returned at once and launchd sent SIGTERM, then SIGKILL once the
      job's ExitTimeOut ran out, and did not start it again. It also ends a job
      launchd keeps respawning. The job is unloaded for this login only — the
      plist stays — and the next launch's start loads it again from its file.
    */
    const ToolResult bootedOut = runTool(QStringLiteral("launchctl"),
                                         {QStringLiteral("bootout"),
                                          QStringLiteral("gui/%1/%2").arg(getuid()).arg(launchdLabel(environment))});
    return bootedOut.exited && bootedOut.exitCode == 0;
#elif defined(Q_OS_LINUX)
    // Also ends a start that is still under way and the restarts Restart=on-failure would make after it.
    const ToolResult stopped =
        runTool(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("stop"),
                                              QStringLiteral("--no-block"), systemdUnit(environment)});
    return stopped.exited && stopped.exitCode == 0;
#else
    Q_UNUSED(environment);
    return false;
#endif
}

} // namespace simorg::client::detail
