// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The cache root Simorg owns and how much it holds, as Settings reads it off `Storage`.
 *
 * The service measures and sweeps it and publishes `workspace.usage`; the directory itself comes from
 * `GET /v1/workspace`. Separate from `Artifacts` because a measurement walks the disk
 * and a list of artifacts reads a few index files.
 */
class StorageModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString cacheRoot READ cacheRoot NOTIFY rootChanged)
    Q_PROPERTY(qint64 cacheBytes READ cacheBytes NOTIFY changed)
    Q_PROPERTY(qint64 totalBytes READ cacheBytes NOTIFY changed)
    Q_PROPERTY(int cacheFiles READ cacheFiles NOTIFY changed)
    /** How many agents have a directory here, running or not. */
    Q_PROPERTY(int agentCount READ agentCount NOTIFY changed)
    /** False while the figure is a floor: the walk stopped at its ceiling. */
    Q_PROPERTY(bool complete READ isComplete NOTIFY changed)
    Q_PROPERTY(bool measuring READ isMeasuring NOTIFY changed)
    /** A measurement has finished, so "0 B" means empty. */
    Q_PROPERTY(bool measured READ isMeasured NOTIFY changed)
    Q_PROPERTY(bool clearing READ isClearing NOTIFY changed)
    /** Why the last sweep did not finish. Empty when it did, or none has run. */
    Q_PROPERTY(QString clearError READ clearError NOTIFY changed)

public:
    explicit StorageModel(client::ServiceSession *session, QObject *parent = nullptr);

    QString cacheRoot() const { return m_root; }
    qint64 cacheBytes() const;
    int cacheFiles() const;
    int agentCount() const;
    bool isComplete() const;
    bool isMeasuring() const;
    bool isMeasured() const;
    bool isClearing() const;
    QString clearError() const;

    /** Asks the service to measure the cache root. A measurement or sweep already running is left to finish. */
    Q_INVOKABLE void refresh();
    /**
     * Asks the service to empty the artifact cache.
     *
     * The argument is what the window thinks is busy and is not sent: the service
     * spares the agents it knows are running, and measures again afterwards.
     */
    Q_INVOKABLE void clearCache(const QVariantList &busyAgentIds = {});

Q_SIGNALS:
    void changed();
    void rootChanged();
    /** A sweep of the cache ended: what it gave back, and how many working agents' folders it left alone. */
    void cleared(qint64 freedBytes, int keptAgents);

private:
    void apply(const QJsonObject &usage);
    bool running(const char *activity) const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_usage;
    QString m_root;
    QString m_requestError;
};

/**
 * The artifacts runtimes recorded in the cache root, as the Artifacts section reads
 * them off `Artifacts`: the service's `workspace.artifacts`, one row per artifact.
 */
class ArtifactsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY changed)
    Q_PROPERTY(int applicationCount READ applicationCount NOTIFY changed)
    /** The applications an agent's runtime installed into its own folder, not the ones the person installed. */
    Q_PROPERTY(int agentApplicationCount READ agentApplicationCount NOTIFY changed)
    Q_PROPERTY(int agentCount READ agentCount NOTIFY changed)
    Q_PROPERTY(qint64 indexedBytes READ indexedBytes NOTIFY changed)
    Q_PROPERTY(bool scanning READ isScanning NOTIFY changed)
    Q_PROPERTY(bool scanned READ isScanned NOTIFY changed)

public:
    enum Role {
        SpecifierRole = Qt::UserRole + 1,
        AgentHandleRole,
        SlugRole,
        TagRole,
        /** The title, or the slug when nothing named it, so a row is never blank. */
        TitleRole,
        KindRole,
        PathRole,
        BytesRole,
        SizeTextRole,
        CachedAtRole,
        /** An application: something installed on this computer rather than only cached. */
        InstalledRole,
        InstalledPathRole,
        AccessRoleRole,
        AgentIdRole,
        /** `agent`, `exec`, or `installed` for what the person installed through the service. */
        CacheRole,
    };

    explicit ArtifactsModel(client::ServiceSession *session, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int applicationCount() const;
    int agentApplicationCount() const;
    int agentCount() const;
    qint64 indexedBytes() const;
    bool isScanning() const;
    bool isScanned() const;

    /** Asks the service to read the index files again. */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap at(int row) const;

Q_SIGNALS:
    void changed();

private:
    void apply(const QJsonObject &catalog);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_catalog;
    QJsonArray m_items;
};

} // namespace simorg::app
