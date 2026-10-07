// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/SimorgCli.h"

#include "simorg/frontend/Logging.h"
#include "simorg/frontend/OldTerminalCommands.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>

#include <utility>

namespace simorg {
namespace {

/** The `simorg` of one document, or empty; a document naming its `qt` is an older Simorg Desktop's command. */
QString versionIn(const QByteArray &document)
{
    QJsonParseError error{};
    const QJsonDocument parsed = QJsonDocument::fromJson(document.trimmed(), &error);
    if (error.error != QJsonParseError::NoError || !parsed.isObject())
        return {};
    const QJsonObject object = parsed.object();
    if (object.contains(QLatin1String("qt")))
        return {};
    return object.value(QLatin1String("simorg")).toString().trimmed();
}

/** An environment variable, or `fallback` when it is unset or empty. */
QString variable(const QProcessEnvironment &environment, const QString &name, const QString &fallback)
{
    const QString value = environment.value(name);
    return value.isEmpty() ? fallback : value;
}

} // namespace

SimorgCli::SimorgCli(QString environment, QObject *parent, int answerLimitMs)
    : QObject(parent)
    , m_environment(std::move(environment))
    , m_answerLimitMs(answerLimitMs)
{
}

void SimorgCli::check()
{
    if (m_process)
        return;
    check(candidatesOnThisComputer());
}

void SimorgCli::check(const QStringList &programs)
{
    if (m_process)
        return;
    m_queue = programs;
    tryNext();
}

void SimorgCli::tryNext()
{
    if (m_queue.isEmpty()) {
        finish({}, {});
        return;
    }
    const QString program = m_queue.takeFirst();
    auto *process = new QProcess(this);
    m_process = process;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("SIMORG_ENV"), m_environment);
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());

    auto *limit = new QTimer(process);
    limit->setSingleShot(true);
    connect(limit, &QTimer::timeout, process, &QProcess::kill);
    connect(process, &QProcess::finished, this, [this, process, program](int code, QProcess::ExitStatus status) {
        const QString version = status == QProcess::NormalExit && code == 0
                                    ? reportedVersion(process->readAllStandardOutput())
                                    : QString();
        process->deleteLater();
        if (!version.isEmpty()) {
            finish(program, version);
            return;
        }
        tryNext();
    });
    // Every other error ends in `finished` as well; a program that never started does not.
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        tryNext();
    });
    process->start(program, {QStringLiteral("version"), QStringLiteral("--json")});
    limit->start(m_answerLimitMs);
}

void SimorgCli::finish(const QString &program, const QString &version)
{
    m_process.clear();
    m_queue.clear();
    const bool news = !m_checked || version != m_version || program != m_program;
    m_checked = true;
    m_version = version;
    m_program = program;
    if (!news)
        return;
    if (version.isEmpty())
        qCInfo(lcApp) << "Simorg CLI is not installed";
    else
        qCInfo(lcApp).noquote() << "Simorg CLI" << version << "at" << program;
    Q_EMIT changed();
}

QStringList SimorgCli::candidates(const QString &home, const QString &dataHome, const QString &localAppData,
                                  const QStringList &path, const QString &appImage)
{
    QStringList found;
    QStringList seen;
    const auto consider = [&](const QString &file) {
        const QFileInfo info(file);
        if (!info.isFile() || !info.isExecutable())
            return;
        // An older Simorg Desktop's command: by the link it made, and by where any chain of links ends.
        if (info.isSymLink() && oldterminalcommands::madeByOlderDesktop(info.symLinkTarget(), appImage))
            return;
        const QString real = info.canonicalFilePath();
        if (oldterminalcommands::madeByOlderDesktop(real, appImage) || seen.contains(real))
            return;
        seen << real;
        found << info.absoluteFilePath();
    };

#ifdef Q_OS_WIN
    Q_UNUSED(home);
    Q_UNUSED(dataHome);
    const QStringList names{QStringLiteral("sim.exe"), QStringLiteral("simorg.exe")};
    // Its installer's folder (packaging/windows/simorg-cli.wxs), which it also puts on the person's PATH.
    QStringList folders{QDir(localAppData).absoluteFilePath(QStringLiteral("Programs/Simorg CLI"))};
#else
    Q_UNUSED(localAppData);
    const QStringList names{QStringLiteral("sim"), QStringLiteral("simorg")};
    // What install.simorg.tech/app put in place, one path per line: the program, then its links.
    QFile record(QDir(dataHome).absoluteFilePath(QStringLiteral("simorg/applications/simorg-cli.installed")));
    if (record.open(QIODevice::ReadOnly | QIODevice::Text)) {
        for (const QByteArray &line : record.readAll().split('\n')) {
            if (!line.trimmed().isEmpty())
                consider(QString::fromUtf8(line.trimmed()));
        }
    }
    // The folders in a home Simorg CLI puts its commands in (simorg-cli src/base/path_rules.hpp).
    const QDir homeDir(home);
    QStringList folders{homeDir.absoluteFilePath(QStringLiteral(".local/bin")),
                        homeDir.absoluteFilePath(QStringLiteral("bin"))};
#endif
    folders << path;
    for (const QString &folder : std::as_const(folders)) {
        if (folder.isEmpty())
            continue;
        for (const QString &name : names)
            consider(QDir(folder).absoluteFilePath(name));
    }
    return found;
}

QStringList SimorgCli::candidatesOnThisComputer()
{
    const QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    const QString home = QDir::homePath();
    QStringList path;
#ifndef Q_OS_WIN
    // The third of Simorg CLI's folders, and not on the PATH a Mac app started from the Finder is given.
    path << QStringLiteral("/usr/local/bin");
#endif
    path << environment.value(QStringLiteral("PATH")).split(QDir::listSeparator(), Qt::SkipEmptyParts);
    return candidates(home,
                      variable(environment, QStringLiteral("XDG_DATA_HOME"),
                               QDir(home).absoluteFilePath(QStringLiteral(".local/share"))),
                      variable(environment, QStringLiteral("LOCALAPPDATA"),
                               QDir(home).absoluteFilePath(QStringLiteral("AppData/Local"))),
                      path, environment.value(QStringLiteral("APPIMAGE")));
}

QString SimorgCli::reportedVersion(const QByteArray &printed)
{
    if (const QString whole = versionIn(printed); !whole.isEmpty())
        return whole;
    // Something printed before the document: the last line that is one, as Simorg CLI reads its own.
    const QList<QByteArray> lines = printed.split('\n');
    for (auto line = lines.crbegin(); line != lines.crend(); ++line) {
        if (const QString version = versionIn(*line); !version.isEmpty())
            return version;
    }
    return {};
}

} // namespace simorg
