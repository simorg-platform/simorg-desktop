// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/ActivityModel.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QUrlQuery>

namespace simorg::app {

using support::number;
using support::text;

ActivityModel::ActivityModel(client::ServiceSession *session, QObject *parent)
    : QAbstractListModel(parent)
{
    // Every level, as the tab has always shown: its filters are by kind, and a debug line is part of the story.
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("level"), QStringLiteral("debug"));
    params.addQueryItem(QStringLiteral("tail"), QString::number(maximumEntries));
    m_topic = session->subscribe(QStringLiteral("journal.entries"), params);
    m_auth = session->subscribe(QStringLiteral("auth.state"));

    connect(m_topic, &client::TopicSubscription::received, this, &ActivityModel::append);
    // The subscription is opened again with its backlog on every connection; the events arrive after this.
    connect(session, &client::ServiceSession::connected, this, &ActivityModel::clear);
    connect(m_auth, &client::TopicSubscription::received, this, [this](const QJsonObject &state) {
        // Signing out deletes the journal, and the view goes with it: the next person's log starts empty.
        // Through `signing_out`, so only the end of a session that was open counts.
        const QString name = text(state, "state");
        if (name == QLatin1String("signed_in")) {
            m_signedIn = true;
        } else if (name == QLatin1String("signed_out") && m_signedIn) {
            m_signedIn = false;
            clear();
        }
    });
}

int ActivityModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant ActivityModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};
    const QJsonObject &entry = m_entries.at(index.row());
    const QDateTime at = m_times.at(index.row());
    switch (role) {
    case AtRole:
        return at;
    case TimeTextRole:
        return at.toString(QStringLiteral("HH:mm:ss"));
    case DateTextRole:
        return at.date() == QDate::currentDate() ? QString() : at.toString(QStringLiteral("d MMM"));
    case KindRole:
        // `virtual-machine`, as the rows and filters spell the kinds; the service writes `virtual_machine`.
        return text(entry, "kind").replace(QLatin1Char('_'), QLatin1Char('-'));
    case LevelRole:
        return text(entry, "level");
    case LevelRankRole:
        return int(number(entry, "level_rank"));
    case LevelTagRole:
        return text(entry, "tag");
    case MessageRole:
        return text(entry, "message");
    case AgentSlugRole:
        return text(entry, "agent_slug");
    case AgentTitleRole:
        return text(entry, "agent_title");
    case VirtualMachineRole:
        return text(entry, "virtual_machine");
    default:
        return {};
    }
}

QHash<int, QByteArray> ActivityModel::roleNames() const
{
    return {
        {AtRole, "at"},
        {TimeTextRole, "timeText"},
        {DateTextRole, "dateText"},
        {KindRole, "kind"},
        {LevelRole, "level"},
        {LevelRankRole, "levelRank"},
        {LevelTagRole, "levelTag"},
        {MessageRole, "message"},
        {AgentSlugRole, "agentSlug"},
        {AgentTitleRole, "agentTitle"},
        {VirtualMachineRole, "virtualMachine"},
    };
}

QVariantMap ActivityModel::at(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_entries.size())
        return map;
    const QHash<int, QByteArray> names = roleNames();
    for (auto it = names.constBegin(); it != names.constEnd(); ++it)
        map.insert(QString::fromUtf8(it.value()), data(index(row), it.key()));
    return map;
}

void ActivityModel::append(const QJsonObject &entry)
{
    if (text(entry, "message").isEmpty())
        return;
    if (m_entries.size() >= maximumEntries) {
        beginRemoveRows({}, 0, 0);
        m_entries.removeFirst();
        m_times.removeFirst();
        endRemoveRows();
    }
    const int row = int(m_entries.size());
    beginInsertRows({}, row, row);
    m_entries.append(entry);
    m_times.append(QDateTime::fromString(text(entry, "at"), Qt::ISODateWithMs).toLocalTime());
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT recorded(at(row));
}

void ActivityModel::clear()
{
    if (m_entries.isEmpty())
        return;
    beginResetModel();
    m_entries.clear();
    m_times.clear();
    endResetModel();
    Q_EMIT countChanged();
}

} // namespace simorg::app
