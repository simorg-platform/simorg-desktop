// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/client/ServiceClient.h"

#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

/**
 * This app's link to the Simorg machine service on this computer, as QML reads it
 * off `Service`.
 *
 * Everything else in this application is a view of something the service holds —
 * the session, the agents, Docker, the shutdown run. This is the view of the one
 * thing underneath all of them, and it exists because the first seconds of a
 * launch are otherwise a screen with nothing to say: the windows cannot know who
 * is signed in until the service answers, and until this model there was no way
 * to tell somebody that *waiting for the service* is what is happening.
 *
 * `ServiceSession` reconnects on its own and reports each attempt that failed with
 * a reason and a sentence. This keeps the last of those, turns the reason into the
 * one distinction a person acts on — something to wait for, or something to fix —
 * and offers the retry that skips the backoff.
 */
class ServiceLinkModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY changed)
    /** True once this app has talked to the service at least once in this run. */
    Q_PROPERTY(bool everConnected READ hasEverConnected NOTIFY changed)
    /** A short phrase for the state, empty while connected. */
    Q_PROPERTY(QString title READ title NOTIFY changed)
    /** The service client's own sentence about the last attempt; empty when none has failed. */
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    /** Nothing here fixes itself: the service is missing, refused or a version this app cannot speak. */
    Q_PROPERTY(bool severe READ isSevere NOTIFY changed)
    /** No service is installed here, which the starting window can fix (`ServiceInstall`). */
    Q_PROPERTY(bool notInstalled READ isNotInstalled NOTIFY changed)

public:
    explicit ServiceLinkModel(client::ServiceSession *session, QObject *parent = nullptr);

    bool isConnected() const { return m_connected; }
    bool hasEverConnected() const { return m_everConnected; }
    QString title() const;
    QString detail() const { return m_detail; }
    bool isSevere() const;
    bool isNotInstalled() const
    {
        return !m_connected && m_reason == client::ServiceClient::Unavailable::NotInstalled;
    }

public Q_SLOTS:
    /**
     * Tries again now, rather than at the end of the backoff.
     *
     * `resumeService` and not a plain reconnect: pressing this is the person
     * asking for Simorg, which is the one thing allowed to start a service that
     * a client stopped.
     */
    void retryNow();

Q_SIGNALS:
    void changed();

private:
    client::ServiceSession *m_session;
    bool m_connected = false;
    bool m_everConnected = false;
    /** Meaningful only while disconnected, and `NotReady` until an attempt has failed. */
    client::ServiceClient::Unavailable m_reason = client::ServiceClient::Unavailable::NotReady;
    QString m_detail;
};

} // namespace simorg::app
