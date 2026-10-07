// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * A bar across the top of the window when this computer is not talking to Simorg.
 *
 * It replaced a full-screen overlay, and the reason is the whole design: losing
 * a socket does not undo anything on the screen behind it. The agents are still
 * on this computer, the containers are still running, Docker is still there to
 * be looked at, and the settings are still editable. Covering all of that to say
 * "connecting" took an application away from somebody over a problem that, most
 * of the time, fixes itself before they have finished reading the sentence.
 *
 * So this pushes the window down by one bar instead. Everything stays reachable;
 * anything that actually needs the platform fails on its own terms, with the
 * same wording this bar is using — see {@link HubModel}.
 *
 * ## What it says
 *
 * A colour, a reason, and a countdown. The colour is amber while Simorg is still
 * trying and red once it has stopped, which is the only distinction that changes
 * what somebody should do. The reason is diagnosed rather than guessed: "no
 * internet connection" and "Simorg is restarting" send a person to two different
 * places, and showing the first when the second is true wastes their afternoon
 * on their own router.
 *
 * The countdown is there so the bar reads as an application that is working on
 * it rather than one that has given up, and {@link HubModel::retryNow}
 * is beside it so nobody has to wait out a thirty-second backoff they can see.
 */
Item {
    id: root

    /** Live diagnosis and countdown, from the Hub client's own monitor. */
    readonly property var link: Hub.connection

    /**
     * This computer's own Simorg, which outranks the platform link.
     *
     * Two different connections can be down and they are not the same news. The
     * Hub is this machine's line to the platform: losing it leaves the agents
     * running and the windows working. The **service** is where the agents, the
     * containers, the session and every reading in this window actually live,
     * and without it the panel is a picture of a computer rather than a view of
     * one — so when both are wrong, this is the one to say. Unsaid, a service
     * that had stopped would leave every screen holding its last reading with
     * nothing on the window to explain why nothing answered.
     */
    readonly property bool serviceDown: !Service.connected

    /**
     * The service left to start its updated binary: said as what it is, a
     * restart that finishes an update and stops no agent, never as a service
     * that went away.
     */
    readonly property bool finishingUpdate: root.serviceDown && Updates.serviceRestarting

    readonly property string title: root.finishingUpdate ? qsTr("Finishing the update")
                                  : root.serviceDown ? Service.title : root.link.title
    readonly property string detail: root.finishingUpdate
                                     ? qsTr("The Simorg machine service is starting its new version. Your agents keep running.")
                                     : root.serviceDown ? Service.detail : root.link.detail

    /**
     * True while the setup screen is covering the window.
     *
     * The two must never be on screen together: before the first handshake there
     * is no dashboard for a bar to sit above, and the setup screen carries the
     * same reason and the same button.
     */
    property bool covered: false

    /**
     * Held open for a few seconds after a reconnect.
     *
     * A bar that vanished the instant the socket came back would leave somebody
     * who looked up a moment too late wondering whether they imagined it. This
     * is the one green thing in the component and it says the outage is over.
     */
    property bool recovered: false

    /** Whether an outage has been reported since the last time all was well. */
    property bool wasTroubled: false

    readonly property bool shown: !covered && (serviceDown || link.troubled || recovered)

    readonly property color accent: recovered ? Theme.emerald
                                   : (serviceDown ? Service.severe : link.severe) ? Theme.danger
                                                                                  : Theme.amber

    readonly property string glyphName: {
        if (recovered)
            return "check-circle";
        // The service is a program on this computer, and its mark is the one the
        // Docker section uses for a daemon that is not answering.
        if (root.serviceDown)
            return Service.severe ? "alert" : "server";
        switch (link.trouble) {
        case ConnectionTrouble.NoNetwork:
            return "network";
        case ConnectionTrouble.CaptivePortal:
            return "lock";
        case ConnectionTrouble.ServerRestarting:
        case ConnectionTrouble.ServerSilent:
        case ConnectionTrouble.ServerUnreachable:
            return "server";
        case ConnectionTrouble.ServerRefused:
            return "shield";
        default:
            return "alert";
        }
    }

    /**
     * The countdown line, in the three states it has.
     *
     * Empty when there is nothing to count: a session that ended for good is not
     * waiting for anything, and a bar that offered to retry it would be lying.
     */
    readonly property string waitText: {
        if (root.recovered)
            return "";
        // The service client backs off on its own and does not publish a clock,
        // so this says that it is still trying rather than inventing a number.
        if (root.serviceDown)
            return Service.severe ? "" : qsTr("Reconnecting…");
        if (root.link.severe)
            return "";
        if (root.link.attempting)
            return qsTr("Reconnecting…");
        const seconds = root.link.retryInSeconds;
        if (seconds > 0)
            return qsTr("Trying again in %1s").arg(seconds);
        if (seconds === 0)
            return qsTr("Trying again…");
        return "";
    }

    /**
     * True for as long as the closing animation has to run, and not a moment
     * after it.
     *
     * The row is in the window's column, so its height is *layout*: the sections
     * below start where this ends. Animating that height is what gives the bar
     * its push, and it is also how the row can be left holding space it no
     * longer wants — an animation is advanced by the render loop, and a window
     * in the tray, on another Space, or still on its way up at launch does not
     * run one. The height stops wherever it had got to, the contents have
     * already faded out, and what is left under the tab bar is a band of
     * nothing that never closes. That is exactly what was found on a real
     * machine: a bar reporting `shown` false, its own `implicitHeight` 0, and
     * the layout still giving it 26 pixels.
     *
     * So the row leaves the layout on a *timer* rather than on an animation.
     * Timers are the event loop's, not the renderer's, and they fire whether or
     * not anybody is looking. Once this is false the item is invisible, a
     * layout leaves out what is invisible, and no stale height can survive it.
     */
    property bool closing: false

    implicitHeight: root.shown ? surface.implicitHeight : 0
    clip: true
    visible: root.shown || root.closing
    z: 4

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
        interval: Theme.duration(Theme.durBase) + 250
        onTriggered: root.closing = false
    }

    // Read out as it appears, the way the sign-in form's own message is.
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.recovered ? qsTr("Reconnected to Simorg")
                                    : root.title + ". " + root.detail

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.duration(Theme.durBase)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    /*
      Recovery is watched rather than bound.

      "It was broken and now it is not" is a transition, and a binding only ever
      sees the state after it. The flag below is what turns the second of those
      readings into the four seconds of green that says so.
    */
    Connections {
        target: root.link

        function onTroubleChanged() {
            if (root.link.troubled) {
                root.wasTroubled = true;
                root.recovered = false;
                recovery.stop();
            } else if (root.wasTroubled) {
                root.wasTroubled = false;
                root.recovered = true;
                recovery.restart();
            }
        }
    }

    Timer {
        id: recovery
        interval: 4000
        onTriggered: root.recovered = false
    }

    Rectangle {
        id: surface
        width: parent.width
        implicitHeight: Math.max(52, row.implicitHeight + 20)
        color: Theme.alpha(root.accent, 0.16)

        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }
        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }

        // A line at the bottom rather than a border all the way round: this is
        // part of the window chrome, not a card floating on it.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.alpha(root.accent, 0.55)
        }

        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: Theme.spaceSm

            Glyph {
                Layout.alignment: Qt.AlignVCenter
                name: root.glyphName
                size: 20
                thickness: 1.7
                tone: root.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                ElidedText {
                    Layout.fillWidth: true
                    text: root.recovered ? qsTr("Back online") : root.title
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                ElidedText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.recovered
                          ? qsTr("Simorg is connected again and this computer is back on your account.")
                          : root.detail
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                }
            }

            /*
              The countdown, and the width it is given.

              Fixed rather than sized to its text: "Trying again in 9s" is
              narrower than "Trying again in 28s", and a label that resized
              itself every second would walk the retry button across the bar
              once a second for as long as the outage lasted.
            */
            ElidedText {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 132
                visible: root.waitText.length > 0
                text: root.waitText
                color: Theme.alpha(root.accent, 0.95)
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            GhostButton {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 32
                // Nothing to retry while the service finishes its own update: it comes back by itself.
                visible: !root.recovered && !root.finishingUpdate
                text: (root.serviceDown ? Service.severe : root.link.severe) ? qsTr("Try again")
                                                                                             : qsTr("Retry now")
                enabled: root.serviceDown || !root.link.attempting
                onClicked: root.serviceDown ? Service.retryNow() : root.link.retryNow()
            }
        }
    }
}
