// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/LegalModel.h"

#include "simorg/client/ServiceSession.h"

#include <QJsonArray>

namespace simorg::app {

using client::ServiceReply;

namespace {

QVariantMap documentOf(const QJsonObject &document)
{
    QVariantList sections;
    for (const QJsonValue &value : document.value(QStringLiteral("sections")).toArray()) {
        const QJsonObject section = value.toObject();
        QStringList points;
        for (const QJsonValue &point : section.value(QStringLiteral("points")).toArray())
            points << point.toString();
        sections << QVariantMap{
            {QStringLiteral("title"), section.value(QStringLiteral("title")).toString()},
            {QStringLiteral("body"), section.value(QStringLiteral("body")).toString()},
            {QStringLiteral("points"), points},
            {QStringLiteral("note"), section.value(QStringLiteral("note")).toString()},
        };
    }
    return QVariantMap{
        {QStringLiteral("id"), document.value(QStringLiteral("id")).toString()},
        {QStringLiteral("title"), document.value(QStringLiteral("title")).toString()},
        {QStringLiteral("glyph"), document.value(QStringLiteral("glyph")).toString()},
        {QStringLiteral("summary"), document.value(QStringLiteral("summary")).toString()},
        {QStringLiteral("sections"), sections},
    };
}

} // namespace

LegalModel::LegalModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_auth(session->subscribe(QStringLiteral("auth.state")))
{
    connect(m_session, &client::ServiceSession::connected, this, &LegalModel::reload);
    /*
      An acceptance recorded or withdrawn anywhere (this window, a terminal) shows on `auth.state`, and so does
      the service carrying another edition, which it does once it has read the website's: a window
      showing the copy the service started with is then showing the wrong text, and would offer an edition the
      service refuses to record.
    */
    connect(m_auth, &client::TopicSubscription::received, this, [this](const QJsonObject &state) {
        const bool termsAccepted = state.value(QStringLiteral("terms_accepted")).toBool();
        // A service from before the edition was published on `auth.state` sends none, and moves no edition.
        const bool editionMoved = m_loaded && state.contains(QStringLiteral("terms_version"))
                                  && state.value(QStringLiteral("terms_version")).toString() != m_version;
        if (!m_termsAcceptedSeen || termsAccepted != m_accepted || editionMoved)
            reload();
        m_termsAcceptedSeen = true;
    });
    if (m_session->isConnected())
        reload();
}

void LegalModel::reload()
{
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/legal"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            apply(reply->object());
    });
}

void LegalModel::apply(const QJsonObject &legal)
{
    const auto text = [&legal](const char *key) { return legal.value(QLatin1String(key)).toString(); };
    QVariantList documents;
    for (const QJsonValue &value : legal.value(QStringLiteral("documents")).toArray())
        documents << documentOf(value.toObject());

    const bool documentsMoved = !m_loaded || m_version != text("version") || m_documents != documents;
    m_loaded = true;
    m_version = text("version");
    m_effective = text("effective");
    m_contactEmail = text("contact_email");
    m_website = text("website_url");
    m_onlineTerms = text("online_terms_url");
    m_onlinePrivacy = text("online_privacy_url");
    m_documents = documents;

    const QJsonObject acceptance = legal.value(QStringLiteral("acceptance")).toObject();
    const bool accepted = acceptance.value(QStringLiteral("accepted")).toBool();
    const QString acceptedVersion = acceptance.value(QStringLiteral("accepted_version")).toString();
    const QDateTime acceptedAt =
        QDateTime::fromString(acceptance.value(QStringLiteral("accepted_at")).toString(), Qt::ISODateWithMs);
    const bool acceptanceMoved =
        accepted != m_accepted || acceptedVersion != m_acceptedVersion || acceptedAt != m_acceptedAt;
    m_accepted = accepted;
    m_acceptedVersion = acceptedVersion;
    m_acceptedAt = acceptedAt;

    if (documentsMoved)
        Q_EMIT documentsChanged();
    if (acceptanceMoved)
        Q_EMIT acceptanceChanged();
}

QVariantMap LegalModel::document(const QString &id) const
{
    const int index = documentIndex(id);
    return index < 0 ? QVariantMap() : m_documents.at(index).toMap();
}

int LegalModel::documentIndex(const QString &id) const
{
    for (int i = 0; i < m_documents.size(); ++i) {
        if (m_documents.at(i).toMap().value(QStringLiteral("id")).toString() == id)
            return i;
    }
    return -1;
}

bool LegalModel::accept()
{
    if (!m_loaded || m_version.isEmpty() || !m_session->isConnected())
        return false;
    acceptThen([](bool, const QString &) {});
    return true;
}

void LegalModel::acceptThen(const std::function<void(bool accepted, const QString &message)> &then)
{
    if (m_accepted && m_acceptedVersion == m_version && !m_version.isEmpty())
        return then(true, QString());
    // An edition nobody has been shown cannot be accepted, and the service would refuse it anyway.
    if (!m_loaded || m_version.isEmpty())
        return then(false, QStringLiteral("The terms could not be read from the Simorg machine service."));
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/legal/accept"), {{QStringLiteral("version"), m_version}});
    connect(reply, &ServiceReply::finished, this, [this, reply, then] {
        if (reply->isError())
            return then(false, reply->problem().message());
        apply(reply->object());
        then(true, QString());
    });
}

bool LegalModel::withdraw()
{
    if (!m_session->isConnected())
        return false;
    ServiceReply *reply = m_session->remove(QStringLiteral("/v1/legal/acceptance"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            reload();
    });
    return true;
}

} // namespace simorg::app
