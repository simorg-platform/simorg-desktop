# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# `simorg-desktop` — the tray-resident GUI.
#
# Qt Widgets is here for one reason: QSystemTrayIcon and its native context
# menu. Everything the user looks at is Qt Quick.

find_package(Qt6 ${SIMORG_QT_MIN_VERSION} REQUIRED COMPONENTS
    Core
    Gui
    Network
    Qml
    Quick
    QuickControls2
    Svg
    Widgets
)

# --- The browser engine, and why it is a switch -------------------------------
#
# An agent's Workbench and Brain are web pages: a renderer published as an
# artifact, fetched at run time. Drawing them needs Chromium, and Chromium is
# a large thing to make mandatory — QtWebEngineCore is a binary of a few hundred
# megabytes inside a framework of about a gigabyte, and linking it means this
# application inherits a browser's security patch cadence.
#
# That price is worth paying for those two screens and it is not a price every
# packager will want to pay on every platform, so it is a decision rather than
# something that arrived with a feature. Off, the rail entries stay and say so:
# see AgentSurfaceUnavailable.qml, which is compiled in under the web view's
# name. A build that silently lost two screens would leave somebody wondering
# why their copy has fewer rooms than the screenshots.
# 6.8 rather than the 6.4 floor the rest of this application builds against, and
# that is a real requirement rather than caution: `WebEngineView.permissionRequested`
# arrived in 6.8, and a surface refuses every camera, microphone and location
# prompt through it. On 6.4 that handler is a binding to a signal that does not
# exist, so the component fails to load — and the alternative, leaving the
# prompts to reach the person at the keyboard, is not one. A build on an older
# Qt gets the switch below turned off and says so on its two screens.
set(SIMORG_WEBENGINE_MIN_VERSION 6.8)

find_package(Qt6 ${SIMORG_WEBENGINE_MIN_VERSION} QUIET COMPONENTS WebEngineQuick)
option(SIMORG_BUILD_WEBENGINE
    "Draw agent surfaces with Qt WebEngine (adds a Chromium dependency)"
    ${Qt6WebEngineQuick_FOUND}
)

if(SIMORG_BUILD_WEBENGINE AND NOT Qt6WebEngineQuick_FOUND)
    message(FATAL_ERROR
        "SIMORG_BUILD_WEBENGINE is on but Qt6::WebEngineQuick ${SIMORG_WEBENGINE_MIN_VERSION} "
        "or later was not found. Install Qt WebEngine, or configure with "
        "-DSIMORG_BUILD_WEBENGINE=OFF."
    )
endif()

message(STATUS "  Agent surfaces: ${SIMORG_BUILD_WEBENGINE}")

# The QML files, kept in qml/ for tidiness but published at the root of the
# module. Without the alias they would land at Simorg/qml/Main.qml, which means
# an extra qmldir (see Qt policy QTP0004) and a load URL that does not match
# how the components import each other.
set(SIMORG_QML_FILES
    qml/ActivityRow.qml
    qml/ActivityText.js
    qml/AgentAccessManagement.qml
    qml/AgentAccessPane.qml
    qml/AgentActivityLog.qml
    qml/AgentContainerLogs.qml
    qml/AgentDashboard.qml
    qml/AgentDetail.qml
    qml/AgentLifecyclePanel.qml
    qml/AgentPermissionsCard.qml
    qml/AgentResourceRow.qml
    qml/AgentState.qml
    qml/AgentStatePill.qml
    qml/AgentSurfacePane.qml
    qml/AgentTile.qml
    qml/AgentTransitionBar.qml
    qml/AgentUpdateBar.qml
    qml/AgentUpdatesBar.qml
    qml/AgentSettingsPane.qml
    qml/ReleaseNoteCard.qml
    qml/AgentVirtualMachinePane.qml
    qml/AgentsBrowser.qml
    qml/AgentsOverview.qml
    qml/AgentsSection.qml
    qml/AccessRequestSheet.qml
    qml/AlertBanner.qml
    qml/AlwaysAllowedApplication.qml
    qml/ApplicationDiscover.qml
    qml/ApplicationRow.qml
    qml/ApplicationsSection.qml
    qml/ConnectionBanner.qml
    qml/CopyAction.qml
    qml/CountdownPill.qml
    qml/AttentionList.qml
    qml/ArtifactList.qml
    qml/AuroraBackground.qml
    qml/Avatar.qml
    qml/BrandDiagram.qml
    qml/BusyRing.qml
    qml/ComingSoon.qml
    qml/ConfirmDialog.qml
    qml/PeerConsentSheet.qml
    qml/PeerList.qml
    qml/DashboardWindow.qml
    qml/DockerConsole.qml
    qml/DockerContainerRow.qml
    qml/DockerContainers.qml
    qml/DockerImages.qml
    qml/DockerIntro.qml
    qml/DockerLogPanel.qml
    qml/DockerMissing.qml
    qml/DockerOverview.qml
    qml/DockerResourcesView.qml
    qml/DockerSection.qml
    qml/DockerStopped.qml
    qml/EditableName.qml
    qml/ElidedText.qml
    qml/GetDockerCard.qml
    qml/GhostButton.qml
    qml/GlassPanel.qml
    qml/GpuOfferPanel.qml
    qml/Glyph.qml
    qml/OsLogo.qml
    qml/GradientText.qml
    qml/HomeSection.qml
    qml/HomeTile.qml
    qml/InstalledApplications.qml
    qml/IconButton.qml
    qml/InfoCallout.qml
    qml/LegalDocumentView.qml
    qml/LegalWindow.qml
    qml/LinkLabel.qml
    qml/LogContextMenu.qml
    qml/LogSearch.qml
    qml/LogSearchBar.qml
    qml/LogSelection.qml
    qml/LogSelectionArea.qml
    qml/LogView.qml
    qml/LoginWindow.qml
    qml/MachineCard.qml
    qml/MachineRegistration.qml
    qml/MachineWelcome.qml
    qml/MachineWelcomeScene.qml
    qml/Main.qml
    qml/MeterBar.qml
    qml/PreflightStepRow.qml
    qml/PreflightWindow.qml
    qml/PrimaryButton.qml
    qml/PulseHex.qml
    qml/RequestedFolderRow.qml
    qml/AgentPathLine.qml
    qml/ResourceMeter.qml
    qml/ResourcePair.qml
    qml/ResourceSlider.qml
    qml/QuittingWindow.qml
    qml/UninstallWindow.qml
    qml/Reveal.qml
    qml/SchemaField.qml
    qml/SchemaForm.qml
    qml/SchemaRuleList.qml
    qml/Platform.js
    qml/SchemaRules.js
    qml/SectionTabs.qml
    qml/ShutdownStep.qml
    qml/SetupIdentityStep.qml
    qml/SetupRuntimeStep.qml
    qml/SetupWelcomeStep.qml
    qml/SetupWindow.qml
    qml/SettingsExecution.qml
    qml/SettingsFiles.qml
    qml/SettingsLogging.qml
    qml/SettingsOverview.qml
    qml/SettingsSection.qml
    qml/SettingsUninstall.qml
    qml/SettingsUpdates.qml
    qml/SettingsLicences.qml
    qml/SegmentedControl.qml
    qml/SelectableText.qml
    qml/SideNav.qml
    qml/SimorgCheckBox.qml
    qml/SimorgTextArea.qml
    qml/SimorgTextField.qml
    qml/SoonSection.qml
    qml/StartingWindow.qml
    qml/Sparkline.qml
    qml/StateDot.qml
    qml/StatTile.qml
    qml/Theme.qml
    qml/ThemeTokens.qml
    qml/Tip.qml
    qml/TipLayer.qml
    qml/UpdatesBar.qml
    qml/UsageBar.qml
    qml/WorkBar.qml
)

# One name, two files, and the build picks which one is compiled in. Everything
# above the view is identical either way — the same pane, the same rail entry,
# the same two functions called on it — so nothing else in the interface has to
# know whether this build can draw a page.
if(SIMORG_BUILD_WEBENGINE)
    list(APPEND SIMORG_QML_FILES qml/AgentSurfaceWebView.qml)
else()
    list(APPEND SIMORG_QML_FILES qml/AgentSurfaceUnavailable.qml)
endif()

foreach(qml_file IN LISTS SIMORG_QML_FILES)
    get_filename_component(qml_name "${qml_file}" NAME)
    set_source_files_properties("${qml_file}" PROPERTIES QT_RESOURCE_ALIAS "${qml_name}")
endforeach()

# After the loop, which would otherwise put this file back under its own name.
# The Loader asks for AgentSurfaceWebView.qml, and in a build with no browser
# engine that name has to resolve to the stand-in.
if(NOT SIMORG_BUILD_WEBENGINE)
    set_source_files_properties(qml/AgentSurfaceUnavailable.qml PROPERTIES
        QT_RESOURCE_ALIAS "AgentSurfaceWebView.qml"
    )
endif()

# Theme is a singleton: every component reads Theme.blue, Theme.motion and the
# rest without importing anything of its own. ThemeTokens is one too — it holds
# both palettes, generated from the shared token table, and Theme picks between
# them. Nothing but Theme should ever name it.
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/ThemeTokens.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# AgentState is a singleton for the same reason: four screens draw the same
# eight container states, and the wording and the colour have to come from one
# place or two of them will eventually disagree about what "stopped" is called.
set_source_files_properties(qml/AgentState.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# Tip is a singleton because there is one pointer. Every elided label in the
# application asks the same object to show its full text, and the one bubble
# TipLayer draws follows it — rather than each of the several hundred labels
# carrying a Controls popup of its own.
set_source_files_properties(qml/Tip.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# The interface is its own static library rather than part of the executable,
# for one reason: the interface tests load Main.qml with the real singletons and
# fail on any QML warning. A QML module compiled into an executable cannot be
# linked by anything, so that test could not exist — and every binding error in
# forty QML files would be found by a person running the app instead.
#
# RESOURCE_PREFIX is pinned because the default moved in Qt 6.5, and
# DesktopApplication::loadQml() loads by explicit qrc: URL so the app builds on
# the 6.4 that current Ubuntu LTS still ships.
qt_add_qml_module(simorg-ui
    STATIC
    URI Simorg
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    QML_FILES ${SIMORG_QML_FILES}
)

# Branding, reachable from both QML (Image.source) and C++ (QSvgRenderer), and
# the application icon at each size a window asks for (AppIdentity.cpp). The
# icon's PNGs are drawn by scripts/make-icons.sh; never edit them by hand.
set(SIMORG_WINDOW_ICON_SIZES 16 22 24 32 48 64 128 256)
set(SIMORG_WINDOW_ICON_FILES "")
foreach(size IN LISTS SIMORG_WINDOW_ICON_SIZES)
    list(APPEND SIMORG_WINDOW_ICON_FILES "${SIMORG_RESOURCE_DIR}/branding/app-icon/simorg-${size}.png")
endforeach()
qt_add_resources(simorg-ui "branding"
    PREFIX "/simorg/branding"
    BASE "${SIMORG_RESOURCE_DIR}/branding"
    FILES
        "${SIMORG_RESOURCE_DIR}/branding/simorg-logo.svg"
        "${SIMORG_RESOURCE_DIR}/branding/simorg-tray.svg"
        ${SIMORG_WINDOW_ICON_FILES}
)

target_link_libraries(simorg-ui PUBLIC
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
)

set_target_properties(simorg-ui PROPERTIES POSITION_INDEPENDENT_CODE ON)

simorg_set_warnings(simorg-ui)


qt_add_executable(simorg-desktop
    AppBridge.cpp
    AppBridge.h
    AppIdentity.cpp
    AppIdentity.h
    AppModels.cpp
    AppModels.h
    AvatarCache.cpp
    AvatarCache.h
    CrashMarker.cpp
    CrashMarker.h
    FlowerLayer.cpp
    FlowerLayer.h
    FlowerShape.cpp
    FlowerShape.h
    HeadlessUpdate.cpp
    HeadlessUpdate.h
    DesktopApplication.cpp
    DesktopApplication.h
    MenuBarController.cpp
    MenuBarController.h
    TrayController.cpp
    TrayController.h
    main.cpp
)

# The scheme the agent-surface host page is served over. Only compiled when
# there is a browser to serve it to; everything it depends on that is worth
# testing lives in SurfaceRouter, in the core library, where a test can call it
# with a QUrl and no Chromium.
if(SIMORG_BUILD_WEBENGINE)
    target_sources(simorg-desktop PRIVATE
        SurfaceSchemeHandler.cpp
        SurfaceSchemeHandler.h
        WebEngineSupport.cpp
        WebEngineSupport.h
    )
    target_compile_definitions(simorg-desktop PRIVATE SIMORG_WITH_WEBENGINE)
endif()

# simorg-uiplugin is the plugin qt_add_qml_module generates alongside a static
# QML module; without it linked, the module's types register but its .qml files
# are never added to the resource system and Main.qml is not found at run time.
# Simorg::Frontend for what stays with the desktop: build facts, the log category,
# autostart, an older release's terminal commands to take away, and the window-level
# single-instance guard.
# Everything else is the Simorg machine service's, reached through Simorg::AppModel.
target_link_libraries(simorg-desktop PRIVATE
    Simorg::AppModel
    Simorg::Client
    Simorg::Frontend
    simorg-ui
    simorg-uiplugin
    Qt6::Gui
    # Named rather than inherited: AvatarCache fetches the signed-in account's
    # picture with its own QNetworkAccessManager, so this target uses Network
    # directly and not only through a library.
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::Widgets
)

if(SIMORG_BUILD_WEBENGINE)
    target_link_libraries(simorg-desktop PRIVATE Qt6::WebEngineQuick)
endif()

set_target_properties(simorg-desktop PROPERTIES
    # No console window behind the app on Windows.
    WIN32_EXECUTABLE ON
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_BUNDLE_NAME "Simorg"
    MACOSX_BUNDLE_GUI_IDENTIFIER "tech.simorg.desktop"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_INFO_PLIST "${SIMORG_PACKAGING_DIR}/macos/Info.plist.in"
)

# macOS shows the bundle name in the menu bar and the Applications folder, so
# it gets the product name; elsewhere the binary keeps its command-line name.
if(APPLE)
    set_target_properties(simorg-desktop PROPERTIES OUTPUT_NAME "Simorg")

    # The Dock and Finder read the icon from the bundle, not from
    # QGuiApplication::setWindowIcon — without this the app gets the blank
    # placeholder icon no matter what the running process asks for.
    set(SIMORG_MACOS_ICON "${SIMORG_PACKAGING_DIR}/macos/Simorg.icns")
    target_sources(simorg-desktop PRIVATE "${SIMORG_MACOS_ICON}")
    set_source_files_properties("${SIMORG_MACOS_ICON}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    set_target_properties(simorg-desktop PROPERTIES
        MACOSX_BUNDLE_ICON_FILE "Simorg.icns"
    )
endif()

# Windows: the icon Explorer, the Start menu and Apps & Features show, and the
# name Task Manager lists the process under.
simorg_add_windows_resources(simorg-desktop DESCRIPTION "Simorg")

simorg_set_warnings(simorg-desktop)

install(TARGETS simorg-desktop
    BUNDLE DESTINATION .
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    COMPONENT desktop
)

# Desktop entry and icon, so the app appears in Linux application menus.
if(SIMORG_LINUX_DESKTOP_FILES)
    install(FILES "${SIMORG_PACKAGING_DIR}/linux/tech.simorg.desktop.desktop"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
        COMPONENT desktop
    )
    # The application icon at every size the hicolor theme names, and scalable.
    # Menus and docks pick the exact size when there is one; the SVG is for the
    # sizes in between.
    foreach(size IN ITEMS 16 22 24 32 48 64 128 256 512)
        install(FILES "${SIMORG_RESOURCE_DIR}/branding/app-icon/simorg-${size}.png"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps"
            RENAME "tech.simorg.desktop.png"
            COMPONENT desktop
        )
    endforeach()
    install(FILES "${SIMORG_RESOURCE_DIR}/branding/app-icon/simorg-app-icon.svg"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps"
        RENAME "tech.simorg.desktop.svg"
        COMPONENT desktop
    )
    install(FILES "${SIMORG_PACKAGING_DIR}/linux/tech.simorg.desktop.metainfo.xml"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/metainfo"
        COMPONENT desktop
    )
endif()

# Bundles Qt's own libraries and QML modules next to the binary. Generated by
# Qt itself, so it stays right as the module list changes.
if(SIMORG_DEPLOY_QT)
    qt_generate_deploy_qml_app_script(
        TARGET simorg-desktop
        OUTPUT_SCRIPT SIMORG_DEPLOY_SCRIPT
        MACOS_BUNDLE_POST_BUILD
        NO_UNSUPPORTED_PLATFORM_ERROR
        DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
    )

    if(APPLE)
        # The script Qt just generated is still wanted for its POST_BUILD half,
        # which links the build tree's bundle at the QML modules so the app can
        # be run out of build/bin. What it cannot be used for is the install,
        # and the reason is one line of it: it deploys the QML imports and then
        # calls macdeployqt with nothing in between, and on a Homebrew Qt there
        # has to be something in between. See cmake/SimorgMacOsDeploy.cmake.
        #
        # So the install runs this second script instead — the same two steps,
        # with the files Qt copied in as links turned into files first.
        # qt6_ rather than the versionless qt_ spelling used everywhere else,
        # and not a style slip: qt_generate_deploy_script is a *macro* that
        # forwards ${ARGV}, which re-parses the arguments and so expands the
        # $\{QT_DEPLOY_PREFIX} and $\{plugins_found} below at configure time —
        # to nothing, since neither exists until the script runs. Qt's own
        # generators call the versioned function for exactly this reason.
        qt6_generate_deploy_script(
            TARGET simorg-desktop
            NAME simorg_macos_deploy
            OUTPUT_SCRIPT SIMORG_MACOS_DEPLOY_SCRIPT
            CONTENT "
include(\"${SIMORG_CMAKE_DIR}/SimorgMacOsDeploy.cmake\")

qt6_deploy_qml_imports(TARGET simorg-desktop PLUGINS_FOUND plugins_found)

simorg_materialise_qml_symlinks(
    \"\${QT_DEPLOY_PREFIX}/$<TARGET_FILE_NAME:simorg-desktop>.app\"
    \"${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}\"
)

qt6_deploy_runtime_dependencies(
    EXECUTABLE \"$<TARGET_FILE_NAME:simorg-desktop>.app\"
    ADDITIONAL_MODULES \${plugins_found}
)
"
        )
        install(SCRIPT "${SIMORG_MACOS_DEPLOY_SCRIPT}" COMPONENT desktop)
    else()
        install(SCRIPT "${SIMORG_DEPLOY_SCRIPT}" COMPONENT desktop)
    endif()
endif()
