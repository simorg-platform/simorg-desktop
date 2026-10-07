// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "AppModels.h"

#include "FlowerLayer.h"
#include "FlowerShape.h"

#include "simorg/appmodel/AccessGrantsModel.h"
#include "simorg/appmodel/ActivityModel.h"
#include "simorg/appmodel/ApplicationsModel.h"
#include "simorg/appmodel/AgentModels.h"
#include "simorg/appmodel/AuthModel.h"
#include "simorg/appmodel/DesktopPeer.h"
#include "simorg/appmodel/DesktopUpdateModel.h"
#include "simorg/appmodel/DockerListModels.h"
#include "simorg/appmodel/DockerModel.h"
#include "simorg/appmodel/HubModel.h"
#include "simorg/appmodel/LegalModel.h"
#include "simorg/appmodel/MachineCatalogModel.h"
#include "simorg/appmodel/MachineSetupModel.h"
#include "simorg/appmodel/PeersModel.h"
#include "simorg/appmodel/PreflightModel.h"
#include "simorg/appmodel/ServiceInstallModel.h"
#include "simorg/appmodel/UpdatesModel.h"
#include "simorg/appmodel/ServiceLinkModel.h"
#include "simorg/appmodel/SettingsModels.h"
#include "simorg/appmodel/ShutdownModel.h"
#include "simorg/appmodel/SurfaceModels.h"
#include "simorg/appmodel/TelemetryModel.h"
#include "simorg/appmodel/UninstallModel.h"
#include "simorg/appmodel/WorkspaceModels.h"
#include "simorg/frontend/OldTerminalCommands.h"

#include <QCoreApplication>

#include <QtQml>

namespace simorg::app {

AppModels AppModels::build(client::ServiceSession *session, const QString &environment, QObject *owner,
                           bool archiveBuild)
{
    AppModels models;
    models.telemetry = new TelemetryModel(session, owner);
    models.flower = new FlowerShape(owner);
    models.serviceLink = new ServiceLinkModel(session, owner);
    models.serviceInstall = new ServiceInstallModel(session, environment, owner);
    models.updates = new UpdatesModel(session, models.serviceInstall, owner);
    DesktopUpdateModel::Options desktop = DesktopUpdateModel::defaults();
    desktop.archiveBuild = archiveBuild;
    models.desktopUpdate = new DesktopUpdateModel(session, models.updates, desktop, owner);

    // Uninstall Simorg: the service's own uninstall, then what only this app can remove.
    UninstallModel::Parts gone = UninstallModel::defaultParts(environment);
    gone.source = QStringLiteral("desktop");
    gone.desktopVersion = QCoreApplication::applicationVersion();
    gone.holdServiceSetup = [install = models.serviceInstall] { install->hold(); };
    gone.removeLoginItems = [] { return removeCommandsAndLoginItems(); };
    gone.removeApp = [desktop](const QStringList &dataPaths) {
        return uninstall::removeInstalledCopy(desktop, dataPaths);
    };
    models.uninstall = new UninstallModel(session, gone, owner);
    models.legal = new LegalModel(session, owner);
    models.auth = new AuthModel(session, models.legal, owner);
    models.shutdown = new ShutdownModel(session, owner);
    models.hub = new HubModel(session, owner);
    models.machineSetup = new MachineSetupModel(session, owner);
    models.machineCatalog = new MachineCatalogModel(session, owner);
    models.machineConfig = new MachineConfigModel(session, owner);
    models.activity = new ActivityModel(session, owner);
    models.storage = new StorageModel(session, owner);
    models.artifacts = new ArtifactsModel(session, owner);
    models.peers = new PeersModel(session, owner);
    models.applications = new ApplicationsModel(session, owner);
    models.applicationDirectory = new ApplicationDirectoryModel(session, owner);
    // Availability in the directory is judged against the driver code the service names for this computer.
    QObject::connect(models.applications, &ApplicationsModel::changed, models.applicationDirectory,
                     [applications = models.applications, directory = models.applicationDirectory] {
                         directory->setDriverCode(applications->driverCode());
                     });
    models.logSettings = new LogSettingsModel(session, owner);
    models.docker = new DockerModel(session, owner);
    models.preflight = new PreflightModel(session, owner);
    models.agentContainers = new AgentContainersModel(session, owner);
    models.agentLifecycle = new AgentLifecycleModel(session, owner);
    models.agentSettings = new AgentSettingsModel(session, owner);
    models.agentDependencies = new AgentDependenciesModel(session, owner);
    models.agentVirtualMachine = new AgentVirtualMachineModel(session, owner);
    models.accessGrants = new AccessGrantsModel(session, owner);
    models.surfaces = new SurfaceRendererModel(session, owner);
    models.surfaceSessions = new SurfaceSessionsModel(session, models.surfaces, owner);
    // A component's log lines are its author's diagnostics: printed in a development build only.
    models.surfaceSessions->setComponentLogs(environment == QLatin1String("dev"));

    // Every container log is `Docker.logs` or an agent page's `Docker.agentLogs`, so the person's cap is applied at this one seam.
    const DockerModel *const docker = models.docker;
    const LogSettingsModel *const logSettings = models.logSettings;
    const auto applyCapacity = [docker, logSettings] {
        docker->logs()->setCapacity(logSettings->capacity());
        docker->agentLogs()->setCapacity(logSettings->capacity());
    };
    applyCapacity();
    QObject::connect(logSettings, &LogSettingsModel::changed, docker, applyCapacity);

    /*
      This app as the application agents use: connected once the platform has
      named it, which the service passes on with Access Management's
      answers, and what an agent writes to its `userLog` lands in that agent's log.
    */
    models.desktopPeer = new DesktopPeer(environment, owner);
    QObject::connect(models.accessGrants, &AccessGrantsModel::changed, models.desktopPeer,
                     [grants = models.accessGrants, peer = models.desktopPeer] {
                         const QStringList named = grants->alwaysAllowedApplications();
                         peer->setSpecifier(named.isEmpty() ? QString() : named.first());
                     });
    QObject::connect(models.desktopPeer, &DesktopPeer::userLog, models.docker, &DockerModel::appendUserLog);
    return models;
}

void AppModels::registerQml() const
{
    // Singletons rather than context properties: QML tooling type-checks them, and components loaded outside the
    // root context see them too.
    // The shape an account wears on the Logos, which every avatar in this app is drawn in.
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Flower", flower);
    // The web's light on that shape and its shadow under it, painted, because a shader is not drawn everywhere.
    qmlRegisterType<FlowerLayer>("Simorg", 1, 0, "FlowerLayer");
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Auth", auth);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Service", serviceLink);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "ServiceInstall", serviceInstall);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Updates", updates);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Uninstall", uninstall);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Legal", legal);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Shutdown", shutdown);
    // `track` only: an error QML could name is one QML already handled; the rest arrive through the log handler.
    qmlRegisterSingletonInstance("Simorg", 1, 0, "WatchDog", telemetry);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Hub", hub);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Docker", docker);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Preflight", preflight);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentContainers", agentContainers);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentLifecycle", agentLifecycle);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentSettings", agentSettings);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentDependencies", agentDependencies);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentVirtualMachine", agentVirtualMachine);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "MachineCatalog", machineCatalog);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AccessGrants", accessGrants);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "MachineConfig", machineConfig);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "MachineSetup", machineSetup);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Activity", activity);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Storage", storage);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "LogSettings", logSettings);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Artifacts", artifacts);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Peers", peers);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "Applications", applications);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "ApplicationDirectory", applicationDirectory);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "AgentSurfaces", surfaces);
    qmlRegisterSingletonInstance("Simorg", 1, 0, "SurfaceSessions", surfaceSessions);

    // The names QML reads enumerations by.
    const auto holder = [](const char *name) {
        return QStringLiteral("%1 is an enum holder").arg(QLatin1String(name));
    };
    qmlRegisterUncreatableType<AuthModel>("Simorg", 1, 0, "AuthState", holder("AuthState"));
    qmlRegisterUncreatableType<HubModel>("Simorg", 1, 0, "HubState", holder("HubState"));
    qmlRegisterUncreatableType<ConnectionModel>("Simorg", 1, 0, "ConnectionTrouble", holder("ConnectionTrouble"));
    qmlRegisterUncreatableType<DockerModel>("Simorg", 1, 0, "DockerStatus", holder("DockerStatus"));
    qmlRegisterUncreatableType<PreflightModel>("Simorg", 1, 0, "PreflightCheck", holder("PreflightCheck"));
    qmlRegisterUncreatableType<PreflightModel>("Simorg", 1, 0, "PreflightState", holder("PreflightState"));
    qmlRegisterUncreatableType<PreflightModel>("Simorg", 1, 0, "PreflightOutcome", holder("PreflightOutcome"));
    qmlRegisterUncreatableType<MachineSetupModel>("Simorg", 1, 0, "SetupState", holder("SetupState"));
    qmlRegisterUncreatableType<AgentVirtualMachineModel>("Simorg", 1, 0, "VirtualMachineStage",
                                                         holder("VirtualMachineStage"));
    qmlRegisterUncreatableType<SurfaceRendererModel>("Simorg", 1, 0, "SurfaceState", holder("SurfaceState"));

    // The models the singletons' properties are declared as; without these a role lookup silently reads undefined,
    // which on screen is an empty list.
    qmlRegisterUncreatableType<ContainerListModel>("Simorg", 1, 0, "ContainerModel",
                                                   QStringLiteral("provided by Docker.containers"));
    qmlRegisterUncreatableType<UpdateRowsModel>("Simorg", 1, 0, "UpdateRows", QStringLiteral("provided by Updates.rows"));
    qmlRegisterUncreatableType<ImageListModel>("Simorg", 1, 0, "ImageModel",
                                               QStringLiteral("provided by Docker.images"));
    qmlRegisterUncreatableType<DockerLogModel>("Simorg", 1, 0, "LogModel", QStringLiteral("provided by Docker.logs"));
    qmlRegisterUncreatableType<HostedAgentModel>("Simorg", 1, 0, "HostedAgentModel",
                                                 QStringLiteral("provided by Hub.agents"));
    qmlRegisterUncreatableType<HostedVirtualMachineModel>("Simorg", 1, 0, "HostedVirtualMachineModel",
                                                          QStringLiteral("provided by Hub.virtualMachines"));
    qmlRegisterUncreatableType<ActivityModel>("Simorg", 1, 0, "ActivityJournal",
                                              QStringLiteral("provided as Activity"));
    qmlRegisterUncreatableType<ArtifactsModel>("Simorg", 1, 0, "ArtifactCatalog",
                                               QStringLiteral("provided as Artifacts"));
    qmlRegisterUncreatableType<PeersModel>("Simorg", 1, 0, "PeerRoster", QStringLiteral("provided as Peers"));
    qmlRegisterUncreatableType<AccessCategoryModel>("Simorg", 1, 0, "AccessCategoryModel",
                                                    QStringLiteral("provided by MachineCatalog.accessCategories"));
    qmlRegisterUncreatableType<SurfaceSessionModel>("Simorg", 1, 0, "SurfaceSession",
                                                    QStringLiteral("opened by SurfaceSessions.open"));
}

} // namespace simorg::app
