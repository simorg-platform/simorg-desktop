// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * A container's state, as one dot.
 *
 * Running gets a slow halo; nothing else moves. Motion is the scarcest signal
 * on a screen, and spending it on the one state that means "this is happening
 * right now" is what makes a list of thirty containers readable at a glance.
 */
Item {
    id: root

    /** `running`, `exited`, `paused`, `created`, `restarting`, `dead`. */
    property string state: ""
    /** `healthy`, `unhealthy`, `starting`, or empty. */
    property string health: ""
    property int size: 8

    implicitWidth: size
    implicitHeight: size

    readonly property color tone: {
        if (root.health === "unhealthy")
            return Theme.rose;
        if (root.state === "running")
            return root.health === "starting" ? Theme.amber : Theme.emerald;
        if (root.state === "paused" || root.state === "restarting")
            return Theme.amber;
        if (root.state === "dead")
            return Theme.rose;
        return Theme.alpha(Theme.textMuted, 0.55);
    }

    readonly property bool live: root.state === "running"

    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: root.size * 2.4
        height: width
        radius: width / 2
        color: Theme.alpha(root.tone, 0.18)
        visible: root.live

        SequentialAnimation on scale {
            running: root.live && Theme.motion
            loops: Animation.Infinite
            NumberAnimation { from: 0.7; to: 1.0; duration: 1400; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.7; duration: 1400; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: root.size / 2
        color: root.tone

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }
}
