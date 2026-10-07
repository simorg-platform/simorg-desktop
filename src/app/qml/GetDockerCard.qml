// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * How Docker comes to a computer that has none: the person installs it.
 *
 * Simorg never installs, updates or bundles Docker. Installing software on somebody's computer —
 * scripts run with administrator rights, groups changed, an engine left
 * listening — is theirs to decide, with a Docker of their choosing. So this says
 * so, links Docker's own page, and gives the one fact that makes it simple:
 * whatever Docker they install, the service finds it once it runs and uses it.
 *
 * One component for every place that says Docker is missing — the check window,
 * the setup wizard's last step and the page that explains Docker — so the three
 * cannot disagree.
 *
 * Where the check has looked at the graphics cards and
 * one Docker would lend this computer's card — Colima with a krunkit machine on
 * a Mac with Apple silicon, Docker Engine on Linux — the graphics panel sits
 * right below with its commands, and this says so: choosing that Docker now is
 * cheaper than making Docker's machine again later.
 */
GlassPanel {
    id: root

    /** The graphics panel below recommends a Docker, with the commands that install it. */
    property bool graphicsBelow: false

    implicitHeight: body.implicitHeight + 40
    accent: Theme.violet

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Glyph {
                name: "server"
                size: 17
                thickness: 1.7
                tone: Theme.violet
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Install Docker yourself")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.graphicsBelow
                  ? qsTr("Simorg does not install Docker. Install any Docker you like — or the one below, which also lets agents use this computer's graphics card. Once it is running, Simorg finds it and uses it.")
                  : qsTr("Simorg does not install Docker. Download and install any Docker you like. Once it is running, Simorg finds it and uses it — nothing else to set up.")
            color: Theme.textBody
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }

        GhostButton {
            Layout.topMargin: 4
            text: qsTr("Get Docker")
            onClicked: App.openExternal(App.getDockerUrl)
        }
    }
}
