// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantMap>

#include <utility>

class QTimer;

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

class HostedAgentModel;
class HostedVirtualMachineModel;

/**
 * Why this computer is not talking to Simorg, and when it tries again: `Hub.connection`.
 *
 * The service diagnoses the connection and publishes it on `hub.connection`;
 * this reads it and counts down to the
 * next attempt between events, so a banner's "trying again in 4 s" moves.
 */
class ConnectionModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(Trouble trouble READ trouble NOTIFY troubleChanged)
    Q_PROPERTY(bool troubled READ isTroubled NOTIFY troubleChanged)
    Q_PROPERTY(bool severe READ isSevere NOTIFY troubleChanged)
    Q_PROPERTY(QString title READ title NOTIFY troubleChanged)
    Q_PROPERTY(QString detail READ detail NOTIFY troubleChanged)
    Q_PROPERTY(bool attempting READ isAttempting NOTIFY troubleChanged)
    Q_PROPERTY(int attempts READ attempts NOTIFY troubleChanged)
    Q_PROPERTY(Reachability reachability READ reachability NOTIFY troubleChanged)
    Q_PROPERTY(int retryInSeconds READ retryInSeconds NOTIFY countdownChanged)

public:
    /** The service's `trouble`: one value per thing a person would do about it. */
    enum class Trouble {
        None,
        NoNetwork,
        CaptivePortal,
        ServerUnreachable,
        ServerRestarting,
        ServerSilent,
        ServerRefused,
        /** Not retrying; a person has to act. */
        Stopped,
    };
    Q_ENUM(Trouble)

    enum class Reachability {
        Unknown,
        Offline,
        Online,
    };
    Q_ENUM(Reachability)

    explicit ConnectionModel(client::ServiceSession *session, QObject *parent = nullptr);

    Trouble trouble() const;
    bool isTroubled() const { return trouble() != Trouble::None; }
    bool isSevere() const;
    QString title() const;
    QString detail() const;
    bool isAttempting() const;
    int attempts() const;
    Reachability reachability() const;
    /** Seconds until the next attempt, counted down between events; 0 when none is scheduled. */
    int retryInSeconds() const { return m_retryInSeconds; }

    /** Applies one `HubConnectionDiagnosis`. */
    void apply(const QJsonObject &diagnosis);

public Q_SLOTS:
    /** Asks the service to try now rather than at the end of the back-off. */
    void retryNow();

Q_SIGNALS:
    void troubleChanged();
    void countdownChanged();

private:
    void tick();

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_diagnosis;
    QDateTime m_nextAttemptAt;
    QTimer *m_countdown;
    int m_retryInSeconds = 0;
};

/**
 * The machine's one Hub connection, as the windows read it off `Hub`.
 *
 * The service holds the connection and
 * publishes `hub.state`; what this computer is comes from `machine.identity`, and
 * the agents and virtual machines placed here from `agents.roster` and `vms.roster`.
 */
class HubModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY stateChanged)
    Q_PROPERTY(bool initializing READ isInitializing NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(bool everConnected READ hasEverConnected NOTIFY stateChanged)
    Q_PROPERTY(bool enrolling READ isEnrolling NOTIFY stateChanged)
    Q_PROPERTY(bool registrable READ isRegistrable NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(QString machineTitle READ machineTitle NOTIFY machineChanged)
    Q_PROPERTY(QString machineCodename READ machineCodename NOTIFY machineChanged)
    Q_PROPERTY(int machineId READ machineId NOTIFY machineChanged)
    /** The sign-in behind this connection is the one that put this computer on the account. */
    Q_PROPERTY(bool newlyRegistered READ isNewlyRegistered NOTIFY machineChanged)
    Q_PROPERTY(QVariantMap machineSummary READ machineSummary NOTIFY machineSummaryChanged)
    /** A rename of this machine is being asked of the platform. */
    Q_PROPERTY(bool renaming READ isRenaming NOTIFY renameChanged)
    /** Why the last rename was refused, in the platform's words; empty once one is asked again. */
    Q_PROPERTY(QString renameError READ renameError NOTIFY renameChanged)
    /**
     * How many agents, and virtual machines, are placed on this computer: the
     * rosters' own counts, live, or -1 while the service has not said.
     */
    Q_PROPERTY(int agentCount READ agentCount NOTIFY countsChanged)
    Q_PROPERTY(int virtualMachineCount READ virtualMachineCount NOTIFY countsChanged)
    Q_PROPERTY(simorg::app::ConnectionModel *connection READ connection CONSTANT)
    Q_PROPERTY(simorg::app::HostedAgentModel *agents READ agents CONSTANT)
    Q_PROPERTY(simorg::app::HostedVirtualMachineModel *virtualMachines READ virtualMachines CONSTANT)

public:
    enum class State {
        Idle,
        Connecting,
        Initializing,
        Ready,
        Reconnecting,
        Failed,
    };
    Q_ENUM(State)

    explicit HubModel(client::ServiceSession *session, QObject *parent = nullptr);

    State state() const { return m_state; }
    bool isConnected() const { return m_state == State::Ready; }
    bool isInitializing() const { return m_state == State::Initializing; }
    QString statusText() const;
    bool hasEverConnected() const;
    bool isEnrolling() const;
    bool isRegistrable() const;
    QString lastError() const;
    QString machineTitle() const;
    QString machineCodename() const;
    int machineId() const;
    bool isNewlyRegistered() const;
    /** What this computer reports about itself, formatted for the machine card, with the raw readings for its meters. */
    QVariantMap machineSummary() const { return m_summary; }
    int agentCount() const;
    int virtualMachineCount() const;
    bool isRenaming() const { return m_renaming; }
    QString renameError() const { return m_renameError; }
    ConnectionModel *connection() const { return m_connection; }
    HostedAgentModel *agents() const { return m_agents; }
    HostedVirtualMachineModel *virtualMachines() const { return m_virtualMachines; }

public Q_SLOTS:
    /** Asks the service to read this computer again. */
    void refreshMachineSummary();
    /**
     * Renames this machine, from Settings.
     *
     * Only the name is sent, to the platform's own machine through the service's
     * proxy, as the signed-in person: the platform moves a handle it made from the
     * old name along with the new one and keeps one somebody chose. The new name
     * and handle arrive the way every rename does — the platform's
     * `user.machine.updated` reaches the service over its Hub socket, and the
     * service updates this machine and publishes it — so
     * this screen, the Logos and every other screen showing the machine change
     * together. `machineRenamed` says the platform kept it, for the moment between
     * its answer and that news.
     */
    void renameMachine(const QString &title);

Q_SIGNALS:
    void stateChanged();
    void machineChanged();
    void machineSummaryChanged();
    void countsChanged();
    void renameChanged();
    /** The platform kept `title` as this machine's name. */
    void machineRenamed(const QString &title);

private:
    void applyState(const QJsonObject &hub);
    void applyIdentity(const QJsonObject &identity);
    /** Announces `countsChanged` when either roster's count, or whether it is known, moved. */
    void recount();

    client::ServiceSession *m_session;
    client::TopicSubscription *m_stateTopic;
    client::TopicSubscription *m_identityTopic;
    ConnectionModel *m_connection;
    HostedAgentModel *m_agents;
    HostedVirtualMachineModel *m_virtualMachines;
    QJsonObject m_hub;
    State m_state = State::Idle;
    QVariantMap m_summary;
    /** Whether the service has said what is placed here: each roster's `known`. */
    bool m_agentsKnown = false;
    bool m_virtualMachinesKnown = false;
    /** The two counts last announced, so a roster that moved nothing says nothing. */
    std::pair<int, int> m_counted{-1, -1};
    bool m_renaming = false;
    QString m_renameError;
};

} // namespace simorg::app
