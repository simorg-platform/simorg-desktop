// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic

/**
 * The brand call to action.
 *
 * One per screen, at most: the button that finishes what somebody came to do —
 * sign in, apply a setting, confirm a choice they have already made. Anything
 * that merely opens something else is a {@link GhostButton}.
 *
 * Blue-to-cyan, squared off, and **flat**. A pill with a coloured glow under it
 * reads as a floating capsule rather than as a control — and in a list of rows
 * it looks like an advertisement sitting on the page. The gradient is there
 * because it is the one place the brand colour does any work.
 *
 * Presses in on click, and swaps its label for a spinner while `busy` — the
 * button stays the same size throughout, so nothing under it moves when a
 * request starts.
 */
Button {
    id: control

    /** Shows the spinner and refuses clicks. */
    property bool busy: false

    implicitHeight: 40
    implicitWidth: Math.max(132, label.implicitWidth + 40)
    enabled: !busy
    font.pixelSize: Theme.fontBody
    font.weight: Font.Bold
    focusPolicy: Qt.StrongFocus

    scale: pressed ? 0.985 : 1
    Behavior on scale {
        NumberAnimation { duration: Theme.duration(Theme.durFast); easing.type: Easing.OutQuad }
    }

    background: Item {
        /*
          No glow, and no lift.

          A tinted rectangle offset below it would make the button appear to
          float above the page. On a sign-in screen that is a flourish; in a
          list of permission rows it is a coloured shadow under a capsule, and
          looks like something went wrong. A button is a surface you press, not
          an object hovering over one.
        */
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: Theme.radiusSmall

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: control.enabled
                           ? (control.hovered ? Theme.ctaFromHover : Theme.ctaFrom)
                           : Theme.alpha(Theme.textMuted, 0.18)
                }
                GradientStop {
                    position: 1.0
                    color: control.enabled
                           ? (control.hovered ? Theme.ctaToHover : Theme.ctaTo)
                           : Theme.alpha(Theme.textMuted, 0.18)
                }
            }
        }

        // Focus ring, for keyboard users only — a mouse click should not leave
        // a halo behind.
        Rectangle {
            anchors.fill: surface
            anchors.margins: -3
            radius: Theme.radiusSmall + 2
            color: "transparent"
            border.width: 2
            border.color: Theme.alpha(Theme.sky, 0.75)
            opacity: control.visualFocus ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.duration(Theme.durFast) }
            }
        }
    }

    contentItem: Item {
        Text {
            id: label
            anchors.centerIn: parent
            text: control.text
            font: control.font
            color: control.enabled ? Theme.textOnAccent : Theme.alpha(Theme.textPrimary, 0.42)
            opacity: control.busy ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: Theme.duration(Theme.durFast) }
            }
        }

        BusyRing {
            anchors.centerIn: parent
            size: 20
            running: control.busy
            opacity: control.busy ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.duration(Theme.durFast) }
            }
        }
    }
}
