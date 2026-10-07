// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * The Simorg market, drawn as it moves.
 *
 * Users, teams and companies stand behind the agents that act for them, and
 * those agents are the only parties that meet in the platform hexagon: intent
 * travels up the right-hand lane in cyan, capability comes back down the left
 * in violet. Provider side above, demand side below, which is the same drawing
 * the landing page animates in HowItWorks.tsx and the web console shows beside
 * its sign-in form, so someone arriving from the website recognises the app
 * before they read a word of it.
 *
 * Authored against a fixed 340×620 grid and scaled to fit, which keeps every
 * coordinate below readable next to the SVG it came from.
 */
Item {
    id: root

    readonly property real designWidth: 340
    readonly property real designHeight: 620

    implicitWidth: designWidth
    implicitHeight: designHeight

    // ---- Geometry --------------------------------------------------------
    readonly property real hexCx: 170
    readonly property real hexCy: 306
    readonly property real hexHw: 58
    readonly property real hexHh: 64

    /**
     * Flat top and bottom, pointed left and right — the platform silhouette.
     * Percentages of the bounding box, straight from the web components.
     */
    readonly property var hexUnitPoints: [
        [22, 4], [78, 4], [100, 50], [78, 96], [22, 96], [0, 50]
    ]

    /** Closed hexagon outline, inset by `inset` pixels. */
    function hexOutline(inset) {
        const hw = hexHw - inset;
        const hh = hexHh - inset;
        const points = hexUnitPoints.map(function (p) {
            return Qt.point(hexCx - hw + (p[0] / 100) * hw * 2,
                            hexCy - hh + (p[1] / 100) * hh * 2);
        });
        points.push(points[0]);   // PathPolyline does not close itself
        return points;
    }

    readonly property var hexEdge: hexOutline(0)
    readonly property var hexFace: hexOutline(2.4)
    readonly property var hexTracePath: hexOutline(1.2)

    readonly property color demandTone: Theme.cyan
    readonly property color providerTone: Theme.violet

    function toneFor(tone) {
        return tone === 0 ? root.demandTone : root.providerTone;
    }

    /**
     * The eight parties. `tone` 0 is the demand side, 1 the provider side, and
     * `place` puts each label on the side of its node where no lane arrives.
     */
    readonly property var nodes: [
        { x:  54, y:  68, r: 21, glyph: "people",   label: "USERS",       tone: 1, place: "above" },
        { x: 170, y:  68, r: 21, glyph: "team",     label: "TEAMS",       tone: 1, place: "above" },
        { x: 286, y:  68, r: 21, glyph: "store",    label: "VENDORS",     tone: 1, place: "above" },
        { x: 170, y: 176, r: 26, glyph: "robot",    label: "AGENTS",      tone: 1, place: "left"  },
        { x: 170, y: 436, r: 26, glyph: "robot",    label: "AGENTS",      tone: 0, place: "right" },
        { x:  54, y: 544, r: 21, glyph: "people",   label: "USERS",       tone: 0, place: "below" },
        { x: 170, y: 544, r: 21, glyph: "team",     label: "TEAMS",       tone: 0, place: "below" },
        { x: 286, y: 544, r: 21, glyph: "building", label: "ENTERPRISES", tone: 0, place: "below" }
    ]

    /**
     * The ten lanes. A `power` lane carries a principal into the agent it
     * powers; a `market` lane crosses the platform. `arrow` is the direction
     * of travel in degrees, and `begin` staggers the packets so they never set
     * off together.
     */
    readonly property var lanes: [
        { x0:  54, y0:  89, c1x:  54, c1y: 120, c2x: 104, c2y: 126, x1: 147, y1: 152, arrow:   31, tone: 1, market: false, begin:  200, dur: 4200 },
        { x0: 170, y0:  89, c1x: 170, c1y: 107, c2x: 170, c2y: 124, x1: 170, y1: 142, arrow:   90, tone: 1, market: false, begin: 1400, dur: 3600 },
        { x0: 286, y0:  89, c1x: 286, c1y: 120, c2x: 236, c2y: 126, x1: 193, y1: 152, arrow:  149, tone: 1, market: false, begin: 2500, dur: 4400 },
        { x0:  54, y0: 523, c1x:  54, c1y: 492, c2x: 104, c2y: 486, x1: 147, y1: 460, arrow:  -31, tone: 0, market: false, begin:  800, dur: 4200 },
        { x0: 170, y0: 523, c1x: 170, c1y: 505, c2x: 170, c2y: 488, x1: 170, y1: 470, arrow:  270, tone: 0, market: false, begin: 2000, dur: 3600 },
        { x0: 286, y0: 523, c1x: 286, c1y: 492, c2x: 236, c2y: 486, x1: 193, y1: 460, arrow:  211, tone: 0, market: false, begin: 3100, dur: 4400 },
        { x0: 200, y0: 423, c1x: 200, c1y: 406, c2x: 200, c2y: 390, x1: 200, y1: 373, arrow:  270, tone: 0, market: true,  begin:    1, dur: 2600 },
        { x0: 200, y0: 239, c1x: 200, c1y: 222, c2x: 200, c2y: 206, x1: 200, y1: 189, arrow:  270, tone: 0, market: true,  begin:  500, dur: 2600 },
        { x0: 140, y0: 189, c1x: 140, c1y: 206, c2x: 140, c2y: 222, x1: 140, y1: 239, arrow:   90, tone: 1, market: true,  begin: 1300, dur: 2600 },
        { x0: 140, y0: 373, c1x: 140, c1y: 390, c2x: 140, c2y: 406, x1: 140, y1: 423, arrow:   90, tone: 1, market: true,  begin: 1800, dur: 2600 }
    ]

    /** The arrowhead at a lane's tip, as a closed polyline. */
    function arrowPoints(tipX, tipY, rotation, size) {
        const a = rotation * Math.PI / 180;
        const cos = Math.cos(a);
        const sin = Math.sin(a);
        function at(px, py) {
            return Qt.point(tipX + px * cos - py * sin, tipY + px * sin + py * cos);
        }
        return [at(-size, -size * 0.6), at(0, 0), at(-size, size * 0.6), at(-size, -size * 0.6)];
    }

    /** Sine polyline for the drifting waves under the diagram. */
    function wavePoints(yBase, amplitude, phase) {
        const points = [];
        const steps = 48;
        for (let i = 0; i <= steps; ++i) {
            const t = i / steps;
            points.push(Qt.point(t * designWidth,
                                 yBase + Math.sin(t * Math.PI * 3 + phase) * amplitude));
        }
        return points;
    }

    /** Drives the halo around the hexagon; one source for all three passes. */
    property real halo: 0.55
    SequentialAnimation on halo {
        running: Theme.motion
        loops: Animation.Infinite
        NumberAnimation { from: 0.45; to: 1.0; duration: 2100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.45; duration: 2100; easing.type: Easing.InOutSine }
    }

    /** The same breath, on the ring around every node. */
    property real nodeHalo: 0.4
    SequentialAnimation on nodeHalo {
        running: Theme.motion
        loops: Animation.Infinite
        NumberAnimation { from: 0.28; to: 0.62; duration: 1800; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.62; to: 0.28; duration: 1800; easing.type: Easing.InOutSine }
    }

    // Everything is authored at design size and scaled as one unit, so stroke
    // widths and dash patterns keep their proportions at any window size.
    Item {
        id: canvas
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: Math.min(root.width / root.designWidth, root.height / root.designHeight)

        // ---- Hub glow ----------------------------------------------------
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.hexCx
                    centerY: root.hexCy
                    centerRadius: 147
                    focalX: root.hexCx
                    focalY: root.hexCy
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.sky, 0.22) }
                    GradientStop { position: 0.55; color: Theme.alpha(Theme.indigo, 0.1) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.indigo, 0) }
                }
                PathAngleArc {
                    centerX: root.hexCx
                    centerY: root.hexCy
                    radiusX: 147
                    radiusY: 147
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        // ---- Orbit rings -------------------------------------------------
        Repeater {
            model: [
                { ringRadius: 76, dash: [3, 12], period: 26000, direction: 1 },
                { ringRadius: 92, dash: [2, 16], period: 40000, direction: -1 }
            ]

            delegate: Shape {
                id: ring
                required property var modelData

                width: modelData.ringRadius * 2
                height: modelData.ringRadius * 2
                x: root.hexCx - modelData.ringRadius
                y: root.hexCy - modelData.ringRadius
                transformOrigin: Item.Center
                antialiasing: true

                RotationAnimation on rotation {
                    running: Theme.motion
                    loops: Animation.Infinite
                    from: 0
                    to: 360 * ring.modelData.direction
                    duration: ring.modelData.period
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.alpha(Theme.blue, 0.3)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: ring.modelData.dash
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.modelData.ringRadius
                        centerY: ring.modelData.ringRadius
                        radiusX: ring.modelData.ringRadius
                        radiusY: ring.modelData.ringRadius
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }
        }

        // ---- Flow lanes --------------------------------------------------
        Repeater {
            model: root.lanes

            delegate: Item {
                id: lane
                required property var modelData
                anchors.fill: parent

                readonly property color tone: root.toneFor(modelData.tone)
                readonly property bool market: modelData.market
                /** Dash lengths are multiples of the pen width, unlike SVG's absolute units. */
                readonly property real penWidth: market ? 2.4 : 1.9
                readonly property real dashLit: 12 / penWidth
                readonly property real dashGap: 300 / penWidth - dashLit
                /**
                 * How far the dash pattern travels per cycle, in pixels, matching
                 * `laneFlow` in AuthBrandPanel.tsx. Stated separately from the
                 * pattern because the two are only equal by coincidence here —
                 * see the waves below, where they are not.
                 */
                readonly property real dashTravel: 300 / penWidth

                Shape {
                    anchors.fill: parent
                    antialiasing: true

                    // The lane's resting track, always visible. A power lane is
                    // dashed: what it carries is a share of somebody's work, not
                    // a delivery down a wire.
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.alpha(lane.tone, lane.market ? 0.38 : 0.3)
                        strokeWidth: lane.market ? 2.2 : 1.7
                        strokeStyle: lane.market ? ShapePath.SolidLine : ShapePath.DashLine
                        dashPattern: [4 / 1.7, 6 / 1.7]
                        capStyle: ShapePath.RoundCap
                        startX: lane.modelData.x0
                        startY: lane.modelData.y0
                        PathCubic {
                            control1X: lane.modelData.c1x; control1Y: lane.modelData.c1y
                            control2X: lane.modelData.c2x; control2Y: lane.modelData.c2y
                            x: lane.modelData.x1; y: lane.modelData.y1
                        }
                    }

                    // A bright segment sweeping along it — traffic, not decoration.
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: lane.tone
                        strokeWidth: lane.penWidth
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [lane.dashLit, lane.dashGap]
                        capStyle: ShapePath.RoundCap
                        startX: lane.modelData.x0
                        startY: lane.modelData.y0
                        PathCubic {
                            control1X: lane.modelData.c1x; control1Y: lane.modelData.c1y
                            control2X: lane.modelData.c2x; control2Y: lane.modelData.c2y
                            x: lane.modelData.x1; y: lane.modelData.y1
                        }

                        // Counts down rather than up: a falling offset walks the
                        // dash forward along the path, the way SVG does it.
                        NumberAnimation on dashOffset {
                            running: Theme.motion
                            loops: Animation.Infinite
                            from: lane.dashTravel
                            to: 0
                            duration: 3400
                        }
                    }

                    // Where the lane arrives.
                    ShapePath {
                        strokeWidth: -1
                        fillColor: lane.tone
                        PathPolyline {
                            path: root.arrowPoints(lane.modelData.x1, lane.modelData.y1,
                                                   lane.modelData.arrow, lane.market ? 7 : 6)
                        }
                    }
                }

                // What travels the lane: an artifact across the market, a spark
                // of work and direction from a principal into its agent.
                PathInterpolator {
                    id: courier
                    path: Path {
                        startX: lane.modelData.x0
                        startY: lane.modelData.y0
                        PathCubic {
                            control1X: lane.modelData.c1x; control1Y: lane.modelData.c1y
                            control2X: lane.modelData.c2x; control2Y: lane.modelData.c2y
                            x: lane.modelData.x1; y: lane.modelData.y1
                        }
                    }

                    NumberAnimation on progress {
                        id: travel
                        running: false
                        loops: Animation.Infinite
                        from: 0
                        to: 1
                        duration: lane.modelData.dur
                    }
                }

                // Staggered start, so the ten packets never set off together.
                Timer {
                    interval: lane.modelData.begin
                    running: Theme.motion
                    onTriggered: travel.start()
                }

                Item {
                    id: packet
                    readonly property real size: lane.market ? 14 : 11
                    x: courier.x
                    y: courier.y
                    visible: Theme.motion
                    // Fades in as it leaves and out as it arrives.
                    opacity: Math.min(1, Math.min(courier.progress, 1 - courier.progress) * 8)

                    Rectangle {
                        anchors.centerIn: parent
                        width: packet.size * 1.24
                        height: width
                        radius: width / 2
                        color: Theme.alpha(Theme.base, 0.96)
                    }

                    Glyph {
                        anchors.centerIn: parent
                        size: packet.size
                        name: lane.market ? "cube" : "bolt"
                        tone: lane.tone
                        thickness: lane.market ? 0.95 : 0.8
                    }
                }
            }
        }

        // ---- Platform hexagon --------------------------------------------
        // Breathing halo: three passes instead of a blur filter, which keeps
        // this on the same code path as everything else here.
        Repeater {
            model: [
                { pen: 16, tint: 0.07 },
                { pen: 10, tint: 0.12 },
                { pen: 5, tint: 0.2 }
            ]

            delegate: Shape {
                id: glow
                required property var modelData
                anchors.fill: parent
                antialiasing: true
                opacity: root.halo

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.alpha(Theme.sky, glow.modelData.tint)
                    strokeWidth: glow.modelData.pen
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: root.hexEdge }
                }
            }
        }

        // Gradient edge: a filled hexagon with a darker one laid over it. Qt
        // Quick strokes a single colour, so the gradient has to be a fill.
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: root.hexCx - root.hexHw; y1: root.hexCy - root.hexHh
                    x2: root.hexCx + root.hexHw; y2: root.hexCy + root.hexHh
                    GradientStop { position: 0.0; color: Theme.cyan }
                    GradientStop { position: 0.5; color: Theme.blue }
                    GradientStop { position: 1.0; color: Theme.violet }
                }
                PathPolyline { path: root.hexEdge }
            }
        }

        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeWidth: -1
                /*
                  Dark in the middle, and that is what makes the mark visible.

                  The brand blue is #007fff and `Theme.blue` is #60a5fa — the
                  mark is the *darker* of the two. Filling the face at 0.55 of
                  it therefore did not fade the mark, it put the mark behind a
                  lighter slab, where it read as a hole rather than as a logo.
                  So the face is held down — but to `baseHigh`, not to `base`.
                  Filling it with near-black was the other mistake: at #030712
                  the hexagon stopped being a surface and became a hole cut in
                  the page, which on a navy backdrop reads as a smudge rather
                  than as a device. #0f1729 is the colour the ambient background
                  already peaks at in the middle of the window, so the core
                  belongs to the same family as everything around it, and the
                  alphas are loose enough that the cyan-blue-violet hexagon
                  underneath still tints it.
                */
                fillGradient: RadialGradient {
                    centerX: root.hexCx; centerY: root.hexCy; centerRadius: 88
                    focalX: root.hexCx; focalY: root.hexCy
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.baseHigh, 0.72) }
                    GradientStop { position: 0.62; color: Theme.alpha(Theme.baseHigh, 0.80) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.baseHigh, 0.88) }
                }
                PathPolyline { path: root.hexFace }
            }
        }

        // A light running the perimeter — the platform is never idle.
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                id: trace
                readonly property real penWidth: 2.4
                readonly property real dashLit: 50 / penWidth
                readonly property real dashGap: 560 / penWidth - dashLit
                /** One lap of the perimeter per cycle — `hexTrace` on the web. */
                readonly property real dashTravel: 560 / penWidth

                fillColor: "transparent"
                strokeColor: Theme.headingFrom
                strokeWidth: penWidth
                strokeStyle: ShapePath.DashLine
                dashPattern: [dashLit, dashGap]
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: root.hexTracePath }

                NumberAnimation on dashOffset {
                    running: Theme.motion
                    loops: Animation.Infinite
                    from: trace.dashTravel
                    to: 0
                    duration: 5000
                }
            }
        }

        /*
          A bloom under the mark.

          The mark is the brand blue, #007fff, which is darker than every accent
          around it — the node icons are Theme.cyan at #22d3ee. On a dark core it
          reads, but it reads as the dimmest thing in a diagram it is supposed to
          be the centre of. This lifts the few pixels behind it rather than
          touching the artwork, so the mark keeps its colour and stops sitting in
          a hole.
        */
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.hexCx; centerY: root.hexCy - 11; centerRadius: 34
                    focalX: root.hexCx; focalY: root.hexCy - 11
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.sky, 0.30) }
                    GradientStop { position: 0.55; color: Theme.alpha(Theme.blue, 0.12) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.blue, 0.0) }
                }
                PathPolyline { path: root.hexFace }
            }
        }

        Image {
            source: "qrc:/simorg/branding/simorg-logo.svg"
            width: 46
            height: 46
            x: root.hexCx - width / 2
            y: root.hexCy - 34
            sourceSize: Qt.size(138, 138)
            smooth: true
            mipmap: true
        }

        Text {
            text: "SIMORG"
            x: root.hexCx - width / 2
            y: root.hexCy + 22
            color: Theme.headingTo
            font.pixelSize: 13
            font.weight: Font.Black
            font.letterSpacing: 1.5
        }

        // ---- The parties -------------------------------------------------
        Repeater {
            model: root.nodes

            delegate: Item {
                id: party
                required property var modelData
                anchors.fill: parent

                readonly property color tone: root.toneFor(modelData.tone)
                readonly property bool agent: modelData.r > 22

                // The breathing ring, outside the node's own edge.
                Rectangle {
                    width: (party.modelData.r + 5) * 2
                    height: width
                    radius: width / 2
                    x: party.modelData.x - width / 2
                    y: party.modelData.y - width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: party.tone
                    opacity: root.nodeHalo
                }

                Rectangle {
                    width: party.modelData.r * 2
                    height: width
                    radius: width / 2
                    x: party.modelData.x - width / 2
                    y: party.modelData.y - width / 2
                    color: Theme.alpha(Theme.base, 0.94)
                    border.width: party.agent ? 1.9 : 1.3
                    border.color: Theme.alpha(party.tone, party.agent ? 0.9 : 0.62)
                }

                Glyph {
                    x: party.modelData.x - size / 2
                    y: party.modelData.y - size / 2
                    size: party.agent ? 25 : 20
                    name: party.modelData.glyph
                    tone: party.tone
                    thickness: party.agent ? 1.55 : 1.3
                }

                Text {
                    id: partyLabel
                    text: party.modelData.label
                    color: party.tone
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1

                    x: {
                        const place = party.modelData.place;
                        if (place === "left")
                            return party.modelData.x - party.modelData.r - 8 - width;
                        if (place === "right")
                            return party.modelData.x + party.modelData.r + 8;
                        return party.modelData.x - width / 2;
                    }
                    y: {
                        const place = party.modelData.place;
                        if (place === "above")
                            return party.modelData.y - party.modelData.r - 6 - height;
                        if (place === "below")
                            return party.modelData.y + party.modelData.r + 6;
                        return party.modelData.y - height / 2;
                    }
                }
            }
        }

        // ---- What the two streams carry ----------------------------------
        Text {
            id: capabilityLabel
            text: "CAPABILITY"
            x: 104 - width
            y: root.hexCy - height / 2
            color: Theme.violet
            font.pixelSize: 10
            font.weight: Font.Black
            font.letterSpacing: 1.6
        }

        Text {
            text: "INTENT"
            x: 236
            y: root.hexCy - height / 2
            color: Theme.cyan
            font.pixelSize: 10
            font.weight: Font.Black
            font.letterSpacing: 1.6
        }

        // ---- Waves -------------------------------------------------------
        Repeater {
            model: [
                { yBase: 598, amplitude: 7, phase: 0.0, tone: Theme.blue, tint: 0.45, period: 13000 },
                { yBase: 606, amplitude: 5, phase: 0.9, tone: Theme.cyan, tint: 0.36, period: 16000 },
                { yBase: 612, amplitude: 4, phase: 1.8, tone: Theme.violet, tint: 0.3, period: 19000 }
            ]

            delegate: Shape {
                id: waveShape
                required property var modelData
                anchors.fill: parent
                antialiasing: true

                ShapePath {
                    id: wave
                    readonly property real penWidth: 2.2
                    readonly property real dashLit: 0.5 / penWidth
                    readonly property real dashGap: 9.5 / penWidth
                    /**
                     * 240px per cycle, as `waveDrift` does on the web — twenty-four
                     * whole dash periods, so the loop is seamless and the dots
                     * actually travel. Moving one period instead would be a
                     * technically correct loop at 0.8px/s, which reads as static.
                     */
                    readonly property real dashTravel: 240 / penWidth

                    fillColor: "transparent"
                    strokeColor: Theme.alpha(waveShape.modelData.tone, waveShape.modelData.tint)
                    strokeWidth: penWidth
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [dashLit, dashGap]
                    capStyle: ShapePath.RoundCap
                    PathPolyline {
                        path: root.wavePoints(waveShape.modelData.yBase,
                                              waveShape.modelData.amplitude,
                                              waveShape.modelData.phase)
                    }

                    NumberAnimation on dashOffset {
                        running: Theme.motion
                        loops: Animation.Infinite
                        from: wave.dashTravel
                        to: 0
                        duration: waveShape.modelData.period
                    }
                }
            }
        }
    }
}
