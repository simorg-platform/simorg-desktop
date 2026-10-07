// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/AccessGrantsModel.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QUrl>

#include <algorithm>

namespace simorg::app {

using support::number;
using support::text;

namespace {

/** Whether this computer's paths are Windows ones, which the service mounts under another name. */
#if defined(Q_OS_WIN)
constexpr bool kWindowsPaths = true;
#else
constexpr bool kWindowsPaths = false;
#endif

/** Rows are told apart by agent and permission together. */
QJsonObject keyed(QJsonObject request)
{
    request.insert(QStringLiteral("_row"),
                   QStringLiteral("%1/%2").arg(number(request, "agent_id")).arg(text(request, "access_key")));
    return request;
}

} // namespace

AccessGrantsModel::AccessGrantsModel(client::ServiceSession *session, QObject *parent)
    : KeyedRowsModel("_row", parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("access.changed")))
{
    connect(m_topic, &client::TopicSubscription::received, this, &AccessGrantsModel::apply);
    if (m_topic->hasValue())
        apply(m_topic->value());
}

void AccessGrantsModel::apply(const QJsonObject &overview)
{
    if (overview == m_overview)
        return;
    m_overview = overview;
    QList<QJsonObject> rows;
    for (const QJsonValue &value : overview.value(QStringLiteral("requests")).toArray())
        rows.append(keyed(value.toObject()));
    reconcile(rows);
    Q_EMIT changed();
}

QStringList AccessGrantsModel::alwaysAllowedApplications() const
{
    QStringList applications;
    for (const QJsonValue &value : m_overview.value(QStringLiteral("always_allowed_applications")).toArray()) {
        if (value.isString() && !value.toString().isEmpty())
            applications.append(value.toString());
    }
    return applications;
}

void AccessGrantsModel::watch(client::ServiceReply *reply)
{
    connect(reply, &client::ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            return;
        Q_EMIT saveFailed(reply->problem().message());
    });
}

QHash<int, QByteArray> AccessGrantsModel::roleNames() const
{
    return {
        {AgentIdRole, "agentId"},
        {AgentSlugRole, "agentSlug"},
        {AgentTitleRole, "agentTitle"},
        {AccessKeyRole, "accessKey"},
        {DecisionRole, "decision"},
        {EffectiveDecisionRole, "effectiveDecision"},
        {MachineRuleRole, "machineRule"},
        {RuledByMachineRole, "ruledByMachine"},
        {ReasonRole, "reason"},
        {MachineCategoryKeysRole, "machineCategoryKeys"},
        {SettingsRole, "settings"},
        {DecidedAtRole, "decidedAt"},
        {UnchosenFolderCountRole, "unchosenFolderCount"},
        {AboutFoldersRole, "aboutFolders"},
    };
}

QVariant AccessGrantsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &request = row(index.row());
    switch (role) {
    case AgentIdRole:
        return int(number(request, "agent_id"));
    case AgentSlugRole:
        return text(request, "agent_slug");
    case AgentTitleRole:
        return text(request, "agent_title").isEmpty() ? text(request, "agent_slug") : text(request, "agent_title");
    case AccessKeyRole:
        return text(request, "access_key");
    case DecisionRole:
        return text(request, "decision");
    case EffectiveDecisionRole:
        return text(request, "effective_decision");
    case MachineRuleRole:
        return text(request, "machine_rule");
    case RuledByMachineRole:
        return request.value(QStringLiteral("ruled_by_machine")).toBool();
    case ReasonRole:
        return text(request, "reason");
    case MachineCategoryKeysRole:
        return request.value(QStringLiteral("machine_category_keys")).toArray().toVariantList();
    case SettingsRole:
        return request.value(QStringLiteral("settings")).toObject().toVariantMap();
    case DecidedAtRole:
        return text(request, "decided_at");
    case UnchosenFolderCountRole:
        return int(number(request, "unchosen_folder_count"));
    case AboutFoldersRole:
        return request.value(QStringLiteral("about_folders")).toBool();
    default:
        return {};
    }
}

int AccessGrantsModel::pendingCount() const
{
    int pending = 0;
    for (int index = 0; index < rowCount(); ++index) {
        if (text(row(index), "effective_decision") == QLatin1String("pending"))
            ++pending;
    }
    return pending;
}

int AccessGrantsModel::ruleCount() const
{
    return int(number(m_overview.value(QStringLiteral("rules")).toObject(), "rule_count"));
}

bool AccessGrantsModel::isLoaded() const
{
    return text(m_overview.value(QStringLiteral("store")).toObject(), "state") == QLatin1String("loaded");
}

bool AccessGrantsModel::isSaving() const
{
    return m_overview.value(QStringLiteral("store")).toObject().value(QStringLiteral("saving")).toBool();
}

QString AccessGrantsModel::rule(const QString &accessKey) const
{
    for (const QJsonValue &value :
         m_overview.value(QStringLiteral("rules")).toObject().value(QStringLiteral("items")).toArray()) {
        if (text(value.toObject(), "access_key") == accessKey)
            return text(value.toObject(), "rule");
    }
    return QStringLiteral("ASK");
}

QString AccessGrantsModel::encodedKey(const QString &accessKey) const
{
    return QString::fromLatin1(QUrl::toPercentEncoding(accessKey));
}

void AccessGrantsModel::setRule(const QString &accessKey, const QString &rule)
{
    watch(m_session->put(QStringLiteral("/v1/access/rules/%1").arg(encodedKey(accessKey)),
                         {{QStringLiteral("rule"), rule}}));
}

QVariantMap AccessGrantsModel::machineSettings(const QString &accessKey) const
{
    for (const QJsonValue &value : m_overview.value(QStringLiteral("settings")).toArray()) {
        const QJsonObject entry = value.toObject();
        if (text(entry, "access_key") == accessKey && entry.value(QStringLiteral("configured")).toBool())
            return entry.value(QStringLiteral("settings")).toObject().toVariantMap();
    }
    return {};
}

void AccessGrantsModel::setMachineSettings(const QString &accessKey, const QVariantMap &settings)
{
    const QString path = QStringLiteral("/v1/access/settings/%1").arg(encodedKey(accessKey));
    if (settings.isEmpty()) {
        watch(m_session->remove(path));
        return;
    }
    watch(m_session->put(path, {{QStringLiteral("settings"), QJsonObject::fromVariantMap(settings)}}));
}

int AccessGrantsModel::machineSettingCount() const
{
    return int(number(m_overview.value(QStringLiteral("rules")).toObject(), "setting_count"));
}

QVariantList AccessGrantsModel::requestsFor(int agentId) const
{
    QVariantList list;
    for (int index = 0; index < rowCount(); ++index) {
        if (number(row(index), "agent_id") == agentId)
            list.append(at(index));
    }
    return list;
}

QVariantList AccessGrantsModel::pendingAgents() const
{
    // By name, so a list on the home screen does not reorder under a pointer when an unrelated update arrives.
    QVariantList agents;
    for (const QJsonValue &value : m_overview.value(QStringLiteral("pending")).toArray()) {
        const QJsonObject agent = value.toObject();
        if (number(agent, "pending_count") <= 0)
            continue;
        agents.append(QVariantMap{
            {QStringLiteral("agentId"), int(number(agent, "agent_id"))},
            {QStringLiteral("agentSlug"), text(agent, "agent_slug")},
            {QStringLiteral("agentTitle"),
             text(agent, "agent_title").isEmpty() ? text(agent, "agent_slug") : text(agent, "agent_title")},
            {QStringLiteral("pendingCount"), int(number(agent, "pending_count"))},
        });
    }
    std::sort(agents.begin(), agents.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap()
                   .value(QStringLiteral("agentTitle"))
                   .toString()
                   .localeAwareCompare(right.toMap().value(QStringLiteral("agentTitle")).toString())
               < 0;
    });
    return agents;
}

int AccessGrantsModel::pendingCountFor(int agentId) const
{
    for (const QJsonValue &value : m_overview.value(QStringLiteral("pending")).toArray()) {
        if (number(value.toObject(), "agent_id") == agentId)
            return int(number(value.toObject(), "pending_count"));
    }
    return 0;
}

int AccessGrantsModel::outstandingFor(int agentId) const
{
    for (const QJsonValue &value : m_overview.value(QStringLiteral("pending")).toArray()) {
        if (number(value.toObject(), "agent_id") == agentId)
            return int(number(value.toObject(), "outstanding_count"));
    }
    return 0;
}

const QJsonObject *AccessGrantsModel::request(int agentId, const QString &accessKey) const
{
    for (int index = 0; index < rowCount(); ++index) {
        const QJsonObject &candidate = row(index);
        if (number(candidate, "agent_id") == agentId && text(candidate, "access_key") == accessKey)
            return &candidate;
    }
    return nullptr;
}

bool AccessGrantsModel::fail(const QString &message)
{
    m_lastError = message;
    return false;
}

bool AccessGrantsModel::decide(int agentId, const QString &accessKey, bool allowed)
{
    m_lastError.clear();
    const QJsonObject *const found = request(agentId, accessKey);
    if (!found)
        return fail(tr("That request is no longer on this computer."));
    // A rule said about agents that had not arrived yet is not something a per-agent screen may talk over.
    if (found->value(QStringLiteral("ruled_by_machine")).toBool())
        return fail(
            tr("A rule for this computer already decides this. Change it under Settings → Access management."));
    // Yes needs something to say yes to: a folder request with an unchosen folder would grant nothing.
    const qint64 unchosen = number(*found, "unchosen_folder_count");
    if (allowed && unchosen > 0)
        return fail(tr("Choose a folder for each one this agent asked for first. %1 still need one.").arg(unchosen));
    watch(m_session->post(
        QStringLiteral("/v1/access/requests/%1/%2/decide").arg(QString::number(agentId), encodedKey(accessKey)),
        {{QStringLiteral("allowed"), allowed}}));
    return true;
}

void AccessGrantsModel::reset(int agentId, const QString &accessKey)
{
    watch(m_session->post(
        QStringLiteral("/v1/access/requests/%1/%2/reset").arg(QString::number(agentId), encodedKey(accessKey))));
}

QVariantList AccessGrantsModel::folders(int agentId, const QString &accessKey) const
{
    const QJsonObject *const found = request(agentId, accessKey);
    if (!found)
        return {};
    QVariantList list;
    for (const QJsonValue &value : found->value(QStringLiteral("folders")).toArray()) {
        const QJsonObject folder = value.toObject();
        list.append(QVariantMap{
            {QStringLiteral("index"), int(number(folder, "index"))},
            {QStringLiteral("dynamic"), folder.value(QStringLiteral("dynamic")).toBool()},
            {QStringLiteral("purpose"), text(folder, "purpose")},
            {QStringLiteral("mode"), text(folder, "mode")},
            {QStringLiteral("path"), text(folder, "path")},
            {QStringLiteral("agentPath"), agentPathOf(text(folder, "path"), kWindowsPaths)},
            {QStringLiteral("chosen"), folder.value(QStringLiteral("chosen")).toBool()},
            {QStringLiteral("writable"), folder.value(QStringLiteral("writable")).toBool()},
        });
    }
    return list;
}

namespace {

/**
 * `path` with `.` and `..` resolved and empty components dropped, `/` its only
 * separator, and `..` never climbing above the root — the service's own
 * normalisation. Written out rather than `QDir::cleanPath`, which on
 * Windows also turns a backslash into a separator, and so would answer a Mac's
 * or Linux's path differently depending on where it was asked.
 */
QString normalised(const QString &path)
{
    const bool absolute = path.startsWith(QLatin1Char('/'));
    QStringList kept;
    for (const QString &part : path.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
        if (part == QLatin1String("."))
            continue;
        if (part == QLatin1String("..")) {
            if (!kept.isEmpty() && kept.constLast() != QLatin1String(".."))
                kept.removeLast();
            else if (!absolute)
                kept.append(part);
            continue;
        }
        kept.append(part);
    }
    const QString joined = kept.join(QLatin1Char('/'));
    return absolute ? QLatin1Char('/') + joined : joined;
}

} // namespace

QString AccessGrantsModel::agentPathOf(const QString &hostPath, bool windows)
{
    QString path = hostPath.trimmed();
    if (path.isEmpty())
        return {};
    if (windows)
        path.replace(QLatin1Char('\\'), QLatin1Char('/'));
    const QChar letter = path.at(0);
    const bool drive = windows && path.size() >= 2 && letter.unicode() < 128 && letter.isLetter()
                       && path.at(1) == QLatin1Char(':') && (path.size() == 2 || path.at(2) == QLatin1Char('/'));
    if (!drive)
        return normalised(path);
    // The rest from the drive's root, so `..` stops there. `X:` alone is the
    // whole drive, which the service never mounts; answered anyway.
    const QString rest = normalised(QLatin1Char('/') + path.mid(2));
    return QLatin1Char('/') + letter.toLower() + (rest == QLatin1String("/") ? QString() : rest);
}

QString AccessGrantsModel::agentPath(const QString &hostPath) const
{
    return agentPathOf(hostPath, kWindowsPaths);
}

bool AccessGrantsModel::chooseFolder(int agentId, const QString &accessKey, int folderIndex, const QString &path)
{
    m_lastError.clear();
    const QJsonObject *const found = request(agentId, accessKey);
    if (!found)
        return fail(tr("That request is no longer on this computer."));
    const QJsonArray folders = found->value(QStringLiteral("folders")).toArray();
    const auto folder = std::find_if(folders.begin(), folders.end(), [folderIndex](const QJsonValue &value) {
        return number(value.toObject(), "index") == folderIndex;
    });
    if (folder == folders.end())
        return fail(tr("That folder is not part of this request any more."));
    if (!folder->toObject().value(QStringLiteral("dynamic")).toBool())
        return fail(tr("This folder was set by the agent's owner and cannot be changed here."));

    // Checked here as well as by the service, so the message is beside the field when somebody picks it.
    QJsonValue chosen(QJsonValue::Null);
    const QString trimmed = path.trimmed();
    if (!trimmed.isEmpty()) {
        const QFileInfo info(trimmed);
        if (!info.exists() || !info.isDir())
            return fail(tr("“%1” is not a folder on this computer.").arg(trimmed));
        if (!info.isReadable())
            return fail(tr("“%1” cannot be read by you, so it cannot be shared.").arg(trimmed));
        chosen = info.absoluteFilePath();
    }
    watch(m_session->put(QStringLiteral("/v1/access/requests/%1/%2/folders/%3")
                             .arg(QString::number(agentId), encodedKey(accessKey), QString::number(folderIndex)),
                         {{QStringLiteral("path"), chosen}}));
    return true;
}

} // namespace simorg::app
