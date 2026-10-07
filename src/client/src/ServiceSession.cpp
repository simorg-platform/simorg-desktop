// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/client/ServiceSession.h"

#include "ServiceStarter.h"

#include <QTimer>

#include <utility>

namespace simorg::client {

TopicSubscription::TopicSubscription(QString topic, QUrlQuery params, QObject *parent)
    : QObject(parent)
    , m_topic(std::move(topic))
    , m_params(std::move(params))
{
}

ServiceSession::ServiceSession(Options options, QObject *parent)
    : QObject(parent)
    , m_options(std::move(options))
    , m_idle(new ServiceClient({m_options.environment, m_options.clientName, false, 0}, this))
    , m_retry(new QTimer(this))
    , m_delayMs(m_options.reconnectMinMs)
{
    m_retry->setSingleShot(true);
    connect(m_retry, &QTimer::timeout, this, &ServiceSession::attempt);
}

void ServiceSession::start()
{
    if (m_started)
        return;
    m_started = true;
    attempt();
}

QJsonObject ServiceSession::version() const
{
    return m_client && m_connected ? m_client->version() : QJsonObject();
}

ServiceClient *ServiceSession::current() const
{
    return m_client && m_connected ? m_client.data() : m_idle;
}

void ServiceSession::resumeService()
{
    m_mayStartStopped = true;
    if (!m_started || m_connected)
        return;
    m_retry->stop();
    m_delayMs = m_options.reconnectMinMs;
    attempt();
}

bool ServiceSession::stopUnreachedService()
{
    if (m_connected)
        return false;
    // The attempt under way goes with its poll, and none follows it: a retry would start the service again.
    m_retry->stop();
    if (m_client)
        m_client->deleteLater();
    m_client = nullptr;
    if (!m_options.startIfAbsent || UpdatingMarker::read(m_options.environment).present)
        return false;
    return detail::stopService(m_options.environment);
}

void ServiceSession::attempt()
{
    if (m_client)
        m_client->deleteLater();

    ServiceClient::Options options;
    options.environment = m_options.environment;
    options.clientName = m_options.clientName;
    options.startIfAbsent = m_options.startIfAbsent;
    options.startWhenStopped = m_mayStartStopped;
    // The first attempt is the app being opened; after that, a service an uninstall stopped stays so.
    options.startWhenUninstalled = !std::exchange(m_attempted, true);
    options.readyTimeoutMs = m_options.readyTimeoutMs;
    auto *client = new ServiceClient(options, this);
    m_client = client;

    connect(client, &ServiceClient::opened, this, [this, client] {
        if (client != m_client)
            return;
        m_connected = true;
        m_delayMs = m_options.reconnectMinMs;
        // From here a service that goes away is not started again on the app's own account.
        m_mayStartStopped = false;
        for (TopicSubscription *subscription : std::as_const(m_subscriptions)) {
            /*
              A refusal belonged to the connection it happened on, and this is a
              different one.

              The service refuses a subscription with a 4xx for a topic it does
              not know — and also, in passing, while it is shutting down or
              holding after a stop. The first is permanent for as long as that
              service is running; the second lasts seconds. Keeping the refusal
              across connections made the second one permanent too: a client that
              happened to subscribe in that window never asked again, and a model
              waiting on that topic — the session, most of all — waited for the
              life of the process with nothing to show for it.
            */
            subscription->m_refused = false;
            open(subscription);
        }
        Q_EMIT connected();
    });
    connect(client, &ServiceClient::unavailable, this,
            [this, client](ServiceClient::Unavailable reason, const QString &detail) {
                if (client != m_client)
                    return;
                Q_EMIT unavailable(reason, detail);
                retryLater();
            });
    client->open();
}

void ServiceSession::retryLater()
{
    m_retry->start(m_delayMs);
    m_delayMs = qMin(m_delayMs * 2, m_options.reconnectMaxMs);
}

TopicSubscription *ServiceSession::subscribe(const QString &topic, const QUrlQuery &params)
{
    const QString key = params.toString(QUrl::FullyEncoded);
    for (TopicSubscription *existing : std::as_const(m_subscriptions)) {
        if (existing->topic() == topic && existing->params().toString(QUrl::FullyEncoded) == key) {
            ++existing->m_holders;
            return existing;
        }
    }
    auto *subscription = new TopicSubscription(topic, params, this);
    subscription->m_holders = 1;
    m_subscriptions.append(subscription);
    if (m_connected)
        open(subscription);
    return subscription;
}

void ServiceSession::release(TopicSubscription *subscription)
{
    if (!subscription || !m_subscriptions.contains(subscription) || --subscription->m_holders > 0)
        return;
    m_subscriptions.removeOne(subscription);
    // Detached first, so the stream's end is not read as the service going away, and never opened again.
    subscription->m_refused = true;
    if (const QPointer<ServiceReply> stream = std::exchange(subscription->m_stream, nullptr))
        stream->abort();
    subscription->deleteLater();
}

void ServiceSession::resubscribe()
{
    if (!m_connected)
        return;
    for (TopicSubscription *subscription : std::as_const(m_subscriptions)) {
        subscription->m_refused = false;
        open(subscription);
    }
}

void ServiceSession::open(TopicSubscription *subscription)
{
    if (subscription->m_refused || !m_client)
        return;
    if (subscription->m_stream)
        subscription->m_stream->abort();

    ServiceReply *stream = m_client->subscribe(subscription->topic(), subscription->params());
    subscription->m_stream = stream;
    const QPointer<ServiceClient> client = m_client;

    connect(stream, &ServiceReply::item, subscription, [subscription](const QJsonObject &item) {
        if (item.value(QStringLiteral("type")).toString() != QLatin1String("event"))
            return;
        subscription->m_value = item.value(QStringLiteral("data")).toObject();
        subscription->m_hasValue = true;
        Q_EMIT subscription->received(subscription->m_value);
    });
    // With the subscription as the context, a released one's stream ending reaches nothing.
    connect(stream, &ServiceReply::finished, subscription, [this, subscription, stream, client] {
        if (subscription->m_stream != stream || client != m_client || !m_connected)
            return;
        const ServiceProblem problem = stream->problem();
        // Refused by the service itself: an unknown topic or parameters it rejects will not start working.
        if (problem.status >= 400 && problem.status < 500) {
            // Not asked for again on this connection; the next one starts over — see `opened` above.
            subscription->m_refused = true;
            Q_EMIT subscription->refused(problem);
            Q_EMIT subscriptionRefused(subscription->topic(), problem);
            return;
        }
        checkAfterLoss(subscription);
    });
}

void ServiceSession::checkAfterLoss(TopicSubscription *subscription)
{
    // A stream that ends is usually the service going away; asking it settles which.
    ServiceReply *probe = m_client->get(QStringLiteral("/v1/version"));
    const QPointer<ServiceClient> client = m_client;
    const QPointer<TopicSubscription> held = subscription;
    connect(probe, &ServiceReply::finished, this, [this, probe, held, client] {
        if (client != m_client || !m_connected)
            return;
        if (probe->isError()) {
            lose();
            return;
        }
        if (!held)
            return; // released while the service was asked
        QTimer::singleShot(m_options.reconnectMinMs, held, [this, held, client] {
            if (held && client == m_client && m_connected)
                open(held);
        });
    });
}

void ServiceSession::lose()
{
    if (!m_connected)
        return;
    m_connected = false;
    for (TopicSubscription *subscription : std::as_const(m_subscriptions)) {
        if (subscription->m_stream)
            subscription->m_stream->abort();
    }
    Q_EMIT disconnected();
    retryLater();
}

ServiceReply *ServiceSession::request(const QByteArray &method, const QString &path, const QJsonDocument &body,
                                      const QUrlQuery &query, bool streaming, int timeoutMs)
{
    return current()->request(method, path, body, query, streaming, timeoutMs);
}

ServiceReply *ServiceSession::get(const QString &path, const QUrlQuery &query)
{
    return current()->get(path, query);
}

ServiceReply *ServiceSession::post(const QString &path, const QJsonObject &body)
{
    return current()->post(path, body);
}

ServiceReply *ServiceSession::put(const QString &path, const QJsonObject &body)
{
    return current()->put(path, body);
}

ServiceReply *ServiceSession::patch(const QString &path, const QJsonObject &mergePatch)
{
    return current()->patch(path, mergePatch);
}

ServiceReply *ServiceSession::remove(const QString &path)
{
    return current()->remove(path);
}

} // namespace simorg::client
