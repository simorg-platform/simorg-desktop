// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * When Simorg runs, and what happens when its window is closed.
 *
 * Two settings that look unrelated and are the same question asked twice —
 * *when is this program running?* Starting with the computer is the answer for
 * the moment somebody logs in; the menu bar is the answer for the moment they
 * press the red button out of habit. Both matter for the same reason: this
 * computer is only a machine anybody can be given work on while this process is
 * up.
 *
 * Both are **facts about this machine**, not preferences stored on an account,
 * so neither follows anybody to their other computers — which is why each says
 * where it is written.
 */
Item {
    id: root

    /*
      Whether the entry actually exists, asked rather than remembered.

      The mechanism is a file in the home directory or a registry value, and a
      person can remove either behind the app's back — with a desktop tweak
      tool, or by deleting a plist. Re-read whenever the page appears so the
      checkbox never disagrees with the computer.
    */
    property bool autostartOn: App.autostartEnabled

    onVisibleChanged: if (visible) root.autostartOn = App.autostartEnabled

    Connections {
        target: App
        function onAutostartChanged() { root.autostartOn = App.autostartEnabled; }
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

                // ---- Startup ---------------------------------------------
                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: startup.implicitHeight + 40

                        ColumnLayout {
                            id: startup
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph {
                                    name: "restart"
                                    size: 16
                                    thickness: 1.7
                                    tone: Theme.cyan
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Startup")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            SimorgCheckBox {
                                Layout.fillWidth: true
                                enabled: App.autostartSupported
                                checked: root.autostartOn
                                text: qsTr("Start Simorg when this computer starts")
                                onToggled: function (checked) {
                                    /*
                                      The checkbox follows the computer, not the
                                      click. `setAutostartEnabled` verifies the
                                      entry by reading it back, so a write a
                                      sandbox or a policy discarded leaves this
                                      where it was and puts the reason below.
                                    */
                                    App.setAutostartEnabled(checked);
                                    root.autostartOn = App.autostartEnabled;
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 30
                                text: qsTr("Simorg keeps your machine on the platform, holds the connection agents are given work over, and runs their containers. It only does that while it is running.")
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            ElidedText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 30
                                visible: App.autostartSupported && App.autostartLocation.length > 0
                                text: qsTr("Written to %1").arg(App.autostartLocation)
                                color: Theme.textFaint
                                font.pixelSize: 11
                                font.family: Theme.monoFamily
                                elide: Text.ElideMiddle
                            }

                            InfoCallout {
                                Layout.fillWidth: true
                                visible: !App.autostartSupported
                                glyph: "info"
                                tone: Theme.sky
                                title: qsTr("Simorg cannot manage this on this computer")
                                body: qsTr("The program a startup entry would point at could not be found. This usually means Simorg is running from a build directory rather than from an install.")
                            }

                            InfoCallout {
                                Layout.fillWidth: true
                                visible: App.autostartError.length > 0
                                glyph: "alert"
                                tone: Theme.amber
                                title: qsTr("That could not be saved")
                                body: App.autostartError
                            }
                        }
                    }
                }

                // ---- Running in the background ---------------------------
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: background.implicitHeight + 40

                        ColumnLayout {
                            id: background
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph {
                                    name: App.trayAvailable ? "check-circle" : "alert"
                                    size: 16
                                    thickness: 1.7
                                    tone: App.trayAvailable ? Theme.emerald : Theme.amber
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Running in the background")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            Text {
                                Layout.fillWidth: true
                                text: App.trayAvailable
                                      ? qsTr("Closing this window does not quit Simorg. It keeps running with an icon in the menu bar, and Quit Simorg, in that icon's menu or in your account menu, stops it.")
                                      : qsTr("This desktop has no menu bar icon for Simorg, so closing the window would leave nothing to reach it by. Simorg asks before it hides, and starting it again brings the window back.")
                                color: Theme.textBody
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: Theme.spaceSm

                                GhostButton {
                                    text: qsTr("Hide to the menu bar")
                                    implicitHeight: 34
                                    enabled: App.trayAvailable
                                    onClicked: App.hideToTray()
                                }

                                GhostButton {
                                    text: qsTr("Quit Simorg")
                                    implicitHeight: 34
                                    // Always asked, in the dashboard's one question about leaving; see DashboardWindow.
                                    onClicked: App.askToQuit()
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
