// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/HubModel.h"

#include "Support.h"
#include "simorg/appmodel/AgentModels.h"
#include "simorg/appmodel/GraphicsCards.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QTimer>

#include <cmath>

namespace simorg::app {

using support::number;
using support::text;

// ---- ConnectionModel ----------------------------------------------------------------

ConnectionModel::ConnectionModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("hub.connection")))
    , m_countdown(new QTimer(this))
{
    m_countdown->setInterval(1'000);
    connect(m_countdown, &QTimer::timeout, this, &ConnectionModel::tick);
    connect(m_topic, &client::TopicSubscription::received, this, &ConnectionModel::apply);
    // With the service gone there is nobody trying, so nothing to count down to.
    connect(m_session, &client::ServiceSession::disconnected, this, [this] { apply({}); });
}

ConnectionModel::Trouble ConnectionModel::trouble() const
{
    const QString name = text(m_diagnosis, "trouble");
    if (name == QLatin1String("no_network"))
        return Trouble::NoNetwork;
    if (name == QLatin1String("captive_portal"))
        return Trouble::CaptivePortal;
    if (name == QLatin1String("server_unreachable"))
        return Trouble::ServerUnreachable;
    if (name == QLatin1String("server_restarting"))
        return Trouble::ServerRestarting;
    if (name == QLatin1String("server_silent"))
        return Trouble::ServerSilent;
    if (name == QLatin1String("server_refused"))
        return Trouble::ServerRefused;
    if (name == QLatin1String("stopped"))
        return Trouble::Stopped;
    return Trouble::None;
}

bool ConnectionModel::isSevere() const
{
    return text(m_diagnosis, "severity") == QLatin1String("severe");
}

QString ConnectionModel::title() const
{
    return text(m_diagnosis, "title");
}

QString ConnectionModel::detail() const
{
    return text(m_diagnosis, "detail");
}

bool ConnectionModel::isAttempting() const
{
    return m_diagnosis.value(QStringLiteral("attempting")).toBool();
}

int ConnectionModel::attempts() const
{
    return int(number(m_diagnosis, "attempts"));
}

ConnectionModel::Reachability ConnectionModel::reachability() const
{
    const QString name = text(m_diagnosis, "reachability");
    if (name == QLatin1String("offline"))
        return Reachability::Offline;
    if (name == QLatin1String("online"))
        return Reachability::Online;
    return Reachability::Unknown;
}

void ConnectionModel::apply(const QJsonObject &diagnosis)
{
    const bool troubleMoved = diagnosis != m_diagnosis;
    m_diagnosis = diagnosis;

    // The service's own clock says when; the seconds it sent are the fallback for a clock that will not parse.
    m_nextAttemptAt = QDateTime::fromString(text(diagnosis, "next_attempt_at"), Qt::ISODateWithMs);
    const qint64 sentSeconds = number(diagnosis, "retry_in_seconds", -1);
    if (!m_nextAttemptAt.isValid() && sentSeconds >= 0)
        m_nextAttemptAt = QDateTime::currentDateTimeUtc().addSecs(sentSeconds);

    if (troubleMoved)
        Q_EMIT troubleChanged();
    tick();
}

void ConnectionModel::tick()
{
    int seconds = 0;
    if (m_nextAttemptAt.isValid() && !isAttempting()) {
        const qint64 left = QDateTime::currentDateTimeUtc().msecsTo(m_nextAttemptAt);
        seconds = left > 0 ? int(std::ceil(double(left) / 1000.0)) : 0;
    }
    if (seconds > 0 && !m_countdown->isActive())
        m_countdown->start();
    else if (seconds == 0)
        m_countdown->stop();
    if (seconds == m_retryInSeconds)
        return;
    m_retryInSeconds = seconds;
    Q_EMIT countdownChanged();
}

void ConnectionModel::retryNow()
{
    m_session->post(QStringLiteral("/v1/hub/retry"));
}

// ---- HubModel -------------------------------------------------------------------------

namespace {

HubModel::State stateNamed(const QString &name)
{
    if (name == QLatin1String("connecting"))
        return HubModel::State::Connecting;
    if (name == QLatin1String("initializing"))
        return HubModel::State::Initializing;
    if (name == QLatin1String("ready"))
        return HubModel::State::Ready;
    if (name == QLatin1String("reconnecting"))
        return HubModel::State::Reconnecting;
    if (name == QLatin1String("failed"))
        return HubModel::State::Failed;
    return HubModel::State::Idle;
}

} // namespace

HubModel::HubModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_stateTopic(session->subscribe(QStringLiteral("hub.state")))
    , m_identityTopic(session->subscribe(QStringLiteral("machine.identity")))
    , m_connection(new ConnectionModel(session, this))
    , m_agents(new HostedAgentModel(this))
    , m_virtualMachines(new HostedVirtualMachineModel(this))
{
    /*
      Held for the app's life: the rosters change only when the Hub says so, and
      every screen counts from them — the Overview's tiles included.

      Not `hub.state`'s counts, which the service takes from the handshake and
      nothing after it: an agent placed here a minute later would reach the
      Agents tab at once, from these rosters, and leave the Overview saying
      "0 agents" until the next reconnect. A count is the roster it counts,
      "told" when the roster says it is known and "not told yet" (-1) until then.
    */
    client::TopicSubscription *const agents = session->subscribe(QStringLiteral("agents.roster"));
    connect(agents, &client::TopicSubscription::received, this, [this](const QJsonObject &roster) {
        m_agents->apply(roster);
        m_agentsKnown = roster.value(QStringLiteral("known")).toBool();
        recount();
    });
    if (agents->hasValue()) {
        m_agents->apply(agents->value());
        m_agentsKnown = agents->value().value(QStringLiteral("known")).toBool();
    }
    client::TopicSubscription *const machines = session->subscribe(QStringLiteral("vms.roster"));
    connect(machines, &client::TopicSubscription::received, this, [this](const QJsonObject &roster) {
        m_virtualMachines->apply(roster);
        m_virtualMachinesKnown = roster.value(QStringLiteral("known")).toBool();
        recount();
    });
    if (machines->hasValue()) {
        m_virtualMachines->apply(machines->value());
        m_virtualMachinesKnown = machines->value().value(QStringLiteral("known")).toBool();
    }
    m_counted = {agentCount(), virtualMachineCount()};

    connect(m_stateTopic, &client::TopicSubscription::received, this, &HubModel::applyState);
    connect(m_identityTopic, &client::TopicSubscription::received, this, &HubModel::applyIdentity);
    connect(m_session, &client::ServiceSession::disconnected, this, [this] {
        // With the service gone nobody can say what is placed here; the rosters are sent again on reconnecting.
        m_agentsKnown = false;
        m_virtualMachinesKnown = false;
        recount();
        applyState({});
    });
    if (m_stateTopic->hasValue())
        applyState(m_stateTopic->value());
    // Every reading present from the start, blank until the service has one: the card binds to each by name.
    applyIdentity(m_identityTopic->hasValue() ? m_identityTopic->value() : QJsonObject());
}

void HubModel::applyState(const QJsonObject &hub)
{
    if (hub == m_hub)
        return;
    const QJsonObject previous = m_hub;
    m_hub = hub;
    m_state = stateNamed(text(hub, "state"));

    Q_EMIT stateChanged();
    if (previous.value(QStringLiteral("machine")) != hub.value(QStringLiteral("machine")))
        Q_EMIT machineChanged();
}

void HubModel::recount()
{
    const std::pair<int, int> counted{agentCount(), virtualMachineCount()};
    if (counted == m_counted)
        return;
    m_counted = counted;
    Q_EMIT countsChanged();
}

void HubModel::applyIdentity(const QJsonObject &identity)
{
    const QJsonObject computer = identity.value(QStringLiteral("computer")).toObject();
    const auto gb = [](qint64 value) { return value > 0 ? QStringLiteral("%1 GB").arg(value) : QString(); };
    const qint64 memoryMb = number(computer, "memory_mb");
    const qint64 storageGb = number(computer, "storage_gb");
    const qint64 storageFreeGb = number(computer, "storage_free_gb");
    // Null when the service could not ask the system, which is not the same as a computer without a card.
    const QJsonValue gpus = computer.value(QStringLiteral("gpus"));
    const QList<graphicscards::Card> cards = graphicscards::cardsOf(gpus);
    const graphicscards::Card *const mainCard = graphicscards::mainCard(cards);

    // Empty strings rather than placeholders: the card hides a row whose value is blank, which is right for a
    // reading the operating system would not give.
    QVariantMap summary{
        {QStringLiteral("deviceName"), text(computer, "device_name")},
        {QStringLiteral("hostname"), text(computer, "hostname")},
        {QStringLiteral("osName"), text(computer, "os_name")},
        {QStringLiteral("osVersion"), text(computer, "os_version")},
        {QStringLiteral("osBuild"), text(computer, "os_build")},
        {QStringLiteral("architecture"), text(computer, "architecture")},
        {QStringLiteral("locale"), text(computer, "locale")},
        {QStringLiteral("cpuModel"), text(computer, "cpu_model")},
        {QStringLiteral("cpuCores"), int(number(computer, "cpu_cores"))},
        {QStringLiteral("memory"), gb(memoryMb / 1024)},
        {QStringLiteral("storage"),
         storageGb > 0 ? QCoreApplication::translate("Hub", "%1 GB free of %2 GB").arg(storageFreeGb).arg(storageGb)
                       : QString()},
        {QStringLiteral("timezone"), text(computer, "timezone")},
        {QStringLiteral("gpus"), graphicscards::toVariantList(cards)},
        {QStringLiteral("gpusKnown"), gpus.isArray()},
        // The card an agent given the graphics card computes on, in a sentence: `NVIDIA GeForce RTX 4090, 24 GB`.
        {QStringLiteral("graphics"),
         mainCard != nullptr ? graphicscards::describe(*mainCard, QStringLiteral(", ")) : QString()},
        // The same readings unformatted, for the meters: a bar divides numbers, and parsing them back out of a
        // translated sentence would break in the first other locale.
        {QStringLiteral("memoryMb"), memoryMb},
        {QStringLiteral("storageGb"), storageGb},
        {QStringLiteral("storageFreeGb"), storageFreeGb},
    };
    if (summary == m_summary)
        return;
    m_summary = summary;
    Q_EMIT machineSummaryChanged();
}

QString HubModel::statusText() const
{
    const QString sentence = text(m_hub, "status_text");
    return sentence.isEmpty() ? QCoreApplication::translate("Hub", "Not connected") : sentence;
}

bool HubModel::hasEverConnected() const
{
    return m_hub.value(QStringLiteral("ever_connected")).toBool();
}

bool HubModel::isEnrolling() const
{
    return m_hub.value(QStringLiteral("enrolling")).toBool();
}

bool HubModel::isRegistrable() const
{
    return m_hub.value(QStringLiteral("registrable")).toBool(true);
}

QString HubModel::lastError() const
{
    return support::problemMessage(m_hub.value(QStringLiteral("last_error")));
}

QString HubModel::machineTitle() const
{
    return text(m_hub.value(QStringLiteral("machine")).toObject(), "title");
}

QString HubModel::machineCodename() const
{
    return text(m_hub.value(QStringLiteral("machine")).toObject(), "slug");
}

int HubModel::machineId() const
{
    return int(number(m_hub.value(QStringLiteral("machine")).toObject(), "machine_id"));
}

bool HubModel::isNewlyRegistered() const
{
    return m_hub.value(QStringLiteral("machine"))
        .toObject()
        .value(QStringLiteral("registered_on_this_sign_in"))
        .toBool();
}

int HubModel::agentCount() const
{
    return m_agentsKnown ? m_agents->rowCount() : -1;
}

int HubModel::virtualMachineCount() const
{
    return m_virtualMachinesKnown ? m_virtualMachines->rowCount() : -1;
}

void HubModel::refreshMachineSummary()
{
    m_session->post(QStringLiteral("/v1/machine/refresh"));
}

void HubModel::renameMachine(const QString &title)
{
    const QString name = title.trimmed();
    if (m_renaming || machineId() <= 0 || name.isEmpty() || name == machineTitle())
        return;
    m_renaming = true;
    m_renameError.clear();
    Q_EMIT renameChanged();
    client::ServiceReply *reply =
        m_session->patch(QStringLiteral("/v1/proxy/back/api/v1/platform/me/machines/%1").arg(machineId()),
                         {{QStringLiteral("title"), name}});
    connect(reply, &client::ServiceReply::finished, this, [this, reply, name] {
        m_renaming = false;
        if (reply->isError())
            m_renameError = reply->problem().message();
        Q_EMIT renameChanged();
        if (!reply->isError())
            Q_EMIT machineRenamed(name);
    });
}

} // namespace simorg::app
