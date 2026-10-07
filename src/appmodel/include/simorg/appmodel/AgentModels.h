// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DockerListModels.h"

#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/** A virtual machine's envelope as the agents screens draw it: `8 GB`, `0.5–2 cores · 1–4 GB`. */
namespace envelope {

/** `{cpuMin, cpuMax, cpuCapped, memoryMin, …}` from the service's `VirtualMachineResources`. */
QVariantMap toMap(const QJsonObject &resources);
QString summary(const QJsonObject &resources);

} // namespace envelope

/**
 * The agents placed on this computer, as `Hub.agents`: the service's `agents.roster`,
 * one row per agent with its slot, lifecycle and container.
 */
class HostedAgentModel : public KeyedRowsModel
{
    Q_OBJECT
    Q_PROPERTY(int runningCount READ runningCount NOTIFY rosterChanged)
    /**
     * The agents offered a newer release of what they were installed from, in
     * roster order: `{agentId, title, tag, releaseTitle, private}` each. What the
     * window's update bar is drawn from.
     */
    Q_PROPERTY(QVariantList updates READ updates NOTIFY rosterChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        SlugRole,
        TitleRole,
        TaglineRole,
        /** The agent's picture, as a platform address the avatar cache resolves. */
        AvatarUrlRole,
        SlotIdRole,
        SlotCodenameRole,
        SlotTitleRole,
        ResourcesRole,
        EnvelopeRole,
        AccessRequestsRole,
        AccessRequestCountRole,
        HasInitialScriptRole,
        FeatureKeysRole,
        PublicTokenRole,
        LifecycleRole,
        ContainerNameRole,
        ContainerStateRole,
        ContainerStateNameRole,
        ContainerIdRole,
        ContainerDetailRole,
        /** The image its container runs, as the service recorded it when the container was made. */
        ContainerImageRole,
        RunningRole,
        /**
         * The newer release on offer, as `{available, artifactTagId, tag, title, notes, private, currentTag}`;
         * `available` false when there is none. A private artifact's tags are empty.
         */
        UpdateRole,
        /**
         * Whether the person signed in here may start, stop and reboot the agent,
         * as the Hub works it out for them and moves on every membership change.
         * False while the Hub has not said.
         */
        CanManageRole,
    };

    /** The container states, in the order QML's `AgentState` names them. */
    enum ContainerState {
        Unknown,
        Starting,
        Running,
        Stopped,
        ImageMissing,
        ImageUntrusted,
        Conflict,
        Failed,
        Unavailable,
    };
    Q_ENUM(ContainerState)

    explicit HostedAgentModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void apply(const QJsonObject &roster);
    const QJsonObject &roster() const { return m_roster; }

    int runningCount() const;
    QVariantList updates() const;
    /** The agents whose containers run or are starting: their folders are not to be swept. */
    Q_INVOKABLE QVariantList busyAgentIds() const;
    Q_INVOKABLE bool contains(int agentId) const;
    /** Every role of one agent, or an empty map. */
    Q_INVOKABLE QVariantMap byId(int agentId) const;

Q_SIGNALS:
    void rosterChanged();

private:
    int rowOf(int agentId) const;

    QJsonObject m_roster;
};

/** The virtual machines pointed at this computer, as `Hub.virtualMachines`: the service's `vms.roster`. */
class HostedVirtualMachineModel : public KeyedRowsModel
{
    Q_OBJECT
    Q_PROPERTY(int onlineCount READ onlineCount NOTIFY aggregateChanged)
    Q_PROPERTY(double committedCpuCores READ committedCpuCores NOTIFY aggregateChanged)
    Q_PROPERTY(qint64 committedMemoryMb READ committedMemoryMb NOTIFY aggregateChanged)
    Q_PROPERTY(qint64 committedStorageMb READ committedStorageMb NOTIFY aggregateChanged)
    Q_PROPERTY(double ceilingCpuCores READ ceilingCpuCores NOTIFY aggregateChanged)
    Q_PROPERTY(qint64 ceilingMemoryMb READ ceilingMemoryMb NOTIFY aggregateChanged)
    Q_PROPERTY(bool anyUncapped READ anyUncapped NOTIFY aggregateChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        CodenameRole,
        TitleRole,
        DescriptionRole,
        AgentIdRole,
        AgentSlugRole,
        AgentTitleRole,
        PrimaryRole,
        OnlineRole,
        ResourcesTextRole,
        EnvelopeRole,
    };

    explicit HostedVirtualMachineModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void apply(const QJsonObject &roster);

    int onlineCount() const;
    double committedCpuCores() const;
    qint64 committedMemoryMb() const;
    qint64 committedStorageMb() const;
    double ceilingCpuCores() const;
    qint64 ceilingMemoryMb() const;
    bool anyUncapped() const;

Q_SIGNALS:
    void aggregateChanged();

private:
    QJsonObject m_aggregates;
};

/**
 * The agents' containers as a whole, as `AgentContainers`: the image they run, a
 * reconciliation on request, and Start for any agent from its card.
 */
class AgentContainersModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool reconciling READ isReconciling NOTIFY changed)
    /**
     * The agents a Start was pressed for from a card and that the platform has
     * not yet said are running, as ids: each card's control stays busy until its
     * agent's own lifecycle frame arrives.
     */
    Q_PROPERTY(QVariantList starting READ starting NOTIFY startsChanged)
    /** Why a Start pressed from a card was refused, in the platform's words, by agent id. */
    Q_PROPERTY(QVariantMap startErrors READ startErrors NOTIFY startsChanged)

public:
    explicit AgentContainersModel(client::ServiceSession *session, QObject *parent = nullptr);

    bool isReconciling() const;
    QVariantList starting() const;
    QVariantMap startErrors() const { return m_startErrors; }

    /** Asks the service to bring every agent's container to what its lifecycle says. */
    Q_INVOKABLE void reconcile();
    /** Forgets the start failures of one agent, or of every agent for 0, so the service tries again. */
    Q_INVOKABLE void clearStartFailures(int agentId = 0);
    /**
     * Presses Start for one agent — the one thing that starts an agent
     * — through the platform as the signed-in person, as
     * the agent's own page does. The container follows the frame that comes back.
     */
    Q_INVOKABLE void start(int agentId);

Q_SIGNALS:
    void changed();
    void startsChanged();

private:
    /** Lets go of every Start the roster now shows running, and of agents that left. */
    void settleStarts(const QJsonObject &roster);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_roster;
    QJsonObject m_value;
    QSet<int> m_starting;
    QVariantMap m_startErrors;
};

/**
 * Start, stop and reboot for one agent, as `AgentLifecycle`: the platform's
 * lifecycle through the service (`/v1/agents/{id}/lifecycle`), which decides whether
 * the signed-in person may manage it and delivers the decision to the computer
 * running the agent.
 */
class AgentLifecycleModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int agentId READ agentId NOTIFY changed)
    Q_PROPERTY(bool canManage READ canManage NOTIFY changed)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString reason READ reason NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    explicit AgentLifecycleModel(client::ServiceSession *session, QObject *parent = nullptr);

    int agentId() const { return m_agentId; }
    bool canManage() const { return m_canManage; }
    bool isBusy() const { return m_requests > 0; }
    QString status() const;
    QString reason() const;
    QString message() const { return m_message; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void open(int agentId);
    Q_INVOKABLE void close();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void reboot();

Q_SIGNALS:
    void changed();
    /** A decision the platform accepted, in the platform's own word: `START`, `STOP` or `REBOOT`. */
    void acted(int agentId, const QString &action);

private:
    void act(const QString &action);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_roster;
    int m_agentId = 0;
    bool m_canManage = false;
    int m_requests = 0;
    QJsonObject m_lifecycle;
    QString m_message;
    QString m_lastError;
};

/**
 * An agent's Settings on this computer, as `AgentSettings`: moving it to the
 * newer release of what it was installed from, and uninstalling it from this
 * computer.
 *
 * Both go to the platform through the service as the signed-in person, which
 * decides who may: an admin of the agent for an update, and an admin or this
 * computer's owner for an uninstall. Nothing here touches Docker. An update
 * that reboots the agent arrives back as a `desktop.agent.lifecycle` frame of
 * reboot type `UPDATE`, and an uninstall as the agent leaving the roster.
 */
class AgentSettingsModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int agentId READ agentId NOTIFY changed)
    Q_PROPERTY(bool loading READ isLoading NOTIFY changed)
    /** Whether the agent was installed from a published release at all. */
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    /** True for an admin of the agent. */
    Q_PROPERTY(bool canUpdate READ canUpdate NOTIFY changed)
    /** Why the signed-in person cannot apply the update on offer, in the platform's words. */
    Q_PROPERTY(QString blockedReason READ blockedReason NOTIFY changed)
    /** `@owner/agent/artifact`, or empty when the artifact is private. */
    Q_PROPERTY(QString source READ source NOTIFY changed)
    Q_PROPERTY(bool sourcePrivate READ sourcePrivate NOTIFY changed)
    /** The release it runs: `{artifactTagId, tag, title, notes, publishedAt}`, or empty. */
    Q_PROPERTY(QVariantMap current READ current NOTIFY changed)
    /** The newer release on offer, in the same shape, or empty when there is none. */
    Q_PROPERTY(QVariantMap available READ available NOTIFY changed)
    /**
     * What's new: every release note since the release it runs, up to the one
     * on offer, newest first, each `{artifactTagId, tag, title, notes,
     * publishedAt, isDeprecated}` with its whole note in Markdown. Empty when
     * nothing is on offer, and for a private artifact.
     */
    Q_PROPERTY(QVariantList releases READ releases NOTIFY changed)
    /** How many releases What's new covers in all; more than `releases` holds past 50. */
    Q_PROPERTY(int releasesTotal READ releasesTotal NOTIFY changed)
    Q_PROPERTY(bool updating READ isUpdating NOTIFY changed)
    Q_PROPERTY(bool uninstalling READ isUninstalling NOTIFY changed)
    /** What the last update or uninstall did, in the platform's words. */
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QStringList warnings READ warnings NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    explicit AgentSettingsModel(client::ServiceSession *session, QObject *parent = nullptr);

    int agentId() const { return m_agentId; }
    bool isLoading() const { return m_reading > 0; }
    bool installed() const;
    bool canUpdate() const;
    QString blockedReason() const;
    QString source() const;
    bool sourcePrivate() const;
    QVariantMap current() const;
    QVariantMap available() const;
    QVariantList releases() const;
    int releasesTotal() const;
    bool isUpdating() const { return m_updating; }
    bool isUninstalling() const { return m_uninstalling; }
    QString message() const { return m_message; }
    QStringList warnings() const { return m_warnings; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void open(int agentId);
    Q_INVOKABLE void close();
    Q_INVOKABLE void refresh();
    /** Moves the agent to the release on offer: the one this page shows. */
    Q_INVOKABLE void applyUpdate();
    /** Takes the agent off this computer. The agent itself is kept. */
    Q_INVOKABLE void uninstall();

Q_SIGNALS:
    void changed();
    /** The platform moved the agent to a newer release; `rebooted` when it is restarting to run it. */
    void updated(int agentId, bool rebooted);
    /** The platform took the agent off this computer. */
    void uninstalled(int agentId);

private:
    client::ServiceSession *m_session;
    client::TopicSubscription *m_roster;
    int m_agentId = 0;
    int m_reading = 0;
    bool m_updating = false;
    bool m_uninstalling = false;
    QJsonObject m_state;
    /** The row's offer, as the roster last carried it, to tell when it moved. */
    QJsonValue m_rowUpdate;
    QString m_message;
    QStringList m_warnings;
    QString m_lastError;
};

/**
 * An agent's **Dependencies**, as `AgentDependencies`: the engine it runs on and
 * the release of every artifact it uses, as its lock holds them, with **Update**
 * and **Forget unused**.
 *
 * Read from the platform through the service's proxy as the signed-in person,
 * who decides who may press either: an owner or admin of the agent. Read again
 * whenever the lock moves, which reaches this computer as the Hub's
 * `desktop.agent.resource.updated` with `LOCK`, relayed on the service's
 * `agents.resource` topic for the agent open here.
 */
class AgentDependenciesModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int agentId READ agentId NOTIFY changed)
    Q_PROPERTY(bool loading READ isLoading NOTIFY changed)
    /** Whether the platform has answered for the agent open here. */
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY changed)
    /** The engine it runs on, `0.6.0`; empty when its `simorg.toml` names none. */
    Q_PROPERTY(QString engineVersion READ engineVersion NOTIFY changed)
    /** True for an owner or admin of the agent. */
    Q_PROPERTY(bool canManage READ canManage NOTIFY changed)
    /**
     * Every artifact it uses at its locked release, each `{specifier, tag,
     * updateTag, updateNotes}`; `updateTag` is what Update would move it to,
     * empty when nothing.
     */
    Q_PROPERTY(QVariantList dependencies READ dependencies NOTIFY changed)
    /** How many of them Update would move. */
    Q_PROPERTY(int movable READ movable NOTIFY changed)
    /** True while Update or Forget unused is under way. */
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    /**
     * What the last press did: `{kind: "update", moved, rebooted}` or `{kind:
     * "forget", forgotten, days}`; empty before one.
     */
    Q_PROPERTY(QVariantMap outcome READ outcome NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    explicit AgentDependenciesModel(client::ServiceSession *session, QObject *parent = nullptr);

    int agentId() const { return m_agentId; }
    bool isLoading() const { return m_reading > 0; }
    bool isLoaded() const { return !m_state.isEmpty(); }
    QString engineVersion() const;
    bool canManage() const;
    QVariantList dependencies() const;
    int movable() const;
    bool isBusy() const { return m_busy; }
    QVariantMap outcome() const { return m_outcome; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void open(int agentId);
    Q_INVOKABLE void close();
    Q_INVOKABLE void refresh();
    /** Moves every `latest`, `^` and `beta` entry to what it resolves to now; a running agent restarts to fetch them. */
    Q_INVOKABLE void update();
    /** Forgets every entry its code has not included in `days` days. */
    Q_INVOKABLE void forgetUnused(int days);

Q_SIGNALS:
    void changed();

private:
    QString path() const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_resources = nullptr;
    int m_agentId = 0;
    int m_reading = 0;
    bool m_busy = false;
    QJsonObject m_state;
    QVariantMap m_outcome;
    QString m_lastError;
};

/**
 * Resizing one agent's virtual machine and rebooting it onto the new size, as
 * `AgentVirtualMachine`. The service runs the sequence and reports it on
 * `vms.resize`, which this listens to while one runs.
 */
class AgentVirtualMachineModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    Q_PROPERTY(Stage stage READ stage NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QVariantList cpuSteps READ cpuSteps NOTIFY stepsChanged)
    Q_PROPERTY(QVariantList memorySteps READ memorySteps NOTIFY stepsChanged)
    Q_PROPERTY(QVariantList storageSteps READ storageSteps NOTIFY stepsChanged)
    Q_PROPERTY(QVariantList gpuSteps READ gpuSteps NOTIFY stepsChanged)

public:
    /** QML's `VirtualMachineStage`. */
    enum Stage {
        Idle,
        Saving,
        Rebooting,
    };
    Q_ENUM(Stage)

    explicit AgentVirtualMachineModel(client::ServiceSession *session, QObject *parent = nullptr);

    bool isBusy() const { return m_requesting || stage() != Idle; }
    Stage stage() const;
    QString lastError() const { return m_lastError; }
    QString message() const { return m_message; }
    QVariantList cpuSteps() const { return m_cpuSteps; }
    QVariantList memorySteps() const { return m_memorySteps; }
    QVariantList storageSteps() const { return m_storageSteps; }
    /** The graphics memory sizes on offer, in MiB; a ceiling alone, since nothing reserves a card's memory. */
    QVariantList gpuSteps() const { return m_gpuSteps; }

    /**
     * Saves `envelope` (`{cpuMin, cpuMax, cpuCapped, memoryMin, …}`) for the agent's
     * virtual machine and reboots the agent onto it. The virtual machine is named by the
     * agent; `virtualMachineId` is the window's and is not sent.
     */
    Q_INVOKABLE void applyAndReboot(int agentId, int virtualMachineId, const QVariantMap &envelope);
    /** Clears the last message and error. */
    Q_INVOKABLE void forget();

Q_SIGNALS:
    void changed();
    void stepsChanged();
    void applied(int agentId, int virtualMachineId);

private:
    void follow(int agentId);
    void apply(const QJsonObject &resize);
    void loadSteps();

    client::ServiceSession *m_session;
    client::TopicSubscription *m_resize = nullptr;
    QJsonObject m_state;
    int m_agentId = 0;
    int m_virtualMachineId = 0;
    bool m_sawRunning = false;
    bool m_requesting = false;
    QString m_lastError;
    QString m_message;
    QVariantList m_cpuSteps;
    QVariantList m_memorySteps;
    QVariantList m_storageSteps;
    QVariantList m_gpuSteps;
};

} // namespace simorg::app
