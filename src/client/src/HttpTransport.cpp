// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/client/HttpTransport.h"

#include "PeerCheck.h"

#include <QLocalSocket>
#include <QTcpSocket>
#include <QTimer>

#include <memory>

namespace simorg::client {
namespace {

constexpr int maxHeaderBytes = 64 * 1024;
constexpr qint64 maxBufferedBodyBytes = 64 * 1024 * 1024;
constexpr qint64 maxChunkBytes = 16 * 1024 * 1024;

/**
     * Reads one HTTP/1.1 response off a socket.
     *
     * One object with an explicit stage, so a streaming reply and a buffered one go
     * through the same parser; they differ only in what happens to a decoded body.
     */
class ResponseParser
{
public:
    enum class Stage { StatusLine, Headers, Body, Done };

    Stage stage() const { return m_stage; }
    int status() const { return m_status; }
    const QHash<QByteArray, QByteArray> &headers() const { return m_headers; }
    QString error() const { return m_error; }

    /** Consumes bytes, appending decoded body to `bodyOut`. False on a malformed response. */
    bool feed(const QByteArray &data, QByteArray *bodyOut)
    {
        m_buffer.append(data);

        while (true) {
            switch (m_stage) {
            case Stage::StatusLine:
            case Stage::Headers: {
                const int end = int(m_buffer.indexOf("\r\n"));
                if (end < 0) {
                    if (m_headerBytes + m_buffer.size() > maxHeaderBytes)
                        return fail(QStringLiteral("the response's headers were too long"));
                    return true;
                }
                m_headerBytes += end + 2;
                if (m_headerBytes > maxHeaderBytes)
                    return fail(QStringLiteral("the response's headers were too long"));

                const QByteArray line = m_buffer.left(end);
                m_buffer.remove(0, end + 2);
                if (m_stage == Stage::StatusLine) {
                    if (!readStatusLine(line))
                        return false;
                    m_stage = Stage::Headers;
                } else if (line.isEmpty()) {
                    if (!resolveFraming())
                        return false;
                    m_stage = m_framing == Framing::None ? Stage::Done : Stage::Body;
                } else {
                    const int colon = int(line.indexOf(':'));
                    if (colon <= 0)
                        return fail(QStringLiteral("the response carried a malformed header"));
                    m_headers.insert(line.left(colon).trimmed().toLower(), line.mid(colon + 1).trimmed());
                }
                break;
            }

            case Stage::Body:
                return readBody(bodyOut);

            case Stage::Done:
                return true;
            }
        }
    }

    /** The peer closed. False when the closing cut the response short. */
    bool atClose(QByteArray *bodyOut)
    {
        if (m_stage == Stage::Done)
            return true;
        if (m_stage == Stage::Body && m_framing == Framing::UntilClose) {
            bodyOut->append(m_buffer);
            m_buffer.clear();
            m_stage = Stage::Done;
            return true;
        }
        if (m_stage == Stage::StatusLine && m_buffer.isEmpty())
            return fail(QStringLiteral("the connection closed before anything was sent"));
        return fail(QStringLiteral("the connection closed in the middle of the response"));
    }

private:
    enum class Framing { Unknown, Length, Chunked, UntilClose, None };

    bool fail(const QString &message)
    {
        m_error = message;
        m_stage = Stage::Done;
        return false;
    }

    bool readStatusLine(const QByteArray &line)
    {
        const QList<QByteArray> parts = line.split(' ');
        bool parsed = false;
        const int status = parts.size() >= 2 ? parts.at(1).toInt(&parsed) : 0;
        if (!line.startsWith("HTTP/1.") || !parsed || status < 100 || status > 599)
            return fail(QStringLiteral("the other end did not answer with HTTP"));
        m_status = status;
        return true;
    }

    bool resolveFraming()
    {
        if (m_headers.value("transfer-encoding").toLower().contains("chunked")) {
            m_framing = Framing::Chunked;
            return true;
        }
        if (m_headers.contains("content-length")) {
            bool parsed = false;
            m_remaining = m_headers.value("content-length").toLongLong(&parsed);
            if (!parsed || m_remaining < 0)
                return fail(QStringLiteral("the response gave an invalid length"));
            m_framing = m_remaining > 0 ? Framing::Length : Framing::None;
            return true;
        }
        // 1xx, 204 and 304 carry nothing whatever the headers say; anything else runs to the close.
        m_framing = (m_status < 200 || m_status == 204 || m_status == 304) ? Framing::None : Framing::UntilClose;
        return true;
    }

    bool readBody(QByteArray *bodyOut)
    {
        switch (m_framing) {
        case Framing::Length: {
            const qint64 take = qMin<qint64>(m_remaining, m_buffer.size());
            bodyOut->append(m_buffer.left(int(take)));
            m_buffer.remove(0, int(take));
            m_remaining -= take;
            if (m_remaining == 0)
                m_stage = Stage::Done;
            return true;
        }
        case Framing::UntilClose:
            bodyOut->append(m_buffer);
            m_buffer.clear();
            return true;
        case Framing::Chunked:
            return readChunks(bodyOut);
        case Framing::None:
        case Framing::Unknown:
            m_stage = Stage::Done;
            return true;
        }
        return true;
    }

    bool readChunks(QByteArray *bodyOut)
    {
        while (true) {
            if (m_chunkRemaining > 0) {
                const qint64 take = qMin<qint64>(m_chunkRemaining, m_buffer.size());
                if (take == 0)
                    return true;
                bodyOut->append(m_buffer.left(int(take)));
                m_buffer.remove(0, int(take));
                m_chunkRemaining -= take;
                continue;
            }
            if (m_awaitingChunkEnd) {
                if (m_buffer.size() < 2)
                    return true;
                if (!m_buffer.startsWith("\r\n"))
                    return fail(QStringLiteral("the response body was framed incorrectly"));
                m_buffer.remove(0, 2);
                m_awaitingChunkEnd = false;
                continue;
            }

            const int end = int(m_buffer.indexOf("\r\n"));
            if (end < 0) {
                if (m_buffer.size() > 1024)
                    return fail(QStringLiteral("the response body was framed incorrectly"));
                return true;
            }
            QByteArray sizeLine = m_buffer.left(end);
            m_buffer.remove(0, end + 2);
            const int semicolon = int(sizeLine.indexOf(';')); // chunk extensions are ignorable
            if (semicolon >= 0)
                sizeLine = sizeLine.left(semicolon);

            bool parsed = false;
            const qint64 size = sizeLine.trimmed().toLongLong(&parsed, 16);
            if (!parsed || size < 0 || size > maxChunkBytes)
                return fail(QStringLiteral("the response body was framed incorrectly"));
            if (size == 0) {
                // Trailers may follow; the connection closes right after either way.
                m_stage = Stage::Done;
                return true;
            }
            m_chunkRemaining = size;
            m_awaitingChunkEnd = true;
        }
    }

    Stage m_stage = Stage::StatusLine;
    Framing m_framing = Framing::Unknown;
    int m_status = 0;
    int m_headerBytes = 0;
    QHash<QByteArray, QByteArray> m_headers;
    QByteArray m_buffer;
    QString m_error;
    qint64 m_remaining = 0;
    qint64 m_chunkRemaining = 0;
    bool m_awaitingChunkEnd = false;
};

} // namespace

HttpReply::HttpReply(QObject *parent)
    : QObject(parent)
{
}

void HttpReply::abort()
{
    if (m_aborted)
        return;
    m_aborted = true;
    // The transport owns the socket, so it is the one that can stop the exchange.
    Q_EMIT abortRequested(QPrivateSignal{});
}

HttpTransport::HttpTransport(QObject *parent)
    : QObject(parent)
{
}

HttpReply *HttpTransport::send(const Request &request)
{
    auto *reply = new HttpReply(this);

    if (!m_endpoint.isUsable()) {
        reply->m_error = QStringLiteral("there is nothing to connect to");
        QTimer::singleShot(0, reply, [reply] {
            Q_EMIT reply->finished();
            reply->deleteLater();
        });
        return reply;
    }

    const bool local = m_endpoint.kind == HttpEndpoint::Kind::LocalSocket;
    QIODevice *socket = local ? static_cast<QIODevice *>(new QLocalSocket(reply)) : new QTcpSocket(reply);

    auto parser = std::make_shared<ResponseParser>();
    auto done = std::make_shared<bool>(false);
    QTimer *timer = nullptr;
    if (request.timeoutMs > 0) {
        timer = new QTimer(reply);
        timer->setSingleShot(true);
        timer->setInterval(request.timeoutMs);
    }

    /*
      One exit, whatever went wrong, so `finished` is emitted exactly once and no
      socket outlives its reply. Deferred a turn: QLocalSocket reports a missing
      socket file from inside connectToServer(), and a reply that finished before
      send() returned it would never be heard by anybody.
    */
    const auto complete = [reply, socket, done, timer](const QString &error) {
        if (*done)
            return;
        *done = true;
        if (timer)
            timer->stop();
        reply->m_error = error;
        socket->close();
        QTimer::singleShot(0, reply, [reply] {
            Q_EMIT reply->finished();
            reply->deleteLater();
        });
    };

    QObject::connect(reply, &HttpReply::abortRequested, reply, [complete] { complete(QStringLiteral("cancelled")); });

    const bool streaming = request.streaming;
    const auto onBytes = [reply, parser, streaming, complete](const QByteArray &data) {
        if (data.isEmpty())
            return;
        const bool hadHeaders = !reply->m_headers.isEmpty() || reply->m_status != 0;
        QByteArray decoded;
        const bool ok = parser->feed(data, &decoded);

        if (!hadHeaders && parser->stage() != ResponseParser::Stage::StatusLine
            && parser->stage() != ResponseParser::Stage::Headers) {
            reply->m_status = parser->status();
            reply->m_headers = parser->headers();
            Q_EMIT reply->headersReceived();
        }

        if (!decoded.isEmpty()) {
            if (streaming && parser->status() >= 200 && parser->status() < 300) {
                Q_EMIT reply->streamData(decoded);
            } else {
                if (reply->m_body.size() + decoded.size() > maxBufferedBodyBytes) {
                    complete(QStringLiteral("the response was too large"));
                    return;
                }
                reply->m_body.append(decoded);
            }
        }

        if (!ok)
            complete(parser->error());
        else if (parser->stage() == ResponseParser::Stage::Done)
            complete(QString());
    };

    QObject::connect(socket, &QIODevice::readyRead, reply, [socket, onBytes, timer] {
        // The timeout is for silence, not for duration: a stream that keeps talking is never cut off.
        if (timer)
            timer->start();
        onBytes(socket->readAll());
    });

    if (timer) {
        const int seconds = request.timeoutMs / 1000;
        QObject::connect(timer, &QTimer::timeout, reply, [complete, seconds] {
            complete(QStringLiteral("no answer within %1 seconds").arg(seconds));
        });
    }

    const auto onDisconnected = [reply, parser, complete] {
        QByteArray tail;
        const bool ok = parser->atClose(&tail);
        if (!tail.isEmpty() && reply->m_body.size() + tail.size() <= maxBufferedBodyBytes)
            reply->m_body.append(tail);
        reply->m_status = parser->status();
        reply->m_headers = parser->headers();
        complete(ok ? QString() : parser->error());
    };

    QByteArray head = request.method + ' ' + request.path.toUtf8();
    if (!request.query.isEmpty())
        head += '?' + request.query.toString(QUrl::FullyEncoded).toUtf8();
    head += " HTTP/1.1\r\n";
    // A loopback listener checks Host against its own address.
    head += "Host: " + (local ? QByteArrayLiteral("localhost") : m_endpoint.target.toUtf8()) + "\r\n";
    head += "Accept: " + request.accept + "\r\n";
    head += "Connection: close\r\n";
    for (const auto &header : request.headers)
        head += header.first + ": " + header.second + "\r\n";
    if (!request.body.isEmpty()) {
        head += "Content-Type: " + request.contentType + "\r\n";
        head += "Content-Length: " + QByteArray::number(request.body.size()) + "\r\n";
    } else if (request.method != QByteArrayLiteral("GET") && request.method != QByteArrayLiteral("HEAD")) {
        head += "Content-Length: 0\r\n";
    }
    head += "\r\n";
    head += request.body;

    if (local) {
        auto *localSocket = static_cast<QLocalSocket *>(socket);
        const bool requireSameUser = m_endpoint.requireSameUser;
        QObject::connect(localSocket, &QLocalSocket::connected, reply,
                         [reply, localSocket, head, timer, requireSameUser, complete] {
                             if (requireSameUser) {
                                 const QString problem = detail::sameUserProblem(localSocket->socketDescriptor());
                                 if (!problem.isEmpty()) {
                                     reply->m_peerRefused = true;
                                     complete(problem);
                                     return;
                                 }
                             }
                             if (timer)
                                 timer->start();
                             localSocket->write(head);
                         });
        QObject::connect(localSocket, &QLocalSocket::disconnected, reply, onDisconnected);
        QObject::connect(localSocket, &QLocalSocket::errorOccurred, reply,
                         [localSocket, complete](QLocalSocket::LocalSocketError error) {
                             if (error == QLocalSocket::PeerClosedError)
                                 return; // a clean close arrives as `disconnected`
                             complete(localSocket->errorString());
                         });
        localSocket->connectToServer(m_endpoint.target);
    } else {
        auto *tcp = static_cast<QTcpSocket *>(socket);
        QObject::connect(tcp, &QTcpSocket::connected, reply, [tcp, head, timer] {
            if (timer)
                timer->start();
            tcp->write(head);
        });
        QObject::connect(tcp, &QTcpSocket::disconnected, reply, onDisconnected);
        QObject::connect(tcp, &QTcpSocket::errorOccurred, reply, [tcp, complete](QAbstractSocket::SocketError error) {
            if (error == QAbstractSocket::RemoteHostClosedError)
                return;
            complete(tcp->errorString());
        });
        const int colon = int(m_endpoint.target.lastIndexOf(QLatin1Char(':')));
        tcp->connectToHost(m_endpoint.target.left(colon), quint16(m_endpoint.target.mid(colon + 1).toUShort()));
    }

    if (timer)
        timer->start();
    return reply;
}

} // namespace simorg::client
