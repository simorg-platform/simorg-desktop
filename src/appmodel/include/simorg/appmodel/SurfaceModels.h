// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QHash>
#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QUrl>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * The renderer an agent's Workbench and Brain are drawn with, as `AgentSurfaces`.
 *
 * The service resolves the engine and theme artifacts when asked and publishes
 * the result on
 * `agents.renderer`; nothing here carries a credential, since everything the page
 * loads is public. What stays here is the page's side: the host document's
 * configuration, the mood it is painted in, and what each surface's page last said
 * about itself.
 */
class SurfaceRendererModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QString engineSpecifier READ engineSpecifier NOTIFY changed)
    Q_PROPERTY(QString themeSpecifier READ themeSpecifier NOTIFY changed)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)

public:
    /** QML's `SurfaceState`. */
    enum State {
        Idle,
        Loading,
        Ready,
        Failed,
    };
    Q_ENUM(State)

    explicit SurfaceRendererModel(client::ServiceSession *session, QObject *parent = nullptr);

    State state() const;
    QString message() const;
    QString engineSpecifier() const;
    QString themeSpecifier() const;
    bool dark() const { return m_dark; }
    /** Set from the window's theme; a document already served learns it from the page. */
    void setDark(bool dark);

    /** Asks the service to resolve the pair, once; a later call does nothing while it resolves or once it has. */
    Q_INVOKABLE void ensureResolved();
    /** Forgets what was resolved and resolves again. */
    Q_INVOKABLE void retry();
    /** The host document a web view loads for one surface: served by this app, with the engine in a frame inside. */
    Q_INVOKABLE QUrl hostUrl(const QString &surface, int agentId) const;

    /**
     * What the host document is configured with: the engine, the theme and its mood,
     * and the addresses the engine is told. No credential. Empty until the renderer
     * is ready, which the page shows as a wait.
     */
    QJsonObject pageConfig(const QString &surface, int agentId, const QString &agentSlug = {},
                           const QString &agentTitle = {}) const;

    /** What one surface's page said: `connected`, `drawn` or `error`; anything else is ignored. */
    void reportStatus(const QString &surface, const QString &state, const QString &detail);
    Q_INVOKABLE bool isConnected(const QString &surface) const;
    /**
     * Whether that surface has actually been drawn, which is later than
     * connected and is the moment worth showing somebody.
     *
     * `connected` means the engine asked to be initialized — it has booted and
     * nothing is on screen yet. Between the two it fetches its own modules,
     * takes the world and runs the surface's program, and it draws its **own**
     * waiting state while it does. A window that uncovered the view at
     * `connected` therefore replaced its spinner with somebody else's, which is
     * the several-splashes-in-a-row this exists to end: one wait, then the
     * surface.
     */
    Q_INVOKABLE bool isDrawn(const QString &surface) const;
    Q_INVOKABLE QString surfaceError(const QString &surface) const;
    /** Forgets what a surface said, because its page is about to say it again. */
    Q_INVOKABLE void forgetStatus(const QString &surface);

    /**
     * A `SurfaceRenderer` as the service answered it: from `agents.renderer`, from a read, or from an opened
     * session, which carries the one its page is drawn with.
     */
    void apply(const QJsonObject &renderer);

    static QString themeDriverCode() { return QStringLiteral("WEB_THEME"); }

Q_SIGNALS:
    void changed();
    void surfaceStatusChanged(const QString &surface);

private:
    void loadConfig();

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    QJsonObject m_renderer;
    QJsonObject m_config;
    bool m_dark = true;
    bool m_asked = false;
    QHash<QString, bool> m_connected;
    /** Surfaces whose page said it has run the program; see isDrawn. */
    QHash<QString, bool> m_drawn;
    QHash<QString, QString> m_errors;
};

/**
 * One open surface, an agent's Workbench or Brain on screen, and the page's only way
 * to reach this app: registered on the web view's channel as `surface`.
 *
 * | The page reads | The page calls | The page hears |
 * | --- | --- | --- |
 * | `worldResponse`, `worldSources`, `program`, `worldLoaded`, `worldError` | `sendClientEvent(event)` | `serverEvent(delivery)` |
 * | `componentLogs`, `carriesEvents` | `report(state, detail)`, `log(level, line)` | `worldChanged()` |
 *
 * Behind it is a surface session of the service: the world is read and the events
 * carried as the signed-in person there, so no credential is anywhere near the page.
 * Every event leaving is stamped with the surface this was opened for, and a delivery
 * for another of the agent's worlds never arrives.
 *
 * Events leave **one at a time, in the order the page said them**: the next is posted
 * once the service has answered the one before. The page seals each under the next
 * counter of its channel, and the agent opens one only when its counter is higher than
 * every counter it has opened — so an event that overtakes an earlier
 * one on the way costs the earlier one. Each request is its own connection to the
 * service, and requests posted side by side reach it in whatever order the sockets
 * do, which is how RAG Tuner's folder and model paths were lost behind the params
 * applied in the same moment.
 */
class SurfaceSessionModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString surface READ surface CONSTANT)
    Q_PROPERTY(int agentId READ agentId CONSTANT)
    Q_PROPERTY(bool componentLogs READ componentLogs CONSTANT)
    Q_PROPERTY(bool worldLoaded READ worldLoaded NOTIFY worldChanged)
    Q_PROPERTY(QString worldResponse READ worldResponse NOTIFY worldChanged)
    Q_PROPERTY(QJsonObject worldSources READ worldSources NOTIFY worldChanged)
    Q_PROPERTY(QString program READ program NOTIFY worldChanged)
    Q_PROPERTY(QString worldError READ worldError NOTIFY worldChanged)
    Q_PROPERTY(bool carriesEvents READ carriesEvents NOTIFY carriesEventsChanged)
    /**
     * The service has answered the open, with the renderer this surface is drawn with applied. A page is built
     * from the renderer at the moment it loads, so it waits for this: the service looks the engine up again for
     * an open when the one in hand is more than a minute old, and a page built a moment earlier would be drawn by
     * whichever engine was current when the service started. Also set when the open fails, so the page still
     * loads with the renderer in hand.
     */
    Q_PROPERTY(bool rendererConfirmed READ rendererConfirmed NOTIFY rendererConfirmedChanged)

public:
    SurfaceSessionModel(client::ServiceSession *session, const QString &surface, int agentId,
                        SurfaceRendererModel *renderer, bool componentLogs, QObject *parent = nullptr);
    ~SurfaceSessionModel() override;

    QString surface() const { return m_surface; }
    int agentId() const { return m_agentId; }
    bool componentLogs() const { return m_componentLogs; }
    bool worldLoaded() const { return m_worldLoaded; }
    QString worldResponse() const;
    QJsonObject worldSources() const;
    QString program() const;
    QString worldError() const { return m_worldError; }
    bool carriesEvents() const;
    bool rendererConfirmed() const { return m_rendererConfirmed; }
    /** The service's session id, once it has one. */
    QString sessionId() const;

    /** Reads the world again, and opens the session again if the service closed it. */
    Q_INVOKABLE void reload();
    /** Something the page's program said, on its way to the agent. */
    Q_INVOKABLE void sendClientEvent(const QJsonObject &event);
    Q_INVOKABLE void report(const QString &state, const QString &detail);
    Q_INVOKABLE void log(const QString &level, const QString &line);

    /** Ends the service's session and stops listening. */
    void close();

Q_SIGNALS:
    void worldChanged();
    void carriesEventsChanged();
    void rendererConfirmedChanged();
    void serverEvent(const QJsonObject &delivery);
    /**
     * What stands on this surface may have changed: the agent's runtime came or went, or it published this
     * surface's world. The platform answers the same read with the agent asleep while no runtime is connected
     * and with the agent's own page once it has one, so the pane throws its page away and reads again — a
     * fresh engine, because the program the old one ran belonged to a world that is gone.
     */
    void worldStale();

private:
    void openSession();
    void loadWorld();
    void applySession(const QJsonObject &session);
    void applyEvent(const QJsonObject &event);
    void applyResource(const QJsonObject &event);
    void confirmRenderer();
    /** Posts the oldest event waiting, unless one is already on its way. */
    void sendNextEvent();
    QString path() const;

    client::ServiceSession *m_session;
    const QString m_surface;
    const int m_agentId;
    QPointer<SurfaceRendererModel> m_renderer;
    const bool m_componentLogs;
    client::TopicSubscription *m_events = nullptr;
    /** `agents.resource` for this agent: where `RUNTIME` and `WORLD` arrive from the platform. */
    client::TopicSubscription *m_resources = nullptr;
    QJsonObject m_state;
    QJsonObject m_world;
    bool m_worldLoaded = false;
    QString m_worldError;
    int m_worldRequest = 0;
    bool m_rendererConfirmed = false;
    bool m_closed = false;
    /** What the page said and the service has not been handed yet, oldest first. */
    QList<QJsonObject> m_outbox;
    /** An event is on its way to the service; the next waits for its answer. */
    bool m_sending = false;
};

/** Where QML opens and closes surfaces, as `SurfaceSessions`. A session is parented here, so `close` ends it. */
class SurfaceSessionsModel : public QObject
{
    Q_OBJECT

public:
    SurfaceSessionsModel(client::ServiceSession *session, SurfaceRendererModel *renderer, QObject *parent = nullptr);

    /** One surface of one agent, its world loading and its session opening; null without an agent. */
    Q_INVOKABLE simorg::app::SurfaceSessionModel *open(const QString &surface, int agentId,
                                                       const QString &publicToken = {});
    /** Closes one. Safe with null. */
    Q_INVOKABLE void close(simorg::app::SurfaceSessionModel *session);
    /** Every session at once: signing out. */
    void closeAll();

    /** On in a development build: a component's log lines are its author's diagnostics. */
    bool componentLogs() const { return m_componentLogs; }
    void setComponentLogs(bool enabled) { m_componentLogs = enabled; }

private:
    client::ServiceSession *m_session;
    QPointer<SurfaceRendererModel> m_renderer;
    QList<QPointer<SurfaceSessionModel>> m_open;
    bool m_componentLogs = false;
};

} // namespace simorg::app
