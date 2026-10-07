// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The screen shown while this computer registers itself with Simorg.
 *
 * It covers the dashboard rather than replacing it, because what is happening
 * underneath is real: the person is signed in, their profile is loaded, and the
 * only thing still in flight is the machine. Swapping the whole window for a
 * spinner would say "nothing has happened yet", which is not true and reads
 * worse when the connection is quick.
 *
 * ## When it is allowed to cover anything
 *
 * Only before the first handshake of a session, and that rule is the important
 * one. A machine that has connected once has a dashboard worth keeping: the
 * agents are listed, the containers are running, and every screen except the
 * ones that need the platform is still true. Losing the socket after that is
 * reported by {@link ConnectionBanner} in a bar at the top, which leaves the
 * application usable while it sorts itself out.
 *
 * Before the first handshake there is genuinely nothing behind this, which is
 * the one case where covering the window is the honest thing to do. Even then
 * it is not a trap: as soon as an attempt has failed, this offers the reason,
 * the countdown, a retry, and a way past it into the parts of the app that do
 * not need a network.
 */
Item {
    id: root

    /** Somebody chose to go and look around instead of waiting. */
    signal dismissed()

    /** Live diagnosis and countdown, from the Hub client's own monitor. */
    readonly property var link: Hub.connection

    /** Something went wrong that retrying will not fix; offer a way out. */
    readonly property bool failed: Hub.state === HubState.Failed

    /** An attempt has failed. There is a reason to show and a wait to skip. */
    readonly property bool troubled: link.troubled

    readonly property color accent: root.failed ? Theme.danger : Theme.amber

    readonly property string waitText: {
        if (root.failed)
            return "";
        if (root.link.attempting)
            return qsTr("Trying now…");
        const seconds = root.link.retryInSeconds;
        if (seconds > 0)
            return qsTr("Trying again in %1s").arg(seconds);
        if (seconds === 0)
            return qsTr("Trying again…");
        return "";
    }

    // The backdrop is opaque enough to make the overlay unambiguous and thin
    // enough to keep the shell visible behind it — this is a step in a process,
    // not a different place.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.base, 0.88)
    }

    // Swallow clicks so nothing underneath can be operated mid-handshake.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 460)
        spacing: Theme.spaceLg

        BusyRing {
            Layout.alignment: Qt.AlignHCenter
            size: 46
            thickness: 3
            tone: Theme.sky
            visible: !root.troubled
            running: visible
        }

        Glyph {
            Layout.alignment: Qt.AlignHCenter
            visible: root.troubled
            name: root.failed ? "alert" : "network"
            size: 46
            thickness: 1.6
            tone: root.accent
        }

        /*
          Two headings, one at a time.

          The brand gradient says "welcome"; a connection problem is not that,
          and painting "No internet connection" in the same blue as the product's
          own name reads as decoration on a fault. The troubled title takes the
          colour of the fault instead.
        */
        GradientText {
            Layout.fillWidth: true
            visible: !root.troubled
            text: qsTr("Setting up this machine")
            pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            visible: root.troubled
            text: root.link.title
            color: root.accent
            font.pixelSize: 24
            font.weight: Font.ExtraBold
            font.letterSpacing: -0.3
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: root.troubled
                  ? root.link.detail
                  : qsTr("Simorg is adding %1 to your account so you can run agents on it.")
                        .arg(Hub.machineTitle.length > 0 ? Hub.machineTitle : qsTr("this computer"))
            color: Theme.textBody
            font.pixelSize: Theme.fontBody
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.55
        }

        /*
          The live status line, so a slow connection looks like progress rather
          than a hang, and the countdown once it is no longer progress. It is the
          same string the CLI prints.
        */
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.troubled ? root.waitText : Hub.statusText
            color: root.troubled ? Theme.alpha(root.accent, 0.95) : Theme.textFaint
            font.pixelSize: Theme.fontSmall
            font.weight: root.troubled ? Font.Medium : Font.Normal
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spaceSm
            visible: root.troubled

            PrimaryButton {
                text: qsTr("Try again")
                enabled: !root.link.attempting
                onClicked: root.link.retryNow()
            }

            /*
              The way out of a screen that is otherwise a wait with no end.

              Most of this application is about this computer rather than about
              the platform: Docker, the images, the artifact cache and every
              setting are all local, and none of them needs a handshake. Somebody
              on a train should be able to go and look at them. Simorg keeps
              trying in the background, and the bar at the top takes over the
              moment they leave this screen.
            */
            GhostButton {
                text: qsTr("Continue without connecting")
                onClicked: root.dismissed()
            }
        }

        GhostButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.failed
            text: qsTr("Sign in again")
            onClicked: App.signOut() // asks first when agents are running here
        }
    }
}
