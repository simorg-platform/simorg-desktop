// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * A container's output, live.
 *
 * A header saying which container this is and what can be done with the whole
 * of it, over a {@link LogView} — which is where everything a reader does with
 * the lines themselves lives: drag to highlight, right click to copy, and a
 * view that follows the newest line until somebody scrolls away from it.
 *
 * Two behaviours worth stating here, because both are the opposite of what a
 * naive implementation does:
 *
 *  - It follows the tail *until you scroll up*, and then stops until you come
 *    back down. A log that yanks you back to the bottom every time a line
 *    arrives cannot be read at all.
 *  - A line is coloured by the level it names — `[INFO]`, `[WARNING]`,
 *    `[ERROR]` and the rest, the way Simorg's engine writes them — and by its
 *    stream only when it names none: stderr is then drawn as an error rather
 *    than merged, because "did that print to stderr" is most of diagnosing a
 *    container that will not start.
 */
Rectangle {
    id: root

    signal closed()

    color: Theme.alpha(Theme.base, 0.6)

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.borderStrong
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 18
                spacing: 11

                Glyph { name: "terminal"; size: 15; thickness: 1.7; tone: Theme.sky }

                Text {
                    text: Docker.logContainerName
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    visible: Docker.logsFollowing
                    implicitWidth: liveLabel.implicitWidth + 14
                    implicitHeight: 17
                    radius: 4
                    color: Theme.alpha(Theme.emerald, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(Theme.emerald, 0.3)

                    Text {
                        id: liveLabel
                        anchors.centerIn: parent
                        text: qsTr("LIVE")
                        color: Theme.alpha(Theme.emerald, 0.95)
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }

                Text {
                    text: qsTr("%1 lines").arg(Docker.logs.count)
                    color: Theme.textFaint
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                // Offered only when it does something: the button is how you
                // get back to following after scrolling away.
                GhostButton {
                    visible: !logs.following
                    text: qsTr("Jump to newest")
                    implicitHeight: 28
                    implicitWidth: 130
                    font.pixelSize: 11
                    onClicked: logs.jumpToNewest()
                }

                CopyAction {
                    text: Docker.logs.count > 0 ? Docker.logs.toPlainText() : ""
                    tooltip: qsTr("Copy everything")
                    copiedLabel: qsTr("%1 lines copied").arg(Docker.logs.count)
                    size: 28
                }

                IconButton {
                    glyph: "trash"
                    tooltip: qsTr("Clear this view")
                    size: 28
                    onClicked: Docker.logs.clear()
                }

                IconButton {
                    glyph: "logout"
                    tooltip: qsTr("Close")
                    size: 28
                    hoverTone: Theme.rose
                    onClicked: root.closed()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }

        // ---- Lines -------------------------------------------------------
        LogView {
            id: logs

            Layout.fillWidth: true
            Layout.fillHeight: true

            model: Docker.logs
            textAt: function (index) { return Docker.logs.lineAt(index); }
            toneAt: function (index) { return Docker.logs.toneAt(index); }
            // The model can join five thousand strings in one pass, which is
            // worth having over the same loop written in QML.
            allText: function () { return Docker.logs.toPlainText(); }

            leftInset: 24
            rightInset: 24
            searchable: true
            clearable: true
            onClearRequested: Docker.logs.clear()

            // Waiting is a state worth drawing: a container that has not written
            // anything since it started looks identical to a broken log viewer.
            emptyState: Component {
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    BusyRing {
                        Layout.alignment: Qt.AlignHCenter
                        running: Docker.logsFollowing
                        size: 20
                        tone: Theme.alpha(Theme.sky, 0.7)
                    }

                    Text {
                        text: qsTr("Waiting for output…")
                        color: Theme.textFaint
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
