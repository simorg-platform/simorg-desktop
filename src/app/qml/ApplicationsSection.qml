// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The Simorg applications on this computer, and the place they are looked
 * after from.
 *
 * An application is a program that runs here, on this computer and never in an
 * agent's container, and that agents can see through and act through once they
 * may: a clipboard, a screenshot tool, a renderer. This tab is their control
 * centre, three views of one question:
 *
 * | | |
 * | --- | --- |
 * | **Installed** | What is on this computer: running or not, what it uses while it runs, what it takes on the disk, which agents here may use it — and Open, Uninstall, show in folder |
 * | **Discover** | What Simorg has: the platform's applications, searched, each marked as published for this computer or not, and Install |
 * | **Connections** | The applications connected to Simorg right now and the answers kept for them, and what agents fetched for themselves |
 *
 * The disk — the cache's size and what is in it — is under Settings → Files
 * and folders, beside the folders it measures, and this tab is about
 * applications alone.
 *
 * ## What the service does and what this does
 *
 * Installing and uninstalling are the machine service's: it downloads the
 * driver this computer needs and
 * unpacks it under the cache root, so signing out takes it away with
 * everything else of the account. **Opening** one is this application's, on
 * the person's own press: the service never starts an application, and a
 * program somebody chose to open is theirs to open.
 */
Item {
    id: root

    property int view: 0

    readonly property var views: [
        { key: "installed", label: qsTr("Installed"), glyph: "cube" },
        { key: "discover", label: qsTr("Discover"), glyph: "store" },
        { key: "connections", label: qsTr("Connections"), glyph: "network" }
    ]

    /** Opens the Discover view, from the empty Installed list. */
    function showDiscover() {
        root.view = 1;
    }

    /*
      The list's usage columns are fed only while this tab is on screen: the
      service samples every running application's process for as long as
      somebody listens, and a hidden tab is nobody.
    */
    readonly property bool watching: root.visible && Window.window !== null && Window.window.visible
    onWatchingChanged: {
        Applications.setActive(root.watching);
        if (root.watching)
            Artifacts.refresh();
    }
    Component.onCompleted: {
        Applications.setActive(root.watching);
        if (root.watching)
            Artifacts.refresh();
    }
    Component.onDestruction: Applications.setActive(false)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ----------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 20
                spacing: 14

                Glyph {
                    name: "cube"
                    size: 18
                    thickness: 1.7
                    tone: Applications.installedCount > 0 ? Theme.sky : Theme.textFaint
                }

                // The title gives way before any control does; see AgentsSection.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 90
                    spacing: 1

                    ElidedText {
                        Layout.fillWidth: true
                        text: Applications.installedCount === 0
                              ? qsTr("Applications")
                              : Applications.installedCount === 1
                                ? qsTr("1 application on this computer")
                                : qsTr("%1 applications on this computer").arg(Applications.installedCount)
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        elide: Text.ElideRight
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.view === 1
                              ? qsTr("Simorg's applications, and which of them this computer can run")
                            : root.view === 2
                              ? qsTr("The applications connected to Simorg now, and your answers to them")
                            : qsTr("Programs that run here and that your agents can use: what they use, and who may use them")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                SegmentedControl {
                    items: root.views
                    currentIndex: root.view
                    onSelected: function (index) { root.view = index; }
                }

                IconButton {
                    glyph: "refresh"
                    tooltip: root.view === 1 ? qsTr("Search again") : qsTr("Read the list again")
                    busy: root.view === 1 && ApplicationDirectory.searching
                    onClicked: {
                        if (root.view === 1)
                            ApplicationDirectory.search();
                        else {
                            Applications.refresh();
                            Artifacts.refresh();
                        }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.view

            InstalledApplications {
                onDiscover: root.showDiscover()
            }

            ApplicationDiscover {
                active: root.view === 1 && root.watching
            }

            // ---- Connections ----------------------------------------------
            ScrollView {
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Connected applications first: they run on this computer and ask its owner before they attach.
                    PeerList {
                        Layout.fillWidth: true
                    }

                    /*
                      What agents fetched for themselves.

                      An agent's runtime can install a program into its own
                      folder, and records it in its index; those are listed
                      here with the role the agent held over it, because a
                      program on this disk that nobody pressed Install for is
                      exactly what an owner should be able to find.
                    */
                    ArtifactList {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 360
                        onlyApplications: true
                        emptyTitle: qsTr("No agent fetched a program for itself")
                        emptyBody: qsTr("An agent can install a program into its own folder on this computer. Anything one did is listed here with the role that agent holds over it, so you can see what was put on this computer and by whom.")
                    }
                }
            }
        }
    }
}
