// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * A proportional bar — how a total divides between named parts.
 *
 * Used for Docker's disk footprint, where the useful question is never "how
 * many gigabytes" on its own but "which of the four things is holding them".
 * Segments below a pixel are still given one, so a category that exists never
 * silently disappears from a chart of what exists.
 */
Item {
    id: root

    /** `[{ value, tone }]`, in the order they should be laid out. */
    property var segments: []
    /** Denominator. Zero means "add the segments up". */
    property real total: 0
    property real radius: 4

    implicitHeight: 8

    readonly property real resolvedTotal: {
        if (root.total > 0)
            return root.total;
        let sum = 0;
        for (let i = 0; i < (root.segments ? root.segments.length : 0); ++i)
            sum += root.segments[i].value;
        return sum;
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.inset
        border.width: 1
        border.color: Theme.borderSubtle
    }

    Item {
        anchors.fill: parent
        anchors.margins: 1
        clip: true

        Row {
            height: parent.height
            spacing: 1

            Repeater {
                model: root.segments

                delegate: Rectangle {
                    required property var modelData

                    readonly property real share: root.resolvedTotal > 0
                                                  ? modelData.value / root.resolvedTotal
                                                  : 0

                    // A share that rounds to nothing still gets a sliver: the
                    // bar is a statement about what is there.
                    width: modelData.value > 0
                           ? Math.max(2, share * (root.width - 2))
                           : 0
                    height: parent.height
                    color: modelData.tone
                    visible: width > 0

                    Behavior on width {
                        enabled: Theme.motion
                        NumberAnimation {
                            duration: Theme.durSlow
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.easeOut
                        }
                    }
                }
            }
        }
    }
}
