// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes
import Simorg

/**
 * This computer powering two agents: the picture on the welcome after a first setup.
 *
 * ## The story it tells
 *
 * The whole message of {@link MachineWelcome} in one drawing. In the middle stands
 * the machine exactly as it stands on the Logos — the seven-cell flower in an
 * amber frame, wearing this computer's own operating-system mark. Either side of
 * it is an agent, waving. When the welcome opens, a line of power runs out from
 * the machine to each of them, and from then on light travels along both lines
 * toward the agents; each time it arrives, the agent's eyes light up.
 *
 * ## Drawn in the Logos's words
 *
 * Amber is the Logos's colour of power, and a power line there is exactly this: thicker than a connection, dim while
 * nothing flows, and carrying bands of light toward the agent while its machine
 * is up. The two agents are the pair from the Logos's own welcome
 * (`FirstBatchWelcome.tsx`, `LaunchTogetherArt`), drawn to the same measurements:
 * the smiling head, one arm waving about the shoulder rather than the middle of
 * the arm, the waves half a beat apart so they are waving rather than marching.
 * Here the other arm reaches in and holds the end of the line.
 *
 * ## Units
 *
 * Laid out on a 260 × 100 board and scaled to the width it is given, the way the
 * web draws into a `viewBox`. The board is cropped close round the drawing —
 * a band of sky with a few stars, the ground, and nothing else — because the
 * card it sits in has to fit a short window, and height spent on empty sky is
 * height the picture does not get. Coordinates are multiplied out rather than scaled
 * by a transform, so strokes and curves are tessellated at the size they are
 * seen and stay crisp; only the right-hand agent is mirrored by a transform, and
 * a mirror loses nothing.
 *
 * ## Motion
 *
 * Everything moves only while {@link running}, and nothing moves when
 * `Theme.motion` is off: then the lines are already drawn, the eyes already lit
 * and the arms at rest, and the picture reads perfectly standing still.
 */
Item {
    id: root

    /** True while the picture is on screen; nothing animates otherwise. */
    property bool running: true

    /** Scene units to pixels: the board is 260 wide and 100 high. */
    readonly property real u: width / 260
    /** Whether anything moves at all. */
    readonly property bool live: root.running && Theme.motion

    implicitWidth: 260
    implicitHeight: width * 100 / 260

    /** How far out the two lines have run from the machine, 0 to 1. */
    property real reach: Theme.motion ? 0 : 1
    /** Where the current is along the lines, 0 to 1, looping. */
    property real phase: 0
    /** A flash in the agents' eyes, 1 the instant light arrives and fading until the next. */
    property real charge: 0
    /** The machine's own light, breathing while it is up. */
    property real breath: 0.6
    property real waveLeft: 0
    property real waveRight: 0
    property real sway: 0

    /** An SVG path on the board, in pixels. Absolute commands only, so every number is a coordinate. */
    function svg(d) {
        const unit = root.u;
        return d.replace(/-?\d+(\.\d+)?/g, function (n) { return (parseFloat(n) * unit).toFixed(2); });
    }

    /** 0 to 1 and back, soft at both ends of a line: bands fade in leaving the machine and out at the hand. */
    function bandOpacity(p) {
        return Math.min(1, p * 6) * Math.min(1, (1 - p) * 7);
    }

    // ---- The intro: the lines run out, and then the current starts -----------
    SequentialAnimation {
        id: intro
        PauseAnimation { duration: 320 }
        NumberAnimation {
            target: root
            property: "reach"
            from: 0
            to: 1
            duration: 760
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
        ScriptAction { script: current.start() }
    }

    /*
      The current and the flash, in one loop so they can never drift apart.

      Two bands per line, half a lap apart, so one arrives every 900ms — and the
      flash peaks exactly then, because the flash's lap is the arrival interval.
      A band arrives at the instant its position wraps, which for the first band
      is the start of every lap: the very first flash is the moment the lines
      finish running out, which reads as the agents being switched on.
    */
    ParallelAnimation {
        id: current
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "phase"
            from: 0
            to: 1
            duration: 1800
        }
        SequentialAnimation {
            NumberAnimation {
                target: root; property: "charge"; from: 1; to: 0
                duration: 900; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root; property: "charge"; from: 1; to: 0
                duration: 900; easing.type: Easing.OutCubic
            }
        }
    }

    onLiveChanged: root.restart()
    Component.onCompleted: root.restart()

    /** From the top: the lines run out again each time the picture is shown. */
    function restart() {
        intro.stop();
        current.stop();
        root.charge = 0;
        root.phase = 0;
        if (!root.live) {
            root.reach = 1;
            return;
        }
        root.reach = 0;
        intro.start();
    }

    SequentialAnimation on breath {
        running: root.live
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 1.0; duration: 2300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.35; duration: 2300; easing.type: Easing.InOutSine }
    }

    /*
      The wave, over 2.6 seconds: a rest at the bottom, further back than forward,
      and a hand that settles rather than swinging evenly — the Logos welcome's
      keyframes, as segments.
    */
    /*
      Handed the scene rather than reaching for `root`: an inline component has a
      scope of its own, and the ids of the file around it are not in it.
    */
    component Wave: SequentialAnimation {
        id: wave
        /** The scene whose arm this moves. */
        property QtObject scene
        /** Which of the two arms, by the scene's property name. */
        property string arm: "waveLeft"
        /** How long this arm waits before its first wave; the loop after it is the same for both. */
        property int lead: 0

        running: wave.scene !== null && wave.scene.live
        onStopped: if (wave.scene) wave.scene[wave.arm] = 0

        PauseAnimation { duration: wave.lead }
        SequentialAnimation {
            loops: Animation.Infinite
            PauseAnimation { duration: 208 }
            NumberAnimation { target: wave.scene; property: wave.arm; to: -18; duration: 572; easing.type: Easing.InOutSine }
            NumberAnimation { target: wave.scene; property: wave.arm; to: 8; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { target: wave.scene; property: wave.arm; to: -12; duration: 598; easing.type: Easing.InOutSine }
            NumberAnimation { target: wave.scene; property: wave.arm; to: 0; duration: 572; easing.type: Easing.InOutSine }
        }
    }

    Wave { scene: root; arm: "waveLeft" }
    // Half a beat behind, so the two are waving rather than marching.
    Wave { scene: root; arm: "waveRight"; lead: 450 }

    SequentialAnimation on sway {
        running: root.live
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: -2.5; duration: 2000; easing.type: Easing.InOutSine }
        NumberAnimation { from: -2.5; to: 0; duration: 2000; easing.type: Easing.InOutSine }
    }

    // ---- Stars ---------------------------------------------------------------
    Repeater {
        model: [
            { x: 20, y: 10, r: 1.6, delay: 0 },
            { x: 48, y: 3, r: 1.2, delay: 700 },
            { x: 86, y: 14, r: 1.3, delay: 1400 },
            { x: 176, y: 8, r: 1.2, delay: 400 },
            { x: 214, y: 3, r: 1.6, delay: 1800 },
            { x: 242, y: 18, r: 1.2, delay: 1100 },
            { x: 6, y: 30, r: 1.2, delay: 2100 },
            { x: 254, y: 36, r: 1.4, delay: 900 }
        ]

        delegate: Rectangle {
            required property var modelData
            width: modelData.r * 2 * root.u
            height: width
            radius: width / 2
            x: modelData.x * root.u - width / 2
            y: modelData.y * root.u - height / 2
            color: Theme.sky
            opacity: root.live ? 0.2 : 0.55

            SequentialAnimation on opacity {
                running: root.live
                loops: Animation.Infinite
                PauseAnimation { duration: modelData.delay }
                NumberAnimation { from: 0.2; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0.2; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
    }

    // ---- The ground, under everybody -----------------------------------------
    Rectangle {
        x: 14 * root.u
        y: 88 * root.u - height / 2
        width: 232 * root.u
        height: Math.max(1, 1.4 * root.u)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.alpha(Theme.sky, 0) }
            GradientStop { position: 0.12; color: Theme.alpha(Theme.sky, 0.32) }
            GradientStop { position: 0.88; color: Theme.alpha(Theme.sky, 0.32) }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.sky, 0) }
        }
    }

    // ---- The two lines of power, run out from the machine --------------------
    Repeater {
        // Each line from the machine's middle to the hand holding its end.
        model: [{ from: 130, to: 61 }, { from: 130, to: 199 }]

        delegate: Item {
            id: line
            required property var modelData
            readonly property real length: Math.abs(modelData.to - modelData.from) * root.reach
            readonly property real towards: modelData.to < modelData.from ? -1 : 1
            readonly property real lineY: 66.5

            anchors.fill: parent

            // The wide, faint glow a power line carries on the Logos.
            Rectangle {
                width: line.length * root.u
                height: 6.5 * root.u
                radius: height / 2
                x: (line.towards < 0 ? line.modelData.from - line.length : line.modelData.from) * root.u
                y: line.lineY * root.u - height / 2
                color: Theme.alpha(Theme.amber, 0.12)
            }

            // The core: dim while it runs out, lit once the current flows.
            Rectangle {
                width: line.length * root.u
                height: 2.2 * root.u
                radius: height / 2
                x: (line.towards < 0 ? line.modelData.from - line.length : line.modelData.from) * root.u
                y: line.lineY * root.u - height / 2
                color: Theme.alpha(Theme.amber, 0.42 + 0.3 * root.reach)
            }

            // The current: two bands half a lap apart, travelling toward the agent.
            Repeater {
                model: 2

                delegate: Rectangle {
                    required property int index
                    readonly property real progress: (root.phase + index * 0.5) % 1
                    // From just outside the machine's frame to the hand.
                    readonly property real startX: line.modelData.from + line.towards * 26
                    readonly property real centreX: startX + (line.modelData.to - startX) * progress

                    visible: root.live && root.reach >= 1
                    width: 12 * root.u
                    height: 2.4 * root.u
                    radius: height / 2
                    x: centreX * root.u - width / 2
                    y: line.lineY * root.u - height / 2
                    opacity: root.bandOpacity(progress)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.alpha(Theme.amber, 0) }
                        GradientStop { position: 0.5; color: Theme.mix(Theme.amber, Theme.textPrimary, 0.45) }
                        GradientStop { position: 1.0; color: Theme.alpha(Theme.amber, 0) }
                    }
                }
            }
        }
    }

    // ---- The machine, as it stands on the Logos --------------------------------
    Avatar {
        id: machine
        size: 60 * root.u
        x: 130 * root.u - size / 2
        y: 52 * root.u - size / 2
        accent: Theme.amber
        initials: ""
        glow: root.live ? root.breath : 0.6
    }

    OsLogo {
        anchors.centerIn: machine
        osName: Hub.machineSummary.osName || ""
        size: 22 * root.u
        tone: Theme.textPrimary
    }

    // ---- The two agents ----------------------------------------------------------
    Repeater {
        model: [
            { left: 20, tone: Theme.sky, mirrored: false },
            { left: 192, tone: Theme.violet, mirrored: true }
        ]

        /*
          One agent, on its own 48 × 64 patch of the board, drawn facing right:
          the waving arm on the outside, and the other reaching in to the line.
          The one on the right is the same drawing in a mirror.
        */
        delegate: Item {
            id: agent
            required property var modelData
            required property int index
            readonly property color tone: modelData.tone
            readonly property real wave: index === 0 ? root.waveLeft : root.waveRight

            x: modelData.left * root.u
            y: (26 + root.sway) * root.u
            width: 48 * root.u
            height: 64 * root.u
            transform: Scale {
                origin.x: agent.width / 2
                xScale: agent.modelData.mirrored ? -1 : 1
            }

            Shape {
                anchors.fill: parent
                antialiasing: true

                ShapePath {
                    strokeColor: agent.tone
                    strokeWidth: 2.4 * root.u
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    // Antenna, ears, smile, body, legs, and the arm holding the line.
                    PathSvg {
                        path: root.svg("M28 10 L28 16 M13 24 L13 30 M43 24 L43 30 "
                                       + "M22 31 Q28 35.5 34 31 M28 38 L28 50 "
                                       + "M28 50 L21 62 M28 50 L35 62 M30 43 L40 41")
                    }
                }
            }

            // The head, a rounded box in the same line.
            Rectangle {
                x: 15 * root.u
                y: 16 * root.u
                width: 26 * root.u
                height: 22 * root.u
                radius: 7 * root.u
                color: "transparent"
                border.width: 2.4 * root.u
                border.color: agent.tone
            }

            // The antenna's tip, and the hand at the end of the line.
            Repeater {
                model: [{ x: 28, y: 7, r: 2.6 }, { x: 41, y: 40.5, r: 2.2 }]

                delegate: Rectangle {
                    required property var modelData
                    width: modelData.r * 2 * root.u
                    height: width
                    radius: width / 2
                    x: modelData.x * root.u - width / 2
                    y: modelData.y * root.u - height / 2
                    color: agent.tone
                }
            }

            /*
              The eyes: dim until the line reaches them, and flushed with the
              line's own amber for an instant each time the current arrives —
              power, in the colour the Logos gives it, in either theme.
            */
            Repeater {
                model: [22, 34]

                delegate: Rectangle {
                    required property var modelData
                    width: 4.2 * root.u * (1 + 0.22 * root.charge)
                    height: width
                    radius: width / 2
                    x: modelData * root.u - width / 2
                    y: 25 * root.u - height / 2
                    color: Theme.mix(agent.tone, Theme.amber, 0.85 * root.charge)
                    opacity: 0.4 + 0.6 * root.reach
                }
            }

            // The waving arm, turned about the shoulder.
            Item {
                anchors.fill: parent
                transform: Rotation {
                    origin.x: 26 * root.u
                    origin.y: 44 * root.u
                    angle: agent.wave
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true

                    ShapePath {
                        strokeColor: agent.tone
                        strokeWidth: 2.4 * root.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: root.svg("M26 44 Q12 42 6 32") }
                    }
                }

                Rectangle {
                    width: 5.2 * root.u
                    height: width
                    radius: width / 2
                    x: 6 * root.u - width / 2
                    y: 31 * root.u - height / 2
                    color: agent.tone
                }
            }
        }
    }
}
