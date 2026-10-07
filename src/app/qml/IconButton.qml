// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * A small square action — start, stop, restart, remove.
 *
 * Icon-only buttons are a readability risk, so every one of these carries a
 * tooltip and a hover tint strong enough that the target is obvious before the
 * click rather than after it. Destructive ones say so in colour.
 */
Item {
    id: root

    property string glyph: ""
    property string tooltip: ""
    property color tone: Theme.textBody
    property color hoverTone: Theme.sky
    property bool busy: false
    property int size: 30

    signal clicked()

    implicitWidth: size
    implicitHeight: size

    opacity: enabled ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: hover.hovered && root.enabled ? Theme.alpha(root.hoverTone, 0.13) : "transparent"
        border.width: 1
        border.color: hover.hovered && root.enabled
                      ? Theme.alpha(root.hoverTone, 0.36)
                      : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    Glyph {
        anchors.centerIn: parent
        visible: !root.busy
        name: root.glyph
        size: Math.round(root.size * 0.53)
        thickness: 1.7
        tone: hover.hovered && root.enabled ? root.hoverTone : root.tone

        Behavior on tone {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    BusyRing {
        anchors.centerIn: parent
        visible: root.busy
        running: root.busy
        size: Math.round(root.size * 0.5)
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.enabled && !root.busy
        onTapped: root.clicked()
    }

    // Hand-rolled rather than Controls' ToolTip: this file is used inside
    // delegates, and a Controls popup per row is a popup per row.
    Rectangle {
        id: tip
        visible: opacity > 0
        opacity: hover.hovered && root.tooltip.length > 0 && root.enabled ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 5
        implicitWidth: tipText.implicitWidth + 16
        implicitHeight: 24
        radius: Theme.radiusSmall
        color: Theme.baseHigh
        border.width: 1
        border.color: Theme.borderStrong
        z: 100

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durFast) }
        }

        Text {
            id: tipText
            anchors.centerIn: parent
            text: root.tooltip
            color: Theme.textBody
            font.pixelSize: 11
        }
    }
}
