// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * The ambient backdrop every Simorg window sits on.
 *
 * Three slowly drifting radial orbs over a deep vertical gradient, a faint
 * hexagon mesh, and a vignette — the same recipe as `panelAmbientBackground`
 * in the web console, rebuilt with Qt Quick Shapes so it stays GPU-drawn.
 *
 * The orbs move on periods of half a minute or more: at that speed the screen
 * feels alive without ever pulling the eye away from the content.
 */
Item {
    id: root

    /** Dialled down behind dense content so text keeps its contrast. */
    property real intensity: 1.0

    // ---- Base wash -------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.base }
            GradientStop { position: 0.25; color: Theme.baseMid }
            GradientStop { position: 0.5; color: Theme.baseHigh }
            GradientStop { position: 0.75; color: Theme.baseMid }
            GradientStop { position: 1.0; color: Theme.base }
        }
    }

    // ---- Hexagon mesh ----------------------------------------------------
    Canvas {
        id: mesh
        anchors.fill: parent
        opacity: 0.5 * root.intensity

        // Painted once per resize — the mesh is static, so nothing here runs
        // per frame.
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.rgba(Theme.cyan.r, Theme.cyan.g, Theme.cyan.b, 0.055);
            ctx.lineWidth = 1;

            const r = 34;                        // hexagon circumradius
            const stepX = r * 1.5;
            const stepY = Math.sqrt(3) * r;

            for (let col = 0; col * stepX < width + r; ++col) {
                const cx = col * stepX;
                const yOffset = (col % 2) ? stepY / 2 : 0;
                for (let row = 0; row * stepY < height + stepY; ++row) {
                    const cy = row * stepY + yOffset;
                    ctx.beginPath();
                    for (let i = 0; i < 6; ++i) {
                        const angle = Math.PI / 3 * i;
                        const px = cx + r * Math.cos(angle);
                        const py = cy + r * Math.sin(angle);
                        if (i === 0)
                            ctx.moveTo(px, py);
                        else
                            ctx.lineTo(px, py);
                    }
                    ctx.closePath();
                    ctx.stroke();
                }
            }
        }
    }

    // ---- Drifting orbs ---------------------------------------------------
    /**
     * A single soft light source.
     *
     * One animated `phase` drives position and scale together, so the orb
     * traces a slow ellipse rather than sliding along one axis and back. It
     * also keeps the whole effect to one animation per orb.
     */
    component Orb: Shape {
        id: orb

        property color tone: Theme.cyan
        property real tint: 0.16
        property real orbRadius: 320
        property real centreX: 0
        property real centreY: 0
        property real spanX: 60
        property real spanY: 60
        /** Seconds for one full drift cycle. */
        property int period: 34
        property real strength: 1.0
        property real phase: 0

        width: orbRadius * 2
        height: orbRadius * 2
        antialiasing: true

        x: centreX - orbRadius + Math.sin(phase * 2 * Math.PI) * spanX
        y: centreY - orbRadius + Math.cos(phase * 2 * Math.PI) * spanY
        scale: 1 + 0.09 * Math.sin(phase * Math.PI)

        NumberAnimation on phase {
            running: Theme.motion
            loops: Animation.Infinite
            from: 0
            to: 1
            duration: orb.period * 1000
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: orb.orbRadius
                centerY: orb.orbRadius
                centerRadius: orb.orbRadius
                focalX: orb.orbRadius
                focalY: orb.orbRadius
                GradientStop { position: 0.0; color: Qt.rgba(orb.tone.r, orb.tone.g, orb.tone.b, orb.tint * orb.strength) }
                GradientStop { position: 0.5; color: Qt.rgba(orb.tone.r, orb.tone.g, orb.tone.b, orb.tint * 0.34 * orb.strength) }
                GradientStop { position: 1.0; color: Qt.rgba(orb.tone.r, orb.tone.g, orb.tone.b, 0) }
            }
            PathAngleArc {
                centerX: orb.orbRadius
                centerY: orb.orbRadius
                radiusX: orb.orbRadius
                radiusY: orb.orbRadius
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Orb {
        tone: Theme.cyan
        tint: 0.15
        strength: root.intensity
        orbRadius: Math.max(260, root.width * 0.42)
        centreX: root.width * 0.5
        centreY: root.height * 0.02
        spanX: root.width * 0.06
        spanY: root.height * 0.05
        period: 38
    }

    Orb {
        tone: Theme.violet
        tint: 0.13
        strength: root.intensity
        orbRadius: Math.max(240, root.width * 0.36)
        centreX: root.width * 0.88
        centreY: root.height * 0.44
        spanX: root.width * 0.05
        spanY: root.height * 0.07
        period: 47
    }

    Orb {
        tone: Theme.blue
        tint: 0.1
        strength: root.intensity
        orbRadius: Math.max(220, root.width * 0.34)
        centreX: root.width * 0.1
        centreY: root.height * 0.9
        spanX: root.width * 0.07
        spanY: root.height * 0.04
        period: 53
    }

    // ---- Vignette --------------------------------------------------------
    // Pulls the eye to the middle and keeps the orbs from washing out the
    // window edges.
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height / 2
                centerRadius: Math.max(root.width, root.height) * 0.62
                focalX: root.width / 2
                focalY: root.height / 2
                GradientStop { position: 0.0; color: Theme.alpha(Theme.base, 0) }
                GradientStop { position: 0.68; color: Theme.alpha(Theme.base, 0.16) }
                GradientStop { position: 1.0; color: Theme.alpha(Theme.base, 0.7) }
            }
            startX: 0
            startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
