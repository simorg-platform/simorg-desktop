// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/ApplicationsModel.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QUrlQuery>

#include <algorithm>

namespace simorg::app {

using client::ServiceReply;
using client::TopicSubscription;
using support::number;
using support::text;

namespace {

/** The slug of `@owner/agent/slug`, for a row with no title. */
QString slugOf(const QString &specifier)
{
    return specifier.section(QLatin1Char('/'), -1);
}

} // namespace

// ---- The installed list ------------------------------------------------------------------------

ApplicationsModel::ApplicationsModel(client::ServiceSession *session, QObject *parent)
    : KeyedRowsModel("specifier", parent)
    , m_session(session)
{
    connect(m_session, &client::ServiceSession::connected, this, &ApplicationsModel::refresh);
}

QString ApplicationsModel::versionless(const QString &specifier)
{
    static const QRegularExpression shape(QStringLiteral("^@([A-Za-z0-9][A-Za-z0-9_-]*)/([A-Za-z0-9][A-Za-z0-9_-]*)/"
                                                         "([A-Za-z0-9][A-Za-z0-9_-]*)(?:[:^].*)?$"));
    const QRegularExpressionMatch match = shape.match(specifier.trimmed());
    if (!match.hasMatch())
        return {};
    return QStringLiteral("@%1/%2/%3").arg(match.captured(1), match.captured(2), match.captured(3)).toLower();
}

void ApplicationsModel::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    if (active) {
        m_topic = m_session->subscribe(QStringLiteral("applications.roster"));
        connect(m_topic, &TopicSubscription::received, this, &ApplicationsModel::apply);
        if (m_topic->hasValue())
            apply(m_topic->value());
    } else if (m_topic) {
        disconnect(m_topic, nullptr, this, nullptr);
        m_session->release(std::exchange(m_topic, nullptr));
    }
    Q_EMIT changed();
}

void ApplicationsModel::refresh()
{
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/applications"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            apply(reply->object());
    });
}

void ApplicationsModel::apply(const QJsonObject &list)
{
    m_list = list;
    m_loaded = true;

    // The installs the person started, by the application they are for; an agent's is its own business (CHN-41).
    QHash<QString, QJsonObject> installs;
    for (const QJsonValue &value : list.value(QStringLiteral("installs")).toArray()) {
        const QJsonObject install = value.toObject();
        if (text(install, "installed_by") != QLatin1String("agent"))
            installs.insert(text(install, "specifier"), install);
    }

    QList<QJsonObject> rows;
    QSet<QString> seen;
    for (const QJsonValue &value : list.value(QStringLiteral("items")).toArray()) {
        QJsonObject row = value.toObject();
        const QString specifier = text(row, "specifier");
        // Singletons only; a service before API 1.4 says nothing of it, and its list is all the person's.
        if (row.contains(QStringLiteral("is_singleton")) && !row.value(QStringLiteral("is_singleton")).toBool())
            continue;
        if (installs.contains(specifier))
            row.insert(QStringLiteral("install"), installs.value(specifier));
        seen.insert(specifier);
        rows.append(row);
    }
    // An install of something not installed yet is a row of its own, so it is on the list the moment it starts.
    for (auto it = installs.cbegin(); it != installs.cend(); ++it) {
        if (seen.contains(it.key()))
            continue;
        rows.append(QJsonObject{{QStringLiteral("specifier"), it.key()},
                                {QStringLiteral("installed"), false},
                                {QStringLiteral("install"), it.value()}});
    }
    reconcile(rows);

    // Told once when an install that was running is gone and the application is there.
    QVariantMap now;
    for (auto it = installs.cbegin(); it != installs.cend(); ++it)
        now.insert(it.key(), text(it.value(), "state"));
    for (auto it = m_installing.cbegin(); it != m_installing.cend(); ++it) {
        if (it.value().toString() == QLatin1String("failed") || now.contains(it.key()))
            continue;
        const QVariantMap row = bySpecifier(it.key());
        if (row.value(QStringLiteral("installed")).toBool())
            Q_EMIT installed(row.value(QStringLiteral("title")).toString());
    }
    m_installing = now;
    Q_EMIT changed();
}

QVariant ApplicationsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &item = row(index.row());
    const QJsonObject peer = item.value(QStringLiteral("peer")).toObject();
    const QJsonObject usage = item.value(QStringLiteral("usage")).toObject();
    const QJsonObject install = item.value(QStringLiteral("install")).toObject();
    const QString specifier = text(item, "specifier");
    switch (role) {
    case SpecifierRole:
        return specifier;
    case TitleRole: {
        const QString title = text(item, "title");
        if (!title.isEmpty())
            return title;
        const QString requested = text(install, "requested");
        return slugOf(requested.isEmpty() ? specifier : versionless(requested));
    }
    case TagRole:
        return text(item, "tag");
    case InstalledRole:
        return item.value(QStringLiteral("installed")).toBool();
    case PathRole:
        return text(item, "path");
    case EntryRole:
        return text(item, "entry");
    case BytesRole:
        return number(item, "bytes");
    case SizeTextRole:
        return item.value(QStringLiteral("installed")).toBool() ? support::formatBytes(number(item, "bytes")) : QString();
    case InstalledAtRole:
        return text(item, "installed_at");
    case DriverRole:
        return text(item, "driver");
    case PeerIdRole:
        return text(peer, "peer_id");
    case PeerStateRole:
        return text(peer, "state");
    case RunningRole: {
        const QString state = text(peer, "state");
        return state == QLatin1String("attached") || state == QLatin1String("paused")
            || state == QLatin1String("declaring");
    }
    case VerificationRole:
        return text(peer, "verification_status");
    case ProcessIdRole:
        return number(peer, "process_id", -1);
    case CpuPercentRole: {
        const QJsonValue cpu = usage.value(QStringLiteral("cpu_percent"));
        return cpu.isDouble() ? cpu.toDouble() : -1.0;
    }
    case MemoryBytesRole:
        return usage.isEmpty() ? qint64(-1) : number(usage, "memory_bytes");
    case AllowedAgentIdsRole:
        return item.value(QStringLiteral("allowed_agent_ids")).toArray().toVariantList();
    case AllowedCountRole:
        return int(item.value(QStringLiteral("allowed_agent_ids")).toArray().size());
    case InstallStateRole:
        return text(install, "state");
    case InstallProgressRole: {
        const qint64 total = number(install, "total_bytes", -1);
        return text(install, "state") == QLatin1String("downloading") && total > 0
            ? double(number(install, "bytes")) / double(total)
            : -1.0;
    }
    case InstallProblemRole:
        return support::problemMessage(install.value(QStringLiteral("problem")));
    case UsedByAgentIdsRole:
        return item.value(QStringLiteral("used_by_agent_ids")).toArray().toVariantList();
    case CanQuitRole:
        return data(index, RunningRole).toBool() && item.contains(QStringLiteral("used_by_agent_ids"));
    default:
        return {};
    }
}

QHash<int, QByteArray> ApplicationsModel::roleNames() const
{
    return {
        {SpecifierRole, "specifier"},
        {TitleRole, "title"},
        {TagRole, "tag"},
        {InstalledRole, "installed"},
        {PathRole, "path"},
        {EntryRole, "entry"},
        {BytesRole, "bytes"},
        {SizeTextRole, "sizeText"},
        {InstalledAtRole, "installedAt"},
        {DriverRole, "driver"},
        {PeerIdRole, "peerId"},
        {PeerStateRole, "peerState"},
        {RunningRole, "running"},
        {VerificationRole, "verification"},
        {ProcessIdRole, "processId"},
        {CpuPercentRole, "cpuPercent"},
        {MemoryBytesRole, "memoryBytes"},
        {AllowedAgentIdsRole, "allowedAgentIds"},
        {AllowedCountRole, "allowedCount"},
        {InstallStateRole, "installState"},
        {InstallProgressRole, "installProgress"},
        {InstallProblemRole, "installProblem"},
        {UsedByAgentIdsRole, "usedByAgentIds"},
        {CanQuitRole, "canQuit"},
    };
}

QString ApplicationsModel::directory() const
{
    return text(m_list, "directory");
}

QString ApplicationsModel::driverCode() const
{
    return text(m_list, "driver");
}

int ApplicationsModel::installedCount() const
{
    int count = 0;
    for (int i = 0; i < rowCount(); ++i)
        count += row(i).value(QStringLiteral("installed")).toBool() ? 1 : 0;
    return count;
}

int ApplicationsModel::runningCount() const
{
    int count = 0;
    for (int i = 0; i < rowCount(); ++i)
        count += data(index(i), RunningRole).toBool() ? 1 : 0;
    return count;
}

int ApplicationsModel::installingCount() const
{
    int count = 0;
    for (const QJsonValue &value : m_list.value(QStringLiteral("installs")).toArray()) {
        const QJsonObject install = value.toObject();
        count += text(install, "state") != QLatin1String("failed")
                         && text(install, "installed_by") != QLatin1String("agent")
                     ? 1
                     : 0;
    }
    return count;
}

qint64 ApplicationsModel::installedBytes() const
{
    qint64 total = 0;
    for (int i = 0; i < rowCount(); ++i)
        total += number(row(i), "bytes");
    return total;
}

QVariantMap ApplicationsModel::bySpecifier(const QString &specifier) const
{
    const QString wanted = versionless(specifier);
    for (int i = 0; i < rowCount(); ++i) {
        if (text(row(i), "specifier") == wanted)
            return at(i);
    }
    return {};
}

void ApplicationsModel::setError(const QString &message)
{
    m_lastError = message;
    Q_EMIT busyChanged();
    if (!message.isEmpty())
        Q_EMIT failed(message);
}

void ApplicationsModel::install(const QString &specifier)
{
    setError({});
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/applications/install"), QJsonObject{{QStringLiteral("specifier"), specifier}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (reply->isError()) {
            setError(reply->problem().message());
            return;
        }
        // The list moves on the topic; without a listener it is read once.
        if (!m_topic)
            refresh();
    });
}

void ApplicationsModel::uninstall(const QString &specifier)
{
    setError({});
    m_removing = versionless(specifier);
    Q_EMIT busyChanged();
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/applications/uninstall"),
                                          QJsonObject{{QStringLiteral("specifier"), specifier}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_removing.clear();
        Q_EMIT busyChanged();
        if (reply->isError()) {
            setError(reply->problem().message());
            return;
        }
        apply(reply->object());
    });
}

void ApplicationsModel::quit(const QString &specifier)
{
    setError({});
    m_quitting = versionless(specifier);
    Q_EMIT busyChanged();
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/applications/stop"), QJsonObject{{QStringLiteral("specifier"), specifier}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_quitting.clear();
        Q_EMIT busyChanged();
        if (reply->isError()) {
            setError(reply->problem().message());
            return;
        }
        apply(reply->object());
    });
}

bool ApplicationsModel::open(const QString &specifier)
{
    setError({});
    const QVariantMap application = bySpecifier(specifier);
    const QString entry = application.value(QStringLiteral("entry")).toString();
    if (entry.isEmpty() || !QFileInfo::exists(entry)) {
        setError(tr("%1 is not installed on this computer, so there is nothing to open.")
                     .arg(application.value(QStringLiteral("title"), specifier).toString()));
        return false;
    }
    const QFileInfo info(entry);
    bool started = false;
#if defined(Q_OS_MACOS)
    // A bundle is opened the way Finder opens it; a bare program is run from its own folder.
    if (info.isDir() && entry.endsWith(QLatin1String(".app")))
        started = QProcess::startDetached(QStringLiteral("/usr/bin/open"), {entry});
    else
        started = QProcess::startDetached(entry, {}, info.absolutePath());
#else
    started = QProcess::startDetached(entry, {}, info.absolutePath());
#endif
    if (!started)
        setError(tr("%1 could not be started.").arg(application.value(QStringLiteral("title")).toString()));
    return started;
}

// ---- The directory -----------------------------------------------------------------------------

ApplicationDirectoryModel::ApplicationDirectoryModel(client::ServiceSession *session, QObject *parent)
    : QAbstractListModel(parent)
    , m_session(session)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    connect(&m_debounce, &QTimer::timeout, this, &ApplicationDirectoryModel::search);
}

QPair<QString, QString> ApplicationDirectoryModel::targetOf(const QString &driverCode)
{
    static const QHash<QString, QPair<QString, QString>> targets{
        {QStringLiteral("BINARY_MAC_APPLE_SILICON"), {QStringLiteral("MACOS"), QStringLiteral("APPLE_SILICON")}},
        {QStringLiteral("BINARY_MAC_X64"), {QStringLiteral("MACOS"), QStringLiteral("X64")}},
        {QStringLiteral("BINARY_LINUX_ARM"), {QStringLiteral("LINUX"), QStringLiteral("ARM64")}},
        {QStringLiteral("BINARY_LINUX_X64"), {QStringLiteral("LINUX"), QStringLiteral("X64")}},
        {QStringLiteral("BINARY_WINDOWS_ARM"), {QStringLiteral("WINDOWS"), QStringLiteral("ARM64")}},
        {QStringLiteral("BINARY_WINDOWS_X64"), {QStringLiteral("WINDOWS"), QStringLiteral("X64")}},
    };
    return targets.value(driverCode);
}

void ApplicationDirectoryModel::setQuery(const QString &query)
{
    if (query == m_query)
        return;
    m_query = query;
    Q_EMIT queryChanged();
    m_debounce.start();
}

void ApplicationDirectoryModel::setDriverCode(const QString &code)
{
    if (code == m_driverCode)
        return;
    m_driverCode = code;
    if (!m_items.isEmpty())
        Q_EMIT dataChanged(index(0), index(rowCount() - 1), {AvailableRole});
    Q_EMIT changed();
}

void ApplicationDirectoryModel::search()
{
    m_debounce.stop();
    QUrlQuery query;
    const QString words = m_query.trimmed();
    if (!words.isEmpty())
        query.addQueryItem(QStringLiteral("q"), words);
    query.addQueryItem(QStringLiteral("categories"), QStringLiteral("applications"));
    query.addQueryItem(QStringLiteral("sort"), QStringLiteral("relevance"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/proxy/back/api/v1/logos/artifacts/search"), query);
    m_reply = reply;
    Q_EMIT changed();
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (m_reply != reply)
            return; // a newer search replaced it
        m_reply.clear();
        m_searched = true;
        if (reply->isError()) {
            m_error = reply->problem().message();
            Q_EMIT changed();
            return;
        }
        m_error.clear();
        apply(reply->object());
    });
}

void ApplicationDirectoryModel::apply(const QJsonObject &page)
{
    beginResetModel();
    m_items.clear();
    int others = 0;
    for (const QJsonValue &value : page.value(QStringLiteral("items")).toArray()) {
        const QJsonObject item = value.toObject();
        if (ApplicationsModel::versionless(text(item, "specifier")).isEmpty())
            continue;
        // A platform from before `isSingleton` says nothing of it, and its applications are all offered.
        if (item.contains(QStringLiteral("isSingleton")) && !item.value(QStringLiteral("isSingleton")).toBool()) {
            ++others;
            continue;
        }
        m_items.append(item);
    }
    m_total = std::max(int(m_items.size()), int(number(page, "total", m_items.size())) - others);
    endResetModel();
    Q_EMIT changed();
}

int ApplicationDirectoryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant ApplicationDirectoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= int(m_items.size()))
        return {};
    const QJsonObject &item = m_items.at(index.row());
    const QJsonArray drivers = item.value(QStringLiteral("drivers")).toArray();
    switch (role) {
    case SpecifierRole:
        return ApplicationsModel::versionless(text(item, "specifier"));
    case NameRole: {
        const QString name = text(item, "name");
        return name.isEmpty() ? text(item, "slug") : name;
    }
    case TaglineRole:
        return text(item, "tagline");
    case OwnerRole:
        return text(item.value(QStringLiteral("owner")).toObject(), "displayName");
    case VersionRole:
        return text(item, "version");
    case DownloadsRole:
        return number(item, "totalDownloads");
    case VerifiedRole:
        return item.value(QStringLiteral("verified")).toBool();
    case AvailableRole: {
        const QPair<QString, QString> here = targetOf(m_driverCode);
        if (here.first.isEmpty() || !item.contains(QStringLiteral("drivers")))
            return -1;
        for (const QJsonValue &value : drivers) {
            const QJsonObject driver = value.toObject();
            if (text(driver, "os").compare(here.first, Qt::CaseInsensitive) == 0
                && text(driver, "platform").compare(here.second, Qt::CaseInsensitive) == 0)
                return 1;
        }
        return 0;
    }
    case PlatformsRole: {
        QStringList titles;
        for (const QJsonValue &value : drivers) {
            const QString title = text(value.toObject(), "categoryTitle");
            if (!title.isEmpty() && !titles.contains(title))
                titles.append(title);
        }
        return titles.join(QStringLiteral(" · "));
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> ApplicationDirectoryModel::roleNames() const
{
    return {
        {SpecifierRole, "specifier"}, {NameRole, "name"},           {TaglineRole, "tagline"},
        {OwnerRole, "owner"},         {VersionRole, "version"},     {DownloadsRole, "downloads"},
        {VerifiedRole, "verified"},   {AvailableRole, "available"}, {PlatformsRole, "platforms"},
    };
}

} // namespace simorg::app
