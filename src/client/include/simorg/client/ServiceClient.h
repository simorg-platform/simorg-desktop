// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/client/Discovery.h"
#include "simorg/client/HttpTransport.h"

#include <QByteArray>
#include <QDeadlineTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QUrlQuery>

class QTimer;

namespace simorg::client {

/**
 * What went wrong with a request: the service's RFC 9457 problem, or a failure
 * to reach it at all.
 */
struct ServiceProblem
{
    /** The HTTP status; 0 when the service was not reached. */
    int status = 0;
    /** The stable code to switch on. `SERVICE_UNREACHABLE` when the service was not reached. */
    QString code;
    QString title;
    QString detail;
    /** The whole object, for the members an area adds to its codes. */
    QJsonObject body;

    /** The detail, or else the title: the sentence to show a person. */
    QString message() const;
};

/**
 * One request to the service. Deletes itself after {@link finished}.
 *
 * A stream delivers each JSON Lines item through
 * {@link item} as it arrives; everything else is read once {@link finished} has
 * arrived.
 */
class ServiceReply : public QObject
{
    Q_OBJECT

public:
    int status() const { return m_status; }
    QByteArray body() const { return m_body; }
    QJsonDocument json() const { return QJsonDocument::fromJson(m_body); }
    QJsonObject object() const { return json().object(); }
    QByteArray header(const QByteArray &name) const;

    /** The service was not reached, answered an error status, or broke a stream. */
    bool isError() const { return m_problem.status != 0 || !m_problem.code.isEmpty(); }
    ServiceProblem problem() const { return m_problem; }

    /** Stops the request; for a stream, closing the connection is what cancels it. */
    void abort();

Q_SIGNALS:
    /** One item of a stream, in order. */
    void item(const QJsonObject &item);
    /** Exactly once. */
    void finished();

private:
    friend class ServiceClient;
    explicit ServiceReply(QObject *parent);

    void takeStreamData(const QByteArray &data);
    void flushStream();

    int m_status = 0;
    QByteArray m_body;
    QHash<QByteArray, QByteArray> m_headers;
    ServiceProblem m_problem;
    QByteArray m_pending;
    QPointer<HttpReply> m_http;
    bool m_aborted = false;
};

/**
 * The Simorg machine service, found and reached.
 *
 * {@link open} reads the discovery file, starts the service when there is none
 * and it may, connects over the pipe and falls back to the loopback HTTP
 * listener with the local token, and checks the API's major version. Requests
 * sent before {@link opened} fail at once.
 */
class ServiceClient : public QObject
{
    Q_OBJECT

public:
    /** The API major version this client speaks. */
    static constexpr int apiMajorVersion = 1;

    enum class Unavailable {
        /** No service is running and starting one was not allowed. */
        NotRunning,
        /** No service is running and none is installed to start. */
        NotInstalled,
        /** An installed service could not be started. */
        StartFailed,
        /** A service was started, or is running, and did not answer in time. */
        NotReady,
        /** The discovery file or the socket's owner cannot be trusted. */
        Untrusted,
        /** The service speaks an API major version this client does not. */
        Incompatible,
        /** A client asked the service to stop, and nobody has asked for it again. */
        Stopped,
        /** The service is replacing itself with a newer version and starts again by itself. */
        Updating,
    };
    Q_ENUM(Unavailable)

    struct Options
    {
        /** `dev` or `prod`. */
        QString environment = QStringLiteral("prod");
        /** Sent as `Simorg-Client`, e.g. `simorg/0.1.0 (macos; arm64)`. */
        QByteArray clientName;
        /** Start the service when none is running. */
        bool startIfAbsent = true;
        /**
         * Start it also when a client asked it to stop. True for
         * what the person asked for, such as a command; false for a client
         * reconnecting on its own, which then reports `Stopped`.
         */
        bool startWhenStopped = true;
        /**
         * Start it also when an uninstall stopped it (its stopped marker names
         * `uninstall`). Only somebody opening Simorg asks for that: a command, or
         * the app's first attempt. A client asking again on its own — for a
         * window, after a lost connection — must not bring back what is being
         * removed, or a removed service would keep running.
         */
        bool startWhenUninstalled = true;
        /** How long a started or starting service has to answer. */
        int readyTimeoutMs = 30'000;
    };

    explicit ServiceClient(Options options, QObject *parent = nullptr);

    void open();
    bool isOpen() const { return m_open; }
    /** Whether {@link open} started the service. */
    bool startedService() const { return m_started; }
    /** The discovery file as last read. */
    const Discovery &discovery() const { return m_discovery; }
    /** The service's `GET /v1/version`, as read while opening. */
    QJsonObject version() const { return m_version; }

    ServiceReply *get(const QString &path, const QUrlQuery &query = {});
    ServiceReply *post(const QString &path, const QJsonObject &body = {});
    ServiceReply *put(const QString &path, const QJsonObject &body);
    ServiceReply *patch(const QString &path, const QJsonObject &mergePatch);
    ServiceReply *remove(const QString &path);

    /**
     * Any request. `body` is sent as JSON unless it is null. A streaming request
     * waits as long as the stream lasts; others give up after `timeoutMs` of silence.
     */
    ServiceReply *request(const QByteArray &method, const QString &path, const QJsonDocument &body = {},
                          const QUrlQuery &query = {}, bool streaming = false, int timeoutMs = 60'000);

    /** A topic as a stream, `GET /v1/events/{topic}` with its parameters in the query. */
    ServiceReply *subscribe(const QString &topic, const QUrlQuery &params = {});

Q_SIGNALS:
    void opened();
    void unavailable(simorg::client::ServiceClient::Unavailable reason, const QString &detail);

private:
    /** The sentence a reason carries on its own; see the definition. */
    static QString sentenceFor(Unavailable reason);
    void startWaiting();
    void pollDiscovery();
    void checkVersion(bool waiting);
    void notAnswered(bool waiting, Unavailable reason, const QString &detail);
    void fail(Unavailable reason, const QString &detail);
    void dispatch(ServiceReply *reply, const HttpTransport::Request &request, bool retried);
    HttpTransport::Request prepare(HttpTransport::Request request) const;
    void usePipe();
    void useHttp();

    Options m_options;
    HttpTransport *m_transport;
    Discovery m_discovery;
    QJsonObject m_version;
    QTimer *m_poll = nullptr;
    QDeadlineTimer m_deadline;
    bool m_opening = false;
    bool m_checking = false;
    bool m_open = false;
    bool m_started = false;
    /** Waiting for a service that is updating itself to come back, rather than for one this started. */
    bool m_waitingForUpdate = false;
    bool m_viaHttp = false;
};

} // namespace simorg::client
