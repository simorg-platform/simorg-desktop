// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * The platform mark as a standalone badge — the hexagon, a drifting orbit ring
 * and the logo. A lighter relative of BrandDiagram for places that want the
 * motif without the whole market around it.
 */
Item {
    id: root

    property real size: 132
    property bool showLogo: true

    implicitWidth: size
    implicitHeight: size

    readonly property real cx: size / 2
    readonly property real cy: size / 2
    readonly property real hw: size * 0.3
    readonly property real hh: size * 0.335

    readonly property var outline: {
        const unit = [[22, 4], [78, 4], [100, 50], [78, 96], [22, 96], [0, 50]];
        const points = unit.map(function (p) {
            return Qt.point(cx - hw + (p[0] / 100) * hw * 2,
                            cy - hh + (p[1] / 100) * hh * 2);
        });
        points.push(points[0]);
        return points;
    }

    property real breath: 0.6
    SequentialAnimation on breath {
        running: Theme.motion
        loops: Animation.Infinite
        NumberAnimation { from: 0.4; to: 1.0; duration: 2300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.4; duration: 2300; easing.type: Easing.InOutSine }
    }

    // Ambient glow behind the mark.
    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.cx; centerY: root.cy; centerRadius: root.size * 0.5
                focalX: root.cx; focalY: root.cy
                GradientStop { position: 0.0; color: Theme.alpha(Theme.sky, 0.2) }
                GradientStop { position: 1.0; color: Theme.alpha(Theme.sky, 0) }
            }
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.size * 0.5; radiusY: root.size * 0.5
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    Shape {
        id: orbit
        width: root.size * 0.92
        height: root.size * 0.92
        x: root.cx - width / 2
        y: root.cy - height / 2
        transformOrigin: Item.Center
        antialiasing: true

        RotationAnimation on rotation {
            running: Theme.motion
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 30000
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.alpha(Theme.blue, 0.34)
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 11]
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: orbit.width / 2; centerY: orbit.height / 2
                radiusX: orbit.width / 2 - 1; radiusY: orbit.height / 2 - 1
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // Halo, gradient edge, then the darker face over it.
    Shape {
        anchors.fill: parent
        antialiasing: true
        opacity: root.breath
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.alpha(Theme.sky, 0.16)
            strokeWidth: 7
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.outline }
        }
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: root.cx - root.hw; y1: root.cy - root.hh
                x2: root.cx + root.hw; y2: root.cy + root.hh
                GradientStop { position: 0.0; color: Theme.cyan }
                GradientStop { position: 0.5; color: Theme.blue }
                GradientStop { position: 1.0; color: Theme.violet }
            }
            PathPolyline { path: root.outline }
        }
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeWidth: -1
            fillColor: Theme.alpha(Theme.base, 0.96)
            PathPolyline {
                path: {
                    const inset = 1.8;
                    const unit = [[22, 4], [78, 4], [100, 50], [78, 96], [22, 96], [0, 50]];
                    const hw = root.hw - inset;
                    const hh = root.hh - inset;
                    const points = unit.map(function (p) {
                        return Qt.point(root.cx - hw + (p[0] / 100) * hw * 2,
                                        root.cy - hh + (p[1] / 100) * hh * 2);
                    });
                    points.push(points[0]);
                    return points;
                }
            }
        }
    }

    Image {
        visible: root.showLogo
        anchors.centerIn: parent
        source: "qrc:/simorg/branding/simorg-logo.svg"
        width: root.size * 0.34
        height: root.size * 0.34
        sourceSize: Qt.size(root.size, root.size)
        smooth: true
        mipmap: true
    }
}
