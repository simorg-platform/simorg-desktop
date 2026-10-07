// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One container.
 *
 * The controls appear on hover and on selection, and are laid out in a fixed
 * slot so that rows do not change width when the pointer crosses them. Stop and
 * Remove ask before they act; start, restart and pause do not, because none of
 * them destroys anything.
 */
Item {
    id: root

    // Roles, supplied by ContainerModel.
    required property string containerId
    required property string shortId
    required property string name
    required property string image
    required property string state
    required property string status
    required property string health
    required property string portsText
    required property bool running
    required property bool paused
    required property string cpuText
    required property string memoryText
    required property real memoryPercent

    property bool compact: false
    property bool selected: false

    /** Set by the list, so the headings and every row agree. */
    property int dotColumn: 20
    property int statusColumn: 170
    property int cpuColumn: 74
    property int memoryColumn: 90
    property int actionColumn: 140

    signal showLogs()
    signal requestStop()
    signal requestRemove()

    implicitHeight: 54

    readonly property bool active: hover.hovered || root.selected

    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.alpha(Theme.blue, 0.1)
             : hover.hovered ? Theme.alpha(Theme.sky, 0.045)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 28
        anchors.rightMargin: 24
        height: 1
        color: Theme.alpha(Theme.borderSubtle, 0.6)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: root.selected ? 26 : 0
        radius: 1.5
        color: Theme.cyan

        Behavior on height {
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 24
        spacing: 14

        StateDot {
            Layout.preferredWidth: root.dotColumn
            Layout.minimumWidth: root.dotColumn
            Layout.maximumWidth: root.dotColumn
            state: root.state
            health: root.health
            size: 8
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                ElidedText {
                    text: root.name
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: 240
                }

                Rectangle {
                    visible: root.health === "unhealthy"
                    implicitWidth: healthLabel.implicitWidth + 12
                    implicitHeight: 16
                    radius: 4
                    color: Theme.alpha(Theme.rose, 0.14)
                    border.width: 1
                    border.color: Theme.alpha(Theme.rose, 0.34)

                    Text {
                        id: healthLabel
                        anchors.centerIn: parent
                        text: qsTr("unhealthy")
                        color: Theme.rose
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.portsText.length > 0
                      ? qsTr("%1  ·  %2").arg(root.image).arg(root.portsText)
                      : root.image
                color: Theme.textFaint
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        ElidedText {
            Layout.preferredWidth: root.statusColumn
            Layout.minimumWidth: root.statusColumn
            Layout.maximumWidth: root.statusColumn
            visible: !root.compact
            text: root.status
            color: root.running ? Theme.alpha(Theme.emerald, 0.9) : Theme.textMuted
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Text {
            Layout.preferredWidth: root.cpuColumn
            Layout.minimumWidth: root.cpuColumn
            Layout.maximumWidth: root.cpuColumn
            horizontalAlignment: Text.AlignRight
            text: root.cpuText
            color: root.running ? Theme.textBody : Theme.textFaint
            font.pixelSize: 12
            font.family: Theme.monoFamily
        }

        ColumnLayout {
            Layout.preferredWidth: root.memoryColumn
            Layout.minimumWidth: root.memoryColumn
            Layout.maximumWidth: root.memoryColumn
            spacing: 3

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.memoryText
                color: root.running ? Theme.textBody : Theme.textFaint
                font.pixelSize: 12
                font.family: Theme.monoFamily
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.running && root.memoryPercent > 0
                implicitHeight: 3
                radius: 1.5
                color: Theme.inset

                Rectangle {
                    width: parent.width * Math.min(1, root.memoryPercent / 100)
                    height: parent.height
                    radius: parent.radius
                    // Memory near a container's own ceiling is the thing that
                    // gets it killed, so the bar changes colour before it does.
                    color: root.memoryPercent > 85 ? Theme.rose
                         : root.memoryPercent > 60 ? Theme.amber
                         : Theme.violet
                }
            }
        }

        // Fixed slot: the row must not resize as the controls fade in.
        Item {
            Layout.preferredWidth: root.actionColumn
            Layout.minimumWidth: root.actionColumn
            Layout.maximumWidth: root.actionColumn
            Layout.fillHeight: true

            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                opacity: root.active ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.duration(Theme.durFast) }
                }

                IconButton {
                    glyph: "terminal"
                    tooltip: qsTr("Logs")
                    size: 28
                    onClicked: root.showLogs()
                }

                IconButton {
                    glyph: root.running ? (root.paused ? "play" : "pause") : "play"
                    tooltip: root.running ? (root.paused ? qsTr("Resume") : qsTr("Pause"))
                                          : qsTr("Start")
                    size: 28
                    onClicked: {
                        if (!root.running)
                            Docker.startContainer(root.containerId);
                        else if (root.paused)
                            Docker.unpauseContainer(root.containerId);
                        else
                            Docker.pauseContainer(root.containerId);
                    }
                }

                IconButton {
                    glyph: "restart"
                    tooltip: qsTr("Restart")
                    size: 28
                    enabled: root.running
                    onClicked: Docker.restartContainer(root.containerId)
                }

                IconButton {
                    glyph: "stop"
                    tooltip: qsTr("Stop")
                    size: 28
                    enabled: root.running
                    hoverTone: Theme.amber
                    onClicked: root.requestStop()
                }

                IconButton {
                    glyph: "trash"
                    tooltip: qsTr("Remove")
                    size: 28
                    hoverTone: Theme.rose
                    onClicked: root.requestRemove()
                }
            }
        }
    }

    HoverHandler { id: hover }

}
