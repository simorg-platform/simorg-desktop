// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The bar that says a newer release of one agent is ready, on the agent's page.
 *
 * An agent installed from a published agent is offered its publisher's newer
 * releases: the platform tells this
 * computer on `desktop.agent.update.available`, and the offer rides on the
 * agent's row as `update`. This draws it above the agent's rail, in the info
 * tone, with one button that opens the agent's Settings, where the update is
 * applied. It goes away by itself once nothing is on offer: the agent was
 * updated here, from the panel, or the release was withdrawn.
 *
 * The words say why updating is worth it — the release's own title when it has
 * one, or the opening words of its release note — rather than only that
 * something is available. The button reads "See what’s new" because Settings
 * opens on every release note since this agent's version. A private artifact's
 * release is never named, so its bar says "a newer release".
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. */
    property var agent: ({})
    /** False while the Settings pane is open, which says the same thing in full. */
    property bool allowed: true

    /** The person pressed the button: open the agent's Settings. */
    signal review()

    readonly property var update: root.agent && root.agent.update ? root.agent.update : ({})
    readonly property bool shown: root.allowed && root.update.available === true
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

    // Leaving the layout is a timer's job, as in UpdatesBar: an animated height
    // can be left part-way by a window in the tray.
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
        tone: Theme.sky
        title: root.update.tag && root.update.tag.length > 0
               ? qsTr("Version %1 is ready").arg(root.update.tag)
               : qsTr("A newer release is ready")
        body: root.update.title && root.update.title.length > 0
              ? root.update.title
              : root.update.excerpt && root.update.excerpt.length > 0
                ? root.update.excerpt
                : qsTr("Update to run the latest improvements from its publisher.")

        PrimaryButton {
            objectName: "reviewAgentUpdate"
            // Where it leads first: every release note since this agent's version.
            text: qsTr("See what’s new")
            implicitHeight: 34
            onClicked: root.review()
        }
    }
}
