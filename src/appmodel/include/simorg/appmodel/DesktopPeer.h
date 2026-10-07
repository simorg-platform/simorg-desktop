// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QString>
#include <QTimer>

namespace simorg::app {

/**
 * Simorg Desktop as an application agents use: `@simorg/betsalel/simorg-desktop`,
 * a singleton every agent may use.
 *
 * The app connects to the machine service's peer pipe the way any application
 * does: it reads the peer discovery file, presents its specifier, declares its
 * fields with `BUILD` and attaches with `START`. On the pipe it is not asked its
 * pairing question, being the service's own front end. From then on an agent
 * that includes it — `"#simorg/betsalel/simorg-desktop" #sd` — reaches it as
 * `vibration.from_agent`, and `"Hello World from inside agent!" sd.userLog`
 * becomes a line in that agent's log here, in the information colour
 * ({@link userLog}).
 *
 * It connects once it knows its own specifier, which the platform names and
 * the service passes on with Access Management's answers, and it keeps the link
 * up: after the service restarts, or closes the link, it tries again after one
 * second and then twice as long each time, up to thirty.
 */
class DesktopPeer : public QObject
{
    Q_OBJECT
    /** `disconnected`, `connecting`, `awaiting_consent`, `attached` or `refused`. */
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)

public:
    /** The fields this release declares: what an agent may write to it. */
    static constexpr const char *script = "$userLog\n";

    explicit DesktopPeer(QString environment, QObject *parent = nullptr);
    /** Closes the link without trying again: a socket closing as its owner goes is not a link lost. */
    ~DesktopPeer() override;

    /** The specifier the platform names this app by; empty, as before anybody signs in, closes the link. */
    void setSpecifier(const QString &specifier);
    QString specifier() const { return m_specifier; }
    QString state() const { return m_state; }

    /** How long the link waits before trying again, first and at most; shorter in tests. */
    void setReconnectDelays(int firstMs, int longestMs);

Q_SIGNALS:
    void stateChanged();
    /** An agent's include had this app write `text` into agent `agentId`'s log. */
    void userLog(qint64 agentId, const QString &text, const QDateTime &at);

private:
    void connectNow();
    void lost();
    void readLines();
    void handle(const QJsonObject &object);
    void send(const QJsonObject &object);
    void setState(const QString &state);

    QString m_environment;
    QString m_specifier;
    QString m_state = QStringLiteral("disconnected");
    QLocalSocket m_socket;
    QTimer m_retry;
    QByteArray m_pending;
    int m_firstDelayMs = 1000;
    int m_longestDelayMs = 30000;
    int m_delayMs = 1000;
};

} // namespace simorg::app
