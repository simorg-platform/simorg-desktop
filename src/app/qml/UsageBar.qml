// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import Simorg

/**
 * What one agent is using of one resource, against what it was promised.
 *
 * The fill is the reading — what its containers use right now — and the tick is
 * its guarantee, so "well inside what it was promised" and "above it, on
 * borrowed headroom" are one glance rather than two numbers to compare. When
 * the envelope has a ceiling, the stretch between guarantee and ceiling is
 * shaded: that is where the agent may go while the machine is quiet.
 *
 * Drawn against what Docker has, like every meter in this application, and
 * never against a number nobody measured: with no reading the track is drawn
 * empty rather than filled with a guess.
 */
Item {
    id: root

    /** In use now, in the resource's own unit. */
    property real value: 0
    /** The guarantee, in the same unit. Zero draws no tick. */
    property real marker: 0
    /** The ceiling, in the same unit. Zero means the envelope has none. */
    property real ceiling: 0
    /** What Docker has, in the same unit. The whole width. */
    property real total: 0
    property color tone: Theme.cyan
    /** False while there is no reading to draw. */
    property bool known: true

    implicitHeight: 6

    function across(amount) {
        if (root.total <= 0)
            return 0;
        return Math.max(0, Math.min(1, amount / root.total)) * root.width;
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.inset
        border.width: 1
        border.color: Theme.borderSubtle
    }

    // Headroom the envelope allows above its guarantee.
    Rectangle {
        visible: root.ceiling > root.marker && root.total > 0
        x: root.across(root.marker)
        width: Math.max(0, root.across(root.ceiling) - root.across(root.marker))
        height: parent.height
        radius: height / 2
        color: Theme.alpha(root.tone, 0.14)
    }

    Rectangle {
        visible: root.known && root.value > 0 && root.total > 0
        width: Math.max(height, root.across(root.value))
        height: parent.height
        radius: height / 2
        color: root.marker > 0 && root.value > root.marker ? Theme.alpha(root.tone, 0.72) : root.tone

        Behavior on width {
            enabled: Theme.motion
            NumberAnimation {
                duration: Theme.durSlow
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }
    }

    // The guarantee, standing a little proud of the track so it reads as a mark.
    Rectangle {
        visible: root.marker > 0 && root.total > 0
        x: Math.min(root.width - width, root.across(root.marker))
        y: -2
        width: 2
        height: parent.height + 4
        radius: 1
        color: Theme.textPrimary
        opacity: 0.7
    }
}
