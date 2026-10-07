// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * Where an agent has a folder of this computer, when that is another path.
 *
 * On Windows the machine service mounts `D:\Documents\research` as
 * `/d/Documents/research`, and a program inside the agent is given paths by
 * that name. Plugins read either spelling, but this is the one that is true in
 * there, and the one a log inside the agent will name — so it is said under
 * the folder, ready to be taken. On a Mac or Linux the two are the same path and nothing is said.
 *
 * One line wherever a folder is shown: a folder an agent asked for
 * ({@link RequestedFolderRow}) and a folder every agent is given
 * ({@link SchemaField}).
 */
RowLayout {
    id: root

    /** The folder as this computer names it. */
    property string path: ""
    /** Where the agent's container has it. */
    property string agentPath: AccessGrants.agentPath(root.path)
    /** True when the two differ, which is what shows this. */
    readonly property bool differs: root.agentPath.length > 0 && root.agentPath !== root.path

    visible: root.differs
    spacing: 6

    Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 1
        text: qsTr("In the agent")
        color: Theme.textFaint
        font.pixelSize: 11
    }

    SelectableText {
        objectName: "agentPath"
        Layout.fillWidth: true
        text: root.agentPath
        color: Theme.textBody
        font.pixelSize: 12
        font.family: Theme.monoFamily
        wrapMode: TextEdit.WrapAnywhere
    }

    CopyAction {
        Layout.alignment: Qt.AlignTop
        text: root.agentPath
        tooltip: qsTr("Copy the path the agent sees")
        size: 22
    }
}
