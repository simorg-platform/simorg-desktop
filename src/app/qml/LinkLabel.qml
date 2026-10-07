// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * An inline link.
 *
 * The underline grows from the left on hover rather than appearing all at once,
 * which is the small kind of detail that makes a native app feel considered.
 */
Item {
    id: root

    property string text: ""
    property color tone: Theme.sky
    property int pixelSize: Theme.fontSmall
    property int weight: Font.DemiBold

    signal activated()

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight + 3

    activeFocusOnTab: true
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
            root.activated();
            event.accepted = true;
        }
    }

    Text {
        id: label
        text: root.text
        color: mouse.containsMouse ? Qt.lighter(root.tone, 1.2) : root.tone
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.family: Theme.fontFamily

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    Rectangle {
        anchors.top: label.bottom
        anchors.topMargin: 1
        anchors.left: label.left
        height: 1
        width: mouse.containsMouse || root.activeFocus ? label.width : 0
        color: root.tone
        opacity: 0.8

        Behavior on width {
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }
    }

    // Focus ring for keyboard navigation; invisible to the mouse.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.radiusSmall
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.sky, 0.6)
        visible: root.activeFocus
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
