// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/DockerModel.h"

#include "Support.h"
#include "simorg/appmodel/DockerListModels.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QUrl>
#include <QUrlQuery>

#include <utility>

namespace simorg::app {

using client::ServiceReply;
using client::TopicSubscription;
using support::number;
using support::text;

namespace {

QString encoded(const QString &id)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(id));
}

QVariantList historyOf(const QJsonObject &samples, const char *key)
{
    QVariantList values;
    for (const QJsonValue &sample : samples.value(QStringLiteral("history")).toArray())
        values.append(sample.toObject().value(QLatin1String(key)).toDouble());
    return values;
}

} // namespace

DockerModel::DockerModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_containers(new ContainerListModel(this))
    , m_images(new ImageListModel(this))
{
    m_logFeed.model = new DockerLogModel(this);
    m_agentLogFeed.model = new DockerLogModel(this);
    connect(m_session, &client::ServiceSession::connected, this, &DockerModel::refresh);
}

DockerModel::~DockerModel()
{
    closeLogs();
    closeAgentLogs();
}

// ---- Listening ----------------------------------------------------------------------------

void DockerModel::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    listen();
}

void DockerModel::setSummaryActive(bool active)
{
    if (active == m_summaryActive)
        return;
    m_summaryActive = active;
    listen();
}

void DockerModel::watchResources(const QString &who, bool on)
{
    const qsizetype before = m_resourceWatchers.size();
    if (on)
        m_resourceWatchers.insert(who);
    else
        m_resourceWatchers.remove(who);
    if (m_resourceWatchers.size() != before)
        listen();
}

void DockerModel::listen()
{
    const bool anyone = m_active || m_summaryActive || !m_resourceWatchers.isEmpty();
    if (anyone)
        hold(&m_statusTopic, QStringLiteral("docker.status"), &DockerModel::applyStatus);
    else
        drop(&m_statusTopic);

    /*
      The limits are state the service keeps and cost nothing to listen to, and
      whether Docker's share can be resized at all is read from them by the
      Agents overview as well as by the Docker section. Held only while the
      section was open, that overview said "the engine runs on the host's own
      kernel" on every Mac until somebody had visited Docker once.
    */
    if (anyone)
        hold(&m_limitsTopic, QStringLiteral("docker.limits"), &DockerModel::applyLimitsState);
    else
        drop(&m_limitsTopic);

    // The container list and its statistics: the Docker section, and the Agents overview's split per agent.
    if (m_active || !m_resourceWatchers.isEmpty()) {
        hold(&m_snapshotTopic, QStringLiteral("docker.snapshot"), &DockerModel::applySnapshot);
    } else if (m_snapshotTopic) {
        drop(&m_snapshotTopic);
        /*
          What was sampled stops being true the moment nobody samples it, and a
          history with a hole in it would draw the hole as a flat line when the
          next screen starts watching — the same reason the service discards its
          own when sampling stops.
        */
        m_agentUsage.clear();
        m_usageHistory.clear();
        Q_EMIT snapshotChanged();
    }

    if (m_active)
        hold(&m_samplesTopic, QStringLiteral("docker.samples"), &DockerModel::applySamples);
    else
        drop(&m_samplesTopic);
}

void DockerModel::hold(TopicSubscription **slot, const QString &topic,
                       void (DockerModel::*apply)(const QJsonObject &))
{
    if (*slot)
        return;
    *slot = m_session->subscribe(topic);
    connect(*slot, &TopicSubscription::received, this, apply);
    if ((*slot)->hasValue())
        (this->*apply)((*slot)->value());
}

void DockerModel::drop(TopicSubscription **slot)
{
    if (!*slot)
        return;
    disconnect(*slot, nullptr, this, nullptr);
    m_session->release(std::exchange(*slot, nullptr));
}

void DockerModel::refresh()
{
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/docker"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (reply->isError())
            return;
        applyStatus(reply->object());
        /*
          No verdict yet: the service has only just started, and its first probe
          is still running — it probes once at start. What it holds until then
          says where the engine is and nothing about whether it answers, and this
          read is the only one a screen that does not subscribe ever gets, so
          without it the app would say "unknown" about Docker for as long as
          nobody opened a screen that listens. A probe asked for
          now joins the one in flight and answers with its result.
        */
        if (status() == Unknown)
            probeAvailability();
    });
}

/*
  The engine's size, read once each time it becomes ready.

  Every meter in this application is drawn against what Docker has — the Agents
  overview, an agent's own page, its virtual machine — and that figure used to
  arrive only with the Docker section's snapshot. So on a fresh launch those
  screens said "waiting for Docker" about an engine that had been up for hours,
  until somebody happened to open the Docker tab. One request per start of the
  engine is the whole cost, and a resize is a restart, so it is read again then.
*/
void DockerModel::fetchEngineInfo()
{
    if (m_engineInfoPending)
        return;
    m_engineInfoPending = true;
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/docker/info"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_engineInfoPending = false;
        if (reply->isError())
            return;
        const QJsonObject info = reply->object();
        if (info == m_engineInfo)
            return;
        m_engineInfo = info;
        Q_EMIT snapshotChanged();
    });
}

void DockerModel::refreshGpu()
{
    if (m_gpuPending || !isReady())
        return;
    m_gpuPending = true;
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/docker/gpu"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_gpuPending = false;
        if (reply->isError())
            return;
        const QJsonObject gpu = reply->object();
        if (gpu == m_gpu)
            return;
        m_gpu = gpu;
        Q_EMIT gpuChanged();
    });
}

// ---- What the service sends ---------------------------------------------------------------

void DockerModel::applyStatus(const QJsonObject &status)
{
    if (status == m_status)
        return;
    const bool wasReady = isReady();
    m_status = status;
    if (isReady() && (!wasReady || m_engineInfo.isEmpty())) {
        fetchEngineInfo();
        // A new engine may be one with a card: Colima's machine made again as a krunkit one, above all.
        refreshGpu();
    } else if (!isReady() && !m_engineInfo.isEmpty()) {
        m_engineInfo = {};
    }
    Q_EMIT statusChanged();
    // The counts behind the readouts come with the status when the snapshot is not listened to.
    if (!m_snapshotTopic)
        Q_EMIT snapshotChanged();
}

void DockerModel::applySnapshot(const QJsonObject &snapshot)
{
    if (snapshot == m_snapshot) {
        /*
          The same snapshot again is news only to the split per agent, which is
          emptied whenever nobody watches: the next screen to subscribe is sent
          the snapshot it was already holding, and ignoring it left that screen
          without a reading until the next statistics round moved something.
        */
        if (m_agentUsage.isEmpty() && !m_snapshot.value(QStringLiteral("containers")).toArray().isEmpty()) {
            rebuildAgentUsage();
            Q_EMIT snapshotChanged();
        }
        return;
    }
    const bool diskMoved = snapshot.value(QStringLiteral("disk")) != m_snapshot.value(QStringLiteral("disk"));
    m_snapshot = snapshot;
    rebuildAgentUsage();

    QList<QJsonObject> containers;
    for (const QJsonValue &value : snapshot.value(QStringLiteral("containers")).toArray())
        containers.append(value.toObject());
    m_containers->apply(containers);
    QList<QJsonObject> images;
    for (const QJsonValue &value : snapshot.value(QStringLiteral("images")).toArray())
        images.append(value.toObject());
    m_images->apply(images);

    Q_EMIT snapshotChanged();
    if (diskMoved)
        Q_EMIT diskChanged();
}

void DockerModel::applySamples(const QJsonObject &samples)
{
    if (samples == m_samples)
        return;
    m_samples = samples;
    Q_EMIT sampleChanged();
}

void DockerModel::applyLimitsState(const QJsonObject &limits)
{
    if (limits == m_limits)
        return;
    m_limits = limits;
    Q_EMIT limitsChanged();
}

// ---- Readings -----------------------------------------------------------------------------

int DockerModel::status() const
{
    const QString name = text(m_status, "availability");
    if (name == QLatin1String("not_installed"))
        return NotInstalled;
    if (name == QLatin1String("not_running"))
        return NotRunning;
    if (name == QLatin1String("starting"))
        return Starting;
    if (name == QLatin1String("ready"))
        return Ready;
    if (name == QLatin1String("unreachable"))
        return Unreachable;
    return Unknown;
}

bool DockerModel::isInstalled() const
{
    return m_status.value(QStringLiteral("installed")).toBool();
}

bool DockerModel::isProbing() const
{
    return m_status.value(QStringLiteral("probing")).toBool();
}

QString DockerModel::detail() const
{
    return text(m_status, "detail");
}

QString DockerModel::endpoint() const
{
    const QJsonObject endpoint = m_status.value(QStringLiteral("endpoint")).toObject();
    const QString kind = text(endpoint, "kind");
    const QString address = text(endpoint, "address");
    if (kind.isEmpty() || kind == QLatin1String("none"))
        return QStringLiteral("none");
    if (kind == QLatin1String("tcp") && !address.startsWith(QLatin1String("tcp://")))
        return QStringLiteral("tcp://") + address;
    return address;
}

QString DockerModel::clientVersion() const
{
    return text(m_status.value(QStringLiteral("client")).toObject(), "version");
}

QString DockerModel::engineVersion() const
{
    return text(m_status.value(QStringLiteral("engine")).toObject(), "version");
}

QString DockerModel::apiVersion() const
{
    return text(m_status.value(QStringLiteral("engine")).toObject(), "api_version");
}

QString DockerModel::platformName() const
{
    return text(m_status.value(QStringLiteral("engine")).toObject(), "platform_name");
}

QString DockerModel::runtimeTitle() const
{
    return text(m_status, "runtime_title");
}

bool DockerModel::isRuntimeManaged() const
{
    return m_status.value(QStringLiteral("runtime_managed")).toBool();
}

QString DockerModel::manualStartCommand() const
{
    return text(m_status, "manual_start_command");
}

QJsonObject DockerModel::info() const
{
    /*
      Only while the snapshot is listened to. A snapshot is kept after its topic
      is dropped, and reading counts from it then froze the Home tile's
      "containers running" at whatever it was when somebody last left the Docker
      section, while the status went on reporting the live ones.
    */
    if (!m_snapshotTopic)
        return {};
    return m_snapshot.value(QStringLiteral("info")).toObject();
}

int DockerModel::containersTotal() const
{
    // The snapshot's `/info` while the section listens; the status's summary counts otherwise.
    const QJsonObject source = info().isEmpty() ? m_status.value(QStringLiteral("counts")).toObject() : info();
    return int(number(source, "containers_total"));
}

int DockerModel::containersRunning() const
{
    const QJsonObject source = info().isEmpty() ? m_status.value(QStringLiteral("counts")).toObject() : info();
    return int(number(source, "containers_running"));
}

int DockerModel::containersStopped() const
{
    const QJsonObject source = info().isEmpty() ? m_status.value(QStringLiteral("counts")).toObject() : info();
    return int(number(source, "containers_stopped"));
}

int DockerModel::containersPaused() const
{
    const QJsonObject source = info().isEmpty() ? m_status.value(QStringLiteral("counts")).toObject() : info();
    return int(number(source, "containers_paused"));
}

int DockerModel::imageCount() const
{
    const QJsonObject source = info().isEmpty() ? m_status.value(QStringLiteral("counts")).toObject() : info();
    return int(number(source, "images"));
}

qint64 DockerModel::memoryTotal() const
{
    if (const qint64 live = number(info(), "memory_total_bytes"); live > 0)
        return live;
    if (const qint64 read = number(m_engineInfo, "memory_total_bytes"); read > 0)
        return read;
    return number(m_samples, "memory_total_bytes");
}

int DockerModel::engineCpus() const
{
    if (const qint64 live = number(info(), "cpus"); live > 0)
        return int(live);
    if (const qint64 read = number(m_engineInfo, "cpus"); read > 0)
        return int(read);
    return int(number(m_samples, "cpus"));
}

/*
  Every container the service labelled as an agent's, added up per agent.

  An agent is more than its runtime: its network gate, and whatever jobs and
  builders it starts, carry its id too, and all of it is this computer working
  for that agent. Each container is kept as well, so an agent's own page can say
  which of them is using what.

  Built once per snapshot rather than on every read, because the history has to
  be: a point is added when the newest sample in an agent's containers moves on,
  so a snapshot published twice in one statistics round is still one point.
*/
void DockerModel::rebuildAgentUsage()
{
    constexpr qsizetype historyLength = 40;

    QVariantMap usage;
    QHash<qint64, QString> newest;
    const QString environment = m_session->environment();
    for (const QJsonValue &value : m_snapshot.value(QStringLiteral("containers")).toArray()) {
        const QJsonObject container = value.toObject();
        const QJsonObject simorg = container.value(QStringLiteral("simorg")).toObject();
        const qint64 agentId = number(simorg, "agent_id");
        if (agentId <= 0)
            continue;
        /*
          Only this environment's agents. A `dev` and a
          `prod` service can share one engine, their platforms number agents
          independently, and an agent of one wears the same id as an agent of the
          other — so another environment's container was counted as this agent's
          use, and a card that had never started read 47 MB in use. A container
          with no environment label was made before the label existed, by this
          computer's own service.
        */
        const QString madeBy = text(container.value(QStringLiteral("labels")).toObject(), "tech.simorg.environment");
        if (!madeBy.isEmpty() && madeBy != environment)
            continue;
        const QString key = QString::number(agentId);
        QVariantMap row = usage.value(key).toMap();
        const bool running = text(container, "state") == QLatin1String("running");
        const QJsonObject stats = container.value(QStringLiteral("stats")).toObject();
        const bool sampled = running && !stats.isEmpty();
        const double cpu = sampled ? stats.value(QStringLiteral("cpu_percent")).toDouble() : 0.0;
        const qint64 memory = sampled ? number(stats, "memory_usage_bytes") : 0;

        row.insert(QStringLiteral("containers"), row.value(QStringLiteral("containers")).toInt() + 1);
        row.insert(QStringLiteral("running"), row.value(QStringLiteral("running")).toInt() + (running ? 1 : 0));
        row.insert(QStringLiteral("sampled"), row.value(QStringLiteral("sampled")).toBool() || sampled);
        row.insert(QStringLiteral("cpuPercent"), row.value(QStringLiteral("cpuPercent")).toDouble() + cpu);
        row.insert(QStringLiteral("memoryBytes"), row.value(QStringLiteral("memoryBytes")).toLongLong() + memory);

        QVariantList items = row.value(QStringLiteral("items")).toList();
        items.append(QVariantMap{
            {QStringLiteral("name"), text(container, "name")},
            {QStringLiteral("type"), text(simorg, "container_type")},
            {QStringLiteral("state"), text(container, "state")},
            {QStringLiteral("status"), text(container, "status")},
            {QStringLiteral("sampled"), sampled},
            {QStringLiteral("cpuPercent"), cpu},
            {QStringLiteral("memoryBytes"), memory},
        });
        row.insert(QStringLiteral("items"), items);
        usage.insert(key, row);

        const QString at = text(stats, "sampled_at");
        if (sampled && at > newest.value(agentId))
            newest.insert(agentId, at);
    }

    // A point per statistics round, per agent; an agent that has gone takes its history with it.
    QHash<qint64, UsageHistory> kept;
    for (auto it = usage.begin(); it != usage.end(); ++it) {
        const qint64 agentId = it.key().toLongLong();
        UsageHistory history = m_usageHistory.value(agentId);
        QVariantMap row = it.value().toMap();
        const QString at = newest.value(agentId);
        if (!at.isEmpty() && at != history.sampledAt) {
            history.sampledAt = at;
            history.cpu.append(row.value(QStringLiteral("cpuPercent")).toDouble() / 100.0);
            history.memory.append(double(row.value(QStringLiteral("memoryBytes")).toLongLong()) / (1024.0 * 1024.0));
            while (history.cpu.size() > historyLength)
                history.cpu.removeFirst();
            while (history.memory.size() > historyLength)
                history.memory.removeFirst();
        }
        row.insert(QStringLiteral("cpuHistory"), history.cpu);
        row.insert(QStringLiteral("memoryHistory"), history.memory);
        it.value() = row;
        kept.insert(agentId, history);
    }
    m_usageHistory = kept;
    m_agentUsage = usage;
}

double DockerModel::cpuPercent() const
{
    return m_samples.value(QStringLiteral("cpu_percent")).toDouble();
}

qint64 DockerModel::memoryUsed() const
{
    return number(m_samples, "memory_used_bytes");
}

QVariantList DockerModel::cpuHistory() const
{
    return historyOf(m_samples, "cpu_percent");
}

QVariantList DockerModel::memoryHistory() const
{
    return historyOf(m_samples, "memory_used_bytes");
}

QJsonObject DockerModel::diskCategory(const char *name) const
{
    return m_snapshot.value(QStringLiteral("disk")).toObject().value(QLatin1String(name)).toObject();
}

qint64 DockerModel::diskImages() const
{
    return number(diskCategory("images"), "size_bytes");
}

qint64 DockerModel::diskContainers() const
{
    return number(diskCategory("containers"), "size_bytes");
}

qint64 DockerModel::diskVolumes() const
{
    return number(diskCategory("volumes"), "size_bytes");
}

qint64 DockerModel::diskBuildCache() const
{
    return number(diskCategory("build_cache"), "size_bytes");
}

qint64 DockerModel::diskReclaimable() const
{
    return number(m_snapshot.value(QStringLiteral("disk")).toObject(), "reclaimable_bytes");
}

qint64 DockerModel::diskTotal() const
{
    return number(m_snapshot.value(QStringLiteral("disk")).toObject(), "total_bytes");
}

bool DockerModel::isDiskMeasured() const
{
    return m_snapshot.value(QStringLiteral("disk")).isObject();
}

QVariantMap DockerModel::limits() const
{
    const QJsonObject host = m_limits.value(QStringLiteral("host")).toObject();
    const QJsonObject minimum = m_limits.value(QStringLiteral("minimum")).toObject();
    const QJsonObject maximum = m_limits.value(QStringLiteral("maximum")).toObject();
    return QVariantMap{
        {QStringLiteral("managed"), m_limits.value(QStringLiteral("managed")).toBool()},
        {QStringLiteral("runtime"), text(m_limits, "runtime")},
        {QStringLiteral("appliesToOtherEngine"), m_limits.value(QStringLiteral("applies_to_other_engine")).toBool()},
        {QStringLiteral("activeRuntimeTitle"), text(m_limits, "active_runtime_title")},
        {QStringLiteral("managedRuntimeTitle"), text(m_limits, "managed_runtime_title")},
        {QStringLiteral("reason"), text(m_limits, "reason")},
        {QStringLiteral("settingsPath"), text(m_limits, "settings_path")},
        {QStringLiteral("cpus"), int(number(m_limits, "cpus"))},
        {QStringLiteral("memoryMib"), number(m_limits, "memory_mib")},
        {QStringLiteral("diskMib"), number(m_limits, "disk_mib")},
        {QStringLiteral("hostCpus"), int(number(host, "cpus"))},
        {QStringLiteral("hostMemoryMib"), number(host, "memory_mib")},
        {QStringLiteral("hostDiskMib"), number(host, "disk_free_mib")},
        {QStringLiteral("minimumCpus"), int(number(minimum, "cpus", 1))},
        {QStringLiteral("minimumMemoryMib"), number(minimum, "memory_mib")},
        {QStringLiteral("minimumDiskMib"), qMax(number(minimum, "disk_mib"), number(m_limits, "disk_floor_mib"))},
        {QStringLiteral("maximumDiskMib"), number(maximum, "disk_mib")},
        {QStringLiteral("maximumMemoryMib"), number(maximum, "memory_mib")},
        {QStringLiteral("explainer"), text(m_limits, "explainer")},
        {QStringLiteral("storageNote"), text(m_limits, "storage_note")},
    };
}

bool DockerModel::restartPending() const
{
    return m_limits.value(QStringLiteral("restart_pending")).toBool();
}

// ---- Actions ------------------------------------------------------------------------------

void DockerModel::act(const QString &action, ServiceReply *reply, const QString &succeeded)
{
    m_busyAction = action;
    Q_EMIT busyChanged();
    connect(reply, &ServiceReply::finished, this, [this, reply, action, succeeded] {
        if (m_busyAction == action) {
            m_busyAction.clear();
            Q_EMIT busyChanged();
        }
        if (reply->isError()) {
            Q_EMIT actionFailed(action, reply->problem().message());
            return;
        }
        const QJsonObject body = reply->object();
        if (body.contains(QStringLiteral("ok"))) { // a DockerActionResult, phrased by the service
            const QString message = text(body, "message");
            if (body.value(QStringLiteral("ok")).toBool())
                Q_EMIT actionSucceeded(action, message);
            else
                Q_EMIT actionFailed(action, message.isEmpty()
                                                ? support::problemMessage(body.value(QStringLiteral("problem")))
                                                : message);
            return;
        }
        // The engine's status or the limits written: applied now rather than at the next event.
        if (body.contains(QStringLiteral("availability")))
            applyStatus(body);
        if (body.value(QStringLiteral("limits")).isObject())
            applyLimitsState(body.value(QStringLiteral("limits")).toObject());
        if (!succeeded.isEmpty())
            Q_EMIT actionSucceeded(action, succeeded);
    });
}

void DockerModel::probeAvailability()
{
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/docker/probe"));
    // Applied when the probe ends rather than left to the next event: nothing may be listening for one.
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            applyStatus(reply->object());
    });
}

void DockerModel::startEngine()
{
    act(QStringLiteral("start_engine"),
        m_session->post(QStringLiteral("/v1/docker/engine/start"),
                        {{QStringLiteral("elevation"), QStringLiteral("os_prompt")}}));
}

void DockerModel::restartEngine()
{
    act(QStringLiteral("restart_engine"),
        m_session->post(QStringLiteral("/v1/docker/engine/restart"),
                        {{QStringLiteral("elevation"), QStringLiteral("os_prompt")}}),
        tr("Docker is restarting with the new limits."));
}

void DockerModel::containerAction(const QString &id, const QString &action)
{
    if (id.isEmpty())
        return;
    act(action, m_session->post(QStringLiteral("/v1/docker/containers/%1/%2").arg(encoded(id), action)));
}

void DockerModel::startContainer(const QString &id)
{
    containerAction(id, QStringLiteral("start"));
}

void DockerModel::stopContainer(const QString &id)
{
    containerAction(id, QStringLiteral("stop"));
}

void DockerModel::restartContainer(const QString &id)
{
    containerAction(id, QStringLiteral("restart"));
}

void DockerModel::pauseContainer(const QString &id)
{
    containerAction(id, QStringLiteral("pause"));
}

void DockerModel::unpauseContainer(const QString &id)
{
    containerAction(id, QStringLiteral("unpause"));
}

void DockerModel::removeContainer(const QString &id, bool force)
{
    if (id.isEmpty())
        return;
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("force"), force ? QStringLiteral("true") : QStringLiteral("false"));
    act(QStringLiteral("remove_container"),
        m_session->request(QByteArrayLiteral("DELETE"), QStringLiteral("/v1/docker/containers/%1").arg(encoded(id)),
                           {}, query));
}

void DockerModel::removeImage(const QString &id, bool force)
{
    if (id.isEmpty())
        return;
    // The window asked before calling this, which is the confirmation the service wants stated.
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("force"), force ? QStringLiteral("true") : QStringLiteral("false"));
    query.addQueryItem(QStringLiteral("confirm"), QStringLiteral("yes"));
    act(QStringLiteral("remove_image"),
        m_session->request(QByteArrayLiteral("DELETE"), QStringLiteral("/v1/docker/images/%1").arg(encoded(id)), {},
                           query));
}

void DockerModel::reclaim(const QString &what)
{
    act(QStringLiteral("prune"),
        m_session->post(QStringLiteral("/v1/docker/prune"),
                        {{QStringLiteral("what"), what}, {QStringLiteral("confirm"), QStringLiteral("yes")}}));
}

bool DockerModel::applyLimits(int cpus, qint64 memoryMib, qint64 diskMib)
{
    const QVariantMap bounds = limits();
    if (cpus < bounds.value(QStringLiteral("minimumCpus")).toInt()
        || memoryMib < bounds.value(QStringLiteral("minimumMemoryMib")).toLongLong())
        return false;
    // Saved without restarting: the page offers the restart, since it stops every running container.
    QJsonObject update{{QStringLiteral("cpus"), cpus}, {QStringLiteral("memory_mib"), memoryMib}};
    if (diskMib > 0)
        update.insert(QStringLiteral("disk_mib"), diskMib);
    act(QStringLiteral("set_limits"), m_session->put(QStringLiteral("/v1/docker/limits"), update),
        tr("Saved. Restart Docker for the new limits to take effect."));
    return true;
}

void DockerModel::reloadLimits()
{
    m_session->post(QStringLiteral("/v1/docker/limits/reload"));
}

// ---- Logs ---------------------------------------------------------------------------------

void DockerModel::openLogs(const QString &id, const QString &name)
{
    follow(m_logFeed, id, name, &DockerModel::logsChanged);
}

void DockerModel::closeLogs()
{
    stopFollowing(m_logFeed, &DockerModel::logsChanged);
}

void DockerModel::openAgentLogs(const QString &containerId, int agentId)
{
    follow(m_agentLogFeed, containerId, {}, &DockerModel::agentLogsChanged, agentId);
}

void DockerModel::appendUserLog(qint64 agentId, const QString &text, const QDateTime &at)
{
    if (agentId <= 0)
        return;
    QList<UserLine> &lines = m_userLogs[agentId];
    lines.append(UserLine{text, at});
    const int capacity = m_agentLogFeed.model->capacity();
    if (capacity > 0 && lines.size() > capacity)
        lines.remove(0, lines.size() - capacity);
    if (m_agentLogFeed.agentId == agentId && !m_agentLogFeed.containerId.isEmpty())
        m_agentLogFeed.model->insert(text, DockerLogModel::Kind::info, at);
}

void DockerModel::closeAgentLogs()
{
    stopFollowing(m_agentLogFeed, &DockerModel::agentLogsChanged);
}

void DockerModel::follow(LogFeed &feed, const QString &id, const QString &name, void (DockerModel::*changed)(),
                         qint64 agentId)
{
    if (feed.containerId == id && feed.agentId == agentId && !feed.stream.isNull())
        return;
    stopFollowing(feed, changed);
    feed.containerId = id;
    feed.containerName = name;
    feed.agentId = agentId;
    feed.model->clear();
    Q_EMIT(this->*changed)();
    if (id.isEmpty())
        return;

    DockerLogModel *lines = feed.model;
    ServiceReply *stream = nullptr;
    if (agentId > 0) {
        /*
          An agent's log is the service's, not Docker's: Docker keeps none of an
          agent's container, and the
          service follows the agent across its containers.
        */
        for (const UserLine &line : m_userLogs.value(agentId))
            lines->insert(line.text, DockerLogModel::Kind::info, line.at);
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("tail"), QStringLiteral("500"));
        query.addQueryItem(QStringLiteral("follow"), QStringLiteral("true"));
        stream = m_session->request(QByteArrayLiteral("GET"), QStringLiteral("/v1/agents/%1/logs").arg(agentId), {},
                                    query, /*streaming=*/true, /*timeoutMs=*/0);
        connect(stream, &ServiceReply::item, lines, [lines](const QJsonObject &item) {
            const QString type = text(item, "type");
            if (type == QLatin1String("line")) {
                lines->insert(text(item, "text"),
                              text(item, "stream") == QLatin1String("STDERR") ? DockerLogModel::Kind::error
                                                                              : DockerLogModel::Kind::output,
                              QDateTime::fromString(text(item, "at"), Qt::ISODateWithMs));
            } else if (type == QLatin1String("state") && text(item, "state") == QLatin1String("ENDED")) {
                lines->append(DockerModel::tr("— the container is no longer producing output"), false);
            }
        });
    } else {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("limit"), QStringLiteral("500"));
        query.addQueryItem(QStringLiteral("follow"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("timestamps"), QStringLiteral("false"));
        stream = m_session->request(QByteArrayLiteral("GET"),
                                    QStringLiteral("/v1/docker/containers/%1/logs").arg(encoded(id)), {}, query,
                                    /*streaming=*/true, /*timeoutMs=*/0);
        connect(stream, &ServiceReply::item, lines, [lines](const QJsonObject &item) {
            if (text(item, "type") == QLatin1String("line"))
                lines->append(text(item, "text"), text(item, "stream") == QLatin1String("stderr"));
        });
    }
    feed.stream = stream;
    // The feed is a member, so it outlives the stream; a closed or replaced stream is not this one any more.
    LogFeed *owner = &feed;
    connect(stream, &ServiceReply::finished, this, [this, owner, stream, changed] {
        if (owner->stream != stream)
            return;
        owner->stream.clear();
        if (stream->isError())
            owner->model->append(tr("— the log stream ended: %1").arg(stream->problem().message()), true);
        else
            owner->model->append(tr("— the container is no longer producing output"), false);
        Q_EMIT(this->*changed)();
    });
    Q_EMIT(this->*changed)();
}

void DockerModel::stopFollowing(LogFeed &feed, void (DockerModel::*changed)())
{
    if (const QPointer<ServiceReply> stream = std::exchange(feed.stream, nullptr))
        stream->abort();
    if (feed.containerId.isEmpty())
        return;
    feed.containerId.clear();
    feed.containerName.clear();
    Q_EMIT(this->*changed)();
}

// ---- Formatting ---------------------------------------------------------------------------

QString DockerModel::formatBytes(qint64 bytes) const
{
    return dockerformat::bytes(bytes);
}

QString DockerModel::formatPercent(double value) const
{
    return dockerformat::percent(value);
}

QString DockerModel::formatAge(qint64 unixSeconds) const
{
    return dockerformat::age(unixSeconds);
}

QString DockerModel::formatGibibytes(qint64 mib, int decimals) const
{
    return dockerformat::gibibytes(mib, decimals);
}

QString DockerModel::formatMegabytes(double mib) const
{
    return dockerformat::megabytes(mib);
}

QString DockerModel::formatCores(double cores) const
{
    return dockerformat::cores(cores);
}

} // namespace simorg::app
