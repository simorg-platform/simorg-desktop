// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The bar that says agents on this computer have a newer release ready,
 * whichever section the window is on.
 *
 * Drawn from `Hub.agents.updates`: every agent placed here whose row carries an
 * offer. One agent names its version and what the
 * release says about itself; several are counted and named. The one button
 * opens the first of them on its Settings pane, where the update is applied,
 * and the bar moves on to the next once it is done. Hidden while that agent's
 * own page is open, which has a bar of its own.
 *
 * Updates are offered, never applied by themselves: the bar stays until each
 * agent is updated or the release is withdrawn.
 */
Item {
    id: root

    /** The agent whose page is open, whose own bar already says this. */
    property int openAgentId: 0

    /** The person pressed the button: open this agent's Settings. */
    signal review(int agentId)

    /*
      Copied into a JavaScript array by hand: a list read from C++ is a sequence
      wrapper, not an array, and its methods are not promised.
    */
    readonly property var offers: {
        const all = Hub.agents.updates;
        const kept = [];
        for (let i = 0; i < all.length; ++i) {
            if (all[i].agentId !== root.openAgentId)
                kept.push(all[i]);
        }
        return kept;
    }
    readonly property bool shown: root.offers.length > 0
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

    function names() {
        return root.offers.map(function (offer) { return offer.title; }).join(", ");
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
        // Singular and plural written out: %n with no catalogue prints literally.
        title: root.offers.length === 1
               ? (root.offers[0].tag.length > 0
                  ? qsTr("%1 %2 is ready").arg(root.offers[0].title).arg(root.offers[0].tag)
                  : qsTr("A newer release of %1 is ready").arg(root.offers[0].title))
               : qsTr("%1 agents have a newer release ready").arg(root.offers.length)
        body: root.offers.length === 1
              ? (root.offers[0].releaseTitle.length > 0
                 ? root.offers[0].releaseTitle
                 : root.offers[0].releaseExcerpt.length > 0
                   ? root.offers[0].releaseExcerpt
                   : qsTr("Update to run the latest improvements from its publisher."))
              : qsTr("%1. Update each from its Settings.").arg(root.names())

        PrimaryButton {
            objectName: "reviewAgentUpdates"
            text: qsTr("See what’s new")
            implicitHeight: 34
            onClicked: {
                if (root.offers.length > 0)
                    root.review(root.offers[0].agentId);
            }
        }
    }
}
