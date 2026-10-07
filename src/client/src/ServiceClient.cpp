// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/client/ServiceClient.h"

#include "ServiceStarter.h"

#include <QJsonArray>
#include <QJsonParseError>
#include <QTimer>

namespace simorg::client {
namespace {

constexpr int versionTimeoutMs = 5'000;
constexpr int pollIntervalMs = 150;
constexpr qsizetype maxStreamLineBytes = 16 * 1024 * 1024;

ServiceProblem problemFromBody(int status, const QByteArray &body)
{
    ServiceProblem problem;
    problem.status = status;
    const QJsonObject object = QJsonDocument::fromJson(body).object();
    problem.body = object;
    problem.code = object.value(QStringLiteral("code")).toString();
    problem.title = object.value(QStringLiteral("title")).toString();
    problem.detail = object.value(QStringLiteral("detail")).toString();
    /*
      A platform answer passed through the proxy is not a problem document:
      the platform says what is wrong in `message` — a sentence, or the list of them
      its validation found. That sentence is the one to show; without it a refusal
      such as "You already have a machine with this slug." reached the screen as the
      status line below.
    */
    if (problem.detail.isEmpty()) {
        const QJsonValue message = object.value(QStringLiteral("message"));
        const QJsonArray sentences = message.toArray();
        problem.detail = message.isArray() ? (sentences.isEmpty() ? QString() : sentences.first().toString())
                                           : message.toString();
    }
    if (problem.code.isEmpty())
        problem.code = QStringLiteral("HTTP_%1").arg(status);
    if (problem.title.isEmpty())
        problem.title = QStringLiteral("The Simorg machine service answered %1").arg(status);
    return problem;
}

ServiceProblem unreachable(const QString &detail)
{
    ServiceProblem problem;
    problem.code = QStringLiteral("SERVICE_UNREACHABLE");
    problem.title = QStringLiteral("The Simorg machine service could not be reached");
    problem.detail = detail;
    return problem;
}

} // namespace

QString ServiceProblem::message() const
{
    return detail.isEmpty() ? title : detail;
}

ServiceReply::ServiceReply(QObject *parent)
    : QObject(parent)
{
}

QByteArray ServiceReply::header(const QByteArray &name) const
{
    return m_headers.value(name.toLower());
}

void ServiceReply::abort()
{
    m_aborted = true;
    if (m_http)
        m_http->abort();
}

void ServiceReply::takeStreamData(const QByteArray &data)
{
    m_pending.append(data);
    qsizetype newline = 0;
    while ((newline = m_pending.indexOf('\n')) >= 0) {
        const QByteArray line = m_pending.left(newline).trimmed();
        m_pending.remove(0, newline + 1);
        if (line.isEmpty())
            continue;

        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (!document.isObject()) {
            m_problem = unreachable(QStringLiteral("the service sent a stream line that is not a JSON object"));
            abort();
            return;
        }
        const QJsonObject object = document.object();
        // An `end` carrying a problem is the stream's failure.
        if (object.value(QStringLiteral("type")).toString() == QLatin1String("end")
            && object.value(QStringLiteral("problem")).isObject()) {
            const QJsonObject problem = object.value(QStringLiteral("problem")).toObject();
            m_problem = problemFromBody(problem.value(QStringLiteral("status")).toInt(500),
                                        QJsonDocument(problem).toJson(QJsonDocument::Compact));
        }
        Q_EMIT item(object);
        if (m_aborted)
            return;
    }
    if (m_pending.size() > maxStreamLineBytes) {
        m_problem = unreachable(QStringLiteral("the service sent a stream line that is too long"));
        abort();
    }
}

void ServiceReply::flushStream()
{
    if (!m_pending.trimmed().isEmpty() && !m_aborted)
        takeStreamData(QByteArrayLiteral("\n"));
    m_pending.clear();
}

ServiceClient::ServiceClient(Options options, QObject *parent)
    : QObject(parent)
    , m_options(std::move(options))
    , m_transport(new HttpTransport(this))
{
}

void ServiceClient::open()
{
    if (m_open || m_opening)
        return;
    m_opening = true;

    m_discovery = Discovery::read(m_options.environment);
    switch (m_discovery.status) {
    case Discovery::Status::Found:
        usePipe();
        checkVersion(false);
        return;
    case Discovery::Status::Invalid:
        fail(Unavailable::Untrusted, m_discovery.problem);
        return;
    case Discovery::Status::Absent:
    case Discovery::Status::Stale:
        break;
    }

    // The service is updating itself, and starting one now would start the old binary.
    const UpdatingMarker updating = UpdatingMarker::read(m_options.environment);
    if (!m_options.startIfAbsent) {
        if (updating.present)
            fail(Unavailable::Updating, {});
        else
            fail(Unavailable::NotRunning, m_discovery.problem);
        return;
    }
    if (updating.present) {
        m_waitingForUpdate = true;
        startWaiting();
        return;
    }
    // Stopped on purpose stays stopped until somebody asks for it; stopped by an uninstall,
    // until somebody opens Simorg.
    if (!m_options.startWhenStopped || !m_options.startWhenUninstalled) {
        const StoppedMarker stopped = StoppedMarker::read(m_options.environment);
        const bool uninstalled = stopped.requestedBy == QLatin1String("uninstall");
        if (stopped.present && (!m_options.startWhenStopped || (uninstalled && !m_options.startWhenUninstalled))) {
            fail(Unavailable::Stopped, uninstalled
                                           ? tr("Simorg is being removed from this computer.")
                                           : tr("Simorg was stopped on this computer, and starts again when you open it."));
            return;
        }
    }
    const detail::StartOutcome outcome = detail::startService(m_options.environment);
    switch (outcome.kind) {
    case detail::StartOutcome::Kind::NotInstalled:
        fail(Unavailable::NotInstalled, outcome.detail);
        return;
    case detail::StartOutcome::Kind::Failed:
        fail(Unavailable::StartFailed, outcome.detail);
        return;
    case detail::StartOutcome::Kind::Asked:
        m_started = true;
        startWaiting();
        return;
    }
}

void ServiceClient::startWaiting()
{
    m_deadline = QDeadlineTimer(m_options.readyTimeoutMs);
    if (!m_poll) {
        m_poll = new QTimer(this);
        m_poll->setInterval(pollIntervalMs);
        connect(m_poll, &QTimer::timeout, this, &ServiceClient::pollDiscovery);
    }
    m_poll->start();
}

void ServiceClient::pollDiscovery()
{
    if (m_checking)
        return;
    m_discovery = Discovery::read(m_options.environment);
    if (m_discovery.status == Discovery::Status::Invalid) {
        fail(Unavailable::Untrusted, m_discovery.problem);
        return;
    }
    if (m_discovery.status == Discovery::Status::Found) {
        usePipe();
        checkVersion(true);
        return;
    }
    if (m_deadline.hasExpired()) {
        if (m_waitingForUpdate && UpdatingMarker::read(m_options.environment).present) {
            fail(Unavailable::Updating, {});
            return;
        }
        fail(Unavailable::NotReady,
             QStringLiteral("it did not start within %1 seconds").arg(m_options.readyTimeoutMs / 1000));
    }
}

void ServiceClient::checkVersion(bool waiting)
{
    m_checking = true;
    HttpTransport::Request request;
    request.path = QStringLiteral("/v1/version");
    request.timeoutMs = versionTimeoutMs;
    HttpReply *http = m_transport->send(prepare(request));

    connect(http, &HttpReply::finished, this, [this, http, waiting] {
        if (!m_opening)
            return;
        if (http->peerRefused()) {
            fail(Unavailable::Untrusted, http->transportError());
            return;
        }
        if (http->hasTransportError()) {
            // The pipe is preferred; the loopback listener is the way round a pipe that will not connect.
            if (!m_viaHttp && m_discovery.httpPort != 0) {
                useHttp();
                checkVersion(waiting);
                return;
            }
            notAnswered(waiting, Unavailable::NotReady,
                        QStringLiteral("it did not answer: %1").arg(http->transportError()));
            return;
        }
        if (http->httpStatus() != 200) {
            notAnswered(waiting, Unavailable::NotReady, problemFromBody(http->httpStatus(), http->body()).message());
            return;
        }

        m_version = QJsonDocument::fromJson(http->body()).object();
        const QString apiVersion = m_version.value(QStringLiteral("api_version")).toString();
        bool parsed = false;
        const int major = apiVersion.section(QLatin1Char('.'), 0, 0).toInt(&parsed);
        if (!parsed || major != apiMajorVersion) {
            fail(Unavailable::Incompatible,
                 QStringLiteral("the Simorg machine service speaks API %1, and this program speaks %2.x")
                     .arg(apiVersion.isEmpty() ? QStringLiteral("of no known version") : apiVersion)
                     .arg(apiMajorVersion));
            return;
        }

        m_checking = false;
        m_opening = false;
        m_open = true;
        if (m_poll)
            m_poll->stop();
        Q_EMIT opened();
    });
}

void ServiceClient::notAnswered(bool waiting, Unavailable reason, const QString &detail)
{
    if (waiting && !m_deadline.hasExpired()) {
        // Started and not answering yet: the next poll tries again.
        m_checking = false;
        return;
    }
    fail(reason, detail);
}

/**
 * What a reason says when whatever produced it had nothing to add.
 *
 * Half of the ways this fails are silent ones — a launch agent that is not
 * installed exits with no output, a discovery file that is simply absent has no
 * problem to report — and the sentence is what every caller shows: the tray
 * notification, the launch window, the CLI. "Simorg is not available:" with
 * nothing after the colon is the kind of nothing this application is not allowed
 * to say.
 */
QString ServiceClient::sentenceFor(Unavailable reason)
{
    switch (reason) {
    case Unavailable::NotInstalled:
        return tr("The Simorg machine service is not set up on this computer yet.");
    case Unavailable::StartFailed:
        return tr("The Simorg machine service is installed but would not start.");
    case Unavailable::NotRunning:
        return tr("The Simorg machine service is not running on this computer.");
    case Unavailable::NotReady:
        return tr("The Simorg machine service is not answering yet.");
    case Unavailable::Untrusted:
        return tr("Something is answering for Simorg on this computer that Simorg does not trust.");
    case Unavailable::Incompatible:
        return tr("The Simorg machine service on this computer is a version this app cannot speak to.");
    case Unavailable::Stopped:
        return tr("Simorg was stopped on this computer, and starts again when you open it.");
    case Unavailable::Updating:
        return tr("The Simorg machine service is updating, and starts again by itself in a moment.");
    }
    return tr("The Simorg machine service is not available.");
}

void ServiceClient::fail(Unavailable reason, const QString &detail)
{
    if (m_poll)
        m_poll->stop();
    m_checking = false;
    m_opening = false;
    Q_EMIT unavailable(reason, detail.trimmed().isEmpty() ? sentenceFor(reason) : detail);
}

void ServiceClient::usePipe()
{
    HttpEndpoint endpoint;
    endpoint.kind = HttpEndpoint::Kind::LocalSocket;
    endpoint.target = m_discovery.pipe;
    endpoint.requireSameUser = true;
    m_transport->setEndpoint(endpoint);
    m_viaHttp = false;
}

void ServiceClient::useHttp()
{
    HttpEndpoint endpoint;
    endpoint.kind = HttpEndpoint::Kind::Tcp;
    endpoint.target = QStringLiteral("127.0.0.1:%1").arg(m_discovery.httpPort);
    m_transport->setEndpoint(endpoint);
    m_viaHttp = true;
}

HttpTransport::Request ServiceClient::prepare(HttpTransport::Request request) const
{
    if (!m_options.clientName.isEmpty())
        request.headers.append({QByteArrayLiteral("Simorg-Client"), m_options.clientName});
    if (m_viaHttp)
        request.headers.append(
            {QByteArrayLiteral("Authorization"), QByteArrayLiteral("Bearer ") + m_discovery.token});
    return request;
}

ServiceReply *ServiceClient::get(const QString &path, const QUrlQuery &query)
{
    return request(QByteArrayLiteral("GET"), path, {}, query);
}

ServiceReply *ServiceClient::post(const QString &path, const QJsonObject &body)
{
    return request(QByteArrayLiteral("POST"), path, body.isEmpty() ? QJsonDocument() : QJsonDocument(body));
}

ServiceReply *ServiceClient::put(const QString &path, const QJsonObject &body)
{
    return request(QByteArrayLiteral("PUT"), path, QJsonDocument(body));
}

ServiceReply *ServiceClient::patch(const QString &path, const QJsonObject &mergePatch)
{
    return request(QByteArrayLiteral("PATCH"), path, QJsonDocument(mergePatch));
}

ServiceReply *ServiceClient::remove(const QString &path)
{
    return request(QByteArrayLiteral("DELETE"), path);
}

ServiceReply *ServiceClient::subscribe(const QString &topic, const QUrlQuery &params)
{
    return request(QByteArrayLiteral("GET"), QStringLiteral("/v1/events/") + topic, {}, params, true, 0);
}

ServiceReply *ServiceClient::request(const QByteArray &method, const QString &path, const QJsonDocument &body,
                                     const QUrlQuery &query, bool streaming, int timeoutMs)
{
    auto *reply = new ServiceReply(this);
    if (!m_open) {
        reply->m_problem = unreachable(QStringLiteral("the connection to the service is not open"));
        QTimer::singleShot(0, reply, [reply] {
            Q_EMIT reply->finished();
            reply->deleteLater();
        });
        return reply;
    }

    HttpTransport::Request http;
    http.method = method;
    http.path = path;
    http.query = query;
    http.streaming = streaming;
    http.timeoutMs = streaming ? 0 : timeoutMs;
    http.accept = streaming ? QByteArrayLiteral("application/jsonl, application/problem+json")
                            : QByteArrayLiteral("application/json, application/problem+json");
    if (!body.isNull()) {
        http.body = body.toJson(QJsonDocument::Compact);
        /*
          The service's own PATCH routes take a JSON merge patch (RFC 7396). A call
          through its proxy is the platform's, which reads only
          `application/json`: sent as a merge patch, its body was dropped unread
          and the platform answered 200 having changed nothing — a machine renamed
          from Settings kept its old name.
        */
        const bool proxied = path.startsWith(QLatin1String("/v1/proxy/"));
        http.contentType = method == QByteArrayLiteral("PATCH") && !proxied
                               ? QByteArrayLiteral("application/merge-patch+json")
                               : QByteArrayLiteral("application/json");
    }
    dispatch(reply, http, false);
    return reply;
}

void ServiceClient::dispatch(ServiceReply *reply, const HttpTransport::Request &request, bool retried)
{
    HttpReply *http = m_transport->send(prepare(request));
    reply->m_http = http;
    if (request.streaming)
        connect(http, &HttpReply::streamData, reply, &ServiceReply::takeStreamData);

    connect(http, &HttpReply::finished, reply, [this, reply, http, request, retried] {
        reply->m_status = http->httpStatus();
        reply->m_body = http->body();
        reply->m_headers.clear();
        for (const QByteArray &name : {QByteArrayLiteral("simorg-upstream"), QByteArrayLiteral("simorg-request-id"),
                                       QByteArrayLiteral("simorg-api-version"), QByteArrayLiteral("location"),
                                       QByteArrayLiteral("content-type")}) {
            const QByteArray value = http->header(name);
            if (!value.isEmpty())
                reply->m_headers.insert(name, value);
        }

        if (http->hasTransportError()) {
            if (reply->m_problem.code.isEmpty()) {
                reply->m_problem =
                    reply->m_aborted
                        ? ServiceProblem{0, QStringLiteral("CANCELLED"), QStringLiteral("Cancelled"), {}, {}}
                        : unreachable(http->transportError());
            }
        } else if (reply->m_status == 401 && m_viaHttp && !retried && http->header("simorg-upstream").isEmpty()) {
            // A rotated local token: read the file again once and retry.
            const Discovery again = Discovery::read(m_options.environment);
            if (again.status == Discovery::Status::Found && again.token != m_discovery.token) {
                m_discovery = again;
                dispatch(reply, request, true);
                return;
            }
            reply->m_problem = problemFromBody(401, reply->m_body);
        } else if (reply->m_status >= 400) {
            reply->m_problem = problemFromBody(reply->m_status, reply->m_body);
        }

        if (request.streaming)
            reply->flushStream();
        Q_EMIT reply->finished();
        reply->deleteLater();
    });
}

} // namespace simorg::client
