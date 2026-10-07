// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/PeersModel.h"

#include "Support.h"

#include <QUrlQuery>

namespace simorg::app {

using support::text;

namespace {

/** A specifier without its tag. */
QString baseOf(const QString &specifier)
{
    const qsizetype slash = specifier.lastIndexOf(QLatin1Char('/'));
    const qsizetype colon = specifier.lastIndexOf(QLatin1Char(':'));
    return colon > slash ? specifier.left(colon) : specifier;
}

QString titleOf(const QJsonObject &peer)
{
    const QString title = text(peer, "title");
    return title.isEmpty() ? text(peer, "specifier") : title;
}

} // namespace

PeersModel::PeersModel(client::ServiceSession *session, QObject *parent)
    : QAbstractListModel(parent)
    , m_session(session)
    , m_roster(session->subscribe(QStringLiteral("peers.roster")))
    , m_pending(session->subscribe(QStringLiteral("peers.pending")))
{
    connect(m_roster, &client::TopicSubscription::received, this, &PeersModel::apply);
    connect(m_pending, &client::TopicSubscription::received, this, &PeersModel::queue);
    if (m_roster->hasValue())
        apply(m_roster->value());
}

void PeersModel::apply(const QJsonObject &roster)
{
    if (roster == m_list)
        return;
    const QJsonArray items = roster.value(QStringLiteral("items")).toArray();
    if (items != m_items) {
        beginResetModel();
        m_items = items;
        endResetModel();
    }
    m_list = roster;
    Q_EMIT changed();
    settle();
}

void PeersModel::queue(const QJsonObject &consentRequest)
{
    const QString peerId = text(consentRequest.value(QStringLiteral("peer")).toObject(), "peer_id");
    if (peerId.isEmpty())
        return;
    for (const QJsonObject &held : std::as_const(m_requests)) {
        if (text(held.value(QStringLiteral("peer")).toObject(), "peer_id") == peerId)
            return;
    }
    m_requests.append(consentRequest);
    Q_EMIT consentRequested(titleOf(consentRequest.value(QStringLiteral("peer")).toObject()));
    settle();
}

void PeersModel::settle()
{
    // A question is only worth asking while its connection is still open and still waiting for the answer.
    while (!m_requests.isEmpty()) {
        const QString peerId = text(m_requests.first().value(QStringLiteral("peer")).toObject(), "peer_id");
        const QJsonObject current = peer(peerId);
        if (!current.isEmpty() && text(current, "state") == QLatin1String("awaiting_consent"))
            break;
        m_requests.removeFirst();
    }
    QVariantMap next;
    if (!m_requests.isEmpty()) {
        const QJsonObject &held = m_requests.first();
        const QJsonObject current = peer(text(held.value(QStringLiteral("peer")).toObject(), "peer_id"));
        const QJsonObject verification = current.value(QStringLiteral("verification")).toObject();
        next.insert(QStringLiteral("peerId"), text(current, "peer_id"));
        next.insert(QStringLiteral("title"), titleOf(current));
        next.insert(QStringLiteral("specifier"), text(current, "specifier"));
        next.insert(QStringLiteral("verification"), text(verification, "status"));
        next.insert(QStringLiteral("verificationDetail"), text(verification, "detail"));
        next.insert(QStringLiteral("reason"), text(held, "reason"));
    }
    if (next != m_request) {
        m_request = next;
        Q_EMIT requestChanged();
    }
}

QJsonObject PeersModel::peer(const QString &peerId) const
{
    for (const QJsonValue &value : m_items) {
        const QJsonObject item = value.toObject();
        if (text(item, "peer_id") == peerId)
            return item;
    }
    return {};
}

int PeersModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant PeersModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return {};
    const QJsonObject item = m_items.at(index.row()).toObject();
    const QJsonObject verification = item.value(QStringLiteral("verification")).toObject();
    switch (role) {
    case PeerIdRole:
        return text(item, "peer_id");
    case TitleRole:
        return titleOf(item);
    case SpecifierRole:
        return text(item, "specifier");
    case StateRole:
        return text(item, "state");
    case ConsentRole:
        return text(item, "consent");
    case VerificationRole:
        return text(verification, "status");
    case VerificationDetailRole:
        return text(verification, "detail");
    case ExecutablePathRole:
        return text(verification, "executable_path");
    case TransportRole:
        return text(item, "transport");
    case AnnouncedRole:
        return item.value(QStringLiteral("announced")).toBool();
    case ConnectedAtRole:
        return text(item, "connected_at");
    default:
        return {};
    }
}

QHash<int, QByteArray> PeersModel::roleNames() const
{
    return {
        {PeerIdRole, "peerId"},
        {TitleRole, "title"},
        {SpecifierRole, "specifier"},
        {StateRole, "state"},
        {ConsentRole, "consent"},
        {VerificationRole, "verification"},
        {VerificationDetailRole, "verificationDetail"},
        {ExecutablePathRole, "executablePath"},
        {TransportRole, "transport"},
        {AnnouncedRole, "announced"},
        {ConnectedAtRole, "connectedAt"},
    };
}

bool PeersModel::isListening() const
{
    return text(m_list.value(QStringLiteral("listener")).toObject(), "state") == QLatin1String("listening");
}

bool PeersModel::pairingsLoaded() const
{
    return m_list.value(QStringLiteral("pairings_loaded")).toBool();
}

QVariantList PeersModel::pairings() const
{
    QVariantList list;
    for (const QJsonValue &value : m_list.value(QStringLiteral("pairings")).toArray()) {
        const QJsonObject pairing = value.toObject();
        QVariantMap row;
        row.insert(QStringLiteral("specifier"), text(pairing, "specifier"));
        row.insert(QStringLiteral("allowed"), pairing.value(QStringLiteral("allowed")).toBool());
        row.insert(QStringLiteral("decidedAt"), text(pairing, "decided_at"));
        row.insert(QStringLiteral("verificationStatus"), text(pairing, "verification_status"));
        list.append(row);
    }
    return list;
}

QVariantList PeersModel::unconnectedPairings() const
{
    QVariantList list;
    for (const QVariant &row : pairings()) {
        const QString base = baseOf(row.toMap().value(QStringLiteral("specifier")).toString());
        bool connected = false;
        for (const QJsonValue &value : m_items)
            connected = connected || baseOf(text(value.toObject(), "specifier")) == base;
        if (!connected)
            list.append(row);
    }
    return list;
}

bool PeersModel::hasDecision(const QString &specifier) const
{
    const QString base = baseOf(specifier);
    for (const QJsonValue &value : m_list.value(QStringLiteral("pairings")).toArray()) {
        if (baseOf(text(value.toObject(), "specifier")) == base)
            return true;
    }
    return false;
}

QVariantMap PeersModel::request() const
{
    return m_request;
}

void PeersModel::decide(const QString &peerId, bool allowed)
{
    if (m_deciding || peerId.isEmpty())
        return;
    setError({});
    setDeciding(true);
    QJsonObject body;
    body.insert(QStringLiteral("allowed"), allowed);
    client::ServiceReply *const reply = m_session->post(QStringLiteral("/v1/peers/%1/consent").arg(peerId), body);
    connect(reply, &client::ServiceReply::finished, this, [this, reply, peerId] {
        setDeciding(false);
        if (reply->isError()) {
            setError(reply->problem().message());
            return;
        }
        // Answered: the question goes, whatever the roster says next.
        m_requests.erase(std::remove_if(m_requests.begin(), m_requests.end(),
                                        [&peerId](const QJsonObject &held) {
                                            return text(held.value(QStringLiteral("peer")).toObject(), "peer_id") ==
                                                   peerId;
                                        }),
                         m_requests.end());
        settle();
    });
}

void PeersModel::detach(const QString &peerId)
{
    if (peerId.isEmpty())
        return;
    setError({});
    client::ServiceReply *const reply = m_session->remove(QStringLiteral("/v1/peers/%1").arg(peerId));
    connect(reply, &client::ServiceReply::finished, this, [this, reply] {
        if (reply->isError())
            setError(reply->problem().message());
    });
}

void PeersModel::forget(const QString &specifier)
{
    if (specifier.isEmpty())
        return;
    setError({});
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("specifier"), specifier);
    client::ServiceReply *const reply =
        m_session->request(QByteArrayLiteral("DELETE"), QStringLiteral("/v1/peers/pairings"), {}, query);
    connect(reply, &client::ServiceReply::finished, this, [this, reply] {
        if (reply->isError())
            setError(reply->problem().message());
    });
}

void PeersModel::dismissRequest()
{
    if (m_requests.isEmpty())
        return;
    m_requests.removeFirst();
    settle();
}

void PeersModel::setDeciding(bool deciding)
{
    if (m_deciding == deciding)
        return;
    m_deciding = deciding;
    Q_EMIT decidingChanged();
}

void PeersModel::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}

} // namespace simorg::app
