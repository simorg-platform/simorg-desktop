// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/SettingsModels.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>

namespace simorg::app {

using client::ServiceReply;
using support::text;

// ---- LogSettingsModel -------------------------------------------------------------------

const QString LogSettingsModel::preferenceKey = QStringLiteral("desktop.logs.retention");
// The platform mounts everything under `/api/v1`; without the prefix a read answers 404, which looks exactly like
// nobody having answered and would leave the default in force for ever.
const QString LogSettingsModel::preferencesPath = QStringLiteral("/v1/proxy/back/api/v1/platform/me/preferences");

LogSettingsModel::LogSettingsModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_auth(session->subscribe(QStringLiteral("auth.state")))
{
    connect(m_auth, &client::TopicSubscription::received, this, [this](const QJsonObject &state) {
        const bool signedIn = text(state, "state") == QLatin1String("signed_in");
        if (signedIn == m_signedIn)
            return;
        m_signedIn = signedIn;
        if (signedIn)
            load();
        else
            reset();
    });
}

void LogSettingsModel::load()
{
    ++m_requests;
    Q_EMIT changed();
    ServiceReply *reply = m_session->get(preferencesPath);
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        --m_requests;
        if (reply->isError()) {
            // Nothing shown: a log capped at the default is not worth interrupting anybody about, and this runs on
            // every sign-in, including the ones without a network.
            Q_EMIT changed();
            return;
        }
        m_loaded = true;
        // An unanswered preference is left out, not null, and the default is its answer.
        const QJsonValue stored = reply->object().value(preferenceKey);
        if (stored.isObject()) {
            const QJsonObject retention = stored.toObject();
            m_maxLines = qBound(minimumMaxLines, retention.value(QStringLiteral("maxLines")).toInt(defaultMaxLines),
                                maximumMaxLines);
            m_unlimited = retention.value(QStringLiteral("unlimited")).toBool(false);
        }
        Q_EMIT changed();
    });
}

void LogSettingsModel::apply(int maxLines, bool unlimited)
{
    const int clamped = qBound(minimumMaxLines, maxLines, maximumMaxLines);
    const bool moved = clamped != m_maxLines || unlimited != m_unlimited;
    m_maxLines = clamped;
    m_unlimited = unlimited;
    m_lastError.clear();
    Q_EMIT changed();
    if (!moved)
        return;

    ++m_requests;
    // Both, always: unticking "unlimited" gives back the number somebody had, not the default.
    ServiceReply *reply = m_session->put(
        preferencesPath, {{QStringLiteral("key"), preferenceKey},
                          {QStringLiteral("value"), QJsonObject{{QStringLiteral("maxLines"), m_maxLines},
                                                                {QStringLiteral("unlimited"), m_unlimited}}}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        --m_requests;
        if (!reply->isError()) {
            m_loaded = true;
            Q_EMIT changed();
            return;
        }
        const QString message = reply->problem().message();
        m_lastError =
            message.isEmpty()
                ? QCoreApplication::translate("LogSettings",
                                              "This is in force on this computer, and could not be saved to your "
                                              "account.")
                : QCoreApplication::translate("LogSettings",
                                              "In force on this computer, but not saved to your account: %1")
                      .arg(message);
        Q_EMIT changed();
    });
}

void LogSettingsModel::setLocalTimes(bool localTimes)
{
    if (m_localTimes == localTimes)
        return;
    m_localTimes = localTimes;
    Q_EMIT localTimesChanged();
}

void LogSettingsModel::reset()
{
    m_maxLines = defaultMaxLines;
    m_unlimited = false;
    m_loaded = false;
    m_lastError.clear();
    Q_EMIT changed();
}

// ---- MachineConfigModel -----------------------------------------------------------------

MachineConfigModel::MachineConfigModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_overview(session->subscribe(QStringLiteral("access.changed")))
{
    connect(m_overview, &client::TopicSubscription::received, this, [this](const QJsonObject &overview) {
        const QString message = support::problemMessage(
            overview.value(QStringLiteral("store")).toObject().value(QStringLiteral("last_error")));
        if (message == m_lastError)
            return;
        m_lastError = message;
        Q_EMIT stateChanged();
    });
}

} // namespace simorg::app
