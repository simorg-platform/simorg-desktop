// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The bar that says an update is ready: whenever Simorg Desktop, the machine service or the agent runtime has a
 * newer version that is not installed yet, in the info tone, with one button
 * that opens Settings → Updates. It has no close button and stays until every
 * update is installed; while one runs it says which, and the button still
 * opens the view. Its words are positive and say why updating matters.
 *
 * Collapsed to nothing when there is nothing, and pushing the window down rather
 * than floating over it, the same shape as the connection bar above it. Its
 * height leaves the layout on a timer, as the signing-out callout's does: an
 * animated height can be left part-way by a window in the tray.
 */
Item {
    id: root

    /** The person pressed the button: open Settings → Updates. */
    signal review()

    readonly property bool shown: Updates.anyAvailable || Updates.updating || Updates.restartPending
    property bool closing: false

    implicitHeight: root.shown ? callout.implicitHeight + 20 : 0
    visible: root.shown || root.closing
    clip: true

    Behavior on implicitHeight {
        enabled: Theme.motion
        NumberAnimation {
            duration: Theme.durBase
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    onShownChanged: {
        if (root.shown) {
            root.closing = false;
            shut.stop();
        } else {
            root.closing = true;
            shut.restart();
        }
    }

    Timer {
        id: shut
        interval: Theme.durBase + 250
        onTriggered: root.closing = false
    }

    InfoCallout {
        id: callout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 10
        glyph: "download"
        // A required update speaks in the warning tone; the words say why.
        tone: Updates.required && !Updates.updating && !Updates.restartPending ? Theme.amber : Theme.sky
        title: Updates.barTitle
        body: Updates.barBody

        RowLayout {
            spacing: 10

            BusyRing {
                visible: Updates.updating
                size: 18
                tone: Theme.sky
            }

            // A prepared Simorg Desktop is finished from here, by the person, when they choose.
            PrimaryButton {
                objectName: "restartToFinish"
                visible: Updates.restartPending
                text: Updates.restartButton
                implicitHeight: 34
                onClicked: Updates.restartToFinish()
            }

            PrimaryButton {
                objectName: "reviewUpdates"
                visible: !Updates.restartPending
                text: Updates.barButton
                implicitHeight: 34
                onClicked: root.review()
            }
        }
    }
}
