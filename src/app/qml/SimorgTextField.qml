// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic

/**
 * The app's text input.
 *
 * A floating label that rises out of the field on focus, a leading glyph, an
 * optional trailing action, and a focus ring that grows from the accent colour.
 * Matches `authFieldSx` in the web console — dark glass, visible borders, and a
 * label that stays legible against the gradient behind it.
 */
Item {
    id: root

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias inputMethodHints: input.inputMethodHints
    property alias readOnly: input.readOnly
    /**
     * Hard cap on what can be typed, in characters.
     *
     * A cap rather than validation after the fact, because the two fields that
     * want one — a six-digit authenticator code, a recovery code — have exactly
     * one correct length, and a field that silently stops accepting characters
     * is a clearer statement of that than an error appearing underneath.
     */
    property alias maximumLength: input.maximumLength
    /**
     * Whether somebody is typing in it right now.
     *
     * Exposed because a form that both binds `text` to a stored value *and*
     * reports every change back has to tell the two apart: a value arriving
     * from outside must update the box, and the box updating must not be
     * mistaken for somebody editing it.
     */
    readonly property alias editing: input.activeFocus

    property string label: ""
    property string glyph: ""
    property string errorText: ""
    property bool hasError: errorText.length > 0
    /** Icon name for the trailing button, e.g. "eye". Empty hides it. */
    property string actionGlyph: ""
    property string actionTooltip: ""
    /**
     * Escape puts the field back rather than reaching whatever is behind it — a
     * name edited where it is read (EditableName.qml). Off everywhere else, where
     * Escape belongs to the dialog or window the field sits in.
     */
    property bool cancelOnEscape: false

    signal accepted()
    signal actionTriggered()
    /** Escape, in a field with `cancelOnEscape`. */
    signal escaped()

    implicitWidth: 320
    implicitHeight: 56 + (hasError ? errorLabel.implicitHeight + 6 : 0)

    function forceInputFocus() {
        input.forceActiveFocus();
    }

    /**
     * Focus with everything already selected, so the next keystroke replaces it.
     *
     * What a refused one-time code needs. The characters stay on screen to be
     * read and compared against the phone, and typing a fresh code over the top
     * is still one action rather than six presses of Backspace first.
     */
    function selectAllText() {
        input.forceActiveFocus();
        input.selectAll();
    }

    readonly property bool floating: input.activeFocus || input.text.length > 0
    readonly property color activeTone: hasError ? Theme.danger : Theme.blue

    Rectangle {
        id: field
        width: parent.width
        height: 56
        radius: Theme.radiusBase
        color: input.activeFocus ? Theme.alpha(Theme.base, 0.68) : Theme.alpha(Theme.base, 0.5)
        border.width: input.activeFocus || root.hasError ? 2 : 1
        border.color: root.hasError
                      ? Theme.alpha(Theme.danger, 0.85)
                      : input.activeFocus
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

        // Focus halo — a soft ring outside the border, so the field lights up
        // without the layout shifting by a pixel.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: parent.radius + 4
            color: "transparent"
            border.width: 2
            border.color: Theme.alpha(root.activeTone, 0.28)
            opacity: input.activeFocus ? 1 : 0
            scale: input.activeFocus ? 1 : 0.97

            Behavior on opacity {
                NumberAnimation { duration: Theme.duration(Theme.durBase) }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.duration(Theme.durBase)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }
        }

        Glyph {
            id: leading
            name: root.glyph
            size: 19
            thickness: 1.55
            visible: root.glyph.length > 0
            tone: input.activeFocus ? root.activeTone : Theme.textMuted
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter

            Behavior on tone {
                ColorAnimation { duration: Theme.duration(Theme.durBase) }
            }
        }

        // The label starts as placeholder text and rises into the border on
        // focus, so the field never loses its name once someone types in it.
        Text {
            id: labelText
            text: root.label
            color: root.hasError
                   ? Theme.danger
                   : input.activeFocus ? Theme.sky : Theme.textMuted
            font.pixelSize: root.floating ? 11 : Theme.fontBody
            font.weight: root.floating ? Font.DemiBold : Font.Normal
            font.letterSpacing: root.floating ? 0.4 : 0
            x: leading.visible ? leading.x + leading.width + 11 : 16
            y: root.floating ? 9 : (field.height - height) / 2

            Behavior on y {
                NumberAnimation {
                    duration: Theme.duration(Theme.durBase)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }
            Behavior on font.pixelSize {
                NumberAnimation { duration: Theme.duration(Theme.durBase) }
            }
            Behavior on color {
                ColorAnimation { duration: Theme.duration(Theme.durBase) }
            }
        }

        TextField {
            id: input

            anchors.left: labelText.left
            anchors.right: action.visible ? action.left : parent.right
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            height: 30

            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0

            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.family: Theme.fontFamily
            selectionColor: Theme.alpha(Theme.blue, 0.45)
            selectedTextColor: Theme.textPrimary
            // The floating label above is the field's name; a placeholder would
            // repeat it and collide with it.
            placeholderText: ""
            background: null
            opacity: root.floating ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.duration(Theme.durFast) }
            }

            onAccepted: root.accepted()
            Keys.onEscapePressed: (event) => {
                event.accepted = root.cancelOnEscape;
                if (root.cancelOnEscape)
                    root.escaped();
            }

            cursorDelegate: Rectangle {
                width: 2
                radius: 1
                color: root.activeTone
                visible: input.activeFocus

                SequentialAnimation on opacity {
                    running: input.activeFocus
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 480; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 480; easing.type: Easing.InOutQuad }
                }
            }
        }

        // Trailing action — the password reveal toggle, today.
        Item {
            id: action
            visible: root.actionGlyph.length > 0
            width: 40
            height: parent.height
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Glyph {
                anchors.centerIn: parent
                name: root.actionGlyph
                size: 19
                thickness: 1.55
                tone: actionHover.hovered ? Theme.sky : Theme.textMuted

                Behavior on tone {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }
            }

            HoverHandler {
                id: actionHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.actionTriggered()
            }
        }

        // Clicking anywhere in the field focuses the input, not just the 30px
        // strip the text sits on.
        TapHandler {
            onTapped: input.forceActiveFocus()
        }
    }

    Text {
        id: errorLabel
        anchors.top: field.bottom
        anchors.topMargin: 6
        anchors.left: field.left
        anchors.leftMargin: 4
        width: field.width - 8
        text: root.errorText
        visible: root.hasError
        color: Theme.danger
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.WordWrap
    }
}
