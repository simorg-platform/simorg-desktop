// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QJsonArray>
#include <QObject>
#include <QString>
#include <QVariantMap>

class QTimer;

namespace simorg::client {
class ServiceSession;
}

namespace simorg::app {

/**
 * What this app reports about itself, as QML reads it off `WatchDog`.
 *
 * Sent to the service (`POST /v1/telemetry/events` and `/errors`), not to the
 * platform: one launch of the service is one anonymous session with one scrubber
 * and one set of limits, and there is no second copy of those rules on the machine
 * to drift. Batched every two
 * seconds; what could not be delivered is dropped, as telemetry is never worth
 * holding up the app for.
 */
class TelemetryModel : public QObject
{
    Q_OBJECT

public:
    explicit TelemetryModel(client::ServiceSession *session, QObject *parent = nullptr);
    ~TelemetryModel() override;

    /** A product event: `section_opened`, `settings_changed`. Properties name no person, path or agent. */
    Q_INVOKABLE void track(const QString &name, const QVariantMap &props = {});

    /** A failure in this app, in the vocabulary of `TelemetryErrorKind`. */
    void reportError(const QString &kind, const QString &message, const QVariantMap &context = {});

    /** Reports `qCritical` and `qFatal` messages as `log` errors, at most twenty a minute. */
    void installMessageHandler();

    /** Hands what is held to the service now, as the app leaves, rather than at the next batch. */
    void flush();

private:
    client::ServiceSession *m_session;
    QTimer *m_flush;
    QJsonArray m_events;
    QJsonArray m_errors;
};

} // namespace simorg::app
