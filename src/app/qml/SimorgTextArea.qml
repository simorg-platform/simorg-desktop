// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic

/**
 * The app's multi-line input, for prose rather than for a value.
 *
 * Separate from {@link SimorgTextField} rather than a mode of it, because the
 * two are different shapes: a field has a label that floats into its border and
 * one line to hold, and this has a fixed heading, a hint underneath and a box
 * somebody writes a page in. Folding them together would have meant a component
 * whose label moves in one mode and does not in the other.
 *
 * The hint is part of the component for a reason particular to what this is
 * used for. The one text area in the application holds a machine's README, and
 * the thing somebody needs to know about that box is *who reads it* — which is
 * not obvious, and is the difference between a line of notes and something an
 * agent can act on.
 */
Item {
    id: root

    property alias text: input.text
    property string label: ""
    property string hint: ""
    property string placeholder: ""
    property int rows: 6

    readonly property bool focused: input.activeFocus

    implicitWidth: 320
    implicitHeight: heading.implicitHeight
                    + 6
                    + box.height
                    + (hint.length > 0 ? hintText.implicitHeight + 6 : 0)

    Text {
        id: heading
        text: root.label
        color: input.activeFocus ? Theme.sky : Theme.textMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    Rectangle {
        id: box
        anchors.top: heading.bottom
        anchors.topMargin: 6
        width: parent.width
        // Whole lines, so the box never ends halfway through one.
        height: root.rows * 21 + 24
        radius: Theme.radiusBase
        color: input.activeFocus ? Theme.alpha(Theme.base, 0.68) : Theme.alpha(Theme.base, 0.5)
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus
                      ? Theme.alpha(Theme.blue, 0.9)
                      : hover.hovered
                        ? Theme.alpha(Theme.sky, 0.5)
                        : Theme.borderStrong

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }

        HoverHandler { id: hover }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true

            TextArea {
                id: input

                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.family: Theme.fontFamily
                selectionColor: Theme.alpha(Theme.blue, 0.45)
                selectedTextColor: Theme.textPrimary
                placeholderText: root.placeholder
                placeholderTextColor: Theme.textFaint
                wrapMode: TextEdit.Wrap
                background: null
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0
            }
        }
    }

    Text {
        id: hintText
        anchors.top: box.bottom
        anchors.topMargin: 6
        width: parent.width
        visible: root.hint.length > 0
        text: root.hint
        color: Theme.textFaint
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.WordWrap
        lineHeight: 1.45
    }
}
