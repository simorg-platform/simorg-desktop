// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QObject>
#include <QString>

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * How much of a log this person wants kept, as Settings reads it off `LogSettings`.
 *
 * A statement about the person rather than the computer, so it is stored on the
 * account as the `desktop.logs.retention` preference and follows them between
 * computers. The service has no route of its own for it: it is read and written
 * through the service's proxy to the platform, which adds the session's token so
 * this app never holds one.
 *
 * Until the platform answers, the default applies; there is no local copy to
 * disagree with the account. A failed write is reported and not rolled back: the
 * lines somebody asked for are kept for this session.
 *
 * `localTimes` is the other half of reading a log, and kept here for that
 * reason: the engine stamps every line in GMT, and this says whether an agent's
 * log shows those times in this computer's own zone instead. It lasts for as
 * long as the app runs, and is not stored on the account.
 */
class LogSettingsModel : public QObject
{
    Q_OBJECT
    /** Whether an agent's log shows its GMT times in this computer's own zone. */
    Q_PROPERTY(bool localTimes READ localTimes WRITE setLocalTimes NOTIFY localTimesChanged)
    /** Lines kept per log window. Meaningless while `unlimited`. */
    Q_PROPERTY(int maxLines READ maxLines NOTIFY changed)
    Q_PROPERTY(bool unlimited READ isUnlimited NOTIFY changed)
    /** The platform has answered, so a field is not edited too early. */
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY changed)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    /** Why the last write did not stick; empty when it did. */
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)
    Q_PROPERTY(int minimumLines READ minimumLines CONSTANT)
    Q_PROPERTY(int maximumLines READ maximumLines CONSTANT)

public:
    /** The platform's name for the preference. */
    static const QString preferenceKey;
    /** The platform's route, reached through the service's proxy. */
    static const QString preferencesPath;

    static constexpr int defaultMaxLines = 10000;
    static constexpr int minimumMaxLines = 200;
    static constexpr int maximumMaxLines = 5000000;

    explicit LogSettingsModel(client::ServiceSession *session, QObject *parent = nullptr);

    int maxLines() const { return m_maxLines; }
    bool isUnlimited() const { return m_unlimited; }
    bool isLoaded() const { return m_loaded; }
    bool isBusy() const { return m_requests > 0; }
    QString lastError() const { return m_lastError; }
    int minimumLines() const { return minimumMaxLines; }
    int maximumLines() const { return maximumMaxLines; }
    /** Lines a log model keeps: 0 for no cap. */
    int capacity() const { return m_unlimited ? 0 : m_maxLines; }
    bool localTimes() const { return m_localTimes; }
    void setLocalTimes(bool localTimes);

public Q_SLOTS:
    /** Reads the account's answer. Done on its own whenever somebody signs in. */
    void load();
    /** Keeps `maxLines` (clamped) or everything, now, and saves it to the account. */
    void apply(int maxLines, bool unlimited);

Q_SIGNALS:
    void changed();
    void localTimesChanged();

private:
    void reset();

    client::ServiceSession *m_session;
    client::TopicSubscription *m_auth;
    int m_maxLines = defaultMaxLines;
    bool m_unlimited = false;
    bool m_localTimes = false;
    bool m_loaded = false;
    bool m_signedIn = false;
    int m_requests = 0;
    QString m_lastError;
};

/**
 * Whether what somebody set about access on this computer reached the platform, as
 * the Access management screen reads it off `MachineConfig`.
 *
 * The rules, settings and decisions themselves are the service's to keep and send
 * (`/v1/access/…`, the agents area). This reads the store's `last_error` from
 * `access.changed`: the last read or write the platform refused or never received,
 * which the service clears once one lands.
 */
class MachineConfigModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)

public:
    explicit MachineConfigModel(client::ServiceSession *session, QObject *parent = nullptr);

    QString lastError() const { return m_lastError; }

Q_SIGNALS:
    void stateChanged();

private:
    client::TopicSubscription *m_overview;
    QString m_lastError;
};

} // namespace simorg::app
