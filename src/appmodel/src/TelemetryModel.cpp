// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/TelemetryModel.h"

#include "simorg/client/ServiceSession.h"

#include <QDateTime>
#include <QJsonObject>
#include <QPointer>
#include <QTimer>

namespace simorg::app {
namespace {

constexpr int flushIntervalMs = 2'000;
/** A burst of errors from one fault says nothing the first twenty did not. */
constexpr int maxLoggedErrorsPerMinute = 20;
/** Held while the service is away; more than this is older than anybody will read. */
constexpr qsizetype maxHeld = 200;

QPointer<TelemetryModel> g_reporter;
QtMessageHandler g_previousHandler = nullptr;

QString now()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

void forwardMessage(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (g_previousHandler)
        g_previousHandler(type, context, message);
    if ((type != QtCriticalMsg && type != QtFatalMsg) || !g_reporter)
        return;

    static qint64 windowStart = 0;
    static int inWindow = 0;
    const qint64 minute = QDateTime::currentSecsSinceEpoch() / 60;
    if (minute != windowStart) {
        windowStart = minute;
        inWindow = 0;
    }
    if (++inWindow > maxLoggedErrorsPerMinute)
        return;
    // Queued: a message can be logged from any thread, and the reporter lives on the main one.
    QMetaObject::invokeMethod(
        g_reporter,
        [message, category = QString::fromUtf8(context.category ? context.category : "")] {
            if (g_reporter)
                g_reporter->reportError(QStringLiteral("log"), message, {{QStringLiteral("category"), category}});
        },
        Qt::QueuedConnection);
}

} // namespace

TelemetryModel::TelemetryModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_flush(new QTimer(this))
{
    m_flush->setInterval(flushIntervalMs);
    m_flush->setSingleShot(true);
    connect(m_flush, &QTimer::timeout, this, &TelemetryModel::flush);
    connect(m_session, &client::ServiceSession::connected, this, [this] {
        if (!m_events.isEmpty() || !m_errors.isEmpty())
            m_flush->start();
    });
}

TelemetryModel::~TelemetryModel()
{
    if (g_reporter == this)
        qInstallMessageHandler(g_previousHandler);
}

void TelemetryModel::track(const QString &name, const QVariantMap &props)
{
    if (name.isEmpty())
        return;
    if (m_events.size() >= maxHeld)
        m_events.removeFirst();
    m_events.append(QJsonObject{{QStringLiteral("name"), name},
                                {QStringLiteral("props"), QJsonObject::fromVariantMap(props)},
                                {QStringLiteral("occurred_at"), now()}});
    if (!m_flush->isActive())
        m_flush->start();
}

void TelemetryModel::reportError(const QString &kind, const QString &message, const QVariantMap &context)
{
    if (message.isEmpty())
        return;
    if (m_errors.size() >= maxHeld)
        m_errors.removeFirst();
    m_errors.append(QJsonObject{{QStringLiteral("kind"), kind},
                                {QStringLiteral("message"), message},
                                {QStringLiteral("context"), QJsonObject::fromVariantMap(context)},
                                {QStringLiteral("occurred_at"), now()}});
    if (!m_flush->isActive())
        m_flush->start();
}

void TelemetryModel::installMessageHandler()
{
    if (g_reporter)
        return;
    g_reporter = this;
    g_previousHandler = qInstallMessageHandler(forwardMessage);
}

void TelemetryModel::flush()
{
    if (!m_session->isConnected())
        return; // sent when the service is back
    if (!m_events.isEmpty()) {
        m_session->post(QStringLiteral("/v1/telemetry/events"), {{QStringLiteral("events"), m_events}});
        m_events = QJsonArray();
    }
    if (!m_errors.isEmpty()) {
        m_session->post(QStringLiteral("/v1/telemetry/errors"), {{QStringLiteral("errors"), m_errors}});
        m_errors = QJsonArray();
    }
}

} // namespace simorg::app
