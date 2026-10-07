// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * A container's state, as a dot and a word in a tinted capsule.
 *
 * The field somebody scans a column of, so it is drawn the same everywhere it
 * appears — see {@link AgentState}, which owns the colour and the wording.
 */
Rectangle {
    id: root

    /** One of `simorg::agentContainerStateName` — `running`, `image-missing`, … */
    property string containerStateName: ""
    property bool running: false
    /** The row's `lifecycle`, so an agent nobody has started reads "Not started". */
    property var lifecycle: null

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 26
    radius: 5
    color: Theme.alpha(AgentState.tone(root.containerStateName), 0.12)
    border.width: 1
    border.color: Theme.alpha(AgentState.tone(root.containerStateName), 0.32)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        StateDot {
            state: root.running ? "running" : AgentState.dot(root.containerStateName)
            size: 7
        }

        Text {
            text: AgentState.labelFor(root.containerStateName, root.lifecycle)
            color: AgentState.tone(root.containerStateName)
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}
