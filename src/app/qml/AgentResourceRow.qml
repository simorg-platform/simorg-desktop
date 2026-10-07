// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One agent's share of this computer, and what it is using of it right now.
 *
 * A row of the resources table under the agents' cards. Three questions per
 * resource, in the order somebody asks them: how much is it using now, how much
 * was it promised, and may it take more. The first is the large number and the
 * bar, the second is the tick on the bar and the line under it, the third is
 * the shaded stretch and the words "up to" or "no ceiling".
 *
 * The swatch on the left is the colour this agent's segment has in the meters
 * above, which is what makes those meters readable at all: a split bar whose
 * parts nobody can name is decoration.
 *
 * "Using now" is every container the service labelled as this agent's — its
 * runtime, its network gate, the jobs it started — because all of it is this
 * computer working for that agent. It is read only while the screen is open
 * (`Docker.watchResources`), and says so rather than showing a zero when there
 * is no reading.
 */
GlassPanel {
    id: root

    required property int agentId
    required property string slug
    required property string title
    required property string avatarUrl
    required property string containerStateName
    required property bool running
    required property var envelope
    /** The row's `lifecycle`, so an agent nobody has started reads "Not started". */
    required property var lifecycle

    /** The colour of this agent's segment in the meters above. */
    property color swatch: Theme.cyan
    /** `Docker.agentUsage[agentId]`, or undefined when nothing of it is sampled. */
    property var usage: undefined
    /** Whether the service is sampling at all right now. */
    property bool sampled: false
    property real dockerCores: 0
    property real dockerMemoryMb: 0
    property bool dockerKnown: false

    signal opened()

    readonly property var shape: root.envelope || ({})
    readonly property bool measured: root.sampled && root.usage !== undefined && root.usage.sampled === true
    readonly property real usedCores: root.measured ? root.usage.cpuPercent / 100 : 0
    readonly property real usedMemoryMb: root.measured ? root.usage.memoryBytes / (1024 * 1024) : 0

    /** Every figure on the row in one unit and one way: cores, in hundredths. */
    function coresText(value) {
        if (value > 0 && value < 0.01)
            return qsTr("under 0.01");
        return Docker.formatCores(value);
    }

    /** What an envelope promises one resource, in words. */
    function promiseText(minimum, maximum, capped, format) {
        const floor = minimum > 0 ? qsTr("%1 guaranteed").arg(format(minimum))
                                  : qsTr("nothing guaranteed");
        return capped ? qsTr("%1 · up to %2").arg(floor).arg(format(maximum))
                      : qsTr("%1 · no ceiling").arg(floor);
    }

    /** Why there is no reading, when there is none. */
    readonly property string silentText: !root.sampled ? qsTr("not measured")
                                       : !root.running ? AgentState.labelFor(root.containerStateName, root.lifecycle).toLowerCase()
                                       : qsTr("waiting for a reading")

    implicitHeight: body.implicitHeight + 28
    interactive: true
    hovered: hover.hovered
    accent: root.swatch

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("%1's resources").arg(root.title)
    Accessible.description: qsTr("Open this agent")

    // The swatch, the full height of the row.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 1
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        width: 3
        radius: 2
        color: root.swatch
    }

    GridLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        columns: root.width > 760 ? 4 : 2
        columnSpacing: Theme.spaceLg
        rowSpacing: Theme.spaceSm

        // ---- Who -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 5
            Layout.columnSpan: root.width > 760 ? 1 : 2
            spacing: 10

            Avatar {
                initials: root.title.length > 0 ? root.title.charAt(0).toUpperCase() : "?"
                remote: root.avatarUrl
                size: 30
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                ElidedText {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StateDot {
                        state: root.running ? "running" : AgentState.dot(root.containerStateName)
                        size: 6
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: AgentState.labelFor(root.containerStateName, root.lifecycle)
                        color: AgentState.tone(root.containerStateName)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ---- Processor ---------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 6
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.measured ? qsTr("%1 cores").arg(root.coresText(root.usedCores)) : "—"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: root.measured ? qsTr("in use") : root.silentText
                    color: Theme.textFaint
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            UsageBar {
                Layout.fillWidth: true
                tone: Theme.cyan
                known: root.measured && root.dockerKnown
                total: root.dockerCores
                value: root.usedCores
                marker: root.shape.cpuMin || 0
                ceiling: root.shape.cpuCapped === true ? (root.shape.cpuMax || 0) : 0
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.promiseText(root.shape.cpuMin || 0, root.shape.cpuMax || 0,
                                       root.shape.cpuCapped === true,
                                       function (v) { return qsTr("%1 cores").arg(Docker.formatCores(v)); })
                color: Theme.textMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        // ---- Memory ------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 6
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.measured ? Docker.formatMegabytes(root.usedMemoryMb) : "—"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: !root.measured ? root.silentText
                        : (root.shape.memoryMin || 0) > 0 && root.usedMemoryMb > root.shape.memoryMin
                          ? qsTr("in use, above its guarantee")
                        : qsTr("in use")
                    color: root.measured && (root.shape.memoryMin || 0) > 0
                           && root.usedMemoryMb > root.shape.memoryMin
                           ? Theme.alpha(Theme.amber, 0.9) : Theme.textFaint
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            UsageBar {
                Layout.fillWidth: true
                tone: Theme.violet
                known: root.measured && root.dockerKnown
                total: root.dockerMemoryMb
                value: root.usedMemoryMb
                marker: root.shape.memoryMin || 0
                ceiling: root.shape.memoryCapped === true ? (root.shape.memoryMax || 0) : 0
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.promiseText(root.shape.memoryMin || 0, root.shape.memoryMax || 0,
                                       root.shape.memoryCapped === true,
                                       function (v) { return Docker.formatMegabytes(v); })
                color: Theme.textMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        // ---- Disk --------------------------------------------------------
        //
        // A promise and nothing else. Docker reports what a container's layers
        // hold only when asked to walk them, which is far too slow to do every
        // few seconds, so there is no honest "in use" to draw beside it.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 4
            spacing: 5

            Text {
                text: (root.shape.storageMin || 0) > 0 ? Docker.formatMegabytes(root.shape.storageMin) : "—"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.shape.storageCapped === true
                      ? qsTr("of disk · up to %1").arg(Docker.formatMegabytes(root.shape.storageMax || 0))
                      : qsTr("of disk · no ceiling")
                color: Theme.textMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler { onTapped: root.opened() }
}
