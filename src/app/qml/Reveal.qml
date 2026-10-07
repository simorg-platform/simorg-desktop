// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * Staggered entrance for a group of elements.
 *
 * The web console gives each item in a list `revealSx(index)` — a 520ms rise on
 * the settle curve, 45ms apart. This is that, as a wrapper: give each child an
 * increasing `step` and they arrive in sequence rather than all at once.
 *
 * The animation is started from Component.onCompleted rather than expressed as
 * a state transition, because QML applies the initial state without animating
 * it and the entrance would never be seen.
 */
Item {
    id: root

    /** Position in the stagger; 45ms of delay per step, capped at twelve. */
    property int step: 0
    /** How far the content rises from. */
    property real distance: 14

    default property alias content: holder.data

    // Sized by the single child, which in turn fills this item — the ordinary
    // Control idiom, and what lets Reveal drop into a layout unchanged.
    readonly property Item child: holder.children.length > 0 ? holder.children[0] : null
    implicitWidth: child ? child.implicitWidth : 0
    implicitHeight: child ? child.implicitHeight : 0

    opacity: Theme.motion ? 0 : 1
    transform: Translate { id: rise; y: Theme.motion ? root.distance : 0 }

    Item {
        id: holder
        anchors.fill: parent
    }

    ParallelAnimation {
        id: enter
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: Theme.duration(Theme.durReveal)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
        NumberAnimation {
            target: rise
            property: "y"
            to: 0
            duration: Theme.duration(Theme.durReveal)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    Timer {
        interval: Theme.motion ? Math.min(root.step, 12) * 45 : 0
        running: true
        onTriggered: enter.start()
    }
}
