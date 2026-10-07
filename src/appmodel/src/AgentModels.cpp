// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/AgentModels.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QRegularExpression>
#include <QUrlQuery>

#include <utility>

namespace simorg::app {

using client::ServiceReply;
using support::number;
using support::text;

namespace {

/**
 * One release as the service names it (`AgentRelease`), in the shape QML reads:
 * `{artifactTagId, tag, title, notes, publishedAt}`. A private artifact's tag,
 * title and notes are empty, because the platform never names them.
 */
QVariantMap releaseMap(const QJsonObject &release)
{
    if (release.isEmpty())
        return {};
    return {
        {QStringLiteral("artifactTagId"), number(release, "artifact_tag_id")},
        {QStringLiteral("tag"), text(release, "tag")},
        {QStringLiteral("title"), text(release, "title")},
        {QStringLiteral("notes"), text(release, "notes")},
        {QStringLiteral("publishedAt"), text(release, "published_at")},
    };
}

/**
 * A release note's opening words as plain text, for a bar with one line to spare.
 *
 * The note is Markdown, and a bar that showed `## What changed` or `**faster**`
 * would show the syntax rather than the words: headings, list markers,
 * emphasis, code and link targets go, images are left out, and the rest runs
 * together on one line, cut at a word. The same rule as the web console's,
 * for the same bar.
 */
QString releaseNoteExcerpt(const QString &note, int max = 160)
{
    static const QRegularExpression fences(QStringLiteral("```[\\s\\S]*?```"));
    static const QRegularExpression images(QStringLiteral("!\\[[^\\]]*\\]\\([^)]*\\)"));
    static const QRegularExpression links(QStringLiteral("\\[([^\\]]*)\\]\\([^)]*\\)"));
    static const QRegularExpression markers(QStringLiteral("^\\s{0,3}(#{1,6}|[-*+]|\\d+[.)]|>)\\s+"),
                                            QRegularExpression::MultilineOption);
    static const QRegularExpression emphasis(QStringLiteral("(\\*\\*|__|\\*|_|`|~~)"));
    static const QRegularExpression spaces(QStringLiteral("\\s+"));
    QString text = note;
    text.replace(fences, QStringLiteral(" "));
    text.replace(images, QStringLiteral(" "));
    text.replace(links, QStringLiteral("\\1"));
    text.replace(markers, QString());
    text.replace(emphasis, QString());
    text = text.replace(spaces, QStringLiteral(" ")).trimmed();
    if (text.size() <= max)
        return text;
    QString cut = text.left(max - 1);
    const qsizetype space = cut.lastIndexOf(QLatin1Char(' '));
    if (space > max * 0.6)
        cut = cut.left(space);
    return cut.trimmed() + QChar(0x2026);
}

/**
 * An agent row's `update`, as `{available, artifactTagId, tag, title, notes,
 * excerpt, private, currentTag}`; `excerpt` is the note's opening words as
 * plain text.
 */
QVariantMap updateMap(const QJsonObject &agent)
{
    const QJsonObject update = agent.value(QStringLiteral("update")).toObject();
    const QJsonObject available = update.value(QStringLiteral("available")).toObject();
    if (available.isEmpty())
        return {{QStringLiteral("available"), false}};
    QVariantMap map = releaseMap(available);
    map.insert(QStringLiteral("available"), true);
    map.insert(QStringLiteral("excerpt"), releaseNoteExcerpt(text(available, "notes")));
    map.insert(QStringLiteral("private"), update.value(QStringLiteral("private")).toBool());
    map.insert(QStringLiteral("currentTag"), text(update.value(QStringLiteral("current")).toObject(), "tag"));
    return map;
}

/** A maximum the envelope names, or nothing for "no ceiling of its own". */
bool cap(const QJsonObject &resources, const char *key, double *value)
{
    const QJsonValue raw = resources.value(QLatin1String(key));
    if (!raw.isDouble())
        return false;
    *value = raw.toDouble();
    return true;
}

/** `512 MB`, `2 GB`: the unit somebody would have typed. */
QString megabytes(qint64 mb)
{
    if (mb >= 1024 && mb % 1024 == 0)
        return QCoreApplication::translate("AgentHost", "%1 GB").arg(mb / 1024);
    if (mb >= 1024)
        return QCoreApplication::translate("AgentHost", "%1 GB").arg(QString::number(double(mb) / 1024.0, 'f', 1));
    return QCoreApplication::translate("AgentHost", "%1 MB").arg(mb);
}

QString cores(double value)
{
    return value == double(qint64(value)) ? QString::number(qint64(value)) : QString::number(value, 'f', 2);
}

QVariantList numbers(const QJsonValue &array)
{
    QVariantList list;
    for (const QJsonValue &value : array.toArray())
        list.append(value.toDouble());
    return list;
}

} // namespace

// ---- Envelopes ----------------------------------------------------------------------------

namespace envelope {

QVariantMap toMap(const QJsonObject &resources)
{
    double cpuMax = 0;
    double memoryMax = 0;
    double storageMax = 0;
    double gpuMax = 0;
    const bool cpuCapped = cap(resources, "cpu_cores_max", &cpuMax);
    const bool memoryCapped = cap(resources, "memory_mb_max", &memoryMax);
    const bool storageCapped = cap(resources, "storage_mb_max", &storageMax);
    // A ceiling alone: nothing reserves a card's memory. Absent from an older service, which is all of it.
    const bool gpuCapped = cap(resources, "gpu_memory_mb_max", &gpuMax);
    // The `capped` flags travel with the numbers: a maximum of zero and no maximum are different facts.
    return QVariantMap{
        {QStringLiteral("cpuMin"), resources.value(QStringLiteral("cpu_cores_min")).toDouble()},
        {QStringLiteral("cpuMax"), cpuMax},
        {QStringLiteral("cpuCapped"), cpuCapped},
        {QStringLiteral("memoryMin"), resources.value(QStringLiteral("memory_mb_min")).toDouble()},
        {QStringLiteral("memoryMax"), memoryMax},
        {QStringLiteral("memoryCapped"), memoryCapped},
        {QStringLiteral("storageMin"), resources.value(QStringLiteral("storage_mb_min")).toDouble()},
        {QStringLiteral("storageMax"), storageMax},
        {QStringLiteral("storageCapped"), storageCapped},
        {QStringLiteral("gpuMax"), gpuMax},
        {QStringLiteral("gpuCapped"), gpuCapped},
    };
}

QString summary(const QJsonObject &resources)
{
    double cpuMax = 0;
    double memoryMax = 0;
    const double cpuMin = resources.value(QStringLiteral("cpu_cores_min")).toDouble();
    const qint64 memoryMin = number(resources, "memory_mb_min");
    const QString cpu =
        cap(resources, "cpu_cores_max", &cpuMax)
            ? QCoreApplication::translate("AgentHost", "%1–%2 cores").arg(cores(cpuMin), cores(cpuMax))
            : QCoreApplication::translate("AgentHost", "%1+ cores").arg(cores(cpuMin));
    const QString memory = cap(resources, "memory_mb_max", &memoryMax)
                               ? QCoreApplication::translate("AgentHost", "%1–%2")
                                     .arg(megabytes(memoryMin), megabytes(qint64(memoryMax)))
                               : QCoreApplication::translate("AgentHost", "%1+").arg(megabytes(memoryMin));
    // All of the card is what every agent had before the ceiling existed; only a limit is worth the words.
    double gpuMax = 0;
    if (cap(resources, "gpu_memory_mb_max", &gpuMax))
        return QCoreApplication::translate("AgentHost", "%1 · %2 · up to %3 of graphics memory")
            .arg(cpu, memory, megabytes(qint64(gpuMax)));
    return QCoreApplication::translate("AgentHost", "%1 · %2").arg(cpu, memory);
}

} // namespace envelope

// ---- HostedAgentModel ---------------------------------------------------------------------

namespace {

HostedAgentModel::ContainerState containerState(const QJsonObject &agent)
{
    static const QStringList names{
        QStringLiteral("unknown"),  QStringLiteral("starting"),      QStringLiteral("running"),
        QStringLiteral("stopped"),  QStringLiteral("image_missing"), QStringLiteral("image_untrusted"),
        QStringLiteral("conflict"), QStringLiteral("failed"),        QStringLiteral("unavailable")};
    const qsizetype index = names.indexOf(text(agent.value(QStringLiteral("container")).toObject(), "state"));
    return HostedAgentModel::ContainerState(index < 0 ? 0 : index);
}

} // namespace

HostedAgentModel::HostedAgentModel(QObject *parent)
    : KeyedRowsModel("id", parent)
{
}

void HostedAgentModel::apply(const QJsonObject &roster)
{
    if (roster == m_roster)
        return;
    m_roster = roster;
    QList<QJsonObject> agents;
    for (const QJsonValue &value : roster.value(QStringLiteral("items")).toArray())
        agents.append(value.toObject());
    reconcile(agents);
    Q_EMIT rosterChanged();
}

QHash<int, QByteArray> HostedAgentModel::roleNames() const
{
    return {
        {IdRole, "agentId"},
        {SlugRole, "slug"},
        {TitleRole, "title"},
        {TaglineRole, "tagline"},
        {AvatarUrlRole, "avatarUrl"},
        {SlotIdRole, "slotId"},
        {SlotCodenameRole, "slotCodename"},
        {SlotTitleRole, "slotTitle"},
        {ResourcesRole, "resourcesText"},
        {EnvelopeRole, "envelope"},
        {AccessRequestsRole, "accessRequests"},
        {AccessRequestCountRole, "accessRequestCount"},
        {HasInitialScriptRole, "hasInitialScript"},
        {FeatureKeysRole, "featureKeys"},
        {PublicTokenRole, "publicToken"},
        {LifecycleRole, "lifecycle"},
        {ContainerNameRole, "containerName"},
        {ContainerStateRole, "containerState"},
        {ContainerStateNameRole, "containerStateName"},
        {ContainerIdRole, "containerId"},
        {ContainerDetailRole, "containerDetail"},
        {ContainerImageRole, "containerImage"},
        {RunningRole, "running"},
        {UpdateRole, "update"},
        {CanManageRole, "canManage"},
    };
}

QVariant HostedAgentModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &agent = row(index.row());
    const QJsonObject slot = agent.value(QStringLiteral("virtual_machine")).toObject();
    const QJsonObject lifecycle = agent.value(QStringLiteral("lifecycle")).toObject();
    const QJsonObject container = agent.value(QStringLiteral("container")).toObject();
    const QJsonObject resources = slot.value(QStringLiteral("resources")).toObject();

    switch (role) {
    case IdRole:
        return int(number(agent, "id"));
    case SlugRole:
        return text(agent, "slug");
    case TitleRole:
        return text(agent, "title");
    case TaglineRole:
        return text(agent, "tagline");
    case AvatarUrlRole:
        // As the Hub sent it: a path with no host on it, which the cache resolves
        // against the API this computer is talking to. Empty for an agent with none.
        return text(agent, "avatar_url");
    case SlotIdRole:
        return int(number(slot, "id"));
    case SlotCodenameRole:
        return text(slot, "slug");
    case SlotTitleRole:
        return text(slot, "title");
    case ResourcesRole:
        return envelope::summary(resources);
    case EnvelopeRole:
        return envelope::toMap(resources);
    case AccessRequestsRole: {
        // The settings are handed over as they came: what a permission's fields mean is the catalogue's business.
        QVariantList requests;
        for (const QJsonValue &value : slot.value(QStringLiteral("access_requests")).toArray()) {
            const QJsonObject request = value.toObject();
            requests.append(QVariantMap{
                {QStringLiteral("accessKey"), text(request, "access_key")},
                {QStringLiteral("machineCategoryKeys"),
                 request.value(QStringLiteral("machine_category_keys")).toArray().toVariantList()},
                {QStringLiteral("reason"), text(request, "reason")},
                {QStringLiteral("settings"), request.value(QStringLiteral("settings")).toObject().toVariantMap()},
            });
        }
        return requests;
    }
    case AccessRequestCountRole:
        return int(slot.value(QStringLiteral("access_requests")).toArray().size());
    case HasInitialScriptRole:
        return agent.value(QStringLiteral("has_initial_script")).toBool();
    case FeatureKeysRole:
        return agent.value(QStringLiteral("feature_keys")).toArray().toVariantList();
    case PublicTokenRole:
        return text(agent, "public_token");
    case LifecycleRole: {
        const QString status = text(lifecycle, "status");
        return QVariantMap{
            {QStringLiteral("status"), status},
            {QStringLiteral("reason"), text(lifecycle, "reason")},
            {QStringLiteral("reasonLabel"), text(lifecycle, "reason_label")},
            {QStringLiteral("detail"), text(lifecycle, "detail")},
            {QStringLiteral("online"), status == QLatin1String("ONLINE")},
            {QStringLiteral("mayAutoStart"), lifecycle.value(QStringLiteral("may_auto_start")).toBool()},
            // Placed here and never started: waiting for somebody to press Start.
            {QStringLiteral("notStarted"),
             status == QLatin1String("OFFLINE")
                 && (text(lifecycle, "reason").isEmpty() || text(lifecycle, "reason") == QLatin1String("NEVER_STARTED"))},
        };
    }
    case CanManageRole:
        return agent.value(QStringLiteral("can_manage")).toBool();
    case ContainerNameRole:
        return text(container, "container_name");
    case ContainerStateRole:
        return int(containerState(agent));
    case ContainerStateNameRole:
        // Hyphenated, as the agents screens' state table spells them.
        return text(container, "state").isEmpty()
                   ? QStringLiteral("unknown")
                   : text(container, "state").replace(QLatin1Char('_'), QLatin1Char('-'));
    case ContainerIdRole:
        return text(container, "container_id");
    case ContainerDetailRole:
        return text(container, "detail");
    case ContainerImageRole:
        return text(container.value(QStringLiteral("record")).toObject(), "image");
    case RunningRole:
        return containerState(agent) == Running;
    case UpdateRole:
        return updateMap(agent);
    default:
        return {};
    }
}

int HostedAgentModel::rowOf(int agentId) const
{
    for (int index = 0; index < rowCount(); ++index) {
        if (number(row(index), "id") == agentId)
            return index;
    }
    return -1;
}

int HostedAgentModel::runningCount() const
{
    int running = 0;
    for (int index = 0; index < rowCount(); ++index) {
        if (containerState(row(index)) == Running)
            ++running;
    }
    return running;
}

QVariantList HostedAgentModel::updates() const
{
    QVariantList updates;
    for (int index = 0; index < rowCount(); ++index) {
        const QJsonObject &agent = row(index);
        const QVariantMap update = updateMap(agent);
        if (!update.value(QStringLiteral("available")).toBool())
            continue;
        updates.append(QVariantMap{
            {QStringLiteral("agentId"), int(number(agent, "id"))},
            {QStringLiteral("title"), text(agent, "title")},
            {QStringLiteral("tag"), update.value(QStringLiteral("tag"))},
            {QStringLiteral("releaseTitle"), update.value(QStringLiteral("title"))},
            {QStringLiteral("releaseExcerpt"), update.value(QStringLiteral("excerpt"))},
            {QStringLiteral("private"), update.value(QStringLiteral("private"))},
        });
    }
    return updates;
}

QVariantList HostedAgentModel::busyAgentIds() const
{
    QVariantList busy;
    for (int index = 0; index < rowCount(); ++index) {
        const ContainerState state = containerState(row(index));
        if (state == Running || state == Starting)
            busy.append(int(number(row(index), "id")));
    }
    return busy;
}

bool HostedAgentModel::contains(int agentId) const
{
    return rowOf(agentId) >= 0;
}

QVariantMap HostedAgentModel::byId(int agentId) const
{
    return at(rowOf(agentId));
}

// ---- HostedVirtualMachineModel ------------------------------------------------------------

HostedVirtualMachineModel::HostedVirtualMachineModel(QObject *parent)
    : KeyedRowsModel("id", parent)
{
}

void HostedVirtualMachineModel::apply(const QJsonObject &roster)
{
    QList<QJsonObject> machines;
    for (const QJsonValue &value : roster.value(QStringLiteral("items")).toArray())
        machines.append(value.toObject());
    reconcile(machines);
    const QJsonObject aggregates = roster.value(QStringLiteral("aggregates")).toObject();
    if (aggregates == m_aggregates)
        return;
    m_aggregates = aggregates;
    Q_EMIT aggregateChanged();
}

QHash<int, QByteArray> HostedVirtualMachineModel::roleNames() const
{
    return {
        {IdRole, "machineId"},          {CodenameRole, "codename"},
        {TitleRole, "title"},           {DescriptionRole, "description"},
        {AgentIdRole, "agentId"},       {AgentSlugRole, "agentSlug"},
        {AgentTitleRole, "agentTitle"}, {PrimaryRole, "isAgentPrimary"},
        {OnlineRole, "online"},         {ResourcesTextRole, "resourcesText"},
        {EnvelopeRole, "envelope"},
    };
}

QVariant HostedVirtualMachineModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &machine = row(index.row());
    const QJsonObject resources = machine.value(QStringLiteral("resources")).toObject();
    switch (role) {
    case IdRole:
        return int(number(machine, "id"));
    case CodenameRole:
        return text(machine, "slug");
    case TitleRole:
        return text(machine, "title");
    case DescriptionRole:
        return text(machine, "description");
    case AgentIdRole:
        return int(number(machine, "agent_id"));
    case AgentSlugRole:
        return text(machine, "agent_slug");
    case AgentTitleRole:
        return text(machine, "agent_title");
    case PrimaryRole:
        return machine.value(QStringLiteral("is_agent_primary")).toBool();
    case OnlineRole:
        return machine.value(QStringLiteral("online")).toBool();
    case ResourcesTextRole:
        return envelope::summary(resources);
    case EnvelopeRole:
        return envelope::toMap(resources);
    default:
        return {};
    }
}

int HostedVirtualMachineModel::onlineCount() const
{
    return int(number(m_aggregates, "online_count"));
}

double HostedVirtualMachineModel::committedCpuCores() const
{
    return m_aggregates.value(QStringLiteral("committed_cpu_cores")).toDouble();
}

qint64 HostedVirtualMachineModel::committedMemoryMb() const
{
    return number(m_aggregates, "committed_memory_mb");
}

qint64 HostedVirtualMachineModel::committedStorageMb() const
{
    return number(m_aggregates, "committed_storage_mb");
}

double HostedVirtualMachineModel::ceilingCpuCores() const
{
    return m_aggregates.value(QStringLiteral("ceiling_cpu_cores")).toDouble();
}

qint64 HostedVirtualMachineModel::ceilingMemoryMb() const
{
    return number(m_aggregates, "ceiling_memory_mb");
}

bool HostedVirtualMachineModel::anyUncapped() const
{
    return m_aggregates.value(QStringLiteral("any_uncapped")).toBool();
}

// ---- AgentContainersModel -----------------------------------------------------------------

AgentContainersModel::AgentContainersModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_roster(session->subscribe(QStringLiteral("agents.roster")))
{
    const auto apply = [this](const QJsonObject &roster) {
        settleStarts(roster);
        const QJsonObject value{{QStringLiteral("agent_image"), roster.value(QStringLiteral("agent_image"))},
                                {QStringLiteral("reconciling"), roster.value(QStringLiteral("reconciling"))}};
        if (value == m_value)
            return;
        m_value = value;
        Q_EMIT changed();
    };
    connect(m_roster, &client::TopicSubscription::received, this, apply);
    if (m_roster->hasValue())
        apply(m_roster->value());
}

bool AgentContainersModel::isReconciling() const
{
    return m_value.value(QStringLiteral("reconciling")).toBool();
}

void AgentContainersModel::reconcile()
{
    m_session->post(QStringLiteral("/v1/agents/reconcile"));
}

QVariantList AgentContainersModel::starting() const
{
    QVariantList ids;
    for (const int id : m_starting)
        ids.append(id);
    return ids;
}

void AgentContainersModel::start(int agentId)
{
    if (agentId <= 0 || m_starting.contains(agentId))
        return;
    m_starting.insert(agentId);
    m_startErrors.remove(QString::number(agentId));
    Q_EMIT startsChanged();
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/agents/%1/lifecycle").arg(agentId),
                                          {{QStringLiteral("action"), QStringLiteral("START")}});
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        if (!reply->isError()) {
            // Busy until the roster says ONLINE: the platform's frame is what moves the container.
            settleStarts(m_roster->value());
            return;
        }
        m_starting.remove(agentId);
        m_startErrors.insert(QString::number(agentId), reply->problem().message());
        Q_EMIT startsChanged();
    });
}

void AgentContainersModel::settleStarts(const QJsonObject &roster)
{
    if (m_starting.isEmpty())
        return;
    QSet<int> placed;
    QSet<int> online;
    for (const QJsonValue &value : roster.value(QStringLiteral("items")).toArray()) {
        const QJsonObject agent = value.toObject();
        const int id = int(number(agent, "id"));
        placed.insert(id);
        if (text(agent.value(QStringLiteral("lifecycle")).toObject(), "status") == QLatin1String("ONLINE"))
            online.insert(id);
    }
    bool moved = false;
    for (auto it = m_starting.begin(); it != m_starting.end();) {
        if (!placed.contains(*it) || online.contains(*it)) {
            it = m_starting.erase(it);
            moved = true;
        } else {
            ++it;
        }
    }
    if (moved)
        Q_EMIT startsChanged();
}

void AgentContainersModel::clearStartFailures(int agentId)
{
    if (agentId > 0) {
        m_session->post(QStringLiteral("/v1/agents/%1/clear-failures").arg(agentId));
        return;
    }
    const QJsonArray agents = m_roster->value().value(QStringLiteral("items")).toArray();
    for (const QJsonValue &agent : agents) {
        if (agent.toObject().value(QStringLiteral("start_failures")).toObject().value(QStringLiteral("count")).toInt()
            > 0)
            m_session->post(QStringLiteral("/v1/agents/%1/clear-failures").arg(number(agent.toObject(), "id")));
    }
}

// ---- AgentLifecycleModel ------------------------------------------------------------------

AgentLifecycleModel::AgentLifecycleModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_roster(session->subscribe(QStringLiteral("agents.roster")))
{
    // A decision made anywhere reaches the roster; the open agent's controls follow it.
    connect(m_roster, &client::TopicSubscription::received, this, [this](const QJsonObject &roster) {
        if (m_agentId <= 0 || isBusy())
            return;
        for (const QJsonValue &value : roster.value(QStringLiteral("items")).toArray()) {
            const QJsonObject agent = value.toObject();
            if (number(agent, "id") != m_agentId)
                continue;
            bool moved = false;
            const QJsonObject lifecycle = agent.value(QStringLiteral("lifecycle")).toObject();
            if (text(lifecycle, "status") != status() || text(lifecycle, "reason") != reason()) {
                m_lifecycle = lifecycle;
                moved = true;
            }
            /*
              Whether this person may act on it, as the Hub last worked it out:
              a role changed in the panel moves the controls here without a
              reload. A Hub that does not say leaves the platform's answer.
            */
            const QJsonValue manage = agent.value(QStringLiteral("can_manage"));
            if (manage.isBool() && manage.toBool() != m_canManage) {
                m_canManage = manage.toBool();
                moved = true;
            }
            if (moved)
                Q_EMIT changed();
        }
    });
}

QString AgentLifecycleModel::status() const
{
    return text(m_lifecycle, "status");
}

QString AgentLifecycleModel::reason() const
{
    return text(m_lifecycle, "reason");
}

void AgentLifecycleModel::open(int agentId)
{
    if (agentId == m_agentId)
        return;
    m_agentId = agentId;
    m_canManage = false;
    m_lifecycle = {};
    m_message.clear();
    m_lastError.clear();
    Q_EMIT changed();
    refresh();
}

void AgentLifecycleModel::close()
{
    open(0);
}

void AgentLifecycleModel::refresh()
{
    if (m_agentId <= 0)
        return;
    const int agentId = m_agentId;
    ++m_requests;
    Q_EMIT changed();
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/agents/%1/lifecycle").arg(agentId));
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        --m_requests;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return; // another agent was opened meanwhile
        }
        if (reply->isError()) {
            // Signed out is not something to say beside a stop button; the controls simply stay hidden.
            if (reply->problem().code != QLatin1String("SESSION_REQUIRED"))
                m_lastError = reply->problem().message();
        } else {
            const QJsonObject answer = reply->object();
            m_canManage = answer.value(QStringLiteral("can_manage")).toBool();
            m_lifecycle = answer.value(QStringLiteral("lifecycle")).toObject();
        }
        Q_EMIT changed();
    });
}

void AgentLifecycleModel::start()
{
    act(QStringLiteral("START"));
}

void AgentLifecycleModel::stop()
{
    act(QStringLiteral("STOP"));
}

void AgentLifecycleModel::reboot()
{
    act(QStringLiteral("REBOOT"));
}

void AgentLifecycleModel::act(const QString &action)
{
    if (m_agentId <= 0 || isBusy())
        return;
    const int agentId = m_agentId;
    ++m_requests;
    m_message.clear();
    m_lastError.clear();
    Q_EMIT changed();
    ServiceReply *reply =
        m_session->post(QStringLiteral("/v1/agents/%1/lifecycle").arg(agentId), {{QStringLiteral("action"), action}});
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId, action] {
        --m_requests;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return;
        }
        if (reply->isError()) {
            m_lastError = reply->problem().message();
            Q_EMIT changed();
            return;
        }
        const QJsonObject result = reply->object();
        m_lifecycle = result.value(QStringLiteral("lifecycle")).toObject();
        // Already phrased for a person, including a decision stored with no computer reachable to act on it.
        m_message = text(result, "detail");
        Q_EMIT changed();
        /*
          The platform's own word for the decision, unchanged.

          Not lowercased: the one thing listening compares it against `START`,
          `STOP` and `REBOOT`, and a word that matched none of them would leave
          the strip on the agent's page on its default, which says *starting*.
          One vocabulary, and it is the API's.
        */
        Q_EMIT acted(agentId, action);
    });
}

// ---- AgentSettingsModel -------------------------------------------------------------------

AgentSettingsModel::AgentSettingsModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_roster(session->subscribe(QStringLiteral("agents.roster")))
{
    /*
      The offer moves on the roster: `desktop.agent.update.available` puts it on
      the agent's row, and an update or a new release moves it again. The page
      reads the platform once more when it does, because whether this person may
      apply the new offer is the platform's answer, not the row's.
    */
    connect(m_roster, &client::TopicSubscription::received, this, [this](const QJsonObject &roster) {
        if (m_agentId <= 0)
            return;
        for (const QJsonValue &value : roster.value(QStringLiteral("items")).toArray()) {
            const QJsonObject agent = value.toObject();
            if (number(agent, "id") != m_agentId)
                continue;
            const QJsonValue update = agent.value(QStringLiteral("update"));
            if (update != m_rowUpdate) {
                const bool first = m_rowUpdate.isUndefined();
                m_rowUpdate = update;
                if (!first && !m_updating)
                    refresh();
            }
        }
    });
}

bool AgentSettingsModel::installed() const
{
    return m_state.value(QStringLiteral("installed")).toBool();
}

bool AgentSettingsModel::canUpdate() const
{
    return m_state.value(QStringLiteral("can_update")).toBool();
}

QString AgentSettingsModel::blockedReason() const
{
    return text(m_state, "blocked_reason");
}

QString AgentSettingsModel::source() const
{
    return text(m_state.value(QStringLiteral("source")).toObject(), "specifier");
}

bool AgentSettingsModel::sourcePrivate() const
{
    return m_state.value(QStringLiteral("source")).toObject().value(QStringLiteral("private")).toBool();
}

QVariantMap AgentSettingsModel::current() const
{
    return releaseMap(m_state.value(QStringLiteral("current")).toObject());
}

QVariantMap AgentSettingsModel::available() const
{
    return releaseMap(
        m_state.value(QStringLiteral("update")).toObject().value(QStringLiteral("available")).toObject());
}

QVariantList AgentSettingsModel::releases() const
{
    QVariantList list;
    for (const QJsonValue &entry : m_state.value(QStringLiteral("releases")).toArray()) {
        const QJsonObject release = entry.toObject();
        QVariantMap map = releaseMap(release);
        if (map.isEmpty())
            continue;
        map.insert(QStringLiteral("isDeprecated"), release.value(QStringLiteral("is_deprecated")).toBool());
        list.append(map);
    }
    return list;
}

int AgentSettingsModel::releasesTotal() const
{
    const QJsonValue total = m_state.value(QStringLiteral("releases_total"));
    return total.isDouble() ? total.toInt() : int(m_state.value(QStringLiteral("releases")).toArray().size());
}

void AgentSettingsModel::open(int agentId)
{
    if (agentId == m_agentId)
        return;
    m_agentId = agentId;
    m_state = {};
    m_rowUpdate = QJsonValue(QJsonValue::Undefined);
    m_message.clear();
    m_warnings.clear();
    m_lastError.clear();
    Q_EMIT changed();
    refresh();
}

void AgentSettingsModel::close()
{
    open(0);
}

void AgentSettingsModel::refresh()
{
    if (m_agentId <= 0)
        return;
    const int agentId = m_agentId;
    ++m_reading;
    Q_EMIT changed();
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/agents/%1/update").arg(agentId));
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        --m_reading;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return; // another agent was opened meanwhile
        }
        if (reply->isError()) {
            // Signed out is not something to say on a settings page; the sections simply stay empty.
            if (reply->problem().code != QLatin1String("SESSION_REQUIRED"))
                m_lastError = reply->problem().message();
        } else {
            m_state = reply->object();
        }
        Q_EMIT changed();
    });
}

void AgentSettingsModel::applyUpdate()
{
    const qint64 release = number(
        m_state.value(QStringLiteral("update")).toObject().value(QStringLiteral("available")).toObject(),
        "artifact_tag_id");
    if (m_agentId <= 0 || release <= 0 || m_updating || m_uninstalling)
        return;
    const int agentId = m_agentId;
    m_updating = true;
    m_message.clear();
    m_warnings.clear();
    m_lastError.clear();
    Q_EMIT changed();
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/agents/%1/update").arg(agentId),
                                          {{QStringLiteral("artifact_tag_id"), release}});
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        m_updating = false;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return;
        }
        if (reply->isError()) {
            // The platform's own sentence, carried as the detail: not an admin, no longer installable, a newer offer.
            m_lastError = reply->problem().message();
            Q_EMIT changed();
            refresh();
            return;
        }
        const QJsonObject result = reply->object();
        m_message = text(result, "detail");
        for (const QJsonValue &warning : result.value(QStringLiteral("warnings")).toArray())
            m_warnings.append(warning.toString());
        const bool rebooted = result.value(QStringLiteral("rebooted")).toBool();
        Q_EMIT changed();
        Q_EMIT updated(agentId, rebooted);
        refresh();
    });
}

void AgentSettingsModel::uninstall()
{
    if (m_agentId <= 0 || m_updating || m_uninstalling)
        return;
    const int agentId = m_agentId;
    m_uninstalling = true;
    m_message.clear();
    m_warnings.clear();
    m_lastError.clear();
    Q_EMIT changed();
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/agents/%1/uninstall").arg(agentId));
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        m_uninstalling = false;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return;
        }
        if (reply->isError()) {
            m_lastError = reply->problem().message();
            Q_EMIT changed();
            return;
        }
        m_message = text(reply->object(), "detail");
        Q_EMIT changed();
        Q_EMIT uninstalled(agentId);
    });
}

// ---- AgentDependenciesModel ---------------------------------------------------------------

AgentDependenciesModel::AgentDependenciesModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
{
}

QString AgentDependenciesModel::path() const
{
    return QStringLiteral("/v1/proxy/back/api/v1/platform/agent/%1/dependencies").arg(m_agentId);
}

QString AgentDependenciesModel::engineVersion() const
{
    return text(m_state, "engine_version");
}

bool AgentDependenciesModel::canManage() const
{
    return m_state.value(QStringLiteral("can_manage")).toBool();
}

QVariantList AgentDependenciesModel::dependencies() const
{
    QVariantList list;
    for (const QJsonValue &value : m_state.value(QStringLiteral("dependencies")).toArray()) {
        const QJsonObject row = value.toObject();
        const QJsonObject update = row.value(QStringLiteral("update")).toObject();
        list.append(QVariantMap{
            {QStringLiteral("specifier"), text(row, "specifier")},
            {QStringLiteral("tag"), text(row, "tag")},
            {QStringLiteral("updateTag"), text(update, "tag")},
            {QStringLiteral("updateNotes"), text(update, "notes")},
        });
    }
    return list;
}

int AgentDependenciesModel::movable() const
{
    int count = 0;
    for (const QJsonValue &value : m_state.value(QStringLiteral("dependencies")).toArray())
        count += value.toObject().value(QStringLiteral("update")).isObject() ? 1 : 0;
    return count;
}

void AgentDependenciesModel::open(int agentId)
{
    if (agentId == m_agentId)
        return;
    if (m_resources != nullptr)
        m_session->release(std::exchange(m_resources, nullptr));
    m_agentId = agentId;
    m_state = {};
    m_outcome.clear();
    m_lastError.clear();
    Q_EMIT changed();
    if (m_agentId <= 0)
        return;
    /*
      The lock moves where this page cannot see it: an include resolved for the
      first time, somebody's Update or Forget unused on another screen. The
      service relays the Hub's word of it for the agent open here, and the list
      is read again then, never on a timer.
    */
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("agent_id"), QString::number(m_agentId));
    m_resources = m_session->subscribe(QStringLiteral("agents.resource"), params);
    connect(m_resources, &client::TopicSubscription::received, this, [this](const QJsonObject &event) {
        if (text(event, "resource") == QLatin1String("LOCK") && number(event, "agent_id") == m_agentId && !m_busy)
            refresh();
    });
    refresh();
}

void AgentDependenciesModel::close()
{
    open(0);
}

void AgentDependenciesModel::refresh()
{
    if (m_agentId <= 0)
        return;
    const int agentId = m_agentId;
    ++m_reading;
    Q_EMIT changed();
    ServiceReply *reply = m_session->get(path());
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        --m_reading;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return; // another agent was opened meanwhile
        }
        if (reply->isError()) {
            // Signed out is not something to say on a settings page; the section simply stays empty.
            if (reply->problem().code != QLatin1String("SESSION_REQUIRED"))
                m_lastError = reply->problem().message();
        } else {
            m_state = reply->object();
            m_lastError.clear();
        }
        Q_EMIT changed();
    });
}

void AgentDependenciesModel::update()
{
    if (m_agentId <= 0 || m_busy)
        return;
    const int agentId = m_agentId;
    m_busy = true;
    m_outcome.clear();
    m_lastError.clear();
    Q_EMIT changed();
    ServiceReply *reply = m_session->post(path() + QStringLiteral("/update"));
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId] {
        m_busy = false;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return;
        }
        if (reply->isError()) {
            // The platform's own sentence: not an owner or admin, or an agent with no engine.
            m_lastError = reply->problem().message();
        } else {
            const QJsonObject result = reply->object();
            m_outcome = {
                {QStringLiteral("kind"), QStringLiteral("update")},
                {QStringLiteral("moved"), int(result.value(QStringLiteral("changes")).toArray().size())},
                {QStringLiteral("rebooted"), result.value(QStringLiteral("rebooted")).toBool()},
            };
        }
        Q_EMIT changed();
        refresh();
    });
}

void AgentDependenciesModel::forgetUnused(int days)
{
    if (m_agentId <= 0 || m_busy || days <= 0)
        return;
    const int agentId = m_agentId;
    m_busy = true;
    m_outcome.clear();
    m_lastError.clear();
    Q_EMIT changed();
    ServiceReply *reply =
        m_session->post(path() + QStringLiteral("/forget-unused"), {{QStringLiteral("older_than_days"), days}});
    connect(reply, &ServiceReply::finished, this, [this, reply, agentId, days] {
        m_busy = false;
        if (agentId != m_agentId) {
            Q_EMIT changed();
            return;
        }
        if (reply->isError()) {
            m_lastError = reply->problem().message();
        } else {
            QStringList forgotten;
            for (const QJsonValue &value : reply->object().value(QStringLiteral("forgotten")).toArray())
                forgotten.append(value.toString());
            m_outcome = {
                {QStringLiteral("kind"), QStringLiteral("forget")},
                {QStringLiteral("forgotten"), forgotten},
                {QStringLiteral("days"), days},
            };
        }
        Q_EMIT changed();
        refresh();
    });
}

// ---- AgentVirtualMachineModel -------------------------------------------------------------

AgentVirtualMachineModel::AgentVirtualMachineModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
{
    connect(m_session, &client::ServiceSession::connected, this, &AgentVirtualMachineModel::loadSteps);
    if (m_session->isConnected())
        loadSteps();
}

void AgentVirtualMachineModel::loadSteps()
{
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/catalog/virtual-machine-steps"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (reply->isError())
            return;
        const QJsonObject steps = reply->object();
        m_cpuSteps = numbers(steps.value(QStringLiteral("cpu_cores")));
        m_memorySteps = numbers(steps.value(QStringLiteral("memory_mb")));
        m_storageSteps = numbers(steps.value(QStringLiteral("storage_mb")));
        m_gpuSteps = numbers(steps.value(QStringLiteral("gpu_memory_mb")));
        Q_EMIT stepsChanged();
    });
}

AgentVirtualMachineModel::Stage AgentVirtualMachineModel::stage() const
{
    if (text(m_state, "state") != QLatin1String("running"))
        return Idle;
    return text(m_state, "stage") == QLatin1String("rebooting") ? Rebooting : Saving;
}

void AgentVirtualMachineModel::applyAndReboot(int agentId, int virtualMachineId, const QVariantMap &envelope)
{
    if (agentId <= 0 || isBusy())
        return;
    // A merge patch: a ceiling that is not capped is null, which removes it.
    const auto pair = [&envelope](QJsonObject *patch, const char *min, const char *max, const char *capped,
                                  const char *minKey, const char *maxKey, bool whole) {
        // No floor for a resource that has none — the graphics card's memory, which nothing reserves.
        const QVariant low = min != nullptr ? envelope.value(QLatin1String(min)) : QVariant();
        if (low.isValid())
            patch->insert(QLatin1String(minKey),
                          whole ? QJsonValue(qint64(low.toDouble())) : QJsonValue(low.toDouble()));
        if (!envelope.contains(QLatin1String(capped)))
            return;
        const double high = envelope.value(QLatin1String(max)).toDouble();
        patch->insert(QLatin1String(maxKey), !envelope.value(QLatin1String(capped)).toBool()
                                                 ? QJsonValue(QJsonValue::Null)
                                             : whole ? QJsonValue(qint64(high))
                                                     : QJsonValue(high));
    };
    QJsonObject patch;
    pair(&patch, "cpuMin", "cpuMax", "cpuCapped", "cpu_cores_min", "cpu_cores_max", false);
    pair(&patch, "memoryMin", "memoryMax", "memoryCapped", "memory_mb_min", "memory_mb_max", true);
    pair(&patch, "storageMin", "storageMax", "storageCapped", "storage_mb_min", "storage_mb_max", true);
    pair(&patch, nullptr, "gpuMax", "gpuCapped", nullptr, "gpu_memory_mb_max", true);

    m_requesting = true;
    m_agentId = agentId;
    m_virtualMachineId = virtualMachineId;
    m_sawRunning = false;
    m_lastError.clear();
    m_message.clear();
    Q_EMIT changed();
    follow(agentId);
    ServiceReply *reply =
        m_session->patch(QStringLiteral("/v1/agents/%1/virtual-machine/resources").arg(agentId), patch);
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_requesting = false;
        if (reply->isError()) {
            m_lastError = reply->problem().message();
            if (m_resize)
                m_session->release(std::exchange(m_resize, nullptr));
            Q_EMIT changed();
            return;
        }
        apply(reply->object());
    });
}

void AgentVirtualMachineModel::follow(int agentId)
{
    if (m_resize)
        m_session->release(std::exchange(m_resize, nullptr));
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("agent_id"), QString::number(agentId));
    m_resize = m_session->subscribe(QStringLiteral("vms.resize"), params);
    connect(m_resize, &client::TopicSubscription::received, this, &AgentVirtualMachineModel::apply);
}

void AgentVirtualMachineModel::apply(const QJsonObject &resize)
{
    if (number(resize, "agent_id") != m_agentId)
        return;
    const QString state = text(resize, "state");
    // What the topic sends on subscribing can be the last resize, finished long ago; only this one's end counts.
    if (state == QLatin1String("running"))
        m_sawRunning = true;
    if (!m_sawRunning)
        return;
    m_state = resize;
    const bool finished = state == QLatin1String("succeeded") || state == QLatin1String("failed");
    if (state == QLatin1String("succeeded")) {
        m_message = text(resize, "message");
        if (m_message.isEmpty())
            m_message = resize.value(QStringLiteral("reboot")).toBool()
                            ? tr("Saved. This agent is restarting on the new size.")
                            : tr("Saved.");
    } else if (state == QLatin1String("failed")) {
        m_lastError = support::problemMessage(resize.value(QStringLiteral("problem")));
    }
    Q_EMIT changed();
    if (!finished)
        return;
    m_sawRunning = false;
    if (m_resize)
        m_session->release(std::exchange(m_resize, nullptr));
    if (state == QLatin1String("succeeded"))
        Q_EMIT applied(m_agentId, m_virtualMachineId);
}

void AgentVirtualMachineModel::forget()
{
    m_lastError.clear();
    m_message.clear();
    Q_EMIT changed();
}

} // namespace simorg::app
