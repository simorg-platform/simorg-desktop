// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Uninstalling Simorg, every step said while it happens.
 *
 * ## Why a window of its own
 *
 * Halfway through, the machine service this app is a front end of goes away on
 * purpose, and every other window would start saying what they say when it is
 * missing: that it is being set up, that the connection was lost. This window is
 * on top of all of them, and Main.qml puts the others away while it is up, so
 * the one thing on screen is the one thing that is true.
 *
 * ## Seven rows, all drawn from the start
 *
 * As the quitting window does: a list that grew as it went would change height
 * under somebody's eyes and never show how much was left. A step that does not
 * apply — the data somebody chose to keep — says so on its row rather than
 * vanishing.
 *
 * ## The two answers that are not failures
 *
 * A closed password prompt leaves the service stopped and still installed. That
 * is said as exactly that, with **Try again** and **Close**. There is no way
 * back to the dashboard from here: the uninstall has already signed out and
 * removed the agents, so Close closes the app, and opening Simorg again starts
 * the service (a failure before the service was asked changes nothing, and Close
 * just puts this window away). When it is done, it says so on a five-second
 * countdown, and the app closes itself: nothing is left for it to be a front end
 * of.
 */
ApplicationWindow {
    id: win

    visible: Uninstall.started
    width: 480
    height: Math.min(640, content.implicitHeight + 64)
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: qsTr("Uninstalling Simorg")

    x: Screen.virtualX + (Screen.width - width) / 2
    y: Screen.virtualY + (Screen.height - height) / 2

    onVisibleChanged: {
        if (visible) {
            win.raise();
            win.requestActivate();
        }
    }

    /** Seconds before the app closes itself, once everything is removed. */
    property int secondsLeft: 5

    Timer {
        id: closing
        interval: 1000
        repeat: true
        running: Uninstall.done && win.secondsLeft > 0
        onTriggered: win.secondsLeft -= 1
    }

    readonly property string headline: Uninstall.done ? qsTr("Simorg is removed")
                                     : Uninstall.declined ? qsTr("Simorg is still installed")
                                     : Uninstall.failed ? qsTr("Simorg could not be removed completely")
                                     : qsTr("Uninstalling Simorg")

    GlassPanel {
        anchors.fill: parent
        anchors.margins: 8
        opaque: true

        // Frameless, so nothing else moves it: dragged from anywhere but text to select or a button, which keep
        // their presses. It stays on top, and must not sit fixed over the windows Windows opens while it waits.
        DragHandler {
            target: null
            grabPermissions: PointerHandler.TakeOverForbidden
            onActiveChanged: {
                if (active)
                    win.startSystemMove();
            }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: Theme.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                BusyRing {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    visible: Uninstall.running
                    size: 20
                    tone: Theme.cyan
                }

                Glyph {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    visible: !Uninstall.running
                    name: Uninstall.done ? "check-circle" : "alert"
                    size: 20
                    thickness: 1.8
                    tone: Uninstall.done ? Theme.emerald : Uninstall.declined ? Theme.amber : Theme.danger
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: win.headline
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    SelectableText {
                        objectName: "uninstallStatus"
                        Layout.fillWidth: true
                        text: Uninstall.status
                        color: Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Repeater {
                    model: Uninstall.steps

                    delegate: RowLayout {
                        id: step
                        required property var modelData

                        objectName: "step_" + modelData.key
                        Layout.fillWidth: true
                        spacing: 10

                        Item {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 1
                            implicitWidth: 16
                            implicitHeight: 16

                            BusyRing {
                                anchors.centerIn: parent
                                visible: step.modelData.state === "running"
                                size: 14
                                tone: Theme.cyan
                            }

                            Glyph {
                                anchors.centerIn: parent
                                visible: step.modelData.state === "done" || step.modelData.state === "failed"
                                name: step.modelData.state === "done" ? "check" : "alert"
                                size: 14
                                thickness: 1.8
                                tone: step.modelData.state === "done" ? Theme.emerald : Theme.danger
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: step.modelData.state === "pending" || step.modelData.state === "skipped"
                                width: step.modelData.state === "skipped" ? 10 : 6
                                height: step.modelData.state === "skipped" ? 2 : 6
                                radius: step.modelData.state === "skipped" ? 1 : 3
                                color: Theme.textFaint
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: step.modelData.label
                                color: step.modelData.state === "pending" || step.modelData.state === "skipped"
                                       ? Theme.textFaint : Theme.textPrimary
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: step.modelData.detail
                                color: Theme.textMuted
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // What the removal printed, when it failed: selectable, for whoever is asked to help.
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, output.implicitHeight + 16)
                visible: Uninstall.failed && Uninstall.output.length > 0
                clip: true

                SelectableText {
                    id: output
                    objectName: "uninstallOutput"
                    width: parent.width
                    text: Uninstall.output
                    color: Theme.textMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                CountdownPill {
                    visible: Uninstall.done
                    secondsLeft: win.secondsLeft
                    totalSeconds: 5
                }

                Text {
                    Layout.fillWidth: true
                    visible: Uninstall.done
                    text: win.secondsLeft === 1
                          ? qsTr("Simorg closes in 1 second, because nothing is left for it to run.")
                          : qsTr("Simorg closes in %1 seconds, because nothing is left for it to run.").arg(win.secondsLeft)
                    color: Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Item {
                    Layout.fillWidth: true
                    visible: !Uninstall.done
                }

                GhostButton {
                    objectName: "closeUninstall"
                    visible: Uninstall.declined || Uninstall.failed
                    text: qsTr("Close")
                    onClicked: Uninstall.close()
                }

                PrimaryButton {
                    objectName: "tryAgain"
                    visible: Uninstall.declined || Uninstall.failed
                    text: qsTr("Try again")
                    onClicked: Uninstall.retry()
                }
            }
        }
    }
}
