// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One folder an agent has asked for.
 *
 * Two shapes in one row, because they are one list to the person reading it:
 * everything this agent would be given, whoever decided it.
 *
 * | | What it shows | What it needs |
 * | --- | --- | --- |
 * | **Named** | the path the agent's owner typed | nothing |
 * | **Chosen here** | what it is for, and the folder you picked | a folder |
 *
 * A folder that has not been chosen is drawn as **unfinished rather than
 * broken**: amber, with the action beside it, because it is a question waiting
 * for an answer and not a fault. The one thing it must never look like is
 * granted.
 */
Item {
    id: root

    /** One entry of `AccessGrants.folders(...)`. */
    property var folder: ({})
    /** False once the request has been answered; the row becomes a readout. */
    property bool editable: true

    signal chooseRequested()
    signal clearRequested()

    readonly property bool dynamic: root.folder.dynamic === true
    readonly property bool chosen: root.folder.chosen === true
    readonly property bool writable: root.folder.writable === true
    /** The one state that needs somebody: asked for, and not yet answered. */
    readonly property bool waiting: root.dynamic && !root.chosen
    /**
     * Where the agent's container has the folder — `/d/Documents/research` for
     * `D:\Documents\research` — which is the path to give a program inside the
     * agent. Shown by {@link AgentPathLine} only where it differs, which is on
     * Windows.
     */
    readonly property string agentPath: root.folder.agentPath || ""

    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: body.implicitHeight + 26
        radius: Theme.radiusBase
        color: Theme.inset
        border.width: 1
        // Amber only while it is waiting. A chosen folder is an ordinary row
        // again, which is what makes the remaining ones findable at a glance.
        border.color: root.waiting ? Theme.alpha(Theme.amber, 0.45) : Theme.borderSubtle

        Behavior on border.color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 13
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Glyph {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                    name: "folder"
                    size: 15
                    thickness: 1.6
                    tone: root.waiting ? Theme.amber
                        : root.writable ? Theme.violet
                                        : Theme.sky
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    // The heading is what the folder is *for* when somebody has
                    // to choose it, and the folder itself when they do not.
                    // Selectable either way: a path is something people copy.
                    SelectableText {
                        Layout.fillWidth: true
                        text: root.dynamic ? (root.folder.purpose || qsTr("A folder on this computer"))
                                           : (root.folder.path || qsTr("No folder was named"))
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.family: root.dynamic ? Theme.fontFamily : Theme.monoFamily
                        wrapMode: root.dynamic ? TextEdit.WordWrap : TextEdit.WrapAnywhere
                    }

                    /*
                      Two items rather than one that switches.

                      A path is monospaced and breaks anywhere, because it has
                      no spaces to break at; a sentence is proportional and
                      wraps at words. One item flipping between those came out
                      looking justified. Whole rather than elided from the
                      middle: a path somebody copies has to be all there.
                    */
                    SelectableText {
                        Layout.fillWidth: true
                        visible: root.dynamic && root.chosen
                        text: root.folder.path || ""
                        color: Theme.textBody
                        font.pixelSize: 12
                        font.family: Theme.monoFamily
                        wrapMode: TextEdit.WrapAnywhere
                    }

                    // Where the agent has it, when that is another path.
                    AgentPathLine {
                        id: inTheAgent
                        Layout.fillWidth: true
                        path: root.folder.path || ""
                        agentPath: root.agentPath
                        visible: inTheAgent.differs && (!root.dynamic || root.chosen)
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.waiting
                        text: qsTr("You have not chosen a folder for this yet.")
                        color: Theme.amber
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.dynamic
                        text: qsTr("Named by the agent's owner. It exists on this computer or it does not.")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                /*
                  What the agent may do with it, always shown and never implied.

                  Read and write is the one worth colouring differently: it is
                  the difference between an agent that can look at somebody's
                  work and one that can delete it.
                */
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: modeLabel.implicitWidth + 18
                    implicitHeight: 22
                    radius: 5
                    readonly property color tone: root.writable ? Theme.violet : Theme.sky
                    color: Theme.alpha(tone, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(tone, 0.3)

                    Text {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: root.writable ? qsTr("CAN CHANGE") : qsTr("READ ONLY")
                        color: parent.tone
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }
                }
            }

            // ---- Choosing -----------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 25
                visible: root.dynamic && root.editable
                spacing: Theme.spaceSm

                GhostButton {
                    implicitHeight: 30
                    font.pixelSize: 12
                    text: root.chosen ? qsTr("Choose a different folder") : qsTr("Choose a folder…")
                    onClicked: root.chooseRequested()
                }

                LinkLabel {
                    visible: root.chosen
                    text: qsTr("Clear")
                    onActivated: root.clearRequested()
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
