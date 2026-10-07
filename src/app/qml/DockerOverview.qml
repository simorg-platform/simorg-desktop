// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Is anything wrong, and what is this costing me.
 *
 * Four readings across the top, then the one breakdown that leads to an action:
 * where Docker's disk has gone, and how much of it can be handed back. Disk is
 * the resource that actually surprises people — a laptop quietly loses eighty
 * gigabytes to build cache and nothing anywhere says so.
 */
Item {
    id: root

    signal openView(int index)

    /** Percentages here are summed across containers, so full load is 100 × cores. */
    readonly property real cpuCeiling: Math.max(100, Docker.engineCpus * 100)

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

                // ---- Readings ------------------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    /*
                      Every tile the same height, set on the tiles rather than on
                      the grid.

                      A fixed height here was right at four across and wrong at
                      two: below 1080 the grid wraps to a second row and a
                      height that only ever described one row drew the two on
                      top of each other. Sizing the cells lets the grid be as
                      tall as the rows it actually has, and the four eyebrow
                      labels still sit on one line.
                    */
                    columns: root.width > 1080 ? 4 : (root.width > 640 ? 2 : 1)
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 148
                        label: qsTr("PROCESSOR")
                        glyph: "cpu"
                        tone: Theme.cyan
                        value: Docker.formatPercent(Docker.cpuPercent)
                        caption: qsTr("across %1 running · %2 cores available")
                                     .arg(Docker.containersRunning).arg(Docker.engineCpus)

                        Sparkline {
                            values: Docker.cpuHistory
                            maximum: root.cpuCeiling
                            tone: Theme.cyan
                            height: 34
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 148
                        label: qsTr("MEMORY")
                        glyph: "memory"
                        tone: Theme.violet
                        value: Docker.formatBytes(Docker.memoryUsed)
                        caption: qsTr("of %1 Docker may use").arg(Docker.formatBytes(Docker.memoryTotal))

                        Sparkline {
                            values: Docker.memoryHistory
                            maximum: Math.max(1, Docker.memoryTotal)
                            tone: Theme.violet
                            height: 34
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 148
                        label: qsTr("CONTAINERS")
                        glyph: "container"
                        tone: Theme.emerald
                        value: Docker.containersRunning
                        caption: Docker.containersTotal > Docker.containersRunning
                                 ? qsTr("running · %1 stopped").arg(Docker.containersStopped)
                                 : qsTr("running")

                        MeterBar {
                            height: 8
                            total: Math.max(1, Docker.containersTotal)
                            segments: [
                                { value: Docker.containersRunning, tone: Theme.emerald },
                                { value: Docker.containersPaused, tone: Theme.amber },
                                { value: Docker.containersStopped,
                                  tone: Theme.alpha(Theme.textMuted, 0.4) }
                            ]
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 148
                        label: qsTr("DISK")
                        glyph: "disk"
                        tone: Theme.amber
                        value: Docker.diskMeasured ? Docker.formatBytes(Docker.diskTotal)
                                                   : qsTr("measuring…")
                        caption: Docker.diskReclaimable > 0
                                 ? qsTr("%1 can be reclaimed")
                                       .arg(Docker.formatBytes(Docker.diskReclaimable))
                                 : qsTr("nothing to reclaim")

                        MeterBar {
                            height: 8
                            segments: [
                                { value: Docker.diskImages, tone: Theme.blue },
                                { value: Docker.diskContainers, tone: Theme.emerald },
                                { value: Docker.diskVolumes, tone: Theme.violet },
                                { value: Docker.diskBuildCache, tone: Theme.amber }
                            ]
                        }
                    }
                }

                // ---- Disk, in detail ------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: disk.implicitHeight + 40

                    ColumnLayout {
                        id: disk
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "disk"; size: 16; thickness: 1.7; tone: Theme.amber }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Where Docker's disk space has gone")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: Docker.formatBytes(Docker.diskTotal)
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.Bold
                                font.family: Theme.monoFamily
                            }
                        }

                        MeterBar {
                            Layout.fillWidth: true
                            implicitHeight: 12
                            radius: 3
                            segments: [
                                { value: Docker.diskImages, tone: Theme.blue },
                                { value: Docker.diskContainers, tone: Theme.emerald },
                                { value: Docker.diskVolumes, tone: Theme.violet },
                                { value: Docker.diskBuildCache, tone: Theme.amber }
                            ]
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.width > 780 ? 4 : 2
                            columnSpacing: Theme.spaceMd
                            rowSpacing: Theme.spaceSm

                            Repeater {
                                model: [
                                    { tone: Theme.blue, label: qsTr("Images"),
                                      value: Docker.diskImages,
                                      note: qsTr("%1 images").arg(Docker.imageCount),
                                      what: "images" },
                                    { tone: Theme.emerald, label: qsTr("Containers"),
                                      value: Docker.diskContainers,
                                      note: qsTr("writable layers"), what: "containers" },
                                    { tone: Theme.violet, label: qsTr("Volumes"),
                                      value: Docker.diskVolumes,
                                      note: qsTr("saved data"), what: "volumes" },
                                    { tone: Theme.amber, label: qsTr("Build cache"),
                                      value: Docker.diskBuildCache,
                                      note: qsTr("speeds up rebuilds"), what: "build" }
                                ]

                                delegate: RowLayout {
                                    id: legend
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 9

                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 4
                                        width: 8
                                        height: 8
                                        radius: 2
                                        color: legend.modelData.tone
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            text: legend.modelData.label
                                            color: Theme.textBody
                                            font.pixelSize: 12
                                        }

                                        Text {
                                            text: Docker.formatBytes(legend.modelData.value)
                                            color: Theme.textPrimary
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            font.family: Theme.monoFamily
                                        }

                                        Text {
                                            text: legend.modelData.note
                                            color: Theme.textFaint
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Reclaiming -----------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: Docker.diskReclaimable > 0
                    implicitHeight: reclaim.implicitHeight + 40
                    accent: Theme.amber

                    ColumnLayout {
                        id: reclaim
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "trash"; size: 16; thickness: 1.7; tone: Theme.amber }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("%1 is not being used by anything")
                                          .arg(Docker.formatBytes(Docker.diskReclaimable))
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Images nothing is built on, layers left over from old builds, and volumes no container refers to. Reclaiming them frees the space; anything still in use is never touched.")
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.45
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: Theme.spaceSm

                            GhostButton {
                                text: qsTr("Reclaim build cache")
                                implicitHeight: 36
                                onClicked: confirm.ask("build", qsTr("build cache"),
                                                       Docker.diskBuildCache)
                            }

                            GhostButton {
                                text: qsTr("Reclaim unused images")
                                implicitHeight: 36
                                onClicked: confirm.ask("images", qsTr("unused images"),
                                                       Docker.diskImages)
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Volumes are separated out and worded differently on
                        // purpose: the other two remove things that can be
                        // rebuilt, and this one removes data that cannot.
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            visible: Docker.diskVolumes > 0
                            text: qsTr("Unused volumes hold saved data — databases, uploads, whatever a container wrote. Simorg does not offer to delete those from here.")
                            color: Theme.textFaint
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- Engine facts ---------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: facts.implicitHeight + 36

                    GridLayout {
                        id: facts
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        columns: root.width > 820 ? 4 : 2
                        columnSpacing: Theme.spaceLg
                        rowSpacing: Theme.spaceSm

                        Repeater {
                            model: [
                                { label: qsTr("ENGINE"), value: Docker.engineVersion },
                                { label: qsTr("API"), value: Docker.apiVersion },
                                { label: qsTr("CLIENT"),
                                  value: Docker.clientVersion.length > 0 ? Docker.clientVersion
                                                                        : qsTr("not on PATH") },
                                { label: qsTr("IMAGES"), value: String(Docker.imageCount) }
                            ]

                            delegate: ColumnLayout {
                                id: fact
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: fact.modelData.label
                                    color: Theme.textFaint
                                    font.pixelSize: Theme.fontEyebrow
                                    font.weight: Font.ExtraBold
                                    font.letterSpacing: 1.2
                                }

                                ElidedText {
                                    Layout.fillWidth: true
                                    text: fact.modelData.value
                                    color: Theme.textBody
                                    font.pixelSize: 13
                                    font.family: Theme.monoFamily
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: confirm
        anchors.fill: parent

        property string pendingWhat: ""

        function ask(what, label, size) {
            confirm.pendingWhat = what;
            confirm.title = qsTr("Reclaim %1?").arg(label);
            confirm.body = qsTr("This permanently removes everything in that category that nothing is currently using. It cannot be undone, but nothing that is in use is affected — and anything removed can be downloaded or rebuilt again.");
            confirm.confirmText = qsTr("Reclaim");
            confirm.open();
        }

        onAccepted: Docker.reclaim(confirm.pendingWhat)
    }
}
