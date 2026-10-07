// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/Profile.h"

#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
struct ServiceProblem;
} // namespace simorg::client

namespace simorg::app {

class LegalModel;

/**
 * The session, as QML reads it off `Auth`.
 *
 * The session is the service's: it signs in, asks for the second factor, keeps
 * and refreshes the token and signs out. This follows `auth.state` and
 * `auth.profile`, and turns the window's gestures into the service's sign-in
 * operations. A sign-in made in a terminal therefore signs this window in too,
 * through the same topics.
 *
 * The signals the windows listen for keep their meaning: `signInSucceeded`,
 * `signInFailed`, `secondFactorRequired`, `secondFactorFailed` and
 * `secondFactorEnded` answer this window's own requests; `stateChanged`,
 * `userChanged` and `signedOut` follow the session whoever moved it.
 */
class AuthModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool known READ isKnown NOTIFY stateChanged)
    Q_PROPERTY(bool signedIn READ isSignedIn NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY stateChanged)
    Q_PROPERTY(simorg::app::Profile user READ user NOTIFY userChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool awaitingSecondFactor READ isAwaitingSecondFactor NOTIFY stateChanged)

public:
    /** The service's states; `SigningOut` is the sign-out sweep, which this app never had before. */
    enum class State {
        SignedOut,
        Restoring,
        SigningIn,
        AwaitingSecondFactor,
        SignedIn,
        SigningOut,
    };
    Q_ENUM(State)

    AuthModel(client::ServiceSession *session, LegalModel *legal, QObject *parent = nullptr);

    State state() const { return m_state; }
    /**
     * Whether the service has said what this computer's session is.
     *
     * False for the moment between the process starting and the first
     * `auth.state` arriving, and that moment is not a signed-out one: the
     * session lives in the service, and this object cannot know what it holds
     * until it has answered. Treating the gap as signed out is what made a
     * launch on a signed-in computer flash the sign-in window for half a second
     * before the dashboard replaced it — see `DesktopApplication::surfaceWindow`.
     *
     * Sticky once true. A connection lost later does not unlearn the session;
     * the service republishes its state on the next subscription, and a window
     * that reverted to "we do not know yet" on every reconnection would be
     * worse than the flash it exists to remove.
     */
    bool isKnown() const { return m_known; }
    bool isSignedIn() const { return m_state == State::SignedIn; }
    bool isAwaitingSecondFactor() const { return m_state == State::AwaitingSecondFactor; }
    bool isBusy() const { return m_serviceBusy || m_requesting; }
    Profile user() const { return m_user; }
    QString lastError() const { return m_lastError; }

    /**
     * Signs in. The terms are accepted immediately before, in the same gesture:
     * the window only lets somebody press Sign in with the box ticked.
     */
    Q_INVOKABLE void signIn(const QString &email, const QString &password);
    Q_INVOKABLE void submitSecondFactor(const QString &code, bool useRecoveryCode = false);
    Q_INVOKABLE void cancelSecondFactor();
    Q_INVOKABLE void signOut();

Q_SIGNALS:
    void stateChanged();
    void userChanged();
    void lastErrorChanged();
    void signInSucceeded();
    void signInFailed(const QString &message);
    void secondFactorRequired();
    void secondFactorFailed(const QString &message);
    /** The half-finished sign-in is over; `reason` is empty when this window cancelled it. */
    void secondFactorEnded(const QString &reason);
    void signedOut();

private:
    void applyState(const QJsonObject &state);
    void setRequesting(bool requesting);
    void setLastError(const QString &message);
    void login(const QString &email, const QString &password);

    client::ServiceSession *m_session;
    LegalModel *m_legal;
    client::TopicSubscription *m_stateTopic;
    client::TopicSubscription *m_profileTopic;
    State m_state = State::SignedOut;
    bool m_known = false;
    bool m_serviceBusy = false;
    bool m_requesting = false;
    Profile m_user;
    QString m_lastError;
};

} // namespace simorg::app
