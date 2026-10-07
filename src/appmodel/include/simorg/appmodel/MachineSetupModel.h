// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceReply;
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The machine setup wizard, as its windows read it off `MachineSetup`.
 *
 * The service walks the platform's wizard and publishes where it stands on
 * `machine.setup`; the three screens post
 * each answer. The runtime step is the service's own check: whatever a window
 * found, the service runs the check itself and reports that.
 */
class MachineSetupModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(Step step READ step NOTIFY stateChanged)
    Q_PROPERTY(bool required READ isRequired NOTIFY stateChanged)
    Q_PROPERTY(bool finished READ isFinished NOTIFY stateChanged)
    Q_PROPERTY(bool listed READ isListed NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY stateChanged)
    Q_PROPERTY(bool undecided READ isUndecided NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(int machineId READ machineId NOTIFY machineChanged)
    Q_PROPERTY(QString title READ title NOTIFY machineChanged)
    Q_PROPERTY(QString slug READ slug NOTIFY machineChanged)
    Q_PROPERTY(QString description READ description NOTIFY machineChanged)
    Q_PROPERTY(QString readme READ readme NOTIFY machineChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY machineChanged)
    Q_PROPERTY(QString runtimeState READ runtimeState NOTIFY stateChanged)
    Q_PROPERTY(bool welcomeOwed READ isWelcomeOwed NOTIFY welcomeOwedChanged)

public:
    /** The screens, in the order they are asked; `Done` is no screen. The service's `step`. */
    enum Step {
        Welcome,
        Identity,
        Runtime,
        Done,
    };
    Q_ENUM(Step)

    /** What was found to run containers in. The service's `runtime_state`. */
    enum RuntimeState {
        Ready,
        Unavailable,
        NotApplicable,
    };
    Q_ENUM(RuntimeState)

    explicit MachineSetupModel(client::ServiceSession *session, QObject *parent = nullptr);

    Step step() const;
    bool isRequired() const;
    bool isFinished() const { return step() == Done; }
    bool isListed() const;
    bool isBusy() const;
    bool isUndecided() const;
    QString lastError() const { return m_lastError; }
    int machineId() const;
    QString title() const;
    QString slug() const;
    QString description() const;
    QString readme() const;
    QString deviceName() const;
    /** What the last runtime report said: `ready`, `unavailable`, or empty before there was one. */
    QString runtimeState() const;

    /**
     * A first setup has just finished here, and its welcome has not been closed.
     *
     * True from the moment the wizard the platform owed this computer — the one
     * after the sign-in that registered it — finishes on its runtime answer with the
     * machine named, until
     * the welcome it opens is closed or the account signs out. A wizard reopened
     * from Settings has met the welcome already, and a sign-out that ends a wizard
     * half way finishes nothing, so neither owes one. Held in memory rather than on
     * the disk: it is a moment of this run, and the service keeps nothing of an
     * account once it signs out.
     */
    bool isWelcomeOwed() const { return m_welcomeOwed; }

    /** The handle a title suggests, as somebody types it. See Slug.h. */
    Q_INVOKABLE QString suggestSlug(const QString &title) const;
    /** Why a handle would be refused, in a sentence; empty when it would not. */
    Q_INVOKABLE QString slugProblem(const QString &value) const;

public Q_SLOTS:
    /** Opens the wizard again on the naming step, from Settings. */
    void reopen();
    void completeWelcome();
    /** Names the machine, which lists it on its owner's panel. */
    void saveIdentity(const QString &title, const QString &handle, const QString &description, const QString &readme);
    /**
     * Has the service report its own check of this computer, which finishes the wizard.
     *
     * The arguments are what the window found and are not sent: the platform is
     * told what the service's last finished check says.
     */
    void reportRuntime(simorg::app::MachineSetupModel::RuntimeState state, const QString &engineVersion,
                       const QString &agentImage, const QString &detail);
    /** The welcome after a first setup was seen and closed; it is not shown again. */
    void acknowledgeWelcome();

Q_SIGNALS:
    void stateChanged();
    void machineChanged();
    /** The last step was answered — never a sign-out, which ends a wizard without finishing it. */
    void completed();
    void welcomeOwedChanged();

private:
    void apply(const QJsonObject &setup);
    void setWelcomeOwed(bool owed);
    void follow(client::ServiceReply *reply, bool nested = false);
    QJsonObject machine() const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_setup;
    QString m_lastError;
    int m_requests = 0;
    bool m_welcomeOwed = false;
};

} // namespace simorg::app
