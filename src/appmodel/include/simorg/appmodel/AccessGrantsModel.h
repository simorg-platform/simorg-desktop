// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DockerListModels.h"

#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace simorg::client {
class ServiceReply;
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * What agents on this computer asked to reach, what was answered, and the rules
 * this computer's owner set for every agent: `AccessGrants`.
 *
 * The service keeps the answers and the rules on the platform and publishes the
 * whole of it on `access.changed`; this is a
 * row per request, with the rules, settings and pending agents read from the same
 * overview. A write refused here, before it is sent, returns false and says why in
 * `lastError()`; one the service refuses is `saveFailed`, and a refusal from the
 * platform arrives as the store's error, which `MachineConfig` shows.
 */
class AccessGrantsModel : public KeyedRowsModel
{
    Q_OBJECT
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY changed)
    Q_PROPERTY(int ruleCount READ ruleCount NOTIFY changed)
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY changed)
    Q_PROPERTY(bool saving READ isSaving NOTIFY changed)
    /**
     * The applications every agent may use whatever `APPLICATIONS` says: Simorg Desktop, as
     * the platform names it. Empty until the
     * service has read it. Every screen that draws that permission shows it as a fixed entry.
     */
    Q_PROPERTY(QStringList alwaysAllowedApplications READ alwaysAllowedApplications NOTIFY changed)

public:
    enum Role {
        AgentIdRole = Qt::UserRole + 1,
        AgentSlugRole,
        AgentTitleRole,
        AccessKeyRole,
        DecisionRole,
        EffectiveDecisionRole,
        MachineRuleRole,
        RuledByMachineRole,
        ReasonRole,
        MachineCategoryKeysRole,
        SettingsRole,
        DecidedAtRole,
        UnchosenFolderCountRole,
        AboutFoldersRole,
    };

    explicit AccessGrantsModel(client::ServiceSession *session, QObject *parent = nullptr);

    QStringList alwaysAllowedApplications() const;

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** Requests nobody has answered and no rule decides. */
    int pendingCount() const;
    int ruleCount() const;
    bool isLoaded() const;
    bool isSaving() const;

    /** `ASK`, `ALWAYS_ALLOW` or `NEVER_ALLOW` for one permission on this computer. */
    Q_INVOKABLE QString rule(const QString &accessKey) const;
    Q_INVOKABLE void setRule(const QString &accessKey, const QString &rule);
    /** The settings this computer gives every agent for one permission; empty when none are set. */
    Q_INVOKABLE QVariantMap machineSettings(const QString &accessKey) const;
    /** Replaces them; an empty map removes them. */
    Q_INVOKABLE void setMachineSettings(const QString &accessKey, const QVariantMap &settings);
    Q_INVOKABLE int machineSettingCount() const;
    /** Every request of one agent, each as `at` gives it. */
    Q_INVOKABLE QVariantList requestsFor(int agentId) const;
    /** `{agentId, agentSlug, agentTitle, pendingCount}` for each agent with something to answer, by name. */
    Q_INVOKABLE QVariantList pendingAgents() const;
    Q_INVOKABLE int pendingCountFor(int agentId) const;
    /** Pending requests, and allowed folder requests with a folder still to choose. */
    Q_INVOKABLE int outstandingFor(int agentId) const;
    Q_INVOKABLE bool decide(int agentId, const QString &accessKey, bool allowed);
    Q_INVOKABLE void reset(int agentId, const QString &accessKey);
    /**
     * `{index, dynamic, purpose, mode, path, agentPath, chosen, writable}` for each folder a
     * folder request names. `agentPath` is where the agent's container has `path`
     * ({@link agentPathOf}), and empty while no folder is chosen.
     */
    Q_INVOKABLE QVariantList folders(int agentId, const QString &accessKey) const;

    /**
     * Where an agent's container has a folder of this computer: the spelling the
     * machine service mounts it under, which is what a person has to give a
     * program inside the agent.
     *
     * The path normalised — `.` and `..` resolved, repeated and trailing
     * separators dropped — and, from a Windows computer, `X:\rest` as `/x/rest`
     * with the drive letter in lower case: `D:\Documents\research` is
     * `/d/Documents/research`. On a Mac or Linux the two are the same path.
     * `windows` is the computer's, a parameter so that both are testable anywhere.
     */
    static QString agentPathOf(const QString &hostPath, bool windows);
    /** {@link agentPathOf} for a folder of this computer, whichever kind it is. */
    Q_INVOKABLE QString agentPath(const QString &hostPath) const;
    /** Records the folder for one entry of a folder request; an empty path un-chooses it. */
    Q_INVOKABLE bool chooseFolder(int agentId, const QString &accessKey, int folderIndex, const QString &path);
    /** Why the last call refused before it sent anything. */
    Q_INVOKABLE QString lastError() const { return m_lastError; }

Q_SIGNALS:
    /** A new overview: any row, rule, setting or folder may have moved. */
    void changed();
    /** A write the service did not take, in its words. */
    void saveFailed(const QString &message);

private:
    void apply(const QJsonObject &overview);
    /** Reports `reply` failing as `saveFailed`; what it changed arrives on `access.changed`. */
    void watch(client::ServiceReply *reply);
    const QJsonObject *request(int agentId, const QString &accessKey) const;
    bool fail(const QString &message);
    QString encodedKey(const QString &accessKey) const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_overview;
    QString m_lastError;
};

} // namespace simorg::app
