// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The terms and the privacy notice, as QML reads them off `Legal`.
 *
 * The service holds both documents, as the website publishes them, and this
 * installation's acceptance; this reads them with `GET /v1/legal` whenever the
 * service connects
 * or `auth.state` says the acceptance or the edition moved. That is how an
 * acceptance made in a terminal reaches the window, and how the website's
 * edition replaces the service's own copy on a screen already showing it.
 */
class LegalModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY documentsChanged)
    Q_PROPERTY(QString version READ version NOTIFY documentsChanged)
    Q_PROPERTY(QString effective READ effective NOTIFY documentsChanged)
    Q_PROPERTY(QString contactEmail READ contactEmail NOTIFY documentsChanged)
    Q_PROPERTY(QString website READ website NOTIFY documentsChanged)
    Q_PROPERTY(QString onlineTerms READ onlineTerms NOTIFY documentsChanged)
    Q_PROPERTY(QString onlinePrivacy READ onlinePrivacy NOTIFY documentsChanged)
    Q_PROPERTY(QVariantList documents READ documents NOTIFY documentsChanged)
    Q_PROPERTY(bool accepted READ accepted NOTIFY acceptanceChanged)
    Q_PROPERTY(QString acceptedVersion READ acceptedVersion NOTIFY acceptanceChanged)
    Q_PROPERTY(QDateTime acceptedAt READ acceptedAt NOTIFY acceptanceChanged)

public:
    explicit LegalModel(client::ServiceSession *session, QObject *parent = nullptr);

    bool isLoaded() const { return m_loaded; }
    QString version() const { return m_version; }
    QString effective() const { return m_effective; }
    QString contactEmail() const { return m_contactEmail; }
    QString website() const { return m_website; }
    QString onlineTerms() const { return m_onlineTerms; }
    QString onlinePrivacy() const { return m_onlinePrivacy; }
    QVariantList documents() const { return m_documents; }
    bool accepted() const { return m_accepted; }
    QString acceptedVersion() const { return m_acceptedVersion; }
    QDateTime acceptedAt() const { return m_acceptedAt; }

    Q_INVOKABLE QVariantMap document(const QString &id) const;
    Q_INVOKABLE int documentIndex(const QString &id) const;

    /**
     * Records this edition as accepted. Answers at once whether a request was
     * sent; the change arrives through {@link acceptanceChanged}. Already accepted
     * is nothing to do.
     */
    Q_INVOKABLE bool accept();
    Q_INVOKABLE bool withdraw();

    /**
     * Accepts when this edition is not yet accepted, then calls `then` with whether
     * the terms are now accepted and, when not, the service's sentence. What a
     * sign-in is sent immediately after.
     */
    void acceptThen(const std::function<void(bool accepted, const QString &message)> &then);

Q_SIGNALS:
    void documentsChanged();
    void acceptanceChanged();

private:
    void reload();
    void apply(const QJsonObject &legal);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_auth;
    bool m_loaded = false;
    QString m_version;
    QString m_effective;
    QString m_contactEmail;
    QString m_website;
    QString m_onlineTerms;
    QString m_onlinePrivacy;
    QVariantList m_documents;
    bool m_accepted = false;
    QString m_acceptedVersion;
    QDateTime m_acceptedAt;
    bool m_termsAcceptedSeen = false;
};

} // namespace simorg::app
