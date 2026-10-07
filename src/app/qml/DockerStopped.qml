// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * Docker is here; it is just not awake.
 *
 * A separate screen from the introduction, and that distinction is the whole
 * point of probing for a client and an application on disk rather than only
 * pinging a socket. Telling somebody who has used Docker for five years that
 * they should install it is the fastest way to lose them.
 */
Item {
    id: root

    readonly property bool starting: Docker.status === DockerStatus.Starting

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 560)
        spacing: Theme.spaceLg

        Reveal {
            step: 0
            Layout.alignment: Qt.AlignHCenter

            /*
              Implicit size, not width/height. Same trap as the badge in
              SoonSection: Reveal measures itself from its child's *implicit*
              size, and a plain Item has none — so this arrived as a zero-high
              item and the heading below it was drawn straight through the
              icon. An Item sized this way still takes its width and height
              from the same two numbers.
            */
            Item {
                implicitWidth: 76
                implicitHeight: 76

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Theme.alpha(root.starting ? Theme.sky : Theme.amber, 0.08)
                    border.width: 1
                    border.color: Theme.alpha(root.starting ? Theme.sky : Theme.amber, 0.26)

                    Behavior on color {
                        ColorAnimation { duration: Theme.duration(Theme.durBase) }
                    }
                }

                BusyRing {
                    anchors.centerIn: parent
                    visible: root.starting
                    running: root.starting
                    size: 30
                    tone: Theme.sky
                }

                Glyph {
                    anchors.centerIn: parent
                    visible: !root.starting
                    name: "container"
                    size: 32
                    thickness: 1.5
                    tone: Theme.amber
                }
            }
        }

        Reveal {
            step: 1
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.starting ? qsTr("Docker is starting")
                         : Docker.runtimeManaged ? qsTr("Docker Engine is installed, but not running")
                                                 : qsTr("Nothing is answering")
                    color: Theme.textPrimary
                    font.pixelSize: 21
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: root.starting
                          ? qsTr("This takes a moment — longer the first time. The screen changes by itself when it is ready.")
                          : Docker.runtimeManaged
                            ? qsTr("Nothing is wrong. Docker only runs when you start it, and Simorg needs it running to build or run anything in a container.")
                            : Docker.detail
                    color: Theme.textBody
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.55
                }
            }
        }

        Reveal {
            step: 2
            Layout.alignment: Qt.AlignHCenter

            RowLayout {
                spacing: Theme.spaceSm

                PrimaryButton {
                    text: qsTr("Start Docker")
                    busy: root.starting
                    // Only an engine Simorg installed is one it may start; an
                    // endpoint pointing elsewhere is somebody else's to bring up.
                    visible: Docker.runtimeManaged
                    onClicked: Docker.startEngine()
                }

                GhostButton {
                    text: qsTr("Check again")
                    onClicked: Docker.refresh()
                }
            }
        }

        /*
          An engine Simorg did not install is one it cannot start, so it says
          what to run instead of offering a button that would fail.

          Only when there is a command worth giving. A remote daemon is started
          on the machine it runs on, and a socket left behind by an uninstalled
          Docker Desktop has nothing left to start at all — in both cases the
          sentence above already says so, and a command block would only be a
          line somebody pastes into a terminal to no effect.
        */
        Reveal {
            step: 3
            Layout.fillWidth: true
            visible: Docker.manualStartCommand.length > 0

            GlassPanel {
                width: parent.width
                implicitHeight: hint.implicitHeight + 34

                ColumnLayout {
                    id: hint
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 17
                    spacing: 9

                    Text {
                        text: qsTr("START IT WHERE IT RUNS")
                        color: Theme.alpha(Theme.sky, 0.9)
                        font.pixelSize: Theme.fontEyebrow
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.5
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.radiusSmall
                        color: Theme.inset
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            /*
                              No `$` in front of it. The prompt character belongs
                              to one family of shells, and this same box holds a
                              PowerShell line on Windows — and without it the
                              text is something somebody can select and paste
                              whole.
                            */
                            text: Docker.manualStartCommand
                            color: Theme.alpha(Theme.emerald, 0.95)
                            font.family: Theme.monoFamily
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        Reveal {
            step: 4
            Layout.fillWidth: true
            visible: Docker.detail.length > 0 && Docker.runtimeManaged

            Text {
                width: parent.width
                text: Docker.detail
                color: Theme.textFaint
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
