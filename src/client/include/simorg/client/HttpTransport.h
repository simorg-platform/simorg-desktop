// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QHash>
#include <QJsonDocument>
#include <QList>
#include <QObject>
#include <QPair>
#include <QString>
#include <QUrlQuery>

namespace simorg::client {

/** Where an HTTP/1.1 server listens: a Unix socket or a named pipe, or a loopback port. */
struct HttpEndpoint
{
    enum class Kind { None, LocalSocket, Tcp };

    Kind kind = Kind::None;
    /** The socket path or pipe name, or `host:port`. */
    QString target;
    /**
     * Refuse a local server running as another user.
     *
     * The run directory is the user's own and nobody else can write to it, so
     * this is the check for when that stopped being true, not for the usual case.
     */
    bool requireSameUser = false;

    bool isUsable() const { return kind != Kind::None && !target.isEmpty(); }
};

/**
 * One exchange with a local HTTP server.
 *
 * Deletes itself once {@link finished} has been delivered, so a call site is a
 * connect and nothing else. Hold it in a QPointer to abort it.
 */
class HttpReply : public QObject
{
    Q_OBJECT

public:
    int httpStatus() const { return m_status; }
    /** The whole body. Empty for a successful streaming reply, which delivers as it goes. */
    QByteArray body() const { return m_body; }
    /** A header by its name in any case. */
    QByteArray header(const QByteArray &name) const { return m_headers.value(name.toLower()); }

    /** Set when the exchange itself failed: nothing to connect to, a broken or refused connection. */
    QString transportError() const { return m_error; }
    bool hasTransportError() const { return !m_error.isEmpty(); }
    /** The local server runs as another user, and nothing was sent to it. */
    bool peerRefused() const { return m_peerRefused; }

    /** Stops the exchange. {@link finished} still arrives, carrying a transport error. */
    void abort();

Q_SIGNALS:
    /** Exactly once. The reply is deleted after it. */
    void finished();
    /** Once the status line and headers are in, before any body. */
    void headersReceived();
    /** Body bytes of a successful streaming request, as they arrive. */
    void streamData(const QByteArray &data);
    /** Internal: {@link abort} asking the transport to close the socket. */
    void abortRequested(QPrivateSignal);

private:
    friend class HttpTransport;
    explicit HttpReply(QObject *parent);

    int m_status = 0;
    QByteArray m_body;
    QHash<QByteArray, QByteArray> m_headers;
    QString m_error;
    bool m_aborted = false;
    bool m_peerRefused = false;
};

/**
 * HTTP/1.1 over a local socket, a named pipe or a loopback port.
 *
 * Written by hand because QNetworkAccessManager cannot address a Unix socket or
 * a named pipe, which is where the Simorg machine service listens first. One
 * request per connection, closed at the end; `Content-Length` or chunked bodies;
 * and a streaming mode that hands body bytes over as they arrive, so a followed
 * log is live rather than a very slow download.
 *
 * Limits keep a misbehaving server from growing this process without bound: the
 * status line and headers may take 64 KiB, a buffered body 64 MiB and one chunk
 * 16 MiB.
 */
class HttpTransport : public QObject
{
    Q_OBJECT

public:
    struct Request
    {
        QByteArray method = QByteArrayLiteral("GET");
        /** Absolute, starting with `/`. */
        QString path;
        QUrlQuery query;
        QByteArray body;
        QByteArray contentType = QByteArrayLiteral("application/json");
        QByteArray accept = QByteArrayLiteral("application/json");
        /** Sent as they are, after the transport's own. */
        QList<QPair<QByteArray, QByteArray>> headers;
        /** Deliver the body through {@link HttpReply::streamData} instead of buffering it. */
        bool streaming = false;
        /** Milliseconds of total silence before giving up. 0 waits forever. */
        int timeoutMs = 20'000;
    };

    explicit HttpTransport(QObject *parent = nullptr);

    void setEndpoint(const HttpEndpoint &endpoint) { m_endpoint = endpoint; }
    HttpEndpoint endpoint() const { return m_endpoint; }

    /** Never null. A reply that cannot be sent finishes on the next turn of the event loop. */
    HttpReply *send(const Request &request);

private:
    HttpEndpoint m_endpoint;
};

} // namespace simorg::client
