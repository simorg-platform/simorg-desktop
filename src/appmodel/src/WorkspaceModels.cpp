// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/WorkspaceModels.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

namespace simorg::app {

using client::ServiceReply;
using support::number;
using support::text;

namespace {

bool isRunning(const QJsonObject &operation)
{
    return text(operation, "state") == QLatin1String("running");
}

} // namespace

// ---- StorageModel -----------------------------------------------------------------------

StorageModel::StorageModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("workspace.usage")))
{
    connect(m_topic, &client::TopicSubscription::received, this, &StorageModel::apply);
    const auto readRoot = [this] {
        ServiceReply *reply = m_session->get(QStringLiteral("/v1/workspace"));
        connect(reply, &ServiceReply::finished, this, [this, reply] {
            const QString root = reply->isError() ? QString() : text(reply->object(), "cache_root");
            if (root.isEmpty() || root == m_root)
                return;
            m_root = root;
            Q_EMIT rootChanged();
        });
    };
    connect(m_session, &client::ServiceSession::connected, this, readRoot);
    if (m_session->isConnected())
        readRoot();
    if (m_topic->hasValue())
        apply(m_topic->value());
}

void StorageModel::apply(const QJsonObject &usage)
{
    if (usage == m_usage)
        return;
    const QJsonObject previous = m_usage;
    m_usage = usage;
    Q_EMIT changed();

    // A sweep that ended while this was listening; the one a first value carries ended before anybody asked here.
    const QJsonObject sweep = usage.value(QStringLiteral("last_sweep")).toObject();
    const QJsonObject before = previous.value(QStringLiteral("last_sweep")).toObject();
    if (previous.isEmpty() || sweep.isEmpty() || text(sweep, "kind") != QLatin1String("clear")
        || text(sweep, "finished_at") == text(before, "finished_at"))
        return;
    Q_EMIT cleared(number(sweep, "freed_bytes"), int(sweep.value(QStringLiteral("kept_agent_ids")).toArray().size()));
}

bool StorageModel::running(const char *activity) const
{
    return isRunning(m_usage) && text(m_usage, "activity") == QLatin1String(activity);
}

qint64 StorageModel::cacheBytes() const
{
    return number(m_usage, "size_bytes");
}

int StorageModel::cacheFiles() const
{
    return int(number(m_usage, "files"));
}

int StorageModel::agentCount() const
{
    return int(number(m_usage, "agents"));
}

bool StorageModel::isComplete() const
{
    return m_usage.value(QStringLiteral("complete")).toBool(true);
}

bool StorageModel::isMeasuring() const
{
    return running("measure");
}

bool StorageModel::isMeasured() const
{
    return m_usage.value(QStringLiteral("measured")).toBool();
}

bool StorageModel::isClearing() const
{
    return running("clear") || running("purge");
}

QString StorageModel::clearError() const
{
    if (!m_requestError.isEmpty())
        return m_requestError;
    const QJsonObject sweep = m_usage.value(QStringLiteral("last_sweep")).toObject();
    return support::problemMessage(sweep.value(QStringLiteral("problem")));
}

void StorageModel::refresh()
{
    // A 409 is a measurement or sweep already running, whose figures arrive on the topic anyway.
    m_session->post(QStringLiteral("/v1/workspace/measure"));
}

void StorageModel::clearCache(const QVariantList &)
{
    m_requestError.clear();
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/workspace/clear"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError() || reply->problem().code == QLatin1String("OPERATION_IN_PROGRESS"))
            return;
        m_requestError = reply->problem().message();
        Q_EMIT changed();
    });
}

// ---- ArtifactsModel ---------------------------------------------------------------------

ArtifactsModel::ArtifactsModel(client::ServiceSession *session, QObject *parent)
    : QAbstractListModel(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("workspace.artifacts")))
{
    connect(m_topic, &client::TopicSubscription::received, this, &ArtifactsModel::apply);
    if (m_topic->hasValue())
        apply(m_topic->value());
}

void ArtifactsModel::apply(const QJsonObject &catalog)
{
    if (catalog == m_catalog)
        return;
    const QJsonArray items = catalog.value(QStringLiteral("items")).toArray();
    if (items != m_items) {
        beginResetModel();
        m_items = items;
        endResetModel();
    }
    m_catalog = catalog;
    Q_EMIT changed();
}

int ArtifactsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant ArtifactsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return {};
    const QJsonObject artifact = m_items.at(index.row()).toObject();
    switch (role) {
    case SpecifierRole:
        return text(artifact, "specifier");
    case AgentHandleRole:
        return text(artifact, "agent_handle");
    case SlugRole:
        return text(artifact, "slug");
    case TagRole:
        return text(artifact, "tag");
    case TitleRole: {
        const QString title = text(artifact, "title");
        return title.isEmpty() ? text(artifact, "slug") : title;
    }
    case KindRole:
        return text(artifact, "kind");
    case PathRole:
        return text(artifact, "path");
    case BytesRole:
        return number(artifact, "size_bytes");
    case SizeTextRole:
        return support::formatBytes(number(artifact, "size_bytes"));
    case CachedAtRole:
        return text(artifact, "cached_at");
    case InstalledRole:
        return artifact.value(QStringLiteral("is_application")).toBool();
    case InstalledPathRole:
        return text(artifact, "installed_path");
    case AccessRoleRole:
        return text(artifact, "access_role");
    case AgentIdRole:
        return int(number(artifact, "agent_id"));
    case CacheRole:
        return text(artifact, "cache");
    default:
        return {};
    }
}

QHash<int, QByteArray> ArtifactsModel::roleNames() const
{
    return {
        {SpecifierRole, "specifier"},
        {AgentHandleRole, "agentHandle"},
        {SlugRole, "slug"},
        {TagRole, "tag"},
        {TitleRole, "title"},
        {KindRole, "kind"},
        {PathRole, "path"},
        {BytesRole, "bytes"},
        {SizeTextRole, "sizeText"},
        {CachedAtRole, "cachedAt"},
        {InstalledRole, "installed"},
        {InstalledPathRole, "installedPath"},
        {AccessRoleRole, "accessRole"},
        {AgentIdRole, "agentId"},
        {CacheRole, "cache"},
    };
}

int ArtifactsModel::applicationCount() const
{
    return int(number(m_catalog, "application_count"));
}

int ArtifactsModel::agentApplicationCount() const
{
    int count = 0;
    for (const QJsonValue &value : m_items) {
        const QJsonObject artifact = value.toObject();
        count += artifact.value(QStringLiteral("is_application")).toBool()
                         && text(artifact, "cache") == QLatin1String("agent")
                     ? 1
                     : 0;
    }
    return count;
}

int ArtifactsModel::agentCount() const
{
    return int(number(m_catalog, "agent_count"));
}

qint64 ArtifactsModel::indexedBytes() const
{
    return number(m_catalog, "indexed_bytes");
}

bool ArtifactsModel::isScanning() const
{
    return isRunning(m_catalog);
}

bool ArtifactsModel::isScanned() const
{
    return m_catalog.value(QStringLiteral("scanned")).toBool();
}

void ArtifactsModel::refresh()
{
    m_session->post(QStringLiteral("/v1/workspace/artifacts/scan"));
}

QVariantMap ArtifactsModel::at(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_items.size())
        return map;
    const QHash<int, QByteArray> names = roleNames();
    for (auto it = names.constBegin(); it != names.constEnd(); ++it)
        map.insert(QString::fromUtf8(it.value()), data(index(row), it.key()));
    return map;
}

} // namespace simorg::app
