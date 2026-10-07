// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DockerListModels.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QPointer>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The applications on this computer, as the Applications section reads them off
 * `Applications`.
 *
 * One row per singleton installed through the service or connected to it — one
 * instance per computer, shared by every agent that uses it — and one per
 * install the person started of an application not installed yet, so a person
 * who pressed Install sees it arrive in the list at once. Any other application
 * is installed and started by the agents that use it, one instance per use, and
 * is not this tab's. Each row carries
 * what the service knows: where it is and what it takes on the disk, its
 * connection and whether it was verified, what its process uses while it runs
 * — sampled only while this model is active, because sampling follows
 * subscribers — which agents placed here may use it, and which are using it.
 *
 * Opening one is this application's job, on the person's press; the service
 * starts one only for an agent's use Access Management allows. Quitting one is
 * the service's, and the question before it, naming the agents using it, is the
 * view's.
 */
class ApplicationsModel : public KeyedRowsModel
{
    Q_OBJECT
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY changed)
    Q_PROPERTY(QString directory READ directory NOTIFY changed)
    /** The driver code that names this computer, such as `BINARY_MAC_APPLE_SILICON`. */
    Q_PROPERTY(QString driverCode READ driverCode NOTIFY changed)
    Q_PROPERTY(int installedCount READ installedCount NOTIFY changed)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY changed)
    Q_PROPERTY(int installingCount READ installingCount NOTIFY changed)
    Q_PROPERTY(qint64 installedBytes READ installedBytes NOTIFY changed)
    /** The usage columns are being fed: the model is active and the service samples. */
    Q_PROPERTY(bool sampling READ isSampling NOTIFY changed)
    /** The specifier an uninstall is waiting on, or empty. */
    Q_PROPERTY(QString removing READ removing NOTIFY busyChanged)
    /** The specifier a quit is waiting on, or empty. */
    Q_PROPERTY(QString quitting READ quitting NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY busyChanged)

public:
    enum Role {
        SpecifierRole = Qt::UserRole + 1,
        /** The title, or the specifier's slug, so a row is never blank. */
        TitleRole,
        TagRole,
        InstalledRole,
        PathRole,
        EntryRole,
        BytesRole,
        SizeTextRole,
        InstalledAtRole,
        DriverRole,
        PeerIdRole,
        /** `attached`, `paused`, `awaiting_consent`, …, or empty when nothing is connected. */
        PeerStateRole,
        /** Connected and past consent: the program is up and talking to Simorg. */
        RunningRole,
        VerificationRole,
        ProcessIdRole,
        /** Share of one core; -1 when there is no reading. */
        CpuPercentRole,
        /** Resident memory; -1 when there is no reading. */
        MemoryBytesRole,
        AllowedAgentIdsRole,
        AllowedCountRole,
        /** `resolving`, `downloading`, `unpacking`, `failed`, or empty when no install is under way. */
        InstallStateRole,
        /** 0 to 1 while downloading with a known size; -1 otherwise. */
        InstallProgressRole,
        InstallProblemRole,
        /** The agents using it now, ascending: whom the question before quitting names. */
        UsedByAgentIdsRole,
        /** Running, and a service that can quit it (API 1.4). */
        CanQuitRole,
    };
    Q_ENUM(Role)

    explicit ApplicationsModel(client::ServiceSession *session, QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool isLoaded() const { return m_loaded; }
    QString directory() const;
    QString driverCode() const;
    int installedCount() const;
    int runningCount() const;
    int installingCount() const;
    qint64 installedBytes() const;
    bool isSampling() const { return m_active && m_topic != nullptr; }
    QString removing() const { return m_removing; }
    QString quitting() const { return m_quitting; }
    QString lastError() const { return m_lastError; }

    /** Listens to `applications.roster` while true, which is also what makes the service sample usage. */
    Q_INVOKABLE void setActive(bool active);
    /** Reads the list once, whether or not anything listens. */
    Q_INVOKABLE void refresh();
    /** Starts installing; progress arrives on the row. */
    Q_INVOKABLE void install(const QString &specifier);
    /** Removes it; refused while it is running and connected. */
    Q_INVOKABLE void uninstall(const QString &specifier);
    /** Quits the singleton, on the person's press, after the view asked when an agent is using it. */
    Q_INVOKABLE void quit(const QString &specifier);
    /** Starts the installed program, on the person's press; false with `lastError` said when it cannot be. */
    Q_INVOKABLE bool open(const QString &specifier);
    /** Every role of the row for `specifier`, versionless or tagged; empty when there is none. */
    Q_INVOKABLE QVariantMap bySpecifier(const QString &specifier) const;
    /** `@owner/agent/artifact`, lower case, from a specifier with or without a tag; empty when it is not one. */
    Q_INVOKABLE static QString versionless(const QString &specifier);

Q_SIGNALS:
    void changed();
    void busyChanged();
    /** A request of this app's was refused, in a sentence for a person. */
    void failed(const QString &message);
    /** An application finished installing; the tray and the window say so. */
    void installed(const QString &title);

private:
    void apply(const QJsonObject &list);
    void setError(const QString &message);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic = nullptr;
    bool m_active = false;
    bool m_loaded = false;
    QJsonObject m_list;
    /** Specifier → state of each install last seen, so a finished one is told once. */
    QVariantMap m_installing;
    QString m_removing;
    QString m_quitting;
    QString m_lastError;
};

/**
 * Simorg's applications, as the platform's directory finds them, for the
 * Discover view: `GET /api/v1/logos/artifacts/search?categories=applications`
 * through the service's proxy, as the person signed in here.
 *
 * Each result says whether it is published for this computer, read from the
 * drivers of its latest release against the driver code the service named, so
 * nobody presses Install on something that has nothing to install here. Only
 * singletons are listed, as on the Applications tab: any other application is
 * installed by the agents that use it.
 */
class ApplicationDirectoryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY changed)
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(bool searching READ isSearching NOTIFY changed)
    Q_PROPERTY(bool searched READ isSearched NOTIFY changed)
    Q_PROPERTY(int total READ total NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    /** What availability is judged against; set from `Applications.driverCode`. */
    Q_PROPERTY(QString driverCode READ driverCode WRITE setDriverCode NOTIFY changed)

public:
    enum Role {
        SpecifierRole = Qt::UserRole + 1,
        NameRole,
        TaglineRole,
        OwnerRole,
        VersionRole,
        DownloadsRole,
        VerifiedRole,
        /** 1 published for this computer, 0 not, -1 the directory did not say. */
        AvailableRole,
        /** `macOS Apple Silicon · Linux x64`, from the release's drivers. */
        PlatformsRole,
    };
    Q_ENUM(Role)

    explicit ApplicationDirectoryModel(client::ServiceSession *session, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString query() const { return m_query; }
    /** Searches again a moment after the last change, so typing is not a request per key. */
    void setQuery(const QString &query);
    bool isSearching() const { return !m_reply.isNull(); }
    bool isSearched() const { return m_searched; }
    int total() const { return m_total; }
    QString error() const { return m_error; }
    QString driverCode() const { return m_driverCode; }
    void setDriverCode(const QString &code);

    /** Searches now, with the query as it stands. */
    Q_INVOKABLE void search();

    /** `{os, platform}` of a driver code, as the directory's drivers write them. */
    static QPair<QString, QString> targetOf(const QString &driverCode);

Q_SIGNALS:
    void changed();
    void queryChanged();

private:
    void apply(const QJsonObject &page);

    client::ServiceSession *m_session;
    QString m_query;
    QString m_driverCode;
    QTimer m_debounce;
    QPointer<QObject> m_reply;
    QList<QJsonObject> m_items;
    int m_total = 0;
    bool m_searched = false;
    QString m_error;
};

} // namespace simorg::app
