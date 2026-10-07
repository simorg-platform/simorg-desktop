// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/AuthModel.h"

#include "simorg/appmodel/LegalModel.h"
#include "simorg/client/ServiceSession.h"

#include <utility>

namespace simorg::app {

using client::ServiceProblem;
using client::ServiceReply;

namespace {

AuthModel::State stateNamed(const QString &name)
{
    if (name == QLatin1String("restoring"))
        return AuthModel::State::Restoring;
    if (name == QLatin1String("signing_in"))
        return AuthModel::State::SigningIn;
    if (name == QLatin1String("awaiting_second_factor"))
        return AuthModel::State::AwaitingSecondFactor;
    if (name == QLatin1String("signed_in"))
        return AuthModel::State::SignedIn;
    if (name == QLatin1String("signing_out"))
        return AuthModel::State::SigningOut;
    return AuthModel::State::SignedOut;
}

} // namespace

AuthModel::AuthModel(client::ServiceSession *session, LegalModel *legal, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_legal(legal)
    , m_stateTopic(session->subscribe(QStringLiteral("auth.state")))
    , m_profileTopic(session->subscribe(QStringLiteral("auth.profile")))
{
    connect(m_stateTopic, &client::TopicSubscription::received, this, &AuthModel::applyState);
    connect(m_profileTopic, &client::TopicSubscription::received, this, [this](const QJsonObject &profile) {
        const Profile user = Profile::fromService(profile);
        if (user == m_user)
            return;
        m_user = user;
        Q_EMIT userChanged();
    });
    if (m_stateTopic->hasValue())
        applyState(m_stateTopic->value());
}

void AuthModel::applyState(const QJsonObject &state)
{
    const State previous = m_state;
    const bool wasBusy = isBusy();
    // The first of these is the answer every window at launch is waiting for; see isKnown().
    const bool learned = !std::exchange(m_known, true);
    m_state = stateNamed(state.value(QStringLiteral("state")).toString());
    m_serviceBusy = state.value(QStringLiteral("busy")).toBool();

    const QJsonObject lastError = state.value(QStringLiteral("last_error")).toObject();
    if (!lastError.isEmpty())
        setLastError(lastError.value(QStringLiteral("message")).toString());

    if (learned || previous != m_state || wasBusy != isBusy())
        Q_EMIT stateChanged();
    if (m_state == State::SignedOut && (previous == State::SignedIn || previous == State::SigningOut))
        Q_EMIT signedOut();
}

void AuthModel::setRequesting(bool requesting)
{
    const bool wasBusy = isBusy();
    m_requesting = requesting;
    if (wasBusy != isBusy())
        Q_EMIT stateChanged();
}

void AuthModel::setLastError(const QString &message)
{
    if (message == m_lastError)
        return;
    m_lastError = message;
    Q_EMIT lastErrorChanged();
}

void AuthModel::signIn(const QString &email, const QString &password)
{
    if (m_requesting)
        return;
    setRequesting(true);
    setLastError(QString());
    m_legal->acceptThen([this, email, password](bool accepted, const QString &message) {
        if (!accepted) {
            setRequesting(false);
            setLastError(message);
            Q_EMIT signInFailed(message);
            return;
        }
        login(email, password);
    });
}

void AuthModel::login(const QString &email, const QString &password)
{
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/auth/login"),
                                          {{QStringLiteral("email"), email}, {QStringLiteral("password"), password}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        setRequesting(false);
        if (reply->isError()) {
            const QString message = reply->problem().message();
            setLastError(message);
            Q_EMIT signInFailed(message);
            return;
        }
        if (reply->status() == 202) {
            Q_EMIT secondFactorRequired();
            return;
        }
        Q_EMIT signInSucceeded();
    });
}

void AuthModel::submitSecondFactor(const QString &code, bool useRecoveryCode)
{
    if (m_requesting)
        return;
    setRequesting(true);
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/auth/second-factor"),
                        {{QStringLiteral("code"), code.trimmed()}, {QStringLiteral("recovery"), useRecoveryCode}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        setRequesting(false);
        if (!reply->isError()) {
            Q_EMIT signInSucceeded();
            return;
        }
        const ServiceProblem problem = reply->problem();
        setLastError(problem.message());
        // An expired or locked challenge is over, back to the password; a wrong code keeps it.
        if (problem.code == QLatin1String("TWO_FACTOR_CHALLENGE_EXPIRED")
            || problem.code == QLatin1String("TWO_FACTOR_LOCKED")
            || problem.code == QLatin1String("NO_SECOND_FACTOR_PENDING")) {
            Q_EMIT secondFactorEnded(problem.message());
            return;
        }
        Q_EMIT secondFactorFailed(problem.message());
    });
}

void AuthModel::cancelSecondFactor()
{
    ServiceReply *reply = m_session->remove(QStringLiteral("/v1/auth/second-factor"));
    connect(reply, &ServiceReply::finished, this, [this] { Q_EMIT secondFactorEnded(QString()); });
}

void AuthModel::signOut()
{
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/auth/logout"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (reply->isError() && reply->problem().code != QLatin1String("OPERATION_IN_PROGRESS"))
            setLastError(reply->problem().message());
    });
}

} // namespace simorg::app
