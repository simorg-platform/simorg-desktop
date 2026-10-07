// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * An inline message above a form.
 *
 * Takes no vertical space when there is nothing to say, and slides its own
 * height open when there is — the form below never jumps, it is pushed.
 */
Item {
    id: root

    property string text: ""
    property string tone: "error"   // "error" | "success" | "info"
    readonly property bool shown: text.length > 0

    readonly property color accent: tone === "success" ? Theme.emerald
                                  : tone === "info" ? Theme.sky
                                  : Theme.danger

    implicitWidth: 320
    implicitHeight: shown ? body.implicitHeight + 22 : 0
    clip: true

    // Announced to screen readers as it appears, the way `role="status"` does
    // on the web sign-in form.
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.text

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.duration(Theme.durBase)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    Rectangle {
        id: surface
        width: parent.width
        height: body.implicitHeight + 22
        radius: Theme.radiusBase
        color: Theme.alpha(root.accent, 0.1)
        border.width: 1
        border.color: Theme.alpha(root.accent, 0.4)

        opacity: root.shown ? 1 : 0
        y: root.shown ? 0 : -6

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }
        Behavior on y {
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }

        Glyph {
            id: icon
            name: root.tone === "success" ? "check" : "alert"
            size: 18
            thickness: 1.6
            tone: root.accent
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.top: parent.top
            anchors.topMargin: 12
        }

        Text {
            id: body
            anchors.left: icon.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: Theme.alpha(root.accent, 0.98)
            font.pixelSize: Theme.fontSmall
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.35
        }
    }
}
