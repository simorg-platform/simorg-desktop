// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DockerListModels.h"

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QTimer;

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

/**
 * Whether this computer can run agents, as the environment check window reads it off
 * `Preflight`.
 *
 * The service runs the check and prepares the computer when the first client
 * connects, publishing `preflight.state`. What stays
 * here is the window's own manners: when to put itself up (at once on a first run,
 * after a second and a half of work otherwise, and always when something needs a
 * decision) and when it was put away.
 */
/**
 * The check's three steps, as rows that stay where they are.
 *
 * A list rather than a fresh value on every event, because a download tells its
 * progress four times a second and a `Repeater` over a
 * plain list builds every row again at each of those: the ring starts spinning
 * from the top, the bar's animation starts from nothing, and what a person sees
 * is a row flashing rather than a download running. Keyed by the check, so a row
 * is the same row from *waiting* to *passed* and only the values change.
 */
class PreflightStepsModel : public KeyedRowsModel
{
    Q_OBJECT

public:
    enum Role {
        /** `connection`, `engine` or `images`. */
        KeyRole = Qt::UserRole + 1,
        /** {@link PreflightModel::Check}. */
        CheckRole,
        /** {@link PreflightModel::State}; not `state`, which every QML item already has. */
        StepStateRole,
        TitleRole,
        DetailRole,
        /** 0 to 1, or -1 where there is nothing to measure. */
        ProgressRole,
        RemedyRole,
    };
    Q_ENUM(Role)

    explicit PreflightStepsModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
};

class PreflightModel : public QObject
{
    Q_OBJECT
    /** The three steps as rows that stay: what a `Repeater` draws. */
    Q_PROPERTY(PreflightStepsModel *stepList READ stepList CONSTANT)
    /** The same, as `{check, key, state, title, detail, progress, remedy}` maps, read off the rows. */
    Q_PROPERTY(QVariantList steps READ steps NOTIFY stepsChanged)
    Q_PROPERTY(int outcome READ outcome NOTIFY stepsChanged)
    Q_PROPERTY(bool running READ isRunning NOTIFY stepsChanged)
    Q_PROPERTY(bool ready READ isReady NOTIFY stepsChanged)
    Q_PROPERTY(bool needsAttention READ needsAttention NOTIFY stepsChanged)
    Q_PROPERTY(double progress READ progress NOTIFY stepsChanged)
    /** The window should be the only one on screen. */
    Q_PROPERTY(bool holding READ isHolding NOTIFY holdingChanged)
    Q_PROPERTY(bool fetching READ isFetching NOTIFY stepsChanged)
    Q_PROPERTY(QString fetchingImage READ fetchingImage NOTIFY stepsChanged)
    /** `184 MB of 512 MB`, or empty when the size is not known. */
    Q_PROPERTY(QString fetchDetail READ fetchDetail NOTIFY stepsChanged)
    /** The one thing worth offering now: `manual`, `start`, `fetch`, `cancel`, `retry`, or empty. */
    Q_PROPERTY(QString remedy READ remedy NOTIFY stepsChanged)
    Q_PROPERTY(QString registry READ registry NOTIFY stepsChanged)
    Q_PROPERTY(bool canFetch READ canFetch NOTIFY stepsChanged)
    /**
     * The code of the problem the last run or fetch ended on (`IMAGE_NOT_PUBLISHED`,
     * `IMAGE_DOWNLOAD_FAILED`, …), or empty when it ended on none.
     */
    Q_PROPERTY(QString problemCode READ problemCode NOTIFY stepsChanged)
    /** The service's own one-line title for that problem, or empty. */
    Q_PROPERTY(QString problemTitle READ problemTitle NOTIFY stepsChanged)
    /**
     * The image this computer needs is not published for it (simorg-machine
     * `IMAGE_NOT_PUBLISHED`, which is also a record published only for
     * another architecture, such as an arm64 image on an amd64 Docker Engine).
     * Downloading again would be refused the same way, so it is not offered;
     * checking again is, because a new release can arrive at any time.
     */
    Q_PROPERTY(bool imageUnavailable READ isImageUnavailable NOTIFY stepsChanged)
    Q_PROPERTY(bool firstRun READ isFirstRun NOTIFY stepsChanged)
    /**
     * What this computer's graphics cards can give an agent and what would make them able to:
     * a `DockerGpu` map, or empty until the service has looked. Beside the
     * checks, never one of them: an agent runs without a card.
     */
    Q_PROPERTY(QVariantMap graphics READ graphics NOTIFY graphicsChanged)

public:
    enum Check {
        Connection,
        Engine,
        Images,
    };
    Q_ENUM(Check)

    /** QML's `PreflightState`. */
    enum State {
        Waiting,
        Checking,
        Working,
        Passed,
        Failed,
    };
    Q_ENUM(State)

    enum Outcome {
        Unknown,
        Busy,
        Ready,
        NeedsAttention,
    };
    Q_ENUM(Outcome)

    /** How long a run may work before the window explains why nothing else has opened. */
    static constexpr int graceMs = 1500;

    explicit PreflightModel(client::ServiceSession *session, QObject *parent = nullptr);

    PreflightStepsModel *stepList() const { return m_steps; }
    QVariantList steps() const;
    int outcome() const;
    bool isRunning() const;
    bool isReady() const { return outcome() == Ready; }
    bool needsAttention() const { return outcome() == NeedsAttention; }
    double progress() const;
    bool isHolding() const { return m_holding; }
    bool isFetching() const;
    QString fetchingImage() const;
    QString fetchDetail() const;
    QString remedy() const;
    QString registry() const;
    bool canFetch() const;
    QString problemCode() const;
    QString problemTitle() const;
    bool isImageUnavailable() const;
    bool isFirstRun() const;
    QVariantMap graphics() const;

public Q_SLOTS:
    /** Asks the service for one full pass. A pass already running is followed instead. */
    void run();
    void fetchMissingImages();
    void cancelFetch();
    /** Puts the window away without everything having passed, until the next run. */
    void dismiss();

Q_SIGNALS:
    void stepsChanged();
    void holdingChanged();
    void graphicsChanged();
    /** One run reached an outcome; `ready` when every check passed. */
    void finished(bool ready);

private:
    void apply(const QJsonObject &run);
    void evaluateHold();
    void setHolding(bool holding);

    client::ServiceSession *m_session;
    client::TopicSubscription *m_topic;
    PreflightStepsModel *m_steps;
    QTimer *m_grace;
    QJsonObject m_run;
    bool m_holding = false;
    bool m_dismissed = false;
    bool m_holdUntilDismissed = false;
};

} // namespace simorg::app
