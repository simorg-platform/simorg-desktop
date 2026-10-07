// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/ServiceLinkModel.h"

#include "simorg/client/ServiceSession.h"

namespace simorg::app {

using Unavailable = client::ServiceClient::Unavailable;

ServiceLinkModel::ServiceLinkModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
{
    connect(session, &client::ServiceSession::connected, this, [this] {
        m_connected = true;
        m_everConnected = true;
        m_detail.clear();
        Q_EMIT changed();
    });
    connect(session, &client::ServiceSession::disconnected, this, [this] {
        m_connected = false;
        // Not a failure yet: the session is already trying again, and the next attempt says why if it cannot.
        m_reason = Unavailable::NotReady;
        m_detail.clear();
        Q_EMIT changed();
    });
    connect(session, &client::ServiceSession::unavailable, this,
            [this](Unavailable reason, const QString &detail) {
                m_connected = false;
                m_reason = reason;
                m_detail = detail;
                Q_EMIT changed();
            });
}

QString ServiceLinkModel::title() const
{
    if (m_connected)
        return {};
    switch (m_reason) {
    case Unavailable::NotInstalled:
        return tr("The Simorg machine service is not set up");
    case Unavailable::StartFailed:
        return tr("Simorg would not start");
    case Unavailable::Untrusted:
        return tr("Simorg on this computer cannot be trusted");
    case Unavailable::Incompatible:
        return tr("Simorg on this computer is a different version");
    case Unavailable::NotRunning:
    case Unavailable::Stopped:
        return tr("Simorg is not running on this computer");
    case Unavailable::Updating:
        return tr("Finishing the update");
    case Unavailable::NotReady:
        break;
    }
    // The ordinary case, and the one a launch spends its first second in.
    return m_everConnected ? tr("Reconnecting to Simorg") : tr("Starting Simorg");
}

bool ServiceLinkModel::isSevere() const
{
    if (m_connected)
        return false;
    switch (m_reason) {
    case Unavailable::NotInstalled:
    case Unavailable::StartFailed:
    case Unavailable::Untrusted:
    case Unavailable::Incompatible:
        return true;
    case Unavailable::NotRunning:
    case Unavailable::Stopped:
    case Unavailable::NotReady:
    case Unavailable::Updating:
        return false;
    }
    return false;
}

void ServiceLinkModel::retryNow()
{
    /*
      Two different "again"s, and which one it is depends on what is wrong.

      With no connection it is the service that has to be reached, and asking is
      also the one thing allowed to start a service a client stopped. With a
      connection already up, the thing that can still be missing is a topic the
      service refused — while it was shutting down, most likely — so what this
      asks for is the subscriptions, which is the only state a client cannot talk
      itself out of.
    */
    if (m_session->isConnected()) {
        m_session->resubscribe();
        return;
    }
    m_session->resumeService();
}

} // namespace simorg::app
