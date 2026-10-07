// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

class QObject;

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

class AccessGrantsModel;
class ApplicationDirectoryModel;
class ApplicationsModel;
class ActivityModel;
class AgentContainersModel;
class AgentDependenciesModel;
class AgentLifecycleModel;
class AgentSettingsModel;
class AgentVirtualMachineModel;
class ArtifactsModel;
class AuthModel;
class DesktopPeer;
class DesktopUpdateModel;
class DockerModel;
class FlowerShape;
class HubModel;
class LegalModel;
class LogSettingsModel;
class MachineCatalogModel;
class MachineConfigModel;
class MachineSetupModel;
class PeersModel;
class PreflightModel;
class ServiceInstallModel;
class UninstallModel;
class UpdatesModel;
class ServiceLinkModel;
class ShutdownModel;
class StorageModel;
class SurfaceRendererModel;
class SurfaceSessionsModel;
class TelemetryModel;

/**
 * Every object the interface's QML singletons are, on one service session, and the
 * one place they are named to QML.
 *
 * Shared by the app and by the interface tests, which compile this file beside
 * themselves: a window the tests render against differently registered objects would
 * be a window the tests do not test.
 */
struct AppModels
{
    /**
     * Builds them all, owned by `owner`, on `session`. `environment` is `dev` or `prod`. `archiveBuild` is
     * `SIMORG_ARCHIVE_BUILD`, which only the app itself knows: a test's copy never replaces itself.
     */
    static AppModels build(client::ServiceSession *session, const QString &environment, QObject *owner,
                           bool archiveBuild = false);

    /** Registers each as its `Simorg` singleton, with the enumeration and model types QML reads. `App` is not one. */
    void registerQml() const;

    TelemetryModel *telemetry = nullptr;
    FlowerShape *flower = nullptr;
    ServiceLinkModel *serviceLink = nullptr;
    /** Installs the machine service when the starting window finds none (`ServiceInstall`). */
    ServiceInstallModel *serviceInstall = nullptr;
    /** Settings → Updates and the bar that leads there. */
    UpdatesModel *updates = nullptr;
    /** The app's own row in Settings → Updates, and its update. Not a QML singleton. */
    DesktopUpdateModel *desktopUpdate = nullptr;
    /** Settings → Uninstall and the window that follows it. */
    UninstallModel *uninstall = nullptr;
    LegalModel *legal = nullptr;
    AuthModel *auth = nullptr;
    ShutdownModel *shutdown = nullptr;
    HubModel *hub = nullptr;
    MachineSetupModel *machineSetup = nullptr;
    MachineCatalogModel *machineCatalog = nullptr;
    MachineConfigModel *machineConfig = nullptr;
    ActivityModel *activity = nullptr;
    StorageModel *storage = nullptr;
    ArtifactsModel *artifacts = nullptr;
    PeersModel *peers = nullptr;
    ApplicationsModel *applications = nullptr;
    ApplicationDirectoryModel *applicationDirectory = nullptr;
    LogSettingsModel *logSettings = nullptr;
    DockerModel *docker = nullptr;
    PreflightModel *preflight = nullptr;
    AgentContainersModel *agentContainers = nullptr;
    AgentLifecycleModel *agentLifecycle = nullptr;
    AgentSettingsModel *agentSettings = nullptr;
    AgentDependenciesModel *agentDependencies = nullptr;
    AgentVirtualMachineModel *agentVirtualMachine = nullptr;
    AccessGrantsModel *accessGrants = nullptr;
    /** This app as the application agents use, on the service's peer pipe. Not a QML singleton. */
    DesktopPeer *desktopPeer = nullptr;
    SurfaceRendererModel *surfaces = nullptr;
    SurfaceSessionsModel *surfaceSessions = nullptr;
};

} // namespace simorg::app
