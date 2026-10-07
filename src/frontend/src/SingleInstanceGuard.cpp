// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/SingleInstanceGuard.h"

#include "simorg/frontend/Logging.h"

#include <QLocalServer>
#include <QLocalSocket>

namespace simorg {
namespace {

constexpr int kConnectTimeoutMs = 400;
constexpr auto kActivateMessage = "activate";

} // namespace

SingleInstanceGuard::SingleInstanceGuard(const QString &key, QObject *parent)
    : QObject(parent)
    , m_key(key)
{
}

bool SingleInstanceGuard::tryBecomePrimary()
{
    QLocalSocket probe;
    probe.connectToServer(m_key);
    if (probe.waitForConnected(kConnectTimeoutMs)) {
        probe.write(kActivateMessage);
        probe.flush();
        probe.waitForBytesWritten(kConnectTimeoutMs);
        probe.disconnectFromServer();
        qCInfo(lcApp) << "another instance is running; asked it to show itself";
        return false;
    }

    m_server = new QLocalServer(this);
    // A crash leaves the socket file behind on Unix and every later start would
    // then fail to listen; nothing answered the probe above, so it is stale.
    QLocalServer::removeServer(m_key);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);

    if (!m_server->listen(m_key)) {
        // Not fatal: worst case the user ends up with two tray icons.
        qCWarning(lcApp) << "cannot listen on" << m_key << m_server->errorString();
        return true;
    }

    connect(m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *client = m_server->nextPendingConnection()) {
            connect(client, &QLocalSocket::disconnected, client, &QLocalSocket::deleteLater);
            Q_EMIT activationRequested();
        }
    });

    return true;
}

} // namespace simorg
