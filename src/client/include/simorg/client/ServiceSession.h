// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/client/ServiceClient.h"

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QUrlQuery>

class QTimer;

namespace simorg::client {

class ServiceSession;

/**
 * One topic, subscribed for as long as the session lives.
 *
 * For a `state` topic, {@link value} is the current value: the service sends it on
 * every subscription, so it is right again after the service comes back. For a
 * `signal` or `stream` topic it is the last item received.
 */
class TopicSubscription : public QObject
{
    Q_OBJECT

public:
    QString topic() const { return m_topic; }
    QUrlQuery params() const { return m_params; }
    /** The latest `data`; empty before the first event. */
    QJsonObject value() const { return m_value; }
    bool hasValue() const { return m_hasValue; }

Q_SIGNALS:
    /** Each event's `data`, in order. */
    void received(const QJsonObject &data);
    /**
     * The service refused the subscription itself — an unknown topic, parameters
     * it rejects, or a service that is shutting down. Not asked for again on this
     * connection; the next connection asks from scratch, and {@link
     * ServiceSession::resubscribe} asks now.
     */
    void refused(const simorg::client::ServiceProblem &problem);

private:
    friend class ServiceSession;
    TopicSubscription(QString topic, QUrlQuery params, QObject *parent);

    QString m_topic;
    QUrlQuery m_params;
    QJsonObject m_value;
    bool m_hasValue = false;
    bool m_refused = false;
    QPointer<ServiceReply> m_stream;
    /** How many `subscribe` calls hold it; `release` ends it at zero. */
    int m_holders = 0;
};

/**
 * The Simorg machine service for the life of a front end that stays open.
 *
 * It connects, keeps its subscriptions open, and when the service goes away —
 * stopped, crashed, upgraded — connects again and subscribes again, starting the
 * service when it may. On Windows, where nothing else starts the service, that is
 * what a client has to do while it runs; on macOS
 * and Linux it asks launchd or systemd, which usually have it back already.
 * Attempts back off from half a second to fifteen seconds.
 */
class ServiceSession : public QObject
{
    Q_OBJECT

public:
    struct Options
    {
        QString environment = QStringLiteral("prod");
        QByteArray clientName;
        bool startIfAbsent = true;
        int reconnectMinMs = 500;
        int reconnectMaxMs = 15'000;
        int readyTimeoutMs = 30'000;
    };

    explicit ServiceSession(Options options, QObject *parent = nullptr);

    /**
     * Connects, and keeps connecting. The first attempt may start the service even
     * when a client asked it to stop, because opening the app is the person asking
     * for it; attempts after a connection was lost do not. Of a
     * service an uninstall stopped, only that first attempt may.
     */
    void start();
    /**
     * The person asked for something that needs the service: the next attempt may
     * start one a client stopped, and it is made now when there is no connection.
     */
    void resumeService();
    bool isConnected() const { return m_connected; }
    /**
     * Stops trying, and asks the system's service manager to stop the service
     * this session never reached: Quit Simorg with nobody to ask over the API.
     *
     * A service that was asked to start and never answered can stay that way —
     * starting, failing and being restarted — until the computer restarts, and a
     * person quitting from the launch window has asked for Simorg to stop, the
     * service with it. Nothing is asked while the service is updating itself:
     * stopping it then would stop the installer it started. True when the manager was asked; see `detail::stopService`.
     */
    bool stopUnreachedService();
    /** Which environment's service this session speaks to: `dev` or `prod`. */
    QString environment() const { return m_options.environment; }
    /** The version the connected service reported, or empty. */
    QJsonObject version() const;

    /** The same topic with the same parameters returns the same object. */
    TopicSubscription *subscribe(const QString &topic, const QUrlQuery &params = {});
    /**
     * Asks for every subscription again on the current connection, refusals
     * included; nothing when there is no connection.
     *
     * The way out of the one state a client cannot talk itself out of: a
     * subscription the service refused while it was shutting down or holding is
     * not retried on that connection, so a topic can be missing while everything
     * else on the same socket works. This is what a person pressing *Try again*
     * on a window that is still waiting for one actually does.
     */
    void resubscribe();

    /**
     * Gives back one `subscribe` of it. When nobody holds it any more its stream is
     * closed, which lets the service stop work that exists only to feed the topic,
     * and the object is deleted.
     */
    void release(TopicSubscription *subscription);

    /** A request on the current connection; without one it fails at once with `SERVICE_UNREACHABLE`. */
    ServiceReply *request(const QByteArray &method, const QString &path, const QJsonDocument &body = {},
                          const QUrlQuery &query = {}, bool streaming = false, int timeoutMs = 60'000);
    ServiceReply *get(const QString &path, const QUrlQuery &query = {});
    ServiceReply *post(const QString &path, const QJsonObject &body = {});
    ServiceReply *put(const QString &path, const QJsonObject &body);
    ServiceReply *patch(const QString &path, const QJsonObject &mergePatch);
    ServiceReply *remove(const QString &path);

Q_SIGNALS:
    void connected();
    void disconnected();
    /** An attempt that did not connect, and why; another follows. */
    void unavailable(simorg::client::ServiceClient::Unavailable reason, const QString &detail);
    /**
     * The service refused one topic, which is a hole in what this client can see
     * rather than a lost connection: everything else on the socket goes on
     * working, and whatever was waiting on that topic waits until the next
     * connection or until somebody asks again.
     */
    void subscriptionRefused(const QString &topic, const simorg::client::ServiceProblem &problem);

private:
    void attempt();
    void retryLater();
    void open(TopicSubscription *subscription);
    /** A stream ended on its own: find out whether the service is still there. */
    void checkAfterLoss(TopicSubscription *subscription);
    void lose();
    ServiceClient *current() const;

    Options m_options;
    QPointer<ServiceClient> m_client;
    /** Never opened: what answers requests made while there is no connection. */
    ServiceClient *m_idle;
    QTimer *m_retry;
    int m_delayMs;
    bool m_started = false;
    /** Whether the next attempt may start a service a client stopped. */
    bool m_mayStartStopped = true;
    /** Whether an attempt has been made: only the first is somebody opening Simorg (ServiceClient::Options). */
    bool m_attempted = false;
    bool m_connected = false;
    QList<TopicSubscription *> m_subscriptions;
};

} // namespace simorg::client
