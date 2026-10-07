// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * An indeterminate spinner in the brand gradient.
 *
 * A single arc that both rotates and breathes in length, so it reads as
 * continuous progress rather than a ticking clock.
 */
Item {
    id: root

    property real size: 22
    property bool running: true
    property color tone: Theme.textPrimary
    property real thickness: 2.4

    implicitWidth: size
    implicitHeight: size
    visible: opacity > 0

    Shape {
        id: shape
        anchors.fill: parent
        antialiasing: true
        transformOrigin: Item.Center

        property real sweep: 90

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.alpha(root.tone, 0.22)
            strokeWidth: root.thickness
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - root.thickness) / 2
                radiusY: (root.size - root.thickness) / 2
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.tone
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - root.thickness) / 2
                radiusY: (root.size - root.thickness) / 2
                startAngle: -90
                sweepAngle: shape.sweep
            }
        }

        RotationAnimation on rotation {
            running: root.running && Theme.motion
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
        }

        SequentialAnimation on sweep {
            running: root.running && Theme.motion
            loops: Animation.Infinite
            NumberAnimation { from: 40; to: 280; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 280; to: 40; duration: 700; easing.type: Easing.InOutQuad }
        }
    }
}
