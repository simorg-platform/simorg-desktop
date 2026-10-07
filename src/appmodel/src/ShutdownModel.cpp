// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/ShutdownModel.h"

#include "simorg/client/ServiceSession.h"

namespace simorg::app {

using client::ServiceReply;

ShutdownModel::ShutdownModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("shutdown.state")))
{
    connect(m_topic, &client::TopicSubscription::received, this, [this](const QJsonObject &run) {
        if (run == m_run)
            return;
        m_run = run;
        Q_EMIT changed();
    });
}

QJsonObject ShutdownModel::member(const char *key) const
{
    return m_run.value(QLatin1String(key)).toObject();
}

int ShutdownModel::phase() const
{
    const QString name = m_run.value(QStringLiteral("phase")).toString();
    if (name == QLatin1String("agents"))
        return Agents;
    if (name == QLatin1String("containers"))
        return Containers;
    if (name == QLatin1String("done"))
        return Done;
    return Idle;
}

QString ShutdownModel::headline() const
{
    return m_run.value(QStringLiteral("headline")).toString();
}

QString ShutdownModel::detail() const
{
    return m_run.value(QStringLiteral("detail")).toString();
}

int ShutdownModel::agentsTotal() const
{
    return member("agents").value(QStringLiteral("total")).toInt();
}

int ShutdownModel::agentsFinished() const
{
    return member("agents").value(QStringLiteral("finished")).toInt();
}

bool ShutdownModel::agentsSettled() const
{
    return member("agents").value(QStringLiteral("settled")).toBool();
}

int ShutdownModel::agentsInterrupted() const
{
    return member("agents").value(QStringLiteral("interrupted")).toInt();
}

QString ShutdownModel::agentsLabel() const
{
    return member("agents").value(QStringLiteral("label")).toString();
}

int ShutdownModel::secondsLeft() const
{
    return member("agents").value(QStringLiteral("seconds_left")).toInt();
}

int ShutdownModel::graceSeconds() const
{
    return member("agents").value(QStringLiteral("grace_seconds")).toInt();
}

int ShutdownModel::total() const
{
    return member("containers").value(QStringLiteral("total")).toInt();
}

int ShutdownModel::stopped() const
{
    return member("containers").value(QStringLiteral("stopped")).toInt();
}

qreal ShutdownModel::progress() const
{
    return m_run.value(QStringLiteral("progress")).toDouble();
}

bool ShutdownModel::isIndeterminate() const
{
    return m_run.value(QStringLiteral("indeterminate")).toBool();
}

bool ShutdownModel::isComplete() const
{
    return phase() == Done || !m_run.value(QStringLiteral("outcome")).isNull();
}

bool ShutdownModel::isLeaving() const
{
    return isComplete() && m_run.value(QStringLiteral("stop_service")).toBool();
}

bool ShutdownModel::isForceAvailable() const
{
    return m_run.value(QStringLiteral("force_available")).toBool();
}

QString ShutdownModel::requestedBy() const
{
    // `simorg-desktop/0.3.1 (macos 26.4; arm64)` is the app `simorg-desktop`.
    const QString client = m_run.value(QStringLiteral("requested_by")).toString().trimmed();
    return client.section(QLatin1Char('/'), 0, 0).section(QLatin1Char(' '), 0, 0);
}

bool ShutdownModel::isAskedHere() const
{
    return !m_askedRun.isEmpty() && m_run.value(QStringLiteral("started_at")).toString() == m_askedRun;
}

void ShutdownModel::begin()
{
    if (isActive())
        return;
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/shutdown"), {{QStringLiteral("reason"), QStringLiteral("USER_REQUEST")},
                                                         {QStringLiteral("stop_service"), true}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        const client::ServiceProblem problem = reply->problem();
        // Somebody else's run got there first, which is the stop this app asked for.
        if (problem.code == QLatin1String("OPERATION_IN_PROGRESS") || problem.code == QLatin1String("SERVICE_STOPPING"))
            return;
        if (reply->isError()) {
            Q_EMIT beginFailed(problem.message());
            return;
        }
        const QJsonObject run = reply->object();
        m_askedRun = run.value(QStringLiteral("started_at")).toString();
        // The answer is the run as it started; unless the topic already brought this run, which may be further on.
        if (m_run.value(QStringLiteral("started_at")).toString() != m_askedRun)
            m_run = run;
        Q_EMIT changed();
    });
}

void ShutdownModel::quitNow()
{
    m_session->post(QStringLiteral("/v1/shutdown/force"));
}

} // namespace simorg::app
