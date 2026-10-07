// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/PreflightModel.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QTimer>

namespace simorg::app {

using support::number;
using support::text;

namespace {

/** Whole kilobytes and megabytes, as a download counts them. */
QString downloaded(qint64 bytes)
{
    const auto tr = [](const char *sentence) { return QCoreApplication::translate("Preflight", sentence); };
    if (bytes < 1000)
        return tr("%1 B").arg(bytes);
    const double kilo = double(bytes) / 1000.0;
    if (kilo < 1000)
        return tr("%1 kB").arg(kilo, 0, 'f', 0);
    const double mega = kilo / 1000.0;
    if (mega < 1000)
        return tr("%1 MB").arg(mega, 0, 'f', 0);
    return tr("%1 GB").arg(mega / 1000.0, 0, 'f', 1);
}

int indexOf(const QString &name, std::initializer_list<const char *> names)
{
    int index = 0;
    for (const char *candidate : names) {
        if (name == QLatin1String(candidate))
            return index;
        ++index;
    }
    return 0;
}

} // namespace

PreflightModel::PreflightModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("preflight.state")))
    , m_steps(new PreflightStepsModel(this))
    , m_grace(new QTimer(this))
{
    m_grace->setSingleShot(true);
    m_grace->setInterval(graceMs);
    // Still working after the grace period: the slow network, or the engine that takes its time to say it is missing.
    connect(m_grace, &QTimer::timeout, this, [this] {
        if (isRunning() && !m_dismissed)
            setHolding(true);
    });
    connect(m_topic, &client::TopicSubscription::received, this, &PreflightModel::apply);
    if (m_topic->hasValue())
        apply(m_topic->value());
}

PreflightStepsModel::PreflightStepsModel(QObject *parent)
    : KeyedRowsModel("key", parent)
{
}

QVariant PreflightStepsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &step = row(index.row());
    switch (role) {
    case KeyRole:
        return text(step, "key");
    case CheckRole:
        return step.value(QStringLiteral("check")).toInt();
    case StepStateRole:
        return step.value(QStringLiteral("state")).toInt();
    case TitleRole:
        return text(step, "title");
    case DetailRole:
        return text(step, "detail");
    case ProgressRole:
        return step.value(QStringLiteral("progress")).toDouble();
    case RemedyRole:
        return text(step, "remedy");
    default:
        return {};
    }
}

QHash<int, QByteArray> PreflightStepsModel::roleNames() const
{
    return {
        {KeyRole, "key"},         {CheckRole, "check"},   {StepStateRole, "stepState"}, {TitleRole, "title"},
        {DetailRole, "detail"},   {ProgressRole, "progress"}, {RemedyRole, "remedy"},
    };
}

void PreflightModel::apply(const QJsonObject &run)
{
    if (run == m_run)
        return;
    const bool wasRunning = isRunning();
    const bool known = !m_run.isEmpty();
    const QString previousEnd = text(m_run, "finished_at");
    // The look at the cards arrives on its own, a few seconds after the pass it followed.
    const bool graphicsMoved = run.value(QStringLiteral("graphics")) != m_run.value(QStringLiteral("graphics"));
    m_run = run;

    // A run that starts, or the first state this window sees, which may be a run that finished before it opened.
    const bool started = isRunning() && (!wasRunning || !known);
    if (started || !known) {
        if (started)
            m_dismissed = false;
        // A first run puts the window up before anything is known and keeps it until Continue; others only when
        // they have to.
        m_holdUntilDismissed = isFirstRun();
        if (m_holdUntilDismissed)
            setHolding(true);
        else if (started)
            m_grace->start();
    }
    // The rows before the signal: whatever reads `steps` reads them.
    QList<QJsonObject> rows;
    for (const QJsonValue &value : m_run.value(QStringLiteral("steps")).toArray()) {
        const QJsonObject step = value.toObject();
        const QJsonValue progress = step.value(QStringLiteral("progress"));
        rows.append(QJsonObject{
            {QStringLiteral("key"), text(step, "check")},
            {QStringLiteral("check"), indexOf(text(step, "check"), {"connection", "engine", "images"})},
            {QStringLiteral("state"),
             indexOf(text(step, "state"), {"waiting", "checking", "working", "passed", "failed"})},
            {QStringLiteral("title"), text(step, "title")},
            {QStringLiteral("detail"), text(step, "detail")},
            // -1 is "no measure", which draws a bar with no end rather than no bar at all.
            {QStringLiteral("progress"), progress.isDouble() ? progress.toDouble() : -1.0},
            {QStringLiteral("remedy"), text(step, "remedy")},
        });
    }
    m_steps->reconcile(rows);

    Q_EMIT stepsChanged();
    if (graphicsMoved)
        Q_EMIT graphicsChanged();
    evaluateHold();
    // By its end time rather than by leaving `running`: a quick run can start and end between two events.
    const QString end = text(run, "finished_at");
    if (known && !isRunning() && !end.isEmpty() && end != previousEnd)
        Q_EMIT finished(isReady());
}

void PreflightModel::evaluateHold()
{
    if (m_dismissed) {
        setHolding(false);
        return;
    }
    switch (outcome()) {
    case Ready:
        // Nothing to say, except after a first run, where closing the moment the last check passed would be a flash.
        setHolding(m_holdUntilDismissed);
        break;
    case NeedsAttention:
        setHolding(true);
        break;
    case Busy: {
        // A download that started without being asked is shown.
        const QJsonArray steps = m_run.value(QStringLiteral("steps")).toArray();
        for (const QJsonValue &step : steps) {
            if (text(step.toObject(), "check") == QLatin1String("images")
                && text(step.toObject(), "state") == QLatin1String("working"))
                setHolding(true);
        }
        break;
    }
    case Unknown:
        break;
    }
}

void PreflightModel::setHolding(bool holding)
{
    if (holding)
        m_grace->stop();
    if (m_holding == holding)
        return;
    m_holding = holding;
    Q_EMIT holdingChanged();
}

QVariantList PreflightModel::steps() const
{
    // Read off the rows, so there is one derivation of a step and not two.
    QVariantList list;
    for (int row = 0; row < m_steps->rowCount(); ++row) {
        QVariantMap step = m_steps->at(row);
        // `state` as the enum, under the name this has always answered with.
        step.insert(QStringLiteral("state"), step.take(QStringLiteral("stepState")));
        list.append(step);
    }
    return list;
}

int PreflightModel::outcome() const
{
    return indexOf(text(m_run, "outcome"), {"unknown", "busy", "ready", "needs_attention"});
}

bool PreflightModel::isRunning() const
{
    return text(m_run, "state") == QLatin1String("running");
}

double PreflightModel::progress() const
{
    return m_run.value(QStringLiteral("progress")).toDouble();
}

bool PreflightModel::isFetching() const
{
    return m_run.value(QStringLiteral("fetch")).isObject();
}

QString PreflightModel::fetchingImage() const
{
    return text(m_run.value(QStringLiteral("fetch")).toObject(), "reference");
}

QString PreflightModel::fetchDetail() const
{
    const QJsonObject fetch = m_run.value(QStringLiteral("fetch")).toObject();
    const qint64 total = number(fetch, "total_bytes");
    if (fetch.isEmpty() || total <= 0)
        return {};
    return QCoreApplication::translate("Preflight", "%1 of %2")
        .arg(downloaded(number(fetch, "received_bytes")), downloaded(total));
}

QString PreflightModel::remedy() const
{
    return text(m_run, "remedy");
}

QString PreflightModel::registry() const
{
    return text(m_run, "registry");
}

bool PreflightModel::canFetch() const
{
    return m_run.value(QStringLiteral("can_fetch")).toBool();
}

QString PreflightModel::problemCode() const
{
    return text(m_run.value(QStringLiteral("problem")).toObject(), "code");
}

QString PreflightModel::problemTitle() const
{
    return text(m_run.value(QStringLiteral("problem")).toObject(), "title");
}

bool PreflightModel::isImageUnavailable() const
{
    // Only while the image step is still the one failing: a later pass that
    // finds the image, or a fetch running again, is no longer this.
    if (problemCode() != QLatin1String("IMAGE_NOT_PUBLISHED"))
        return false;
    for (const QJsonValue &value : m_run.value(QStringLiteral("steps")).toArray()) {
        const QJsonObject step = value.toObject();
        if (text(step, "check") == QLatin1String("images"))
            return text(step, "state") == QLatin1String("failed");
    }
    return false;
}

bool PreflightModel::isFirstRun() const
{
    return m_run.value(QStringLiteral("first_run")).toBool();
}

QVariantMap PreflightModel::graphics() const
{
    return m_run.value(QStringLiteral("graphics")).toObject().toVariantMap();
}

void PreflightModel::run()
{
    // A 409 is a run or a preparation already going, which the topic is showing.
    m_session->post(QStringLiteral("/v1/preflight/run"));
}

void PreflightModel::fetchMissingImages()
{
    m_session->post(QStringLiteral("/v1/preflight/fetch"));
}

void PreflightModel::cancelFetch()
{
    m_session->post(QStringLiteral("/v1/preflight/cancel"));
}

void PreflightModel::dismiss()
{
    m_dismissed = true;
    setHolding(false);
}

} // namespace simorg::app
