// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic

/**
 * The ordinary button, and the one most actions should use.
 *
 * Outlined, squared off, filling faintly on hover. Anything that opens
 * something, navigates somewhere, or is one of several equal choices belongs
 * here; {@link PrimaryButton} is reserved for the single action that finishes
 * what somebody came to do.
 *
 * Sharp corners are the house style — see `Theme.radiusSmall` — because a screen that asks somebody to grant an agent
 * their filesystem should read as an instrument rather than as a toy.
 */
Button {
    id: control

    /** A glyph drawn before the text, by its name in Glyph.qml; none when empty. */
    property string glyph: ""
    /** Turns the glyph while something runs, so the wait reads as work under way. */
    property bool spinning: false

    implicitHeight: 36
    implicitWidth: Math.max(96, content.implicitWidth + 32)

    onSpinningChanged: if (!spinning) icon.rotation = 0
    font.pixelSize: Theme.fontBody
    font.weight: Font.DemiBold
    focusPolicy: Qt.StrongFocus

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.hovered ? Theme.alpha(Theme.ctaFrom, 0.16) : Theme.alpha(Theme.base, 0.35)
        border.width: control.visualFocus ? 2 : 1
        border.color: control.hovered || control.visualFocus
                      ? Theme.alpha(Theme.blue, 0.6)
                      : Theme.borderStrong

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 8

            Glyph {
                id: icon
                visible: control.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                name: control.glyph
                size: 15
                thickness: 1.7
                tone: label.color

                RotationAnimation on rotation {
                    running: control.spinning && Theme.motion
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font: control.font
                color: control.enabled ? Theme.alpha(Theme.textPrimary, 0.92) : Theme.textFaint
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
