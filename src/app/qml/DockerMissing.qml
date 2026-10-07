// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * Docker is not on this computer, seen from the Docker tab.
 *
 * Short on purpose. The introduction to what Docker is lives in the window that
 * runs before anybody signs in: whether this computer can run a container is a
 * fact about the computer, and it belongs at the start rather than three clicks
 * into a dashboard.
 *
 * What is left is the honest statement, Docker's own page, and a way to check
 * again once it is installed. Simorg installs no Docker: whichever the person
 * installs, the next check finds it.
 */
Item {
    id: root

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 560)
        spacing: Theme.spaceLg

        Reveal {
            step: 0
            Layout.alignment: Qt.AlignHCenter

            // Implicit size, not width and height: Reveal measures itself from
            // its child's implicit size, and a plain Item has none.
            Item {
                implicitWidth: 76
                implicitHeight: 76

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Theme.alpha(Theme.sky, 0.08)
                    border.width: 1
                    border.color: Theme.alpha(Theme.sky, 0.26)
                }

                Glyph {
                    anchors.centerIn: parent
                    name: "container"
                    size: 32
                    thickness: 1.5
                    tone: Theme.sky
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
                    text: qsTr("Docker is not on this computer yet")
                    color: Theme.textPrimary
                    font.pixelSize: 21
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Agents run inside sealed boxes, and Docker is the software that runs them. Simorg does not install Docker: install any Docker you like, and once it is running Simorg finds it and uses it.")
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
                    text: qsTr("Get Docker")
                    onClicked: App.openExternal(App.getDockerUrl)
                }

                GhostButton {
                    text: qsTr("Check again")
                    onClicked: Preflight.run()
                }
            }
        }
    }
}
