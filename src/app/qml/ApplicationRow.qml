// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * One application on this computer, as a row of the control centre.
 *
 * Four columns, read left to right: **what** it is and where it stands — the
 * state as a word, not a colour alone; **who** may use it — the agents placed
 * here whose Applications permission reaches it; **what it takes** — its
 * process's CPU and memory while it runs, sampled only while this tab is open,
 * and its size on the disk; and **what can be done** — Open, or Quit while it
 * runs, show in folder, Uninstall.
 *
 * While it installs, the row is the install: the phase it is in and, while it
 * downloads, how far. A failed one says why, and offers to try again.
 */
GlassPanel {
    id: root

    required property string specifier
    required property string title
    required property string tag
    required property bool installed
    required property string path
    required property string entry
    required property var bytes
    required property string peerState
    required property bool running
    required property string verification
    required property real cpuPercent
    required property var memoryBytes
    required property var allowedAgentIds
    required property int allowedCount
    required property string installState
    required property real installProgress
    required property string installProblem
    required property var usedByAgentIds
    required property bool canQuit

    /** A refusal of the last action pressed on this row. */
    property string problem: ""
    /** An uninstall is waiting on the service. */
    property bool busy: false

    signal openRequested()
    signal quitRequested()
    signal revealRequested()
    signal uninstallRequested()
    signal retryRequested()

    readonly property bool installing: root.installState.length > 0 && root.installState !== "failed"
    readonly property bool failedInstall: root.installState === "failed"
    readonly property bool asking: root.peerState === "awaiting_consent"

    /** The state, as a word and as a colour: never the colour alone. */
    readonly property string statusText: root.failedInstall ? qsTr("Could not install")
                                       : root.installState === "downloading"
                                         ? (root.installProgress >= 0
                                            ? qsTr("Downloading %1%").arg(Math.round(root.installProgress * 100))
                                            : qsTr("Downloading…"))
                                       : root.installState === "unpacking" ? qsTr("Unpacking…")
                                       : root.installing ? qsTr("Finding it…")
                                       : root.asking ? qsTr("Waiting for your answer")
                                       : root.running ? qsTr("Running")
                                       : root.installed ? qsTr("Not running")
                                       : qsTr("Connected, not installed here")
    readonly property color statusTone: root.failedInstall ? Theme.rose
                                      : root.installing ? Theme.violet
                                      : root.asking ? Theme.amber
                                      : root.running ? Theme.emerald
                                      : root.installed ? Theme.textMuted
                                      : Theme.sky

    /** The agents that may use it, by name. */
    readonly property var agentNames: {
        const names = [];
        const ids = root.allowedAgentIds || [];
        for (let i = 0; i < ids.length; ++i) {
            const agent = Hub.agents.byId(ids[i]);
            names.push(agent && agent.title ? agent.title : qsTr("Agent %1").arg(ids[i]));
        }
        return names;
    }

    /** Who may use it, in words. */
    readonly property string agentsText: root.agentNames.length === 0
                                         ? qsTr("None of the agents here")
                                         : root.agentNames.length <= 3
                                           ? root.agentNames.join(", ")
                                           : qsTr("%1 and %2 more").arg(root.agentNames.slice(0, 2).join(", "))
                                                                   .arg(root.agentNames.length - 2)
    /** What it uses now, in words. */
    readonly property string usageText: root.memoryBytes >= 0
                                        ? (root.cpuPercent >= 0
                                           ? qsTr("%1 CPU · %2 memory").arg(Docker.formatPercent(root.cpuPercent))
                                                                      .arg(Docker.formatBytes(root.memoryBytes))
                                           : qsTr("%1 memory").arg(Docker.formatBytes(root.memoryBytes)))
                                        : root.running ? qsTr("measuring…")
                                        : qsTr("nothing while it is not running")

    /*
      Four columns where there is room for them. At the narrowest windows the
      who and the what-it-uses fold into one line under the name, rather than
      four columns squeezing each other into overlapping words.
    */
    readonly property bool wide: root.width > 1060

    implicitHeight: body.implicitHeight + 30
    accent: root.statusTone

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // ---- What -------------------------------------------------
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 44
                implicitHeight: 44
                radius: Theme.radiusLarge
                color: Theme.alpha(root.statusTone, 0.1)
                border.width: 1
                border.color: Theme.alpha(root.statusTone, 0.3)

                Glyph {
                    anchors.centerIn: parent
                    name: "cube"
                    size: 20
                    thickness: 1.6
                    tone: root.statusTone
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 5
                Layout.minimumWidth: 180
                Layout.alignment: Qt.AlignTop
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ElidedText {
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                        Layout.fillWidth: true
                        text: root.title
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitWidth: statusLabel.implicitWidth + 14
                        implicitHeight: 18
                        radius: 9
                        color: Theme.alpha(root.statusTone, 0.1)
                        border.width: 1
                        border.color: Theme.alpha(root.statusTone, 0.35)

                        Text {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: root.statusText
                            color: root.statusTone
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                SelectableText {
                    Layout.fillWidth: true
                    text: root.tag.length > 0 ? root.specifier + ":" + root.tag : root.specifier
                    color: Theme.textFaint
                    font.pixelSize: 11
                    font.family: Theme.monoFamily
                }

                // Narrow: who, and what it uses, on one line under the name.
                ElidedText {
                    Layout.fillWidth: true
                    visible: !root.wide
                    text: root.installed
                          ? qsTr("%1 · %2 · %3 on disk").arg(root.agentsText).arg(root.usageText)
                                                        .arg(Docker.formatBytes(root.bytes))
                          : qsTr("%1 · %2").arg(root.agentsText).arg(root.usageText)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                // A program that is not the one this computer downloaded is worth a word.
                Text {
                    Layout.fillWidth: true
                    visible: root.verification === "mismatch"
                    text: qsTr("The running program is not the one Simorg installed.")
                    color: Theme.amber
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // ---- Who ---------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 4
                Layout.alignment: Qt.AlignTop
                visible: root.wide
                spacing: 3

                ElidedText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: qsTr("AGENTS THAT MAY USE IT")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.1
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: root.agentsText
                    color: root.agentNames.length === 0 ? Theme.textFaint : Theme.textBody
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            // ---- What it takes -----------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 4
                Layout.alignment: Qt.AlignTop
                visible: root.wide
                spacing: 3

                ElidedText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: qsTr("USES")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.1
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: root.usageText
                    color: root.memoryBytes >= 0 ? Theme.textBody : Theme.textFaint
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                ElidedText {
                    Layout.fillWidth: true
                    visible: root.installed
                    text: qsTr("%1 on disk").arg(Docker.formatBytes(root.bytes))
                    color: Theme.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // ---- What can be done --------------------------------------
            // A fixed width, so every row's columns line up whichever buttons it has.
            RowLayout {
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                Layout.preferredWidth: 200
                Layout.minimumWidth: 200
                spacing: 4

                Item { Layout.fillWidth: true }

                BusyRing {
                    visible: root.installing || root.busy
                    running: root.installing || root.busy
                    size: 18
                }

                PrimaryButton {
                    visible: root.installed && !root.installing && !root.canQuit
                    enabled: !root.running && !root.busy && root.entry.length > 0
                    text: root.running ? qsTr("Running") : qsTr("Open")
                    implicitHeight: 32
                    onClicked: root.openRequested()
                }

                GhostButton {
                    visible: root.canQuit
                    enabled: !root.busy
                    text: qsTr("Quit")
                    implicitHeight: 32
                    onClicked: root.quitRequested()
                }

                GhostButton {
                    visible: root.failedInstall
                    text: qsTr("Try again")
                    implicitHeight: 32
                    onClicked: root.retryRequested()
                }

                IconButton {
                    visible: root.installed
                    glyph: "folder"
                    tooltip: qsTr("Show in folder")
                    size: 30
                    onClicked: root.revealRequested()
                }

                IconButton {
                    visible: root.installed && !root.installing
                    glyph: "trash"
                    tooltip: root.running ? qsTr("Quit it first to uninstall") : qsTr("Uninstall")
                    hoverTone: Theme.rose
                    size: 30
                    enabled: !root.busy
                    onClicked: root.uninstallRequested()
                }
            }
        }

        // The download, while there is one to measure.
        MeterBar {
            Layout.fillWidth: true
            visible: root.installState === "downloading" && root.installProgress >= 0
            height: 4
            total: 1
            segments: [{ value: Math.max(0, root.installProgress), tone: Theme.violet }]
        }

        // Why, where the button that failed is.
        SelectableText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.failedInstall ? root.installProblem : root.problem
            color: Theme.rose
            font.pixelSize: 12
        }
    }
}
