// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#include "simorg/appmodel/UpdatesModel.h"

#include "simorg/appmodel/ServiceInstallModel.h"
#include "simorg/client/ServiceSession.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSysInfo>
#include <QUrl>

#include <utility>

namespace simorg::app {

using client::ServiceReply;
using client::ServiceSession;
using client::TopicSubscription;

namespace updatecopy {

QString itemName(const QString &item, bool sentenceStart)
{
    if (item == QLatin1String("desktop"))
        return QObject::tr("Simorg Desktop");
    if (item == QLatin1String("cli"))
        return QObject::tr("Simorg CLI");
    if (item == QLatin1String("service"))
        return sentenceStart ? QObject::tr("The Simorg machine service") : QObject::tr("the Simorg machine service");
    return sentenceStart ? QObject::tr("The agent runtime") : QObject::tr("the agent runtime");
}

QString barTitle()
{
    return QObject::tr("Keep Simorg up to date");
}

QString barBody(const QStringList &items)
{
    const QString why = QObject::tr("Updating brings you the latest fixes and security improvements, and keeps your "
                                    "agents running at their best.");
    if (items.isEmpty())
        return {};
    if (items.size() == 1)
        return QObject::tr("A new version of %1 is ready. %2").arg(itemName(items.first(), false), why);
    QStringList names;
    for (const QString &item : items)
        names.append(itemName(item, false));
    const QString last = names.takeLast();
    return QObject::tr("New versions of %1 and %2 are ready. %3").arg(names.join(QStringLiteral(", ")), last, why);
}

QString updatingSentence(const QString &item)
{
    if (item == QLatin1String("desktop"))
        return QObject::tr("Updating Simorg Desktop. It closes and opens again on the new version.");
    if (item == QLatin1String("cli"))
        return QObject::tr("Updating Simorg CLI. Your agents keep running, because the sim command does not run them.");
    if (item == QLatin1String("service"))
        return QObject::tr("Updating the Simorg machine service. Your agents keep running while it restarts.");
    return QObject::tr("Updating the agent runtime. Your agents restart on the new version one at a time.");
}

QString barButton()
{
    return QObject::tr("Review and update");
}

QString requiredTitle()
{
    return QObject::tr("An update is required");
}

QString requiredBody(const QStringList &items)
{
    if (items.isEmpty())
        return {};
    QStringList names;
    for (const QString &item : items)
        names.append(itemName(item, false));
    const QString last = names.takeLast();
    const QString which = names.isEmpty() ? last : QObject::tr("%1 and %2").arg(names.join(QStringLiteral(", ")), last);
    return QObject::tr("The version of %1 on this computer is older than Simorg now supports, so updating is "
                       "required. Nothing stops working because of it.")
        .arg(which);
}

QString restartButton()
{
    return QObject::tr("Restart to finish updating");
}

QString beforeUpdating(const QString &item)
{
    if (item == QLatin1String("desktop"))
        return QObject::tr("Simorg Desktop closes and opens again on the new version, because an app cannot replace "
                           "itself while it runs.");
    if (item == QLatin1String("cli"))
        return QObject::tr("The sim command replaces itself with the new version. Your agents keep running, because "
                           "the sim command does not run them.");
    if (item == QLatin1String("service"))
        return QObject::tr("Your administrator password is asked for, because the machine service is installed for "
                           "everybody on this computer. Your agents keep running while it restarts.");
    return QObject::tr("Your running agents restart on the new version one at a time, because a running agent keeps "
                       "the version it started on.");
}

QString beforeUpdatingOlderService()
{
    return QObject::tr("Your administrator password is asked for, because the machine service is installed for "
                       "everybody on this computer. Your running agents stop and start again once, because this older "
                       "version cannot update itself without stopping them; later updates keep them running.");
}

QString updatingOlderService()
{
    return QObject::tr("Updating the Simorg machine service. Your agents start again as soon as the new version is "
                       "running.");
}

} // namespace updatecopy

namespace {

QString text(const QJsonObject &object, const char *key)
{
    return object.value(QLatin1String(key)).toString();
}

/** Whether an update in `phase` may still be cancelled. */
bool cancellable(const QString &item, const QString &phase)
{
    // A prepared Simorg Desktop waits for somebody's restart; "Not now" leaves it for the next Update.
    if (phase == QLatin1String("ready_to_restart"))
        return true;
    if (item == QLatin1String("agent_runtime"))
        return phase == QLatin1String("downloading") || phase == QLatin1String("loading");
    // `unpacking` is the app's own; the service's rows never reach it.
    return phase == QLatin1String("choosing") || phase == QLatin1String("downloading") ||
           phase == QLatin1String("verifying") || phase == QLatin1String("unpacking") ||
           phase == QLatin1String("waiting_for_permission");
}

QString rowTitle(const QString &item)
{
    if (item == QLatin1String("desktop"))
        return QObject::tr("Simorg Desktop");
    if (item == QLatin1String("cli"))
        return QObject::tr("Simorg CLI");
    if (item == QLatin1String("service"))
        return QObject::tr("Simorg machine service");
    return QObject::tr("Agent runtime");
}

bool hasUpdate(const QJsonObject &row)
{
    const QString state = text(row, "state");
    return !row.value(QStringLiteral("available")).toString().isEmpty() &&
           (state == QLatin1String("available") || state == QLatin1String("updating") ||
            state == QLatin1String("failed"));
}

bool isRunning(const QJsonObject &row)
{
    const QJsonObject operation = row.value(QStringLiteral("operation")).toObject();
    return !operation.isEmpty() && operation.value(QStringLiteral("outcome")).isNull();
}

/** Prepared and waiting for somebody's restart, which is not an update running. */
bool readyToRestart(const QJsonObject &row)
{
    return isRunning(row) &&
           text(row.value(QStringLiteral("operation")).toObject(), "phase") == QLatin1String("ready_to_restart");
}

} // namespace

UpdateRowsModel::UpdateRowsModel(QObject *parent) : KeyedRowsModel("item", parent) {}

QHash<int, QByteArray> UpdateRowsModel::roleNames() const
{
    return {
        {ItemRole, "item"},           {TitleRole, "title"},         {InstalledRole, "installed"},
        {AvailableRole, "available"}, {StateRole, "updateState"},         {CanUpdateRole, "canUpdate"},
        {ReasonRole, "reason"},       {PhaseRole, "phase"},         {ProgressRole, "progress"},
        {MessageRole, "message"},     {OutcomeRole, "outcome"},     {ProblemRole, "problem"},
        {OutputRole, "output"},       {CancellableRole, "cancellable"}, {ExplanationRole, "explanation"},
        {LastUpdateRole, "lastUpdate"}, {RefusalRole, "refusal"},
        {NotesRole, "notes"},           {RequiredRole, "required"}, {ReadyToRestartRole, "readyToRestart"},
        {DownloadStateRole, "downloadState"},
    };
}

QVariant UpdateRowsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &item = row(index.row());
    const QString name = text(item, "item");
    const QJsonObject operation = item.value(QStringLiteral("operation")).toObject();
    const bool running = !operation.isEmpty() && operation.value(QStringLiteral("outcome")).isNull();
    switch (role) {
    case ItemRole:
        return name;
    case TitleRole:
        return rowTitle(name);
    case InstalledRole:
        return text(item, "installed");
    case AvailableRole:
        return text(item, "available");
    case StateRole:
        return text(item, "state");
    case CanUpdateRole:
        return item.value(QStringLiteral("can_update")).toBool();
    case ReasonRole:
        return text(item, "unavailable_reason");
    case PhaseRole:
        return running ? text(operation, "phase") : QString();
    case ProgressRole: {
        // -1 for "no measure": the bar sweeps rather than stopping or disappearing.
        const QJsonValue progress = operation.value(QStringLiteral("progress"));
        return running && progress.isDouble() ? progress.toDouble() : -1.0;
    }
    case MessageRole:
        return text(operation, "message");
    case OutcomeRole:
        return operation.value(QStringLiteral("outcome")).toString();
    case ProblemRole: {
        const QJsonObject problem = operation.value(QStringLiteral("problem")).toObject();
        const QString detail = text(problem, "detail");
        return detail.isEmpty() ? text(problem, "title") : detail;
    }
    case OutputRole:
        return text(operation, "output");
    case CancellableRole:
        return running && cancellable(name, text(operation, "phase"));
    case ExplanationRole:
        if (!hasUpdate(item) || running)
            return QString();
        return item.value(QStringLiteral("legacy")).toBool() ? updatecopy::beforeUpdatingOlderService()
                                                            : updatecopy::beforeUpdating(name);
    case LastUpdateRole: {
        const QJsonObject last = item.value(QStringLiteral("last_update")).toObject();
        if (last.isEmpty())
            return QString();
        if (text(last, "outcome") == QLatin1String("succeeded"))
            return QObject::tr("Updated from %1 to %2.").arg(text(last, "from"), text(last, "to"));
        return QObject::tr("The update from %1 to %2 did not finish, so %1 is still running.")
            .arg(text(last, "from"), text(last, "to"));
    }
    case RefusalRole:
        return text(item, "refusal");
    case NotesRole: {
        QVariantList notes;
        for (const QJsonValue &value : item.value(QStringLiteral("notes")).toArray()) {
            const QJsonObject note = value.toObject();
            notes.append(QVariantMap{{QStringLiteral("version"), text(note, "version")},
                                     {QStringLiteral("notes"), text(note, "notes")}});
        }
        return notes;
    }
    case RequiredRole:
        return item.value(QStringLiteral("required")).toBool();
    case ReadyToRestartRole:
        return readyToRestart(item);
    case DownloadStateRole:
        return text(item.value(QStringLiteral("download")).toObject(), "state");
    default:
        return {};
    }
}

UpdatesModel::UpdatesModel(ServiceSession *session, ServiceInstallModel *install, QObject *parent)
    : QObject(parent), m_session(session), m_install(install), m_rows(new UpdateRowsModel(this))
{
    if (!m_session)
        return;
    connect(m_session, &ServiceSession::connected, this, [this] {
        m_restarting = false;
        // A service older than API 1.1 has no updates area, and its row is read from the index instead.
        const QString api = m_session->version().value(QStringLiteral("api_version")).toString();
        m_legacy = api.section(QLatin1Char('.'), 1, 1).toInt() < 1 && api.section(QLatin1Char('.'), 0, 0) == QLatin1String("1");
        if (m_legacy)
            readLegacyIndex();
        subscribe();
        rebuild();
    });
    connect(m_session, &ServiceSession::disconnected, this, [this] {
        // The service left to start its updated binary; the connection bar says so rather than "unavailable".
        for (const QJsonObject &row : std::as_const(m_serviceRows)) {
            if (text(row, "item") == QLatin1String("service") &&
                text(row.value(QStringLiteral("operation")).toObject(), "phase") == QLatin1String("restarting"))
                m_restarting = true;
        }
        Q_EMIT changed();
    });
    if (m_install) {
        connect(m_install, &ServiceInstallModel::changed, this, [this] {
            if (m_legacy)
                rebuild();
        });
    }
    subscribe();
}

void UpdatesModel::subscribe()
{
    if (m_subscription || !m_session)
        return;
    m_subscription = m_session->subscribe(QStringLiteral("updates.state"));
    connect(m_subscription, &TopicSubscription::received, this, &UpdatesModel::applyDocument);
    connect(m_subscription, &TopicSubscription::refused, this, [this] {
        // An older service: the topic does not exist there.
        m_legacy = true;
        readLegacyIndex();
        rebuild();
    });
    if (m_subscription->hasValue())
        applyDocument(m_subscription->value());
}

void UpdatesModel::applyDocument(const QJsonObject &document)
{
    m_legacy = false;
    m_checkedAt = text(document, "checked_at");
    // A service before the setting says nothing of it, and the switch is not shown.
    const QJsonValue automatic = document.value(QStringLiteral("auto_update"));
    m_autoUpdateOffered = automatic.isBool();
    m_autoUpdate = automatic.toBool();
    m_serviceRows.clear();
    QJsonObject desktop;
    for (const QJsonValue &value : document.value(QStringLiteral("items")).toArray()) {
        // This app's row as the service checked it goes to the app's own model, which draws the row.
        if (text(value.toObject(), "item") == QLatin1String("desktop"))
            desktop = value.toObject();
        else
            m_serviceRows.append(value.toObject());
    }
    if (desktop != m_serviceDesktop) {
        m_serviceDesktop = desktop;
        if (!desktop.isEmpty())
            Q_EMIT serviceDesktopChanged(desktop);
    }
    rebuild();
}

void UpdatesModel::readLegacyIndex(const std::function<void()> &done)
{
    // Only where this app can install a package: a development build talks to a service built from source.
    if (!m_install || !m_install->isAvailable()) {
        if (done)
            done();
        return;
    }
    if (!m_network)
        m_network = new QNetworkAccessManager(this);
    // What pressing would find first: the installer and this computer's package, checked as the setup checks them,
    // so the row never offers an update that is refused before the password.
    m_install->checkPublished([this](const QString &problem) {
        m_legacyBlocked = problem;
        rebuild();
    });
    const QString host = serviceinstall::downloadHost();
    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(host + QStringLiteral("/binaries/simorgm/index.json"))));
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        if (done)
            done();
        if (reply->error() != QNetworkReply::NoError)
            return;
        const QByteArray body = reply->readAll();
        const QString target =
            serviceinstall::packageTarget(serviceinstall::thisPlatform(), QSysInfo::currentCpuArchitecture());
        const QString current = QJsonDocument::fromJson(body).object().value(QStringLiteral("current")).toString();
        m_legacyAvailable = serviceinstall::publishedFor(body, target) ? current : QString();
        rebuild();
    });
}

void UpdatesModel::applyLegacy()
{
    // The service's own row, from GET /v1/version and the release index, updated through ServiceInstall.
    // A build that cannot install a package (a development one) shows no row rather than an update it cannot make.
    if (!m_install || !m_install->isAvailable()) {
        m_serviceRows.clear();
        return;
    }
    // `legacy`: replaced by its package rather than updating itself, which stops its agents once.
    QJsonObject row{{QStringLiteral("item"), QStringLiteral("service")}, {QStringLiteral("legacy"), true}};
    const QString installed = m_session ? m_session->version().value(QStringLiteral("version")).toString() : QString();
    row.insert(QStringLiteral("installed"), installed);
    const bool newer = !m_legacyAvailable.isEmpty() && m_legacyAvailable != installed;
    row.insert(QStringLiteral("available"), newer ? QJsonValue(m_legacyAvailable) : QJsonValue());
    row.insert(QStringLiteral("state"), newer ? QStringLiteral("available") : QStringLiteral("up_to_date"));
    const bool can = m_install && m_install->isAvailable() && m_legacyBlocked.isEmpty();
    row.insert(QStringLiteral("can_update"), newer && can);
    if (newer && !can && m_install) {
        row.insert(QStringLiteral("unavailable_reason"),
                   !m_install->isAvailable()
                       ? m_install->unavailableReason()
                       : tr("%1, so Simorg cannot update this older service from here yet.").arg(m_legacyBlocked));
    }
    if (m_install && m_install->wasAttempted()) {
        QJsonObject operation{{QStringLiteral("phase"), QStringLiteral("installing")},
                              {QStringLiteral("message"), m_install->status()},
                              {QStringLiteral("progress"), QJsonValue()},
                              {QStringLiteral("output"), m_install->output()}};
        if (m_install->isRunning()) {
            operation.insert(QStringLiteral("outcome"), QJsonValue());
            row.insert(QStringLiteral("state"), QStringLiteral("updating"));
        } else if (m_install->hasFailed()) {
            operation.insert(QStringLiteral("outcome"), QStringLiteral("failed"));
            operation.insert(QStringLiteral("problem"), QJsonObject{{QStringLiteral("title"), m_install->status()}});
            if (newer)
                row.insert(QStringLiteral("state"), QStringLiteral("failed"));
        } else {
            operation.insert(QStringLiteral("outcome"),
                             m_install->wasDeclined() ? QStringLiteral("declined") : QStringLiteral("succeeded"));
        }
        row.insert(QStringLiteral("operation"), operation);
    }
    m_serviceRows = {row};
}

void UpdatesModel::rebuild()
{
    if (m_legacy)
        applyLegacy();
    /*
      Simorg Desktop first, then the service, then the agent runtime, and Simorg CLI
      last, listed by the service only once the sim command registered on this computer.
    */
    QList<QJsonObject> rows;
    if (!m_desktopRow.isEmpty())
        rows.append(m_desktopRow);
    for (const char *name : {"service", "agent_runtime", "cli"}) {
        for (const QJsonObject &row : std::as_const(m_serviceRows)) {
            if (text(row, "item") == QLatin1String(name))
                rows.append(row);
        }
    }
    for (QJsonObject &row : rows) {
        // A refusal belongs to the press that caused it; once the item is running it has been answered.
        const QString item = text(row, "item");
        if (isRunning(row))
            m_refusals.remove(item);
        else if (m_refusals.contains(item))
            row.insert(QStringLiteral("refusal"), m_refusals.value(item));
    }
    m_current = rows;
    m_rows->reconcile(rows);
    Q_EMIT changed();
}

void UpdatesModel::requestReview()
{
    if (std::exchange(m_reviewPending, true))
        return;
    Q_EMIT reviewPendingChanged();
}

void UpdatesModel::reviewed()
{
    if (!std::exchange(m_reviewPending, false))
        return;
    Q_EMIT reviewPendingChanged();
}

void UpdatesModel::setDesktopRow(const QJsonObject &row)
{
    m_desktopRow = row;
    rebuild();
}

bool UpdatesModel::anyAvailable() const
{
    for (const QJsonObject &row : m_current) {
        if (hasUpdate(row))
            return true;
    }
    return false;
}

bool UpdatesModel::isUpdating() const
{
    for (const QJsonObject &row : m_current) {
        if (isRunning(row) && !readyToRestart(row))
            return true;
    }
    return false;
}

bool UpdatesModel::isRequired() const
{
    for (const QJsonObject &row : m_current) {
        if (hasUpdate(row) && row.value(QStringLiteral("required")).toBool())
            return true;
    }
    return false;
}

bool UpdatesModel::isRestartPending() const
{
    for (const QJsonObject &row : m_current) {
        if (readyToRestart(row))
            return true;
    }
    return false;
}

QString UpdatesModel::barTitle() const
{
    return isRequired() && !isUpdating() && !isRestartPending() ? updatecopy::requiredTitle() : updatecopy::barTitle();
}

QString UpdatesModel::barBody() const
{
    for (const QJsonObject &row : m_current) {
        if (isRunning(row) && !readyToRestart(row))
            return row.value(QStringLiteral("legacy")).toBool() ? updatecopy::updatingOlderService()
                                                               : updatecopy::updatingSentence(text(row, "item"));
    }
    // Prepared, and the app's own sentence says what the restart does.
    for (const QJsonObject &row : m_current) {
        if (readyToRestart(row))
            return text(row.value(QStringLiteral("operation")).toObject(), "message");
    }
    QStringList items;
    QStringList required;
    for (const QJsonObject &row : m_current) {
        if (!hasUpdate(row))
            continue;
        items.append(text(row, "item"));
        if (row.value(QStringLiteral("required")).toBool())
            required.append(text(row, "item"));
    }
    return required.isEmpty() ? updatecopy::barBody(items) : updatecopy::requiredBody(required);
}

void UpdatesModel::restartToFinish()
{
    Q_EMIT desktopRestartRequested();
}

void UpdatesModel::check()
{
    Q_EMIT desktopCheckRequested();
    if (!m_session || m_checking)
        return;
    m_checking = true;
    Q_EMIT changed();
    const auto done = [this] {
        m_checking = false;
        Q_EMIT changed();
    };
    if (m_legacy) {
        readLegacyIndex(done);
        return;
    }
    /*
      The answer is the same document `updates.state` carries, and it is applied from the reply as well: the screen
      that asked shows what was found the moment it is found, whatever the topic is doing.
    */
    ServiceReply *reply = m_session->post(QStringLiteral("/v1/updates/check"));
    connect(reply, &ServiceReply::finished, this, [this, reply, done] {
        if (!reply->isError() && reply->object().contains(QStringLiteral("items")))
            applyDocument(reply->object());
        done();
    });
}

void UpdatesModel::update(const QString &item)
{
    if (m_refusals.remove(item) > 0)
        rebuild();
    if (item == QLatin1String("desktop")) {
        Q_EMIT desktopUpdateRequested();
        return;
    }
    if (item == QLatin1String("service") && m_legacy) {
        if (m_install)
            m_install->install();
        return;
    }
    if (!m_session)
        return;
    // Simorg CLI's is run by the service with the sim command it registered.
    const QString path = item == QLatin1String("service") ? QStringLiteral("/v1/updates/service")
                         : item == QLatin1String("cli")  ? QStringLiteral("/v1/updates/cli")
                                                          : QStringLiteral("/v1/updates/agent-runtime");
    const QJsonObject body = item == QLatin1String("service")
                                 ? QJsonObject{{QStringLiteral("elevation"), QStringLiteral("os_prompt")}}
                                 : QJsonObject{};
    ServiceReply *reply = m_session->post(path, body);
    connect(reply, &ServiceReply::finished, this, [this, reply, item] {
        if (reply->isError())
            refuse(item, reply->problem().detail.isEmpty() ? reply->problem().title : reply->problem().detail);
    });
}

void UpdatesModel::setAutoUpdate(bool on)
{
    if (!m_session || m_autoUpdateSaving || !m_autoUpdateOffered || on == m_autoUpdate)
        return;
    m_autoUpdateSaving = true;
    m_autoUpdateError.clear();
    Q_EMIT changed();
    ServiceReply *reply = m_session->put(QStringLiteral("/v1/updates/policy"), {{QStringLiteral("auto_update"), on}});
    connect(reply, &ServiceReply::finished, this, [this, reply] {
        m_autoUpdateSaving = false;
        if (reply->isError()) {
            m_autoUpdateError = reply->problem().detail.isEmpty() ? reply->problem().title : reply->problem().detail;
            Q_EMIT changed();
            return;
        }
        // The answer is the list with the saved setting; `updates.state` says the same a moment later.
        applyDocument(reply->object());
    });
}

void UpdatesModel::cancel(const QString &item)
{
    if (m_refusals.remove(item) > 0)
        rebuild();
    if (item == QLatin1String("desktop")) {
        Q_EMIT desktopCancelRequested();
        return;
    }
    if (!m_session || m_legacy)
        return;
    const QString path = item == QLatin1String("service") ? QStringLiteral("/v1/updates/service/cancel")
                         : item == QLatin1String("cli")  ? QStringLiteral("/v1/updates/cli/cancel")
                                                          : QStringLiteral("/v1/updates/agent-runtime/cancel");
    ServiceReply *reply = m_session->post(path);
    connect(reply, &ServiceReply::finished, this, [this, reply, item] {
        if (reply->isError())
            refuse(item, reply->problem().detail.isEmpty() ? reply->problem().title : reply->problem().detail);
    });
}

void UpdatesModel::refuse(const QString &item, const QString &message)
{
    m_refusals.insert(item, message);
    rebuild();
    Q_EMIT actionFailed(item, message);
}

} // namespace simorg::app
