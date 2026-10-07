// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/SurfaceModels.h"

#include "Support.h"
#include "simorg/appmodel/SurfaceRouter.h"
#include "simorg/client/ServiceSession.h"

#include <QJsonDocument>
#include <QLoggingCategory>
#include <QUrl>
#include <QUrlQuery>

#include <utility>

namespace simorg::app {
namespace {

// Internal to this file: the category's name is shared with the rest of the app's surface lines.
Q_LOGGING_CATEGORY(lcSurfaceModel, "simorg.surface", QtInfoMsg)

} // namespace

using client::ServiceReply;
using support::number;
using support::text;

// ---- SurfaceRendererModel -----------------------------------------------------------------

SurfaceRendererModel::SurfaceRendererModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("agents.renderer")))
{
    connect(m_topic, &client::TopicSubscription::received, this, &SurfaceRendererModel::apply);
    connect(m_session, &client::ServiceSession::connected, this, &SurfaceRendererModel::loadConfig);
    if (m_session->isConnected())
        loadConfig();
    if (m_topic->hasValue())
        apply(m_topic->value());
}

void SurfaceRendererModel::loadConfig()
{
    // The addresses the engine is told, as the service is configured, so the page and the service agree.
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/config"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (reply->isError())
            return;
        m_config = reply->object();
        Q_EMIT changed();
    });
    // A resolution asked for before the service went away is asked for again.
    if (m_asked && state() != Ready)
        m_session->get(QStringLiteral("/v1/surfaces/renderer"));
}

void SurfaceRendererModel::apply(const QJsonObject &renderer)
{
    if (renderer == m_renderer)
        return;
    m_renderer = renderer;
    Q_EMIT changed();
}

SurfaceRendererModel::State SurfaceRendererModel::state() const
{
    const QString name = text(m_renderer, "state");
    if (name == QLatin1String("loading"))
        return Loading;
    if (name == QLatin1String("ready"))
        return Ready;
    if (name == QLatin1String("failed"))
        return Failed;
    return Idle;
}

QString SurfaceRendererModel::message() const
{
    return text(m_renderer, "message");
}

QString SurfaceRendererModel::engineSpecifier() const
{
    return text(m_renderer, "engine_specifier");
}

QString SurfaceRendererModel::themeSpecifier() const
{
    return text(m_renderer, "theme_specifier");
}

void SurfaceRendererModel::setDark(bool dark)
{
    if (dark == m_dark)
        return;
    m_dark = dark;
    Q_EMIT changed();
}

void SurfaceRendererModel::ensureResolved()
{
    m_asked = true;
    if (state() == Loading || state() == Ready)
        return;
    // The read is what starts resolution; its answer is also the state, applied without waiting for the topic.
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/surfaces/renderer"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            apply(reply->object());
    });
}

void SurfaceRendererModel::retry()
{
    m_asked = true;
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/surfaces/renderer/retry"));
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (!reply->isError())
            apply(reply->object());
    });
}

QUrl SurfaceRendererModel::hostUrl(const QString &surface, int agentId) const
{
    return SurfaceRouter::documentUrl(surface, agentId);
}

QJsonObject SurfaceRendererModel::pageConfig(const QString &surface, int agentId, const QString &agentSlug,
                                             const QString &agentTitle) const
{
    if (state() != Ready)
        return {};
    const QJsonObject endpoints = m_config.value(QStringLiteral("endpoints")).toObject();
    /*
      Identity and addresses, and nothing that could be used as one: the engine runs on
      another origin and mounts modules published by somebody else. The same keys
      the web panel sends, without a member role, since owning the machine an agent was
      placed on does not make somebody a member of it.
    */
    const QJsonObject environment{
        {QStringLiteral("AGENT_ID"), agentId > 0 ? QString::number(agentId) : QString()},
        {QStringLiteral("PLATFORM_API_ADDRESS"), text(endpoints, "api_endpoint")},
        {QStringLiteral("PLATFORM_WS_ADDRESS"), text(endpoints, "hub_socket_url")},
        {QStringLiteral("STATIC_BASE_URL"), text(endpoints, "wom_endpoint")},
        {QStringLiteral("SIMORG_AGENT_SLUG"), agentSlug},
        {QStringLiteral("SIMORG_SURFACE"), surface},
        {QStringLiteral("SIMORG_HOST"), QStringLiteral("SIMORG_DESKTOP")},
    };
    return QJsonObject{
        {QStringLiteral("surface"), surface},
        {QStringLiteral("agentId"), agentId},
        {QStringLiteral("agentSlug"), agentSlug},
        {QStringLiteral("agentTitle"), agentTitle},
        {QStringLiteral("engineDocumentUrl"), text(m_renderer, "engine_document_url")},
        {QStringLiteral("engineSpecifier"), engineSpecifier()},
        {QStringLiteral("theme"),
         QJsonObject{
             {QStringLiteral("artifactSpecifier"), themeSpecifier()},
             {QStringLiteral("driver"), themeDriverCode()},
             // Answered once, by the app, so the surface agrees with the window around it.
             {QStringLiteral("choice"), m_dark ? QStringLiteral("dark") : QStringLiteral("light")},
             {QStringLiteral("source"),
              QJsonObject{{QStringLiteral("url"), text(m_renderer, "theme_module_url")},
                          {QStringLiteral("integrity"), text(m_renderer, "theme_module_integrity")}}},
         }},
        {QStringLiteral("environment"), environment},
        // The engine log, in a development build and never in production.
        {QStringLiteral("devtools"), text(m_config, "environment") == QLatin1String("dev")},
    };
}

void SurfaceRendererModel::reportStatus(const QString &surface, const QString &state, const QString &detail)
{
    // From an untrusted document: compared, never obeyed.
    if (state == QLatin1String("connected")) {
        m_connected.insert(surface, true);
        m_errors.remove(surface);
    } else if (state == QLatin1String("drawn")) {
        // The page has run the surface's program, so whatever is going to be on
        // screen is on it. Connected as well, for a page that says this first.
        m_connected.insert(surface, true);
        m_drawn.insert(surface, true);
        m_errors.remove(surface);
    } else if (state == QLatin1String("error")) {
        m_errors.insert(surface, detail.isEmpty() ? tr("The renderer reported an error.") : detail.left(2000));
    } else {
        qCWarning(lcSurfaceModel) << "agent surface: ignoring an unknown report" << state.left(64);
        return;
    }
    Q_EMIT surfaceStatusChanged(surface);
}

bool SurfaceRendererModel::isConnected(const QString &surface) const
{
    return m_connected.value(surface);
}

bool SurfaceRendererModel::isDrawn(const QString &surface) const
{
    return m_drawn.value(surface);
}

QString SurfaceRendererModel::surfaceError(const QString &surface) const
{
    return m_errors.value(surface);
}

void SurfaceRendererModel::forgetStatus(const QString &surface)
{
    m_connected.remove(surface);
    m_drawn.remove(surface);
    m_errors.remove(surface);
    Q_EMIT surfaceStatusChanged(surface);
}

// ---- SurfaceSessionModel ------------------------------------------------------------------

SurfaceSessionModel::SurfaceSessionModel(client::ServiceSession *session, const QString &surface, int agentId,
                                         SurfaceRendererModel *renderer, bool componentLogs, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_surface(surface)
    , m_agentId(agentId)
    , m_renderer(renderer)
    , m_componentLogs(componentLogs)
{
    openSession();
    loadWorld();
    /*
      The two facts that change what the platform answers for this surface, relayed by the service from the
      host frame the Hub sends the computer running the agent. Its container's own state cannot stand in for
      them: a container that is up has not necessarily connected, and one that stopped is not off the Hub
      until its socket closes — the read would come a moment too soon either way.
    */
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("agent_id"), QString::number(m_agentId));
    m_resources = m_session->subscribe(QStringLiteral("agents.resource"), params);
    connect(m_resources, &client::TopicSubscription::received, this, &SurfaceSessionModel::applyResource);
}

SurfaceSessionModel::~SurfaceSessionModel()
{
    close();
}

QString SurfaceSessionModel::path() const
{
    return QStringLiteral("/v1/agents/%1/features/%2/sessions")
        .arg(QString::number(m_agentId), QString::fromLatin1(QUrl::toPercentEncoding(m_surface)));
}

QString SurfaceSessionModel::sessionId() const
{
    return text(m_state, "session_id");
}

QString SurfaceSessionModel::worldResponse() const
{
    return text(m_world, "response");
}

QJsonObject SurfaceSessionModel::worldSources() const
{
    return m_world.value(QStringLiteral("sources")).toObject();
}

QString SurfaceSessionModel::program() const
{
    return text(m_world, "program");
}

bool SurfaceSessionModel::carriesEvents() const
{
    return !m_closed && m_state.value(QStringLiteral("carries_events")).toBool();
}

void SurfaceSessionModel::openSession()
{
    ServiceReply *reply = m_session->post(path());
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        if (m_closed)
            return;
        if (reply->isError()) {
            qCWarning(lcSurfaceModel).noquote()
                << QStringLiteral("%1 of agent %2 could not open a session: %3")
                       .arg(m_surface, QString::number(m_agentId), reply->problem().message());
            confirmRenderer();
            return;
        }
        QJsonObject opened = reply->object();
        // The renderer this page is drawn with, looked up again by the service for this open.
        const QJsonValue renderer = opened.take(QStringLiteral("renderer"));
        if (renderer.isObject() && m_renderer)
            m_renderer->apply(renderer.toObject());
        confirmRenderer();
        applySession(opened);
        if (m_events)
            m_session->release(std::exchange(m_events, nullptr));
        QUrlQuery params;
        params.addQueryItem(QStringLiteral("session_id"), sessionId());
        m_events = m_session->subscribe(QStringLiteral("agents.features.events"), params);
        connect(m_events, &client::TopicSubscription::received, this, &SurfaceSessionModel::applyEvent);
    });
}

void SurfaceSessionModel::confirmRenderer()
{
    if (m_rendererConfirmed)
        return;
    m_rendererConfirmed = true;
    Q_EMIT rendererConfirmedChanged();
}

void SurfaceSessionModel::applySession(const QJsonObject &session)
{
    const bool carried = carriesEvents();
    m_state = session;
    if (carried != carriesEvents())
        Q_EMIT carriesEventsChanged();
}

void SurfaceSessionModel::applyEvent(const QJsonObject &event)
{
    const QString kind = text(event, "kind");
    if (kind == QLatin1String("delivery")) {
        const QJsonObject delivery = event.value(QStringLiteral("delivery")).toObject();
        // The world this surface shows, and no other of the agent's.
        if (text(delivery, "feature") == m_surface)
            Q_EMIT serverEvent(delivery);
    } else if (kind == QLatin1String("accepted")) {
        if (m_componentLogs) {
            const QJsonObject accepted = event.value(QStringLiteral("accepted")).toObject();
            qCInfo(lcSurfaceModel).noquote() << QStringLiteral("%1/%2 reached %3 runtime(s)")
                                               .arg(m_surface, text(accepted, "codename"),
                                                    QString::number(number(accepted, "delivered")));
        }
    } else if (kind == QLatin1String("refused")) {
        // Always said: a channel the published world does not declare is the author's mistake, and this is where it shows.
        qCWarning(lcSurfaceModel).noquote() << QStringLiteral("the Hub refused %1/%2: %3 — %4")
                                              .arg(m_surface, text(event, "codename"), text(event, "code"),
                                                   text(event, "message"));
    } else if (kind == QLatin1String("state")) {
        applySession(event.value(QStringLiteral("session")).toObject());
    }
}

void SurfaceSessionModel::applyResource(const QJsonObject &event)
{
    if (m_closed)
        return;
    const QString resource = text(event, "resource");
    // A runtime coming or going changes every surface of the agent; a world, only the one it draws.
    if (resource == QLatin1String("RUNTIME")
        || (resource == QLatin1String("WORLD") && text(event, "resource_key") == m_surface))
        Q_EMIT worldStale();
}

void SurfaceSessionModel::loadWorld()
{
    const int request = ++m_worldRequest;
    m_worldLoaded = false;
    m_worldError.clear();
    m_world = {};
    Q_EMIT worldChanged();
    ServiceReply *reply =
        m_session->get(QStringLiteral("/v1/agents/%1/features/%2/world")
                           .arg(QString::number(m_agentId), QString::fromLatin1(QUrl::toPercentEncoding(m_surface))));
    connect(reply, &ServiceReply::finished, this, [this, reply, request] {
        if (request != m_worldRequest)
            return; // a later read is the current one
        if (reply->isError())
            m_worldError = reply->problem().message();
        else
            m_world = reply->object(); // unpublished is an empty world, which draws the engine and nothing in it
        m_worldLoaded = true;
        Q_EMIT worldChanged();
    });
}

void SurfaceSessionModel::reload()
{
    loadWorld();
    if (!m_closed && text(m_state, "state") == QLatin1String("closed"))
        openSession();
}

void SurfaceSessionModel::sendClientEvent(const QJsonObject &event)
{
    QJsonObject payload = event;
    // Overwritten, not defaulted: a page naming another world is asking to speak on one it is not showing.
    payload.insert(QStringLiteral("feature"), m_surface);
    const QString codename = text(payload, "codename");
    if (!carriesEvents() || sessionId().isEmpty()) {
        // Said out loud: a program that writes before the session is open would otherwise look like one that never wrote.
        qCWarning(lcSurfaceModel).noquote()
            << QStringLiteral(
                   "%1/%2 was not sent: this surface is not connected to the agent yet, and what a page says "
                   "before then is not kept for later.")
                   .arg(m_surface, codename);
        return;
    }
    /*
      A bound, so a service that stops answering cannot make a page's events pile up here without end. Dropping
      the newest is what the channel tolerates: a counter that never arrives holds nothing up, while one that
      arrives after a later one is refused.
    */
    constexpr qsizetype maxWaiting = 256;
    if (m_outbox.size() >= maxWaiting) {
        qCWarning(lcSurfaceModel).noquote()
            << QStringLiteral("%1/%2 was not sent: %3 events are already waiting for the service to answer.")
                   .arg(m_surface, codename, QString::number(maxWaiting));
        return;
    }
    m_outbox.append(payload);
    sendNextEvent();
}

void SurfaceSessionModel::sendNextEvent()
{
    if (m_sending || m_outbox.isEmpty())
        return;
    if (!carriesEvents() || sessionId().isEmpty()) {
        // The session closed while these waited; the page opens a new one and says them again if they still matter.
        for (const QJsonObject &dropped : std::as_const(m_outbox))
            qCWarning(lcSurfaceModel).noquote()
                << QStringLiteral("%1/%2 was not sent: this surface stopped being connected to the agent.")
                       .arg(m_surface, text(dropped, "codename"));
        m_outbox.clear();
        return;
    }
    const QJsonObject payload = m_outbox.takeFirst();
    const QString codename = text(payload, "codename");
    m_sending = true;
    ServiceReply *reply =
        m_session->post(path() + QLatin1Char('/') + sessionId() + QStringLiteral("/events"), payload);
    connect(reply, &ServiceReply::finished, this, [this, reply, codename] {
        m_sending = false;
        if (reply->isError())
            qCWarning(lcSurfaceModel).noquote()
                << QStringLiteral("%1/%2 was not sent: %3").arg(m_surface, codename, reply->problem().message());
        // Answered or refused, it is behind us: a refused counter holds nothing up, an overtaken one is lost.
        sendNextEvent();
    });
}

void SurfaceSessionModel::report(const QString &state, const QString &detail)
{
    if (m_renderer)
        m_renderer->reportStatus(m_surface, state, detail);
}

void SurfaceSessionModel::log(const QString &level, const QString &line)
{
    if (!m_componentLogs)
        return;
    const QString upper = level.toUpper();
    if (upper == QLatin1String("ERROR") || upper == QLatin1String("FATAL"))
        qCCritical(lcSurfaceModel).noquote() << line;
    else if (upper == QLatin1String("WARNING") || upper == QLatin1String("WARN"))
        qCWarning(lcSurfaceModel).noquote() << line;
    else
        qCInfo(lcSurfaceModel).noquote() << line;
}

void SurfaceSessionModel::close()
{
    if (m_closed)
        return;
    const bool carried = carriesEvents();
    m_closed = true;
    m_outbox.clear();
    if (m_events)
        m_session->release(std::exchange(m_events, nullptr));
    if (m_resources)
        m_session->release(std::exchange(m_resources, nullptr));
    if (!sessionId().isEmpty())
        m_session->remove(path() + QLatin1Char('/') + sessionId());
    if (carried)
        Q_EMIT carriesEventsChanged();
}

// ---- SurfaceSessionsModel -----------------------------------------------------------------

SurfaceSessionsModel::SurfaceSessionsModel(client::ServiceSession *session, SurfaceRendererModel *renderer,
                                           QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_renderer(renderer)
{
}

SurfaceSessionModel *SurfaceSessionsModel::open(const QString &surface, int agentId, const QString &)
{
    if (agentId <= 0 || surface.isEmpty())
        return nullptr;
    auto *session = new SurfaceSessionModel(m_session, surface, agentId, m_renderer, m_componentLogs, this);
    m_open.append(session);
    return session;
}

void SurfaceSessionsModel::close(SurfaceSessionModel *session)
{
    if (!session)
        return;
    m_open.removeAll(session);
    session->close();
    session->deleteLater();
}

void SurfaceSessionsModel::closeAll()
{
    const QList<QPointer<SurfaceSessionModel>> open = std::exchange(m_open, {});
    for (const QPointer<SurfaceSessionModel> &session : open)
        close(session);
}

} // namespace simorg::app
