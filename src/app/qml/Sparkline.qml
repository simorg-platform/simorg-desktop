// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * A small history line — CPU or memory over the last couple of minutes.
 *
 * Drawn with Qt Quick Shapes rather than a Canvas: the data changes every few
 * seconds, and a Canvas repaint is a full software rasterisation of the item
 * every time it does. This is a scene-graph node that the GPU redraws for free.
 *
 * The vertical scale is the caller's, not the data's. A line that renormalises
 * to its own maximum makes 2% CPU and 90% CPU look identical, which is the one
 * thing a monitoring readout must never do.
 */
Item {
    id: root

    /** Values, oldest first. */
    property var values: []
    /** Top of the scale. Values above it are clipped to the top edge. */
    property real maximum: 100
    property color tone: Theme.cyan
    property real thickness: 1.6
    /** Draws a translucent wash between the line and the baseline. */
    property bool filled: true

    implicitHeight: 40

    readonly property int sampleCount: values ? values.length : 0

    /** Screen-space points for the line itself. */
    readonly property var linePoints: {
        const count = root.sampleCount;
        if (count < 2 || root.width <= 0)
            return [];

        const scale = root.maximum > 0 ? root.maximum : 1;
        const step = root.width / (count - 1);
        const inset = root.thickness;      // keep the stroke inside the item
        const usable = Math.max(1, root.height - inset * 2);

        const points = [];
        for (let i = 0; i < count; ++i) {
            const value = Math.max(0, Math.min(scale, root.values[i]));
            points.push(Qt.point(i * step, inset + usable - (value / scale) * usable));
        }
        return points;
    }

    readonly property var areaPoints: {
        const line = root.linePoints;
        if (line.length < 2)
            return [];
        // The same line, closed down to the baseline and back.
        return line.concat([Qt.point(root.width, root.height),
                            Qt.point(0, root.height)]);
    }

    Shape {
        id: shape

        anchors.fill: parent
        antialiasing: true
        visible: root.linePoints.length >= 2

        // The curve renderer where the running Qt has one; see OsLogo.qml for
        // why this is an assignment rather than a binding.
        Component.onCompleted: {
            if (Shape.CurveRenderer !== undefined)
                shape.preferredRendererType = Shape.CurveRenderer;
        }

        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: root.height
                GradientStop { position: 0.0; color: Theme.alpha(root.tone, 0.28) }
                GradientStop { position: 1.0; color: Theme.alpha(root.tone, 0.0) }
            }
            PathPolyline { path: root.filled ? root.areaPoints : [] }
        }

        ShapePath {
            strokeColor: root.tone
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.linePoints }
        }
    }

    // The most recent sample, marked — the eye goes to it first, and it is the
    // one number the line is actually reporting.
    Rectangle {
        visible: root.linePoints.length >= 2
        width: 5
        height: 5
        radius: 2.5
        color: root.tone
        x: root.width - width / 2
        y: (root.linePoints.length ? root.linePoints[root.linePoints.length - 1].y : 0) - height / 2
    }

    // Something to look at before the first samples arrive, so the tile does
    // not appear broken for its first three seconds.
    Rectangle {
        visible: root.linePoints.length < 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        height: 1
        color: Theme.alpha(root.tone, 0.25)
    }
}
