// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace simorg::client {
class ServiceReply;
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

class ContainerListModel;
class DockerLogModel;
class ImageListModel;

/**
 * The container engine on this computer, as the Docker screens and the readouts
 * on every screen read it off `Docker`.
 *
 * The service probes and polls the engine,
 * and only while somebody listens, so this listens only while a
 * screen shows it: `setSummaryActive` holds `docker.status`, the probe every thirty
 * seconds behind the home tile and the toolbar; `setActive` adds the container
 * list, statistics, disk usage, limits and action results that the Docker section
 * shows; `watchResources` holds the container list and its statistics for the
 * screens that split them per agent — the Agents overview and an agent's own page. The engine's own size is read once
 * whenever it becomes ready, whatever is listening, because every meter in the app
 * is drawn against it. Every action is a request to the service, and its answer is passed on as
 * `actionSucceeded` or `actionFailed`: the outcomes of this app's own requests, so
 * one press is one message.
 */
class DockerModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool ready READ isReady NOTIFY statusChanged)
    Q_PROPERTY(bool installed READ isInstalled NOTIFY statusChanged)
    Q_PROPERTY(bool probing READ isProbing NOTIFY statusChanged)
    Q_PROPERTY(QString detail READ detail NOTIFY statusChanged)
    Q_PROPERTY(QString endpoint READ endpoint NOTIFY statusChanged)
    Q_PROPERTY(QString clientVersion READ clientVersion NOTIFY statusChanged)
    Q_PROPERTY(QString engineVersion READ engineVersion NOTIFY statusChanged)
    Q_PROPERTY(QString apiVersion READ apiVersion NOTIFY statusChanged)
    Q_PROPERTY(QString platformName READ platformName NOTIFY statusChanged)
    Q_PROPERTY(QString runtimeTitle READ runtimeTitle NOTIFY statusChanged)
    Q_PROPERTY(bool runtimeManaged READ isRuntimeManaged NOTIFY statusChanged)
    Q_PROPERTY(QString manualStartCommand READ manualStartCommand NOTIFY statusChanged)

    Q_PROPERTY(int containersTotal READ containersTotal NOTIFY snapshotChanged)
    Q_PROPERTY(int containersRunning READ containersRunning NOTIFY snapshotChanged)
    Q_PROPERTY(int containersStopped READ containersStopped NOTIFY snapshotChanged)
    Q_PROPERTY(int containersPaused READ containersPaused NOTIFY snapshotChanged)
    Q_PROPERTY(int imageCount READ imageCount NOTIFY snapshotChanged)
    Q_PROPERTY(qint64 memoryTotal READ memoryTotal NOTIFY snapshotChanged)
    Q_PROPERTY(int engineCpus READ engineCpus NOTIFY snapshotChanged)
    /**
     * What each agent's containers are using right now, keyed by the agent id as a string:
     * `{cpuPercent, memoryBytes, sampled, containers, running, items, cpuHistory, memoryHistory}`.
     * `items` is each container on its own — `{name, type, state, status, cpuPercent,
     * memoryBytes, sampled}` — and the two histories are the last couple of minutes, kept
     * only while somebody watches. Empty unless the container list is listened to
     * (`setActive` or `watchResources`), because it is only sampled then.
     */
    Q_PROPERTY(QVariantMap agentUsage READ agentUsage NOTIFY snapshotChanged)
    /** Whether {@link agentUsage} is being fed right now. */
    Q_PROPERTY(bool usageSampled READ isUsageSampled NOTIFY snapshotChanged)

    Q_PROPERTY(double cpuPercent READ cpuPercent NOTIFY sampleChanged)
    Q_PROPERTY(qint64 memoryUsed READ memoryUsed NOTIFY sampleChanged)
    Q_PROPERTY(QVariantList cpuHistory READ cpuHistory NOTIFY sampleChanged)
    Q_PROPERTY(QVariantList memoryHistory READ memoryHistory NOTIFY sampleChanged)

    Q_PROPERTY(qint64 diskImages READ diskImages NOTIFY diskChanged)
    Q_PROPERTY(qint64 diskContainers READ diskContainers NOTIFY diskChanged)
    Q_PROPERTY(qint64 diskVolumes READ diskVolumes NOTIFY diskChanged)
    Q_PROPERTY(qint64 diskBuildCache READ diskBuildCache NOTIFY diskChanged)
    Q_PROPERTY(qint64 diskReclaimable READ diskReclaimable NOTIFY diskChanged)
    Q_PROPERTY(qint64 diskTotal READ diskTotal NOTIFY diskChanged)
    Q_PROPERTY(bool diskMeasured READ isDiskMeasured NOTIFY diskChanged)

    /**
     * What an agent allowed the graphics card is given on this computer
     * (`GET /v1/docker/gpu`):
     * `available`, `name`, `detail`, `commands`, `guide`. Empty until the
     * engine is ready and the service has looked.
     */
    Q_PROPERTY(QVariantMap gpu READ gpu NOTIFY gpuChanged)
    Q_PROPERTY(QVariantMap limits READ limits NOTIFY limitsChanged)
    Q_PROPERTY(bool restartPending READ restartPending NOTIFY limitsChanged)

    Q_PROPERTY(simorg::app::ContainerListModel *containers READ containers CONSTANT)
    Q_PROPERTY(simorg::app::ImageListModel *images READ images CONSTANT)
    Q_PROPERTY(simorg::app::DockerLogModel *logs READ logs CONSTANT)
    Q_PROPERTY(QString logContainerId READ logContainerId NOTIFY logsChanged)
    Q_PROPERTY(QString logContainerName READ logContainerName NOTIFY logsChanged)
    Q_PROPERTY(bool logsFollowing READ isFollowingLogs NOTIFY logsChanged)
    /**
     * An agent's page has a log of its own, apart from the Docker section's.
     *
     * One shared stream made the two screens take it from each other, and made
     * the agent's page close its stream every time somebody looked at another
     * pane — so coming back to Logs emptied it and streamed the backlog in again,
     * scrolling from the top to the bottom in front of them. This one stays open
     * for as long as the agent's page is, whichever pane or tab is on screen.
     */
    Q_PROPERTY(simorg::app::DockerLogModel *agentLogs READ agentLogs CONSTANT)
    Q_PROPERTY(QString agentLogContainerId READ agentLogContainerId NOTIFY agentLogsChanged)
    Q_PROPERTY(bool agentLogsFollowing READ isFollowingAgentLogs NOTIFY agentLogsChanged)

    Q_PROPERTY(QString busyAction READ busyAction NOTIFY busyChanged)

public:
    /** QML's `DockerStatus`: the service's `availability`. */
    enum Status {
        Unknown,
        NotInstalled,
        NotRunning,
        Starting,
        Ready,
        Unreachable,
    };
    Q_ENUM(Status)

    explicit DockerModel(client::ServiceSession *session, QObject *parent = nullptr);
    ~DockerModel() override;

    int status() const;
    bool isReady() const { return status() == Ready; }
    bool isInstalled() const;
    bool isProbing() const;
    QString detail() const;
    /** The socket path, the pipe, or `tcp://host:port`; `none` when there is nothing to talk to. */
    QString endpoint() const;
    QString clientVersion() const;
    QString engineVersion() const;
    QString apiVersion() const;
    QString platformName() const;
    QString runtimeTitle() const;
    bool isRuntimeManaged() const;
    QString manualStartCommand() const;

    int containersTotal() const;
    int containersRunning() const;
    int containersStopped() const;
    int containersPaused() const;
    int imageCount() const;
    qint64 memoryTotal() const;
    int engineCpus() const;
    QVariantMap agentUsage() const { return m_agentUsage; }
    bool isUsageSampled() const { return m_snapshotTopic != nullptr; }

    double cpuPercent() const;
    qint64 memoryUsed() const;
    QVariantList cpuHistory() const;
    QVariantList memoryHistory() const;

    qint64 diskImages() const;
    qint64 diskContainers() const;
    qint64 diskVolumes() const;
    qint64 diskBuildCache() const;
    qint64 diskReclaimable() const;
    qint64 diskTotal() const;
    bool isDiskMeasured() const;

    QVariantMap gpu() const { return m_gpu.toVariantMap(); }

    /** What the Resources page binds to, keyed as it always was. */
    QVariantMap limits() const;
    bool restartPending() const;

    ContainerListModel *containers() const { return m_containers; }
    ImageListModel *images() const { return m_images; }
    DockerLogModel *logs() const { return m_logFeed.model; }
    QString logContainerId() const { return m_logFeed.containerId; }
    QString logContainerName() const { return m_logFeed.containerName; }
    bool isFollowingLogs() const { return !m_logFeed.stream.isNull(); }
    DockerLogModel *agentLogs() const { return m_agentLogFeed.model; }
    QString agentLogContainerId() const { return m_agentLogFeed.containerId; }
    bool isFollowingAgentLogs() const { return !m_agentLogFeed.stream.isNull(); }

    /** The action this app asked for and has no answer to yet — `stop`, `prune` — or empty. */
    QString busyAction() const { return m_busyAction; }

    /** Listens to everything the Docker section shows while true. */
    Q_INVOKABLE void setActive(bool active);
    /** Listens to the engine's status while true: the dashboard's readouts. */
    Q_INVOKABLE void setSummaryActive(bool active);
    /**
     * Listens to the containers and their statistics while any screen named here wants them:
     * `who` is the screen, so two of them showing at once cannot switch it off for each other.
     */
    Q_INVOKABLE void watchResources(const QString &who, bool on);
    /**
     * Reads the status once, whether or not a screen listens — and, when the
     * service holds no verdict yet because its first probe is still running,
     * waits for that probe's.
     */
    Q_INVOKABLE void refresh();
    /**
     * Asks the service what this computer can give of its graphics cards. The
     * service keeps its answer for five minutes, so a screen asks whenever it
     * appears and the look runs only when that answer is old.
     */
    Q_INVOKABLE void refreshGpu();
    /**
     * Asks the service to probe now rather than at its next round, joining a
     * probe already in flight, and applies the verdict when it ends.
     */
    Q_INVOKABLE void probeAvailability();
    Q_INVOKABLE void startEngine();
    Q_INVOKABLE void restartEngine();
    Q_INVOKABLE void startContainer(const QString &id);
    Q_INVOKABLE void stopContainer(const QString &id);
    Q_INVOKABLE void restartContainer(const QString &id);
    Q_INVOKABLE void pauseContainer(const QString &id);
    Q_INVOKABLE void unpauseContainer(const QString &id);
    Q_INVOKABLE void removeContainer(const QString &id, bool force);
    Q_INVOKABLE void removeImage(const QString &id, bool force);
    /** `containers`, `images`, `volumes` or `build`: one kind of unused thing at a time. */
    Q_INVOKABLE void reclaim(const QString &what);
    Q_INVOKABLE void openLogs(const QString &id, const QString &name);
    Q_INVOKABLE void closeLogs();
    /**
     * Follows agent `agentId`'s log into {@link agentLogs} while its container is
     * `containerId`; the same container again is a no-op. The log is the
     * service's own record of what the agent's engine wrote
     * (`GET /v1/agents/{id}/logs`),
     * with this app's own `userLog` lines for the agent put where their time puts
     * them.
     */
    Q_INVOKABLE void openAgentLogs(const QString &containerId, int agentId);
    Q_INVOKABLE void closeAgentLogs();
    /**
     * What an agent's include had Simorg Desktop write into that agent's log
     * (`userLog`): kept while this app runs,
     * and shown in the log among the agent's own lines, in the information colour.
     */
    void appendUserLog(qint64 agentId, const QString &text, const QDateTime &at);
    /** False when the numbers are outside what the limits allow, and nothing is sent. */
    Q_INVOKABLE bool applyLimits(int cpus, qint64 memoryMib, qint64 diskMib);
    Q_INVOKABLE void reloadLimits();

    Q_INVOKABLE QString formatBytes(qint64 bytes) const;
    Q_INVOKABLE QString formatPercent(double value) const;
    Q_INVOKABLE QString formatAge(qint64 unixSeconds) const;
    Q_INVOKABLE QString formatGibibytes(qint64 mib, int decimals = 1) const;
    Q_INVOKABLE QString formatMegabytes(double mib) const;
    Q_INVOKABLE QString formatCores(double cores) const;

Q_SIGNALS:
    void statusChanged();
    void snapshotChanged();
    void sampleChanged();
    void diskChanged();
    void limitsChanged();
    void gpuChanged();
    void logsChanged();
    void agentLogsChanged();
    void busyChanged();
    void actionSucceeded(const QString &action, const QString &message);
    void actionFailed(const QString &action, const QString &message);

private:
    void listen();
    void hold(client::TopicSubscription **slot, const QString &topic,
              void (DockerModel::*apply)(const QJsonObject &));
    void drop(client::TopicSubscription **slot);
    void applyStatus(const QJsonObject &status);
    void applySnapshot(const QJsonObject &snapshot);
    void applySamples(const QJsonObject &samples);
    void applyLimitsState(const QJsonObject &limits);
    void fetchEngineInfo();
    void rebuildAgentUsage();
    void act(const QString &action, client::ServiceReply *reply, const QString &succeeded = {});
    void containerAction(const QString &id, const QString &action);
    QJsonObject info() const;
    QJsonObject diskCategory(const char *name) const;

    /** One followed container log: the lines, whose they are, and the stream feeding them. */
    struct LogFeed
    {
        DockerLogModel *model = nullptr;
        QString containerId;
        QString containerName;
        /** The agent whose log this is; 0 for a container's own. */
        qint64 agentId = 0;
        QPointer<client::ServiceReply> stream;
    };
    /** One `userLog` line, kept for its agent. */
    struct UserLine
    {
        QString text;
        QDateTime at;
    };
    void follow(LogFeed &feed, const QString &id, const QString &name, void (DockerModel::*changed)(),
                qint64 agentId = 0);
    void stopFollowing(LogFeed &feed, void (DockerModel::*changed)());

    client::ServiceSession *m_session;
    ContainerListModel *m_containers;
    ImageListModel *m_images;
    LogFeed m_logFeed;
    LogFeed m_agentLogFeed;
    /** Each agent's `userLog` lines, newest last, at most a log's capacity of them. */
    QHash<qint64, QList<UserLine>> m_userLogs;

    bool m_active = false;
    bool m_summaryActive = false;
    QSet<QString> m_resourceWatchers;
    client::TopicSubscription *m_statusTopic = nullptr;
    client::TopicSubscription *m_snapshotTopic = nullptr;
    client::TopicSubscription *m_samplesTopic = nullptr;
    client::TopicSubscription *m_limitsTopic = nullptr;

    QJsonObject m_status;
    /** `GET /v1/docker/info`, read once each time the engine becomes ready: its size, whatever listens. */
    QJsonObject m_engineInfo;
    bool m_engineInfoPending = false;
    /** `GET /v1/docker/gpu`, read with the engine's info and whenever a screen showing it appears. */
    QJsonObject m_gpu;
    bool m_gpuPending = false;
    QJsonObject m_snapshot;
    /** Built from each snapshot while it is listened to; see {@link agentUsage}. */
    QVariantMap m_agentUsage;
    /** Per agent, the last samples and the moment of the newest, so one round is one point. */
    struct UsageHistory
    {
        QVariantList cpu;
        QVariantList memory;
        QString sampledAt;
    };
    QHash<qint64, UsageHistory> m_usageHistory;
    QJsonObject m_samples;
    QJsonObject m_limits;
    QString m_busyAction;
};

} // namespace simorg::app
