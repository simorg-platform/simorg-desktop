// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * One of the two rooms an agent draws for itself.
 *
 * **Workbench** is whatever the agent wants the people using it to see and work
 * in. **Brain** is where it offers the controls. Neither is drawn by this
 * application: both are the same renderer — an *engine* artifact, fetched at
 * run time and painted with a *theme* artifact — told which surface it is on.
 * The difference between these two panes is one string.
 *
 * That is the same arrangement Simorg's web panel uses for the same two pages,
 * and deliberately so. An agent that puts an interface on its Workbench should find
 * it there whether somebody opens the web panel or this application, and the
 * only way that stays true is if neither client authors anything inside.
 *
 * ## Why there is no role here
 *
 * The web panel hands the engine the seat the viewer holds and lets the agent
 * decide what that earns. This application has nothing to hand over: owning the
 * computer an agent was placed on does not make somebody a member of it, and
 * inventing a role would be telling an agent something untrue about who is
 * looking. So the engine is told which surface and which agent, and works the
 * rest out for itself.
 *
 * ## What is on screen while it loads
 *
 * **One** curtain, over the view rather than instead of it, so the page is
 * mounted and loading underneath while it shows — and it stays up until the room
 * is actually drawn rather than until the engine says hello. Those are different
 * moments, and the gap between them would otherwise show several waits in a
 * row — a spinner, the engine's own spinner, an empty ground — each one
 * centred, none of them the last. It lifts on the page
 * reporting it has drawn, on a failure this can explain, or on a wait long
 * enough that covering a working view is the worse of two bad options.
 */
Item {
    id: root

    /** `WORKBENCH` or `BRAIN`. Travels to the engine and no further. */
    required property string surface
    /** How the room is named on screen, and in the view's accessible title. */
    required property string title
    /** The agent whose room this is. Zero while the page has no agent. */
    property int agentId: 0
    /** The agent's public token, which names its worlds. Empty from an older Hub. */
    property string publicToken: ""

    /**
     * Whether this pane is the one on screen.
     *
     * The web view is created when this becomes true and destroyed when it
     * stops being true. A Chromium view costs a process and a few hundred
     * megabytes of address space; four agents' worth of them, held open behind
     * a rail nobody is looking at, is not a page somebody would forgive.
     */
    property bool active: false

    /** True once the engine inside has asked to be initialized. */
    property bool connected: false
    /**
     * True once the page says the surface is actually on screen.
     *
     * Later than {@link connected}, and the difference is the whole of what
     * somebody sees: *connected* is the engine saying hello, with nothing drawn
     * yet, and between the two it fetches its modules, takes the world and runs
     * the program — drawing its own waiting state while it does. Uncovering the
     * view at *connected* therefore replaced this pane's spinner with the
     * engine's, and sometimes a third before the room appeared. One wait, then
     * the room.
     */
    property bool drawn: false
    /** What the page last reported it could not do, or an empty string. */
    property string pageError: ""

    /**
     * Waiting has gone on long enough that covering the view is the worse of
     * two bad options.
     *
     * A page that connects and then never says it drew anything is either an
     * engine taking a very long time or one that is quietly stuck, and the
     * honest answer to both is to show what is actually there rather than a
     * spinner with no end. Generous on purpose: the engine and its theme are
     * downloads, and on a cold cache over a slow line they are not quick.
     */
    property bool uncovered: false

    /**
     * Whatever is going to be on screen is on it, or waiting has been given up
     * — or there is nothing to wait for: a build with no browser engine puts its
     * explanation where the page would be, and nothing ever reports from it.
     */
    readonly property bool ready: root.drawn || root.uncovered
                                  || (loader.item !== null && loader.item.drawsNothing === true)

    Timer {
        interval: 20000
        running: root.connected && !root.drawn && !root.uncovered && root.active
        onTriggered: root.uncovered = true
    }

    readonly property bool resolving: AgentSurfaces.state === SurfaceState.Loading
                                      || AgentSurfaces.state === SurfaceState.Idle
    readonly property bool failed: AgentSurfaces.state === SurfaceState.Failed

    /**
     * The surface this pane has open — its world, its program and its own
     * connection into the agent — for exactly as long as the view exists.
     *
     * Opened when the pane comes on screen with a renderer resolved, and closed
     * when it goes, which takes the Hub connection with it: an agent nobody is
     * looking at has nobody to send events to.
     */
    property var session: null
    readonly property bool wanted: root.active && AgentSurfaces.state === SurfaceState.Ready
                                   && root.agentId > 0
    /** Why the world could not be read, or an empty string. */
    readonly property string worldError: root.session ? root.session.worldError : ""

    onWantedChanged: root.syncSession()

    function syncSession() {
        if (root.wanted && !root.session) {
            root.session = SurfaceSessions.open(root.surface, root.agentId, root.publicToken);
        } else if (!root.wanted && root.session) {
            const closing = root.session;
            root.session = null;
            SurfaceSessions.close(closing);
        }
    }

    Component.onDestruction: {
        if (root.session)
            SurfaceSessions.close(root.session);
    }

    /*
      The agent woke, fell asleep, or published this room: what the platform answers for it has changed.

      While the agent is offline the platform answers with the agent asleep, and once it has connected and
      published, with its own room — or with the agent awake and nothing drawn. So the room is read again, in a
      fresh page: the program the old one ran was written for a world that is no longer there. The curtain
      comes back for the moment that takes, like any other reload.
    */
    Connections {
        target: root.session
        ignoreUnknownSignals: true
        function onWorldStale() {
            root.reload();
        }
    }

    /*
      Set rather than bound, because what they read is a function call.

      QML takes binding dependencies on properties, and a service with one entry
      per surface would need a property per surface it has never heard of. So
      the service says *which* surface reported and this asks about its own —
      the same shape `AgentDetail` uses for the agent model, and for the same
      reason.
    */
    function refreshStatus() {
        root.connected = AgentSurfaces.isConnected(root.surface);
        root.drawn = AgentSurfaces.isDrawn(root.surface);
        root.pageError = AgentSurfaces.surfaceError(root.surface);
    }

    Connections {
        target: AgentSurfaces
        function onSurfaceStatusChanged(surface) {
            if (surface === root.surface)
                root.refreshStatus();
        }
    }

    onSurfaceChanged: root.refreshStatus()

    onActiveChanged: {
        if (!root.active) {
            /*
              What the page said goes with the page.

              Leaving this pane destroys the view — a Chromium process is not
              held open behind a rail nobody is looking at — so coming back
              boots a new engine that has drawn nothing. Keeping the last
              visit's report would uncover the view over that boot, which is the
              second-visit version of the several-waits-in-a-row this curtain
              exists to end.
            */
            AgentSurfaces.forgetStatus(root.surface);
            root.uncovered = false;
            return;
        }
        // Asked for on the way in rather than at start-up: most sessions never
        // open one of these, and three requests nobody needed is three requests.
        AgentSurfaces.ensureResolved();
    }

    /*
      The mood, whenever the window's own changes.

      Sent into a page that is already on screen, because a document that has
      been served cannot be re-served — the `color-scheme` in it was decided at
      the moment it was built. The engine caches the theme module by URL, so
      re-sending the same source with the other column costs nothing.
    */
    Connections {
        target: Theme
        function onDarkChanged() {
            AgentSurfaces.dark = Theme.dark;
            if (loader.item)
                loader.item.applyThemeChoice(Theme.dark ? "dark" : "light");
        }
    }

    Component.onCompleted: {
        AgentSurfaces.dark = Theme.dark;
        root.refreshStatus();
        root.syncSession();
    }

    /** Throws the page away and asks for it again — the world with it. */
    function reload() {
        // The curtain comes back with the page: a reload is a wait like any other.
        root.uncovered = false;
        AgentSurfaces.forgetStatus(root.surface);
        if (AgentSurfaces.state === SurfaceState.Failed)
            AgentSurfaces.retry();
        if (root.session)
            root.session.reload();
        if (loader.item)
            loader.item.reloadSurface();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    /*
      Created only while this pane is the one on screen, and only once there is
      something to load. Two reasons, and the second is the one that matters
      here: a view pointed at the host page before the engine has resolved would
      be served a document that says "no renderer" and would have to be reloaded
      the moment one arrived.
    */
    /*
      ---- Article 50(1) of the EU AI Act, drawn --------------------------------

      A person talking to an agent is told so at the first interaction, clearly
      and before anything else on the surface: on the Brain, which is a
      conversation, and on the Landing page, which is what a stranger opens —
      not on the Workbench, the agent's own controls for its members. Outside
      the web view on purpose: the agent draws the surface and could not be
      trusted to draw this. The words are the platform's own, the same sentence
      the web panel draws over the same surfaces.
    */
    Rectangle {
        id: aiNotice
        objectName: "aiNotice"
        readonly property bool needed: root.surface === "BRAIN" || root.surface === "LANDING"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: needed
        height: needed ? noticeRow.implicitHeight + 12 : 0
        color: Theme.inset
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }
        RowLayout {
            id: noticeRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8
            Glyph {
                name: "robot"
                size: 14
                thickness: 1.6
                tone: Theme.textBody
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textBody
                font.pixelSize: 11
                textFormat: Text.StyledText
                text: qsTr("<b>You are talking to an AI agent.</b> Its replies are generated automatically and can be wrong, so check anything you intend to act on.")
            }
        }
    }

    Loader {
        id: loader
        // Named so a test can find it and check that it really loaded a view
        // rather than satisfying "no warnings" by doing nothing.
        objectName: "surfaceLoader"
        anchors.top: aiNotice.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Once the open is answered: the page is built from the renderer that answer confirmed.
        active: root.session !== null && root.session.rendererConfirmed
        source: "AgentSurfaceWebView.qml"

        onLoaded: {
            item.surface = Qt.binding(function () { return root.surface; });
            item.agentId = Qt.binding(function () { return root.agentId; });
            // Last, because the view loads its page the moment it has a session.
            item.session = Qt.binding(function () { return root.session; });
        }
    }

    /*
      ---- What sits over it until the room is drawn ------------------------

      One curtain, lifted once, and faded rather than cut: what is underneath
      arrives a frame at a time — the engine's ground, then its own furniture —
      and a curtain that vanished on a single frame showed every one of those
      steps as a separate flash. It is over the view rather than instead of it,
      so the page is mounted and loading the whole time it is up.
    */
    Item {
        // Named so a test can watch it lift: when it does is the whole of what
        // this change was about.
        objectName: "surfaceCurtain"
        anchors.fill: loader

        readonly property bool shown: !root.ready || root.failed || root.worldError.length > 0
                                      || root.agentId <= 0

        opacity: shown ? 1 : 0
        visible: opacity > 0
        // Nothing underneath is pressable while this is fading out.
        enabled: shown

        Behavior on opacity {
            enabled: Theme.motion
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.base
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 420)
            spacing: 14

            readonly property bool waiting: root.agentId > 0 && !root.failed
                                            && root.pageError.length === 0
                                            && root.worldError.length === 0

            BusyRing {
                Layout.alignment: Qt.AlignHCenter
                running: parent.waiting
                visible: running
                size: 26
            }

            Glyph {
                Layout.alignment: Qt.AlignHCenter
                visible: !parent.waiting
                name: root.surface === "BRAIN" ? "brain" : "widgets"
                size: 26
                tone: Theme.textFaint
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Theme.textBody
                font.pixelSize: 13
                /*
                  Three states, and none of them says "Nothing to show here". A
                  resolved engine whose page has not spoken yet is *still
                  loading*, with the view mounted and working underneath this;
                  and an agent's room being empty is something only the engine
                  can know, so it is the engine's sentence to write rather than
                  ours.
                */
                text: root.agentId <= 0
                      ? qsTr("This agent is no longer on this computer.")
                    : root.failed || root.pageError.length > 0 || root.worldError.length > 0
                      ? qsTr("%1 has not started yet.").arg(root.title)
                    : qsTr("Loading %1").arg(root.title.toLowerCase())
            }

            /*
              The reason underneath, in small print, rather than in the
              headline. An engine that cannot be resolved is a real
              misconfiguration and hiding it would leave somebody staring at
              "nothing here" with no way to find out why — but it is our
              plumbing, and the first line somebody reads should be about the
              thing they came to see.
            */
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text.length > 0
                color: Theme.textFaint
                font.pixelSize: 11
                font.family: Theme.monoFamily
                text: root.failed ? AgentSurfaces.message
                    : root.worldError.length > 0 ? root.worldError
                    : root.pageError
            }

            GhostButton {
                Layout.alignment: Qt.AlignHCenter
                visible: (root.failed || root.pageError.length > 0 || root.worldError.length > 0)
                         && root.agentId > 0
                text: qsTr("Reload the renderer")
                onClicked: root.reload()
            }
        }
    }
}
