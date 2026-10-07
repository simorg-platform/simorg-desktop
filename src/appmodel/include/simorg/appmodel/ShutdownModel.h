// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * A run of the service's shutdown, as the quit window reads it off `Shutdown`.
 *
 * The service runs the sequence: the
 * agents asked to finish, then their containers stopped and kept. This follows
 * `shutdown.state`. `begin` is this app asking for it; a run can equally be asked
 * for by another app on this computer (`requestedBy`), or started by the
 * computer shutting down or the person logging out. `quitNow` is its Force, which
 * the service offers 20 seconds after the run started.
 */
class ShutdownModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ isActive NOTIFY changed)
    Q_PROPERTY(int phase READ phase NOTIFY changed)
    Q_PROPERTY(QString headline READ headline NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(int agentsTotal READ agentsTotal NOTIFY changed)
    Q_PROPERTY(int agentsFinished READ agentsFinished NOTIFY changed)
    Q_PROPERTY(bool agentsSettled READ agentsSettled NOTIFY changed)
    Q_PROPERTY(int agentsInterrupted READ agentsInterrupted NOTIFY changed)
    Q_PROPERTY(QString agentsLabel READ agentsLabel NOTIFY changed)
    Q_PROPERTY(int secondsLeft READ secondsLeft NOTIFY changed)
    Q_PROPERTY(int graceSeconds READ graceSeconds NOTIFY changed)
    Q_PROPERTY(int total READ total NOTIFY changed)
    Q_PROPERTY(int stopped READ stopped NOTIFY changed)
    Q_PROPERTY(qreal progress READ progress NOTIFY changed)
    Q_PROPERTY(bool indeterminate READ isIndeterminate NOTIFY changed)
    Q_PROPERTY(bool complete READ isComplete NOTIFY changed)
    Q_PROPERTY(bool leaving READ isLeaving NOTIFY changed)
    Q_PROPERTY(bool forceAvailable READ isForceAvailable NOTIFY changed)
    Q_PROPERTY(QString requestedBy READ requestedBy NOTIFY changed)
    Q_PROPERTY(bool askedHere READ isAskedHere NOTIFY changed)

public:
    /** Read from QML as plain ints, as the quit window has always read them. */
    enum Phase {
        Idle = 0,
        Agents = 1,
        Containers = 2,
        Done = 3,
    };
    Q_ENUM(Phase)

    explicit ShutdownModel(client::ServiceSession *session, QObject *parent = nullptr);

    bool isActive() const { return phase() != Idle; }
    int phase() const;
    QString headline() const;
    QString detail() const;
    int agentsTotal() const;
    int agentsFinished() const;
    bool agentsSettled() const;
    int agentsInterrupted() const;
    QString agentsLabel() const;
    int secondsLeft() const;
    int graceSeconds() const;
    int total() const;
    int stopped() const;
    qreal progress() const;
    bool isIndeterminate() const;
    /** The run has an outcome. */
    bool isComplete() const;
    /** Complete, and the service is stopping with it. */
    bool isLeaving() const;
    /** The service offers Force now. */
    bool isForceAvailable() const;
    /** The app that asked for the run, by the name before its version (`simorg`, `simorg-desktop`); empty when none. */
    QString requestedBy() const;
    /** This app asked for the run in flight. */
    bool isAskedHere() const;

public Q_SLOTS:
    /**
     * Asks the service to stop the agents, their containers and itself. Safe to call
     * twice; while a run is already in flight it asks nothing.
     */
    void begin();
    /** Stops waiting for the agents and moves on: the run's Force. */
    void quitNow();

Q_SIGNALS:
    void changed();
    /** The service would not stop, in its words. */
    void beginFailed(const QString &message);

private:
    QJsonObject member(const char *key) const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_run;
    /** The `started_at` of the run this app asked for. */
    QString m_askedRun;
};

} // namespace simorg::app
