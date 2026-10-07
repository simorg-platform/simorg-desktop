// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/DesktopPeer.h"

#include "simorg/client/Discovery.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>

#include <algorithm>

namespace simorg::app {

namespace {

/** A line the service sends is at most this long. */
constexpr qsizetype maxLineBytes = qsizetype{1024} * 1024;

/** The `id` both script requests carry, as every plugin's and application's default script does. */
const QString scriptId = QStringLiteral("DEFAULT_CONSCIOUSNESS");

QJsonObject scriptRequest(const QString &action)
{
    QJsonObject request{{QStringLiteral("action"), action}, {QStringLiteral("id"), scriptId}};
    if (action == QLatin1String("BUILD"))
        request.insert(QStringLiteral("script"), QString::fromLatin1(DesktopPeer::script));
    return QJsonObject{{QStringLiteral("__script_req"), request}};
}

/** What a field's entry carries: the bare value, or `{ "value": … }` as PROTOCOL.md writes one. */
QString textOf(const QJsonValue &entry)
{
    const QJsonValue value = entry.isObject() && entry.toObject().contains(QStringLiteral("value"))
                                 ? entry.toObject().value(QStringLiteral("value"))
                                 : entry;
    if (value.isString())
        return value.toString();
    if (value.isObject())
        return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact));
    if (value.isArray())
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact));
    return value.toVariant().toString();
}

} // namespace

DesktopPeer::DesktopPeer(QString environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &DesktopPeer::connectNow);
    connect(&m_socket, &QLocalSocket::connected, this, [this] {
        setState(QStringLiteral("connecting"));
        // The plugin protocol's initialization, with this application's specifier beside it.
        send(QJsonObject{
            {QStringLiteral("__initialization_req"),
             QJsonObject{{QStringLiteral("agent_config"), QJsonObject{}},
                         {QStringLiteral("application"),
                          QJsonObject{{QStringLiteral("specifier"), m_specifier},
                                      {QStringLiteral("title"), QStringLiteral("Simorg Desktop")}}}}}});
    });
    connect(&m_socket, &QLocalSocket::readyRead, this, &DesktopPeer::readLines);
    connect(&m_socket, &QLocalSocket::disconnected, this, &DesktopPeer::lost);
    connect(&m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
        if (m_socket.state() == QLocalSocket::UnconnectedState)
            lost();
    });
}

DesktopPeer::~DesktopPeer()
{
    m_retry.stop();
    disconnect(&m_socket, nullptr, this, nullptr);
    m_socket.abort();
}

void DesktopPeer::setReconnectDelays(int firstMs, int longestMs)
{
    m_firstDelayMs = firstMs;
    m_longestDelayMs = longestMs;
    m_delayMs = firstMs;
}

void DesktopPeer::setSpecifier(const QString &specifier)
{
    if (specifier == m_specifier)
        return;
    m_specifier = specifier;
    m_retry.stop();
    m_socket.abort();
    m_pending.clear();
    m_delayMs = m_firstDelayMs;
    setState(QStringLiteral("disconnected"));
    if (!m_specifier.isEmpty())
        connectNow();
}

void DesktopPeer::connectNow()
{
    if (m_specifier.isEmpty() || m_socket.state() != QLocalSocket::UnconnectedState)
        return;
    const QString pipe = client::readPeerPipe(m_environment);
    if (pipe.isEmpty()) {
        lost();
        return;
    }
    m_pending.clear();
    m_socket.connectToServer(pipe);
}

void DesktopPeer::lost()
{
    if (m_state != QLatin1String("refused"))
        setState(QStringLiteral("disconnected"));
    if (m_specifier.isEmpty() || m_retry.isActive())
        return;
    // One second, then twice as long each time, up to thirty.
    m_retry.start(m_delayMs);
    m_delayMs = std::min(m_delayMs * 2, m_longestDelayMs);
}

void DesktopPeer::readLines()
{
    m_pending.append(m_socket.readAll());
    for (qsizetype newline = m_pending.indexOf('\n'); newline >= 0; newline = m_pending.indexOf('\n')) {
        const QByteArray line = m_pending.left(newline);
        m_pending.remove(0, newline + 1);
        const QJsonDocument document = QJsonDocument::fromJson(line);
        if (document.isObject())
            handle(document.object());
        if (m_socket.state() != QLocalSocket::ConnectedState)
            return;
    }
    if (m_pending.size() > maxLineBytes)
        m_socket.abort();
}

void DesktopPeer::handle(const QJsonObject &object)
{
    // The optional control keys.
    if (object.contains(QStringLiteral("ping"))) {
        send(QJsonObject{{QStringLiteral("pong"), object.value(QStringLiteral("ping"))}});
        return;
    }
    if (object.contains(QStringLiteral("handshake"))) {
        send(QJsonObject{{QStringLiteral("handshake.ack"), object.value(QStringLiteral("handshake"))}});
        return;
    }
    if (object.contains(QStringLiteral("shutdown"))) {
        m_socket.disconnectFromServer();
        return;
    }

    // Accepted with nothing in it, or refused and about to be closed.
    if (object.contains(QStringLiteral("__initialization_res"))) {
        if (object.value(QStringLiteral("__initialization_res")).toObject().contains(QStringLiteral("refused"))) {
            setState(QStringLiteral("refused"));
            return;
        }
        send(scriptRequest(QStringLiteral("BUILD")));
        setState(QStringLiteral("awaiting_consent"));
        return;
    }
    if (object.contains(QStringLiteral("__script_res"))) {
        const QJsonObject answer = object.value(QStringLiteral("__script_res")).toObject();
        const QString action = answer.value(QStringLiteral("action")).toString();
        if (!answer.value(QStringLiteral("success")).toBool()) {
            setState(QStringLiteral("refused"));
            return;
        }
        if (action == QLatin1String("BUILD")) {
            send(scriptRequest(QStringLiteral("START")));
        } else if (action == QLatin1String("START")) {
            m_delayMs = m_firstDelayMs;
            setState(QStringLiteral("attached"));
        }
        return;
    }

    // An agent's include speaking to this app, in the namespace kept for agents.
    const QJsonObject from = object.value(QStringLiteral("vibration.from_agent")).toObject();
    if (from.isEmpty())
        return;
    bool numeric = false;
    const qint64 agentId = from.value(QStringLiteral("agent_id")).toString().toLongLong(&numeric);
    const QJsonObject map = from.value(QStringLiteral("vibration_map")).toObject();
    if (!numeric || agentId <= 0)
        return;
    if (map.contains(QStringLiteral("userLog")))
        Q_EMIT userLog(agentId, textOf(map.value(QStringLiteral("userLog"))), QDateTime::currentDateTimeUtc());
}

void DesktopPeer::send(const QJsonObject &object)
{
    if (m_socket.state() != QLocalSocket::ConnectedState)
        return;
    QByteArray line = QJsonDocument(object).toJson(QJsonDocument::Compact);
    line.append('\n');
    m_socket.write(line);
}

void DesktopPeer::setState(const QString &state)
{
    if (state == m_state)
        return;
    m_state = state;
    Q_EMIT stateChanged();
}

} // namespace simorg::app
