// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include "simorg/appmodel/DockerListModels.h"

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>

#include <functional>

class QNetworkAccessManager;

namespace simorg::client {
class ServiceSession;
class TopicSubscription;
} // namespace simorg::client

namespace simorg::app {

class ServiceInstallModel;

/**
 * The words of the updates bar and view — positive, action-oriented, and saying
 * why updating matters — kept apart from the model so every sentence is tested.
 */
namespace updatecopy {

/** `desktop`, `service` or `agent_runtime` as a person reads it, at the start of a sentence or inside one. */
QString itemName(const QString &item, bool sentenceStart);

/** The bar's title. */
QString barTitle();

/** The bar's body for the items with an update, in the order given: one names it, several are joined. */
QString barBody(const QStringList &items);

/** The bar's sentence while `item` updates. */
QString updatingSentence(const QString &item);

/** The bar's button. */
QString barButton();

/** The bar's title while an update is required rather than offered. */
QString requiredTitle();

/** The bar's body for required updates, in the order given, with why they are required. */
QString requiredBody(const QStringList &items);

/** The button that hands a prepared Simorg Desktop over. */
QString restartButton();

/** What pressing Update on `item` will do, said before it is pressed, with its reason. */
QString beforeUpdating(const QString &item);

/**
 * The same for a service older than API 1.1, which its new package replaces: stopping it stops its agents, so
 * they start again once, unlike every update after it.
 */
QString beforeUpdatingOlderService();

/** The bar's sentence while that older service is replaced. */
QString updatingOlderService();

} // namespace updatecopy

/**
 * One row per updatable thing (`UpdateItem`) for Settings → Updates, changed row by row so progress moves on the rows
 * already on screen and bars never restart.
 */
class UpdateRowsModel : public KeyedRowsModel
{
    Q_OBJECT

public:
    enum Role {
        ItemRole = Qt::UserRole + 1,
        TitleRole,
        InstalledRole,
        AvailableRole,
        StateRole,
        CanUpdateRole,
        ReasonRole,
        PhaseRole,
        ProgressRole,
        MessageRole,
        OutcomeRole,
        ProblemRole,
        OutputRole,
        CancellableRole,
        ExplanationRole,
        LastUpdateRole,
        RefusalRole,
        /** Every release note since the installed version, newest first, as `{version, notes}` maps. */
        NotesRole,
        /** The update is required rather than offered. */
        RequiredRole,
        /** Simorg Desktop is prepared and waits only for a restart. */
        ReadyToRestartRole,
        /** The download ahead: `idle`, `downloading`, `ready` or `failed`. */
        DownloadStateRole,
    };

    explicit UpdateRowsModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
};

/**
 * Updates, as QML reads them off `Updates`: the
 * Simorg machine service and the agent runtime image from the service's
 * `updates.state`, and Simorg Desktop from the app's own model, which takes the
 * release the service checked for it.
 *
 * Nothing updates by itself unless the machine's **Install updates
 * automatically** is on, which the service carries out and
 * this model only shows and changes: the bar says an update is ready and stays
 * until it is installed, and each row's Update is the person's press. A service
 * older than API 1.1 has no updates area; its row is then read from the release
 * index directly and updated the way a missing service is installed, through
 * `ServiceInstall`, which is how a computer with an older service is brought
 * across.
 */
class UpdatesModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(simorg::app::UpdateRowsModel *rows READ rows CONSTANT)
    /** Whether the bar shows: something has an update that is not installed yet. */
    Q_PROPERTY(bool anyAvailable READ anyAvailable NOTIFY changed)
    Q_PROPERTY(bool updating READ isUpdating NOTIFY changed)
    /** An update on offer is required, which the bar says in its title and its tone. */
    Q_PROPERTY(bool required READ isRequired NOTIFY changed)
    /** Simorg Desktop is prepared, and the bar's button restarts it to finish. */
    Q_PROPERTY(bool restartPending READ isRestartPending NOTIFY changed)
    Q_PROPERTY(QString barTitle READ barTitle NOTIFY changed)
    Q_PROPERTY(QString barBody READ barBody NOTIFY changed)
    Q_PROPERTY(QString barButton READ barButton CONSTANT)
    Q_PROPERTY(QString restartButton READ restartButton CONSTANT)
    /** The service left to start its updated binary and has not answered again yet. */
    Q_PROPERTY(bool serviceRestarting READ isServiceRestarting NOTIFY changed)
    /** When the service last checked, in RFC 3339; empty before the first check. */
    Q_PROPERTY(QString checkedAt READ checkedAt NOTIFY changed)
    /** A check somebody asked for is under way (`check()`), for the button that asked to say so. */
    Q_PROPERTY(bool checking READ isChecking NOTIFY changed)
    /**
     * This app was just opened by its own update: the window shows Settings → Updates, where the
     * person pressed it, and calls `reviewed()`.
     */
    Q_PROPERTY(bool reviewPending READ isReviewPending NOTIFY reviewPendingChanged)
    /**
     * Whether this machine installs its updates by itself, as the service last heard
     * from the platform. `autoUpdateOffered` is false until a service that knows the setting says it.
     */
    Q_PROPERTY(bool autoUpdate READ autoUpdate NOTIFY changed)
    Q_PROPERTY(bool autoUpdateOffered READ autoUpdateOffered NOTIFY changed)
    /** A change of the setting is on its way to the platform. */
    Q_PROPERTY(bool autoUpdateSaving READ autoUpdateSaving NOTIFY changed)
    /** Why the last change was not saved, in the service's or the platform's words; empty otherwise. */
    Q_PROPERTY(QString autoUpdateError READ autoUpdateError NOTIFY changed)

public:
    UpdatesModel(client::ServiceSession *session, ServiceInstallModel *install, QObject *parent = nullptr);

    UpdateRowsModel *rows() const { return m_rows; }
    bool anyAvailable() const;
    bool isUpdating() const;
    bool isRequired() const;
    bool isRestartPending() const;
    QString barTitle() const;
    QString barBody() const;
    QString barButton() const { return updatecopy::barButton(); }
    QString restartButton() const { return updatecopy::restartButton(); }
    bool isServiceRestarting() const { return m_restarting; }
    QString checkedAt() const { return m_checkedAt; }
    bool isChecking() const { return m_checking; }
    bool isReviewPending() const { return m_reviewPending; }
    bool autoUpdate() const { return m_autoUpdate; }
    bool autoUpdateOffered() const { return m_autoUpdateOffered; }
    bool autoUpdateSaving() const { return m_autoUpdateSaving; }
    QString autoUpdateError() const { return m_autoUpdateError; }

    /** Asks the window to show Settings → Updates once it is up. */
    void requestReview();

    /** The app's own row (W7); nothing until the app has checked itself. */
    void setDesktopRow(const QJsonObject &row);

    /** The rows as they stand, service first; exposed for tests. */
    QList<QJsonObject> currentRows() const { return m_current; }

public Q_SLOTS:
    /** Asks the service to read both indexes now; the view calls it as it opens. */
    void check();
    /** `desktop`, `service`, `agent_runtime` or `cli`: the person pressed Update. */
    void update(const QString &item);
    void cancel(const QString &item);
    /** The window has shown Settings → Updates. */
    void reviewed();
    /** The person pressed Restart to finish updating. */
    void restartToFinish();
    /** The person turned Install updates automatically on or off; the service saves it on the platform. */
    void setAutoUpdate(bool on);

Q_SIGNALS:
    void changed();
    /** A press the service refused, with its sentence; the row shows it too, as `refusal`. */
    void actionFailed(const QString &item, const QString &message);
    /** The person pressed Update on the app's own row; the desktop update model takes it. */
    void desktopUpdateRequested();
    void desktopCancelRequested();
    /** The Updates view opened, or something asked for a check: the app checks for itself too. */
    void desktopCheckRequested();
    void reviewPendingChanged();
    /** The service's own row for this app, the release it checked and its notes. */
    void serviceDesktopChanged(const QJsonObject &item);
    /** The person pressed Restart to finish updating; the desktop update model hands over. */
    void desktopRestartRequested();

private:
    void subscribe();
    void applyDocument(const QJsonObject &document);
    void applyLegacy();
    /** `done` once the index has answered or failed; the check button waits on it. */
    void readLegacyIndex(const std::function<void()> &done = {});
    void rebuild();
    void refuse(const QString &item, const QString &message);

    client::ServiceSession *m_session;
    QPointer<ServiceInstallModel> m_install;
    client::TopicSubscription *m_subscription = nullptr;
    UpdateRowsModel *m_rows;
    QList<QJsonObject> m_serviceRows;
    QJsonObject m_desktopRow;
    /** The service's `desktop` item, handed to the desktop update model as it moves. */
    QJsonObject m_serviceDesktop;
    QList<QJsonObject> m_current;
    QString m_checkedAt;
    bool m_legacy = false;
    bool m_restarting = false;
    bool m_reviewPending = false;
    bool m_checking = false;
    bool m_autoUpdate = false;
    bool m_autoUpdateOffered = false;
    bool m_autoUpdateSaving = false;
    QString m_autoUpdateError;
    QString m_legacyAvailable;
    /** Why the installer an older service is updated with cannot run yet (its pre-flight check); empty when it can. */
    QString m_legacyBlocked;
    /** The service's sentence for the last press it refused, per item, until the next press of that item. */
    QHash<QString, QString> m_refusals;
    QNetworkAccessManager *m_network = nullptr;
};

} // namespace simorg::app
