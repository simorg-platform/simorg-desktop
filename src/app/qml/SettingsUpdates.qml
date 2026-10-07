// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Settings → Updates: Simorg Desktop, the Simorg machine service and the agent
 * runtime, each with what is installed, what is available, and an Update the
 * person presses. Nothing here updates by itself unless **Install updates
 * automatically** is on, the machine's own setting, which this view changes and
 * the Logos and Simorg CLI's `sim update --auto` change too. Each row says what
 * the update brings, every release note since the version here, whether it is
 * required, and whether it was downloaded ahead; a Simorg Desktop
 * update asked for elsewhere waits here for Restart to finish updating.
 *
 * Opening the view asks the service to check again, and **Check for updates**
 * asks again whenever somebody wants to know now: a release published while the
 * view is open is found on the press, not six hours later. Each row says what
 * pressing Update will do, and
 * why, before it is pressed; while it runs, the bar and the service's own
 * sentence say what is happening, and a failure is said with what the
 * installer printed, selectable.
 */
Item {
    id: root

    /** Asks for a fresh check; SettingsSection calls it whenever this view is shown. */
    function refresh() {
        Updates.check();
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 860
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 26
                Layout.bottomMargin: 34
                spacing: Theme.spaceLg

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    GhostButton {
                        objectName: "checkForUpdates"
                        glyph: "refresh"
                        spinning: Updates.checking
                        text: Updates.checking ? qsTr("Checking…") : qsTr("Check for updates")
                        enabled: !Updates.checking
                        onClicked: Updates.check()
                    }
                }

                // The machine's own setting, saved on the platform, shown once the service knows it.
                GlassPanel {
                    objectName: "automaticUpdates"
                    Layout.fillWidth: true
                    visible: Updates.autoUpdateOffered
                    implicitHeight: automatic.implicitHeight + 40
                    accent: Updates.autoUpdate ? Theme.emerald : Theme.blue

                    ColumnLayout {
                        id: automatic
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: 8

                        SimorgCheckBox {
                            id: installAutomatically
                            objectName: "installAutomatically"
                            Layout.fillWidth: true
                            enabled: !Updates.autoUpdateSaving
                            checked: Updates.autoUpdate
                            text: qsTr("Install updates automatically")
                            // The box follows the setting as the service reports it, not the click.
                            onToggled: function (checked) {
                                Updates.setAutoUpdate(checked);
                                installAutomatically.checked = Qt.binding(() => Updates.autoUpdate);
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            text: qsTr("The machine service, the agent runtime and Simorg Desktop install each release once it has downloaded, so this computer stays current with nobody pressing Update. Simorg Desktop is never closed for it: it waits for you to restart.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            lineHeight: 1.45
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            visible: Updates.autoUpdateError.length > 0
                            text: Updates.autoUpdateError
                            color: Theme.danger
                            font.pixelSize: 12
                        }
                    }
                }

                Repeater {
                    model: Updates.rows

                    delegate: GlassPanel {
                        id: panel

                        required property string item
                        required property string title
                        required property string installed
                        required property string available
                        required property string updateState
                        required property bool canUpdate
                        required property string reason
                        required property string phase
                        required property real progress
                        required property string message
                        required property string outcome
                        required property string problem
                        required property string output
                        required property bool cancellable
                        required property string explanation
                        required property string lastUpdate
                        required property string refusal
                        required property var notes
                        required property bool required
                        required property bool readyToRestart
                        required property string downloadState

                        readonly property bool running: panel.updateState === "updating" && !panel.readyToRestart
                        readonly property bool offered: panel.available.length > 0 && !panel.running
                        property bool notesOpen: false
                        readonly property color tone: panel.updateState === "failed" ? Theme.danger
                                                    : panel.offered && panel.required ? Theme.amber
                                                    : panel.offered ? Theme.sky : Theme.emerald

                        Layout.fillWidth: true
                        implicitHeight: body.implicitHeight + 40
                        accent: panel.tone

                        ColumnLayout {
                            id: body
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph {
                                    name: panel.item === "desktop" ? "widgets"
                                        : panel.item === "cli" ? "terminal"
                                        : panel.item === "service" ? "server" : "container"
                                    size: 16
                                    thickness: 1.7
                                    tone: panel.tone
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: panel.title
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: panel.offered
                                              ? qsTr("Version %1 is ready. You have %2.").arg(panel.available).arg(panel.installed || qsTr("an earlier one"))
                                              : panel.running ? qsTr("Updating to %1.").arg(panel.available)
                                              : panel.installed.length > 0 ? qsTr("Version %1, the newest.").arg(panel.installed)
                                              : qsTr("Not known yet.")
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                GhostButton {
                                    visible: panel.cancellable
                                    text: panel.readyToRestart ? qsTr("Not now") : qsTr("Cancel")
                                    implicitHeight: 34
                                    onClicked: Updates.cancel(panel.item)
                                }

                                // Prepared, and waiting only for somebody here to say when.
                                PrimaryButton {
                                    visible: panel.readyToRestart
                                    text: Updates.restartButton
                                    onClicked: Updates.restartToFinish()
                                }

                                PrimaryButton {
                                    visible: panel.offered && !panel.readyToRestart
                                    enabled: panel.canUpdate
                                    text: panel.updateState === "failed" ? qsTr("Try again") : qsTr("Update")
                                    onClicked: Updates.update(panel.item)
                                }
                            }

                            // Required rather than offered, with why.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.offered && panel.required
                                text: qsTr("Required: the version on this computer is older than Simorg now supports.")
                                color: Theme.amber
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Downloaded ahead, so pressing Update only switches.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.offered && panel.canUpdate
                                         && (panel.downloadState === "downloading" || panel.downloadState === "ready")
                                text: panel.downloadState === "ready"
                                      ? qsTr("Downloaded and checked already, so updating takes a moment.")
                                      : qsTr("Downloading in the background, so updating is quick when you press it.")
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Every release note since the version here, newest first, folded until asked.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: (panel.offered || panel.running || panel.readyToRestart) && panel.notes.length > 0
                                spacing: 6

                                GhostButton {
                                    objectName: "whatsNew"
                                    glyph: panel.notesOpen ? "chevron-up" : "chevron-down"
                                    text: panel.notes.length === 1 ? qsTr("What's new in %1").arg(panel.notes[0].version)
                                                                   : qsTr("What's new in %1 versions").arg(panel.notes.length)
                                    implicitHeight: 30
                                    onClicked: panel.notesOpen = !panel.notesOpen
                                }

                                Repeater {
                                    model: panel.notesOpen ? panel.notes : []

                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: qsTr("Version %1").arg(modelData.version)
                                            color: Theme.textPrimary
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.notes
                                            textFormat: Text.MarkdownText
                                            color: Theme.textBody
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            onLinkActivated: link => Qt.openUrlExternally(link)
                                        }
                                    }
                                }
                            }

                            // A press the service refused, beside the button that was pressed, in the service's words.
                            SelectableText {
                                Layout.fillWidth: true
                                visible: panel.refusal.length > 0
                                text: panel.refusal
                                color: Theme.danger
                                font.pixelSize: 12
                            }

                            // What pressing Update will do, and why, said before it is pressed.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.offered && panel.canUpdate && panel.explanation.length > 0
                                text: panel.explanation
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Why it cannot be pressed here, in the service's own words.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.reason.length > 0 && !panel.running
                                text: panel.reason
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Prepared: what the restart does, said before it is pressed.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.readyToRestart
                                text: panel.message
                                color: Theme.textBody
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: panel.running
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: panel.message
                                    color: Theme.textBody
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                WorkBar {
                                    Layout.fillWidth: true
                                    working: panel.running
                                    progress: panel.progress
                                }
                            }

                            // A failure, with the service's sentence and what the installer printed.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !panel.running && (panel.outcome === "failed" || panel.outcome === "declined")
                                spacing: 6

                                SelectableText {
                                    Layout.fillWidth: true
                                    text: panel.outcome === "declined" ? panel.message
                                                                       : (panel.problem.length > 0 ? panel.problem : panel.message)
                                    color: panel.outcome === "declined" ? Theme.textMuted : Theme.danger
                                    font.pixelSize: 12
                                }

                                SelectableText {
                                    Layout.fillWidth: true
                                    visible: panel.outcome === "failed" && panel.output.length > 0
                                    text: panel.output
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    font.family: Theme.monoFamily
                                }
                            }

                            // The service that started after an update says how it went.
                            Text {
                                Layout.fillWidth: true
                                visible: panel.lastUpdate.length > 0 && !panel.running
                                text: panel.lastUpdate
                                color: Theme.emerald
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: Updates.rows.count === 0
                    text: qsTr("Checking for updates…")
                    color: Theme.textFaint
                    font.pixelSize: 12
                }
            }
        }
    }
}
