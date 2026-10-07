// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/client/ServiceSession.h"

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace simorg::app {

/**
 * The applications on this computer connected to the Simorg machine service, as
 * the window reads them off `Peers`.
 *
 * An application always runs on the host, never in an agent's container: a person
 * starts it, it connects to the service, and this computer's owner decides once
 * whether it may attach. One row per open connection from `peers.roster`, with the
 * decisions kept for this machine beside them. Every `peers.pending` the service
 * raises is queued, and `request` is the first of them whose connection is still
 * waiting for an answer — the question the consent sheet asks. A decision is stored
 * on the platform before the service applies it, so `deciding` stays true until it
 * has been; a refusal of the request is `error`.
 */
class PeersModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY changed)
    Q_PROPERTY(bool listening READ isListening NOTIFY changed)
    Q_PROPERTY(bool pairingsLoaded READ pairingsLoaded NOTIFY changed)
    Q_PROPERTY(QVariantList pairings READ pairings NOTIFY changed)
    /** The decisions kept for specifiers no open connection presents: `pairings`' shape. */
    Q_PROPERTY(QVariantList unconnectedPairings READ unconnectedPairings NOTIFY changed)
    Q_PROPERTY(QVariantMap request READ request NOTIFY requestChanged)
    Q_PROPERTY(bool deciding READ isDeciding NOTIFY decidingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    enum Role {
        PeerIdRole = Qt::UserRole + 1,
        /** The title the application gave itself, or its specifier, so a row is never blank. */
        TitleRole,
        SpecifierRole,
        /** `initializing`, `awaiting_consent`, `declaring`, `attached`, `paused` or `refused`. */
        StateRole,
        /** `pending`, `allowed` or `refused`. */
        ConsentRole,
        /** `verified`, `unverified` or `mismatch`. */
        VerificationRole,
        VerificationDetailRole,
        ExecutablePathRole,
        TransportRole,
        AnnouncedRole,
        ConnectedAtRole,
    };

    explicit PeersModel(client::ServiceSession *session, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool isListening() const;
    bool pairingsLoaded() const;
    /** `{ specifier, allowed, decidedAt, verificationStatus }` for each decision kept. */
    QVariantList pairings() const;
    QVariantList unconnectedPairings() const;
    /** Whether a decision is kept for `specifier`, whatever tag either names. */
    Q_INVOKABLE bool hasDecision(const QString &specifier) const;
    /** `{ peerId, title, specifier, verification, verificationDetail, reason }`, or empty. */
    QVariantMap request() const;
    bool isDeciding() const { return m_deciding; }
    QString error() const { return m_error; }

    /** Allows or refuses the application on this connection; its sheet closes when the answer is stored. */
    Q_INVOKABLE void decide(const QString &peerId, bool allowed);
    /** Closes the connection; the decision stays, so it attaches again when it reconnects. */
    Q_INVOKABLE void detach(const QString &peerId);
    /** Forgets the decision about a specifier, so its next connection is asked again. */
    Q_INVOKABLE void forget(const QString &specifier);
    /** Puts the current question aside without answering it; the application keeps waiting. */
    Q_INVOKABLE void dismissRequest();

Q_SIGNALS:
    void changed();
    void requestChanged();
    void decidingChanged();
    void errorChanged();
    /** A new question was raised: the tray says so while the window is closed. */
    void consentRequested(const QString &title);

private:
    void apply(const QJsonObject &roster);
    void queue(const QJsonObject &consentRequest);
    void settle();
    void setDeciding(bool deciding);
    void setError(const QString &error);
    QJsonObject peer(const QString &peerId) const;

    client::ServiceSession *m_session;
    client::TopicSubscription *m_roster;
    client::TopicSubscription *m_pending;
    QJsonObject m_list;
    QJsonArray m_items;
    /** The questions raised, oldest first; each is `PeerConsentRequest`. */
    QList<QJsonObject> m_requests;
    QVariantMap m_request;
    bool m_deciding = false;
    QString m_error;
};

} // namespace simorg::app
