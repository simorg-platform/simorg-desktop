// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonObject>
#include <QList>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The log of what the platform asked this computer to do, as the Activity tab reads
 * it off `Activity`.
 *
 * The service keeps the journal
 * and Simorg CLI's `sim logs` reads the same one, so the tab and a terminal cannot describe
 * one event differently. This holds the newest entries of `journal.entries`: the
 * backlog when it subscribes, then each entry as the service records it. The
 * service is asked for the backlog again on every connection, so the view is
 * rebuilt then rather than appended to twice.
 */
class ActivityModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        AtRole = Qt::UserRole + 1,
        /** `HH:mm:ss` in local time. */
        TimeTextRole,
        /** `d MMM`, or empty for today, so a list being watched is not a column of today's date. */
        DateTextRole,
        KindRole,
        LevelRole,
        LevelRankRole,
        LevelTagRole,
        MessageRole,
        AgentSlugRole,
        AgentTitleRole,
        VirtualMachineRole,
    };

    /** Entries held; the oldest go first. */
    static constexpr int maximumEntries = 500;

    explicit ActivityModel(client::ServiceSession *session, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE QVariantMap at(int row) const;

public Q_SLOTS:
    /** Empties the view. The journal itself is the service's history and stays. */
    void clear();

Q_SIGNALS:
    void countChanged();
    /** One entry as it arrived, the backlog's included, in the shape of `at`. */
    void recorded(const QVariantMap &entry);

private:
    void append(const QJsonObject &entry);

    client::TopicSubscription *m_topic;
    client::TopicSubscription *m_auth;
    QList<QJsonObject> m_entries;
    QList<QDateTime> m_times;
    bool m_signedIn = false;
};

} // namespace simorg::app
