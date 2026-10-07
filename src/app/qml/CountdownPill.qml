// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * How long is left, as a clock face rather than a sentence.
 *
 * ## Why a wait needs a number on it
 *
 * Two minutes of a spinner reads as a hang. That is not a figure of speech: a
 * person who cannot tell "working" from "stuck" reaches for the force quit, and
 * a force quit during a shutdown is the one action that leaves every container
 * running — the exact outcome the whole graceful-quit sequence exists to
 * prevent.
 *
 * A number going down fixes it, and it fixes it *because it moves*. Somebody who
 * can see 1:47 become 1:46 knows the app is alive, knows roughly how long they
 * are committing to, and can make an informed decision about the *Force Quit!*
 * link beside it instead of a panicked one about the Dock.
 *
 * ## Minutes and seconds, and never a bare count
 *
 * "1:47" rather than "107 seconds". Nobody converts a large number of seconds
 * into a feeling about time without doing arithmetic, and this is read at a
 * glance by somebody who wants to close their laptop.
 *
 * ## It calms down as it runs out, rather than sounding an alarm
 *
 * The ring drains and the tone shifts once, near the end. It deliberately does
 * **not** turn red or flash: nothing is going wrong. The budget running low
 * means the agents are taking their full allowance, which is the system working
 * as designed, and an alarm about correct behaviour teaches people to ignore
 * alarms.
 */
RowLayout {
    id: root

    /** Whole seconds remaining. Zero hides the pill. */
    property int secondsLeft: 0
    /** The whole budget, so the ring has a scale to drain against. */
    property int totalSeconds: 0

    /**
     * Below this, the clock is always in its warning tone.
     *
     * A floor as well as a fraction, because a fraction alone gets short budgets
     * wrong. At a fifth of a ten-minute allowance the warning arrives with two
     * minutes to spare, which is fair; at a fifth of a fifteen-second one it
     * arrives with three seconds left, which is too late to be worth showing.
     *
     * Fifteen seconds is roughly the shortest warning somebody can actually act
     * on — long enough to read it, look at *Force Quit!*, and decide.
     */
    readonly property int lowWaterSeconds: 15

    /**
     * The last stretch, where the tone shifts.
     *
     * Whichever of the two rules fires first. On a long budget that is the
     * fraction; on a short one it is the floor, which means a machine configured
     * with a fifteen-second grace shows the warning tone throughout — and that is
     * honest rather than a bug: with fifteen seconds in total you are always
     * nearly out of time.
     */
    readonly property bool runningLow:
        root.totalSeconds > 0
        && (root.secondsLeft <= root.totalSeconds * 0.2
            || root.secondsLeft <= root.lowWaterSeconds)

    readonly property color tone: root.runningLow ? Theme.amber : Theme.cyan

    /** `1:47`, or `0:09`. Seconds are always two digits so the width holds. */
    readonly property string clock: {
        const total = Math.max(0, root.secondsLeft)
        const minutes = Math.floor(total / 60)
        const seconds = total % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    visible: root.secondsLeft > 0
    spacing: 7

    /**
     * A ring that drains, beside the digits.
     *
     * The digits say exactly how long; the ring says *roughly* how much of the
     * allowance is gone, which is the thing somebody actually reads at a glance.
     * Neither alone does both jobs.
     */
    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 14
        implicitHeight: 14

        Canvas {
            id: ring
            anchors.fill: parent

            /*
              Repainted on every change rather than animated.

              The value moves once a second and the arc is fourteen pixels
              across; a `Behavior` between two positions that close together
              would spend its whole duration mid-tween and never settle, which
              looks like a ring that never quite lands on a value.
            */
            property real fraction: root.totalSeconds > 0
                                    ? Math.max(0, Math.min(1, root.secondsLeft / root.totalSeconds))
                                    : 0
            property color stroke: root.tone

            onFractionChanged: requestPaint()
            onStrokeChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()

                const half = width / 2
                const radius = half - 1.5

                // The track it drains against, so an almost-empty ring still
                // reads as a ring rather than as a stray mark.
                ctx.beginPath()
                ctx.arc(half, half, radius, 0, Math.PI * 2)
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.22)
                ctx.stroke()

                if (fraction <= 0)
                    return

                // Clockwise from twelve, which is the direction every clock a
                // person has ever read goes.
                ctx.beginPath()
                ctx.arc(half, half, radius, -Math.PI / 2,
                        -Math.PI / 2 + Math.PI * 2 * fraction)
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.strokeStyle = stroke
                ctx.stroke()
            }
        }
    }

    Text {
        id: clock

        Layout.alignment: Qt.AlignVCenter
        text: root.clock
        color: root.tone
        font.pixelSize: 11
        font.weight: Font.DemiBold

        /*
          Tabular figures, so the digits do not shuffle sideways every second.

          Proportional numerals make "1:11" narrower than "1:00", and a clock
          that jitters horizontally draws the eye to the movement rather than to
          the value — on a window whose entire job is to be read calmly.

          Assigned here rather than written as `font.features:` because that
          property arrived in Qt 6.6 and this application builds against 6.4 —
          the floor that decides which glibc the released Linux build needs, and
          so which machines it runs on. A declarative line naming a property an
          older Qt does not have is not a warning, it is a file that will not
          load: this pill is inside the shutdown window, so on 6.4 the *quitting
          sequence* was what disappeared. Guarded, an older Qt gets proportional
          digits and everything else works.
        */
        Component.onCompleted: {
            if (typeof clock.font.features === "object")
                clock.font.features = ({ "tnum": 1 });
        }
    }
}
