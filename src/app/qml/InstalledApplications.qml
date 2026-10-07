// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The applications on this computer, and everything that can be done to them
 * from here.
 *
 * Four figures across the top — how many are installed, how many are running,
 * what they take on the disk, how many are installing — and then one row each.
 * A row says what the application is and where it stands, which agents placed
 * here may use it, what it uses while it runs, and offers Open — or Quit while
 * it runs — show in folder and Uninstall. Only singletons are here: one
 * instance per computer, shared by every agent that uses it. Any other
 * application is installed and started by the agents that use it.
 *
 * Simorg Desktop leads the list whatever else is on it. It is this application,
 * it is not installed through Simorg — it is how Simorg got here — and every
 * agent may always use it, which is the fact worth seeing beside the others.
 *
 * A refusal is said on the row that was pressed, beside the button, rather than
 * at the top of a list somebody may have scrolled.
 */
Item {
    id: root

    /** Asks the section for the Discover view. */
    signal discover()

    /** The application a button was last pressed for, which is where a refusal is said. */
    property string actedOn: ""

    readonly property string desktopSpecifier: AccessGrants.alwaysAllowedApplications.length > 0
                                               ? AccessGrants.alwaysAllowedApplications[0] : ""

    Connections {
        target: Applications
        function onInstalled(title) {
            root.actedOn = "";
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 24
                spacing: Theme.spaceMd

                // ---- Four figures ---------------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    columns: root.width > 900 ? 4 : 2
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("INSTALLED")
                        glyph: "cube"
                        tone: Theme.sky
                        value: String(Applications.installedCount)
                        caption: Applications.installedCount === 0
                                 ? qsTr("nothing installed from Simorg yet")
                                 : qsTr("installed from Simorg")
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("RUNNING")
                        glyph: "play"
                        tone: Theme.emerald
                        value: String(Applications.runningCount)
                        caption: qsTr("connected to Simorg now")
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("ON DISK")
                        glyph: "disk"
                        tone: Theme.amber
                        value: Applications.installedBytes > 0 ? Docker.formatBytes(Applications.installedBytes) : "—"
                        caption: qsTr("removed when you sign out")
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("INSTALLING")
                        glyph: "download"
                        tone: Theme.violet
                        value: String(Applications.installingCount)
                        caption: Applications.installingCount === 0 ? qsTr("nothing under way")
                                                                    : qsTr("downloading or unpacking")
                    }
                }

                // ---- This application ----------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.desktopSpecifier.length > 0
                    accent: Theme.sky
                    implicitHeight: desktopRow.implicitHeight + 28

                    RowLayout {
                        id: desktopRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: Theme.radiusLarge
                            color: Theme.alpha(Theme.sky, 0.1)
                            border.width: 1
                            border.color: Theme.alpha(Theme.sky, 0.3)

                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/simorg/branding/simorg-logo.svg"
                                sourceSize: Qt.size(64, 64)
                                width: 28
                                height: 28
                                smooth: true
                                mipmap: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: qsTr("Simorg Desktop")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: qsTr("this application · %1").arg(App.version)
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                }
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                text: root.desktopSpecifier
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.monoFamily
                            }
                        }

                        Rectangle {
                            implicitWidth: allowedRow.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.alpha(Theme.emerald, 0.4)

                            RowLayout {
                                id: allowedRow
                                anchors.centerIn: parent
                                spacing: 5

                                Glyph { name: "lock"; size: 11; thickness: 1.7; tone: Theme.emerald }

                                Text {
                                    text: qsTr("Every agent may use it")
                                    color: Theme.emerald
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                // ---- One row each ---------------------------------------
                Repeater {
                    model: Applications

                    delegate: ApplicationRow {
                        Layout.fillWidth: true
                        problem: root.actedOn === specifier ? Applications.lastError : ""
                        busy: Applications.removing === specifier || Applications.quitting === specifier
                        onOpenRequested: {
                            root.actedOn = specifier;
                            Applications.open(specifier);
                        }
                        onQuitRequested: {
                            root.actedOn = specifier;
                            // Asked first only when an agent is using it.
                            if (usedByAgentIds.length > 0)
                                quitConfirm.ask(specifier, title, usedByAgentIds);
                            else
                                Applications.quit(specifier);
                        }
                        onRevealRequested: App.revealPath(entry.length > 0 ? entry : path)
                        onUninstallRequested: {
                            root.actedOn = specifier;
                            uninstallConfirm.ask(specifier, title);
                        }
                        onRetryRequested: {
                            root.actedOn = specifier;
                            Applications.install(specifier);
                        }
                    }
                }

                // ---- Nothing installed yet ------------------------------
                ComingSoon {
                    Layout.fillWidth: true
                    visible: Applications.loaded && Applications.count === 0
                    glyph: "cube"
                    tone: Theme.sky
                    title: qsTr("No applications are installed here yet")
                    body: qsTr("Applications are programs that run on this computer and that your agents can use once you allow them: a clipboard, a screenshot tool, a renderer. Find one in Discover and install it here.")
                    points: [
                        qsTr("Installed for this account, and removed when you sign out"),
                        qsTr("An agent uses one only if its Applications permission allows it"),
                        qsTr("Open one from here whenever you want it running"),
                        qsTr("Simorg starts one only for an agent you allowed to use it")
                    ]
                }

                GhostButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: Applications.loaded && Applications.count === 0
                    text: qsTr("Discover applications")
                    implicitHeight: 36
                    onClicked: root.discover()
                }

                // ---- Where they are ------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    visible: Applications.directory.length > 0
                    spacing: 6

                    Text {
                        text: qsTr("Installed in")
                        color: Theme.textFaint
                        font.pixelSize: 12
                    }

                    LinkLabel {
                        text: Applications.directory
                        pixelSize: 12
                        onActivated: App.revealPath(Applications.directory)
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    /*
      Asked before anything is removed, at this view's own root so it does not
      scroll away from the row it is about.
    */
    ConfirmDialog {
        id: uninstallConfirm
        anchors.fill: parent

        property string specifier: ""

        function ask(which, name) {
            uninstallConfirm.specifier = which;
            uninstallConfirm.title = qsTr("Uninstall %1?").arg(name);
            uninstallConfirm.body = qsTr("Its files are removed from this computer. What you allowed it, and which agents may use it, is kept, so installing it again needs no new answers.");
            uninstallConfirm.confirmText = qsTr("Uninstall");
            uninstallConfirm.open();
        }

        onAccepted: Applications.uninstall(uninstallConfirm.specifier)
    }

    /*
      Asked before quitting an application an agent is using, naming the agent:
      quitting it ends what that agent is doing with it.
    */
    ConfirmDialog {
        id: quitConfirm
        anchors.fill: parent

        property string specifier: ""

        function ask(which, name, agentIds) {
            const names = [];
            for (let i = 0; i < agentIds.length; ++i) {
                const agent = Hub.agents.byId(agentIds[i]);
                names.push(agent && agent.title ? agent.title : qsTr("Agent %1").arg(agentIds[i]));
            }
            const who = names.length === 1 ? names[0]
                      : names.length === 2 ? qsTr("%1 and %2").arg(names[0]).arg(names[1])
                      : qsTr("%1, %2 and %3 more").arg(names[0]).arg(names[1]).arg(names.length - 2);
            quitConfirm.specifier = which;
            quitConfirm.title = qsTr("Quit %1?").arg(name);
            quitConfirm.body = names.length === 1
                               ? qsTr("%1 is using %2 right now. Quitting it closes an application that agent is using.")
                                     .arg(who).arg(name)
                               : qsTr("%1 are using %2 right now. Quitting it closes an application those agents are using.")
                                     .arg(who).arg(name);
            quitConfirm.confirmText = qsTr("Quit");
            quitConfirm.open();
        }

        onAccepted: Applications.quit(quitConfirm.specifier)
    }
}
