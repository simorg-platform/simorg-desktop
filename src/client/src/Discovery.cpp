// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/client/Discovery.h"

#include "PeerCheck.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QtGlobal>

#ifndef Q_OS_WIN
#include <unistd.h>
#endif

namespace simorg::client {
namespace {

constexpr qint64 maxDiscoveryBytes = 64 * 1024;

Discovery invalid(const QString &problem)
{
    Discovery discovery;
    discovery.status = Discovery::Status::Invalid;
    discovery.problem = problem;
    return discovery;
}

} // namespace

bool isEnvironmentName(const QString &name)
{
    return name == QLatin1String("dev") || name == QLatin1String("prod");
}

QString runDirectory()
{
    const QString overridden = qEnvironmentVariable("SIMORG_RUN_DIR");
    if (!overridden.isEmpty())
        return QDir::cleanPath(overridden);

#if defined(Q_OS_MACOS)
    return QDir::homePath() + QStringLiteral("/Library/Application Support/Simorg/run");
#elif defined(Q_OS_WIN)
    return QDir::cleanPath(qEnvironmentVariable("LOCALAPPDATA") + QStringLiteral("/Simorg/run"));
#else
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty())
        return QDir::cleanPath(runtime + QStringLiteral("/simorg"));
    return QDir::homePath() + QStringLiteral("/.local/state/simorg/run");
#endif
}

QString configDirectory()
{
    const QString overridden = qEnvironmentVariable("SIMORG_CONFIG_DIR");
    if (!overridden.isEmpty())
        return QDir::cleanPath(overridden);

#if defined(Q_OS_MACOS)
    return QDir::homePath() + QStringLiteral("/Library/Application Support/Simorg");
#elif defined(Q_OS_WIN)
    return QDir::cleanPath(qEnvironmentVariable("APPDATA") + QStringLiteral("/Simorg"));
#else
    const QString xdg = qEnvironmentVariable("XDG_CONFIG_HOME");
    return xdg.isEmpty() ? QDir::homePath() + QStringLiteral("/.config/simorg")
                         : QDir::cleanPath(xdg + QStringLiteral("/simorg"));
#endif
}

QString discoveryFilePath(const QString &environment)
{
    return runDirectory() + QStringLiteral("/simorgm-") + environment + QStringLiteral(".json");
}

QString stoppedMarkerPath(const QString &environment)
{
    return runDirectory() + QStringLiteral("/simorgm-") + environment + QStringLiteral(".stopped");
}

StoppedMarker StoppedMarker::read(const QString &environment)
{
    StoppedMarker marker;
    if (!isEnvironmentName(environment))
        return marker;
    const QString path = stoppedMarkerPath(environment);
    const QFileInfo info(path);
    if (!info.exists() || info.size() > maxDiscoveryBytes)
        return marker;
#ifndef Q_OS_WIN
    if (info.ownerId() != geteuid() || (info.permissions() & (QFileDevice::WriteGroup | QFileDevice::WriteOther)))
        return marker;
#endif
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return marker;
    // Present even when unreadable as JSON: the service wrote it, and what it says is only who asked.
    marker.present = true;
    const QJsonObject content = QJsonDocument::fromJson(file.read(maxDiscoveryBytes)).object();
    marker.requestedBy = content.value(QStringLiteral("requested_by")).toString();
    marker.stoppedAt = content.value(QStringLiteral("stopped_at")).toString();
    return marker;
}

QString updatingMarkerPath(const QString &environment)
{
    return runDirectory() + QStringLiteral("/simorgm-") + environment + QStringLiteral(".updating");
}

UpdatingMarker UpdatingMarker::read(const QString &environment)
{
    UpdatingMarker marker;
    if (!isEnvironmentName(environment))
        return marker;
    const QString path = updatingMarkerPath(environment);
    const QFileInfo info(path);
    if (!info.exists() || info.size() > maxDiscoveryBytes)
        return marker;
#ifndef Q_OS_WIN
    if (info.ownerId() != geteuid() || (info.permissions() & (QFileDevice::WriteGroup | QFileDevice::WriteOther)))
        return marker;
#endif
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return marker;
    const QJsonObject content = QJsonDocument::fromJson(file.read(maxDiscoveryBytes)).object();
    const qint64 pid = qint64(content.value(QStringLiteral("pid")).toDouble(0));
    const QDateTime startedAt =
        QDateTime::fromString(content.value(QStringLiteral("started_at")).toString(), Qt::ISODate);
    // Five minutes, as the service's own packages judge it: long enough for any install to finish.
    const bool recent = startedAt.isValid() && startedAt.secsTo(QDateTime::currentDateTimeUtc()) < 5 * 60;
    marker.present = (pid > 0 && detail::processIsAlive(pid)) || recent;
    marker.from = content.value(QStringLiteral("from")).toString();
    marker.to = content.value(QStringLiteral("to")).toString();
    return marker;
}

QString peerDiscoveryFilePath(const QString &environment)
{
    return runDirectory() + QStringLiteral("/simorgm-peers-") + environment + QStringLiteral(".json");
}

QString readPeerPipe(const QString &environment, QString *problem)
{
    const auto fail = [problem](const QString &why) {
        if (problem != nullptr)
            *problem = why;
        return QString();
    };
    if (!isEnvironmentName(environment))
        return fail(QStringLiteral("“%1” is not an environment").arg(environment));
    const QString path = peerDiscoveryFilePath(environment);
    QFile file(path);
    const QFileInfo info(path);
    if (!info.exists())
        return fail(QStringLiteral("there is no %1: is the Simorg machine service running?").arg(path));
    if (info.size() > maxDiscoveryBytes)
        return fail(QStringLiteral("%1 is too large to be the service's").arg(path));
#ifndef Q_OS_WIN
    // Written owner-only, beside the service's own discovery file.
    if (info.ownerId() != geteuid())
        return fail(QStringLiteral("%1 belongs to another user").arg(path));
    if (info.permissions() & (QFileDevice::WriteGroup | QFileDevice::WriteOther))
        return fail(QStringLiteral("%1 can be changed by other users").arg(path));
#endif
    if (!file.open(QIODevice::ReadOnly))
        return fail(QStringLiteral("%1 could not be read: %2").arg(path, file.errorString()));
    const QJsonDocument document = QJsonDocument::fromJson(file.read(maxDiscoveryBytes));
    const QJsonObject object = document.object();
    if (!document.isObject() || object.value(QStringLiteral("schema")).toInt(0) != 1
        || object.value(QStringLiteral("service")).toString() != QLatin1String("simorgm")
        || object.value(QStringLiteral("environment")).toString() != environment)
        return fail(QStringLiteral("%1 is not this environment's peer discovery file").arg(path));
    const QString pipe = object.value(QStringLiteral("pipe")).toString();
    if (pipe.isEmpty())
        return fail(QStringLiteral("%1 names no pipe").arg(path));
    return pipe;
}

Discovery Discovery::read(const QString &environment)
{
    if (!isEnvironmentName(environment))
        return invalid(QStringLiteral("“%1” is not an environment").arg(environment));

    const QString path = discoveryFilePath(environment);
    QFile file(path);
    if (!file.exists())
        return {};

    const QFileInfo info(path);
    if (info.size() > maxDiscoveryBytes)
        return invalid(QStringLiteral("%1 is too large to be the service's").arg(path));
#ifndef Q_OS_WIN
    // The service writes it owner-only in a directory only its user can enter.
    if (info.ownerId() != geteuid())
        return invalid(QStringLiteral("%1 belongs to another user").arg(path));
    if (info.permissions() & (QFileDevice::WriteGroup | QFileDevice::WriteOther))
        return invalid(QStringLiteral("%1 can be changed by other users").arg(path));
#endif
    if (!file.open(QIODevice::ReadOnly)) {
        // Removed between the check and the open: the service stopped.
        if (!file.exists())
            return {};
        return invalid(QStringLiteral("%1 could not be read: %2").arg(path, file.errorString()));
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.read(maxDiscoveryBytes), &parseError);
    if (!document.isObject())
        return invalid(QStringLiteral("%1 is not a JSON object").arg(path));
    const QJsonObject object = document.object();

    const int schema = object.value(QStringLiteral("schema")).toInt(0);
    if (schema != 1) {
        return invalid(schema > 1 ? QStringLiteral("%1 was written by a newer Simorg machine service").arg(path)
                                  : QStringLiteral("%1 has no schema this client knows").arg(path));
    }
    if (object.value(QStringLiteral("service")).toString() != QLatin1String("simorgm"))
        return invalid(QStringLiteral("%1 was not written by the Simorg machine service").arg(path));
    if (object.value(QStringLiteral("environment")).toString() != environment)
        return invalid(QStringLiteral("%1 names another environment").arg(path));

    Discovery discovery;
    discovery.status = Status::Found;
    discovery.environment = environment;
    discovery.version = object.value(QStringLiteral("version")).toString();
    discovery.apiVersion = object.value(QStringLiteral("api_version")).toString();

    const double pid = object.value(QStringLiteral("pid")).toDouble(0);
    discovery.pid = qint64(pid);
    if (pid < 1 || double(discovery.pid) != pid)
        return invalid(QStringLiteral("%1 names no process").arg(path));

    discovery.pipe = object.value(QStringLiteral("pipe")).toString();
    if (discovery.pipe.isEmpty())
        return invalid(QStringLiteral("%1 names no pipe").arg(path));

    static const QRegularExpression tokenShape(QStringLiteral("^[0-9a-f]{64}$"));
    const QString token = object.value(QStringLiteral("token")).toString();
    if (!tokenShape.match(token).hasMatch())
        return invalid(QStringLiteral("%1 carries no valid token").arg(path));
    discovery.token = token.toLatin1();

    const QJsonValue http = object.value(QStringLiteral("http"));
    if (http.isObject()) {
        const int port = http.toObject().value(QStringLiteral("port")).toInt(0);
        if (port < 1 || port > 65535)
            return invalid(QStringLiteral("%1 names an invalid HTTP port").arg(path));
        discovery.httpPort = quint16(port);
    }

    if (!detail::processIsAlive(discovery.pid)) {
        discovery.status = Status::Stale;
        discovery.problem = QStringLiteral("the service that wrote %1 is no longer running").arg(path);
    }
    return discovery;
}

} // namespace simorg::client
