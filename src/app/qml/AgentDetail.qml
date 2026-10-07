// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * One agent, in full.
 *
 * The third navigation depth in the app and the last: tabs change what the
 * window is about, the segmented control changes the lens on the agents, and
 * this rail changes which part of *one* agent is open. A rail rather than more
 * segments because the two panes are not lenses on the same thing — Dashboard
 * is what the platform gave this agent, Logs is what its container is saying —
 * and because a rail leaves room for the third and fourth pane this page will
 * grow.
 *
 * ## Why the agent is looked up rather than passed in
 *
 * A tile hands over an id, and everything on this page is read from the model
 * against that id. Copying the row's values in at the moment of the click would
 * make this a photograph: the agent would go on saying "starting…" after its
 * container came up, and an agent taken off this computer while its page was
 * open would still be shown as running here. So the page re-reads itself
 * whenever the model moves, and closes itself when the agent goes away.
 */
Item {
    id: root

    required property int agentId

    /** Back to the cards on the overview. */
    signal closed()
    /** The one fix this page can offer when the engine is down. */
    signal openDocker()

    /**
     * Which pane is open, by key rather than by number.
     *
     * It was an index into a fixed list of six, and that stopped being possible
     * the moment the list stopped being fixed: the rail an agent gets depends on
     * what that agent is *made of*, so "pane 2" means the Brain on one agent and
     * the virtual machine on the next. The keys below are the whole vocabulary,
     * and the two lists that matter are both derived from them.
     */
    property string pane: "dashboard"

    /*
      Every pane this page can draw, in the order they are asked about.

      Dashboard is what this agent *is*. The middle three are what the agent
      *shows* — the rooms it draws for itself, which are not this application's
      pages at all: an engine artifact renders them and this is the frame around
      it. Virtual machine is what it *runs in*, Access management is what it may
      *do*, and Logs is what it is *saying*.

      The agent's own rooms sit directly under Dashboard, and above the three
      screens about *this computer's* relationship with it, because that is the
      order somebody needs them in: what the agent is and what it is showing you
      first, then what you have given it and what it is allowed to touch. It is
      also where the web panel puts them, so the two front ends agree about what
      an agent's rooms are.

      Virtual machine is above Access management because it is the pane with
      hardware on it: it is the one screen in this application that only makes
      sense on the machine, since every meter is drawn against what *this* box
      has to give.

      Settings is last, under Logs: updating the agent to a newer release of
      what it was installed from, and uninstalling it from this computer. The
      two things somebody does *to* the agent rather than reads about it, and
      the bar that says an update is ready leads here.

      `feature` is what makes a pane conditional. A pane with none is about this
      computer's relationship with the agent and is always drawn; a pane with one
      is a room the agent either has or does not, and `API` has no pane at all —
      an endpoint is not a room, nobody looks at it, and a tab that opened onto
      nothing would be this application inventing a screen the platform does not
      have.
    */
    readonly property var allPanes: [
        { key: "dashboard", label: qsTr("Dashboard"), glyph: "gauge", feature: "" },
        { key: "workbench", label: qsTr("Workbench"), glyph: "widgets", feature: "WORKBENCH" },
        { key: "brain", label: qsTr("Brain"), glyph: "brain", feature: "BRAIN" },
        { key: "landing", label: qsTr("Landing"), glyph: "globe", feature: "LANDING" },
        { key: "virtual-machine", label: qsTr("Virtual machine"), glyph: "vm", feature: "" },
        { key: "access", label: qsTr("Access management"), glyph: "shield", feature: "" },
        { key: "logs", label: qsTr("Logs"), glyph: "terminal", feature: "" },
        { key: "settings", label: qsTr("Settings"), glyph: "settings", feature: "" }
    ]

    /** What the platform says this agent is made of. Empty until it has said. */
    readonly property var featureKeys: root.present && root.agent.featureKeys
                                       ? root.agent.featureKeys : []

    /**
     * The rail, for this agent: the fixed panes plus the rooms it actually has.
     *
     * The same rule the web panel applies, deliberately word for word, because the two front ends drawing different rooms for one
     * agent is the thing worth avoiding here:
     *
     * - **Brain is always offered.** It is the one feature an agent cannot turn
     *   off, so reading it off the payload would only produce a rail with a gap
     *   in it for the moment before the platform answers.
     * - **Workbench and Landing are offered only when the platform has said so.**
     *   A room that turns out not to exist sends somebody to a surface whose
     *   only possible message is that the agent published nothing — which is
     *   equally true of a feature switched off and of one that never existed,
     *   and neither is worth the click. An entry that appears a beat later is
     *   the smaller error.
     */
    readonly property var panes: root.allPanes.filter(function (entry) {
        if (entry.feature === "" || entry.feature === "BRAIN")
            return true;
        return root.featureKeys.indexOf(entry.feature) >= 0;
    })

    /** Where a key sits in the rail. -1 when this agent has no such pane. */
    function indexOfPane(key) {
        for (let i = 0; i < root.panes.length; ++i) {
            if (root.panes[i].key === key)
                return i;
        }
        return -1;
    }

    /**
     * Where a key sits in the stack, which is every pane rather than this
     * agent's.
     *
     * The stack holds all eight whatever the rail shows. Building it from the
     * filtered list instead would destroy and recreate panes whenever an agent's
     * features changed — including, on a `WORKBENCH` switched on elsewhere, the
     * browser view somebody was reading in the pane next door.
     */
    function stackIndexOf(key) {
        for (let i = 0; i < root.allPanes.length; ++i) {
            if (root.allPanes[i].key === key)
                return i;
        }
        return 0;
    }

    /** Opens this agent's own access screen. Where a notification lands. */
    function showAccess() {
        root.pane = "access";
    }

    /** Opens the slice of this computer it runs in. */
    function showVirtualMachine() {
        root.pane = "virtual-machine";
    }

    /** Opens its Settings, where an update is applied. Where the update bars lead. */
    function showSettings() {
        root.pane = "settings";
    }

    /*
      A room that has gone takes you back to the Dashboard.

      An owner switching a surface off while somebody is standing in it is an
      ordinary thing to do from the panel, and the frame that says so arrives
      here a second later. Without this the rail would lose the entry and the
      stack would go on drawing the pane behind it, with nothing selected.
    */
    onPanesChanged: {
        if (root.indexOfPane(root.pane) < 0)
            root.pane = "dashboard";
    }

    /** Asks the shell for the machine-wide rules, from a row that is ruled. */
    signal openMachineRules()

    /** The agent's row, re-read whenever anything about it could have moved. */
    property var agent: ({})

    readonly property bool present: root.agent !== undefined && root.agent.agentId > 0

    function refresh() {
        root.agent = root.agentId > 0 ? Hub.agents.byId(root.agentId) : ({});
    }

    onAgentIdChanged: {
        root.pane = "dashboard";
        root.refresh();
        /*
          Whether this person may start or stop this agent is the platform's
          answer, and it is asked once per agent opened. Nothing on this page
          can work it out for itself: owning the computer an agent runs on does
          not make somebody a member of it. See AgentLifecycleControl.
        */
        AgentLifecycle.open(root.agentId);
        // Its update and whether this person may apply it are the platform's answer too.
        AgentSettings.open(root.agentId);
        AgentDependencies.open(root.agentId);
    }

    Component.onCompleted: {
        root.refresh();
        AgentLifecycle.open(root.agentId);
        AgentSettings.open(root.agentId);
        AgentDependencies.open(root.agentId);
    }

    // Leaving the page puts the controls away. An answer about the agent just
    // closed must not still be on screen behind the next one.
    Component.onDestruction: {
        AgentLifecycle.close();
        AgentSettings.close();
        AgentDependencies.close();
    }

    /*
      Three signals, because three different things move this row.

      `dataChanged` is a container starting or failing, `countChanged` is an
      agent arriving or leaving, and a reset is a whole handshake landing. QML
      cannot take a binding dependency on any of them, so the page is told.
    */
    Connections {
        target: Hub.agents
        function onDataChanged() { root.refresh(); }
        function onCountChanged() { root.refresh(); }
        function onModelReset() { root.refresh(); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Who this is -----------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 62

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12

                IconButton {
                    glyph: "arrow-left"
                    tooltip: qsTr("All agents")
                    onClicked: root.closed()
                }

                Avatar {
                    initials: root.present && root.agent.title.length > 0
                              ? root.agent.title.charAt(0).toUpperCase()
                              : "?"
                    remote: root.present && root.agent.avatarUrl ? root.agent.avatarUrl : ""
                    size: 32
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    spacing: 0

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.present ? root.agent.title : qsTr("This agent has gone")
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        elide: Text.ElideRight
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.present
                              ? "@" + root.agent.slug
                                + (root.agent.tagline.length > 0
                                   ? " · " + root.agent.tagline : "")
                              : qsTr("It is no longer placed on this computer.")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                AgentStatePill {
                    visible: root.present
                    containerStateName: root.present ? root.agent.containerStateName : ""
                    running: root.present && root.agent.running
                    lifecycle: root.present ? root.agent.lifecycle : null
                }

                IconButton {
                    glyph: "refresh"
                    tooltip: qsTr("Check this container again")
                    busy: AgentContainers.reconciling
                    onClicked: AgentContainers.reconcile()
                }
            }
        }

        /*
          Whatever this agent is in the middle of, across the whole space.

          Above the rail rather than inside a pane, because a reboot is watched
          from wherever somebody happened to be standing when they pressed it —
          often the Logs, to see it come back. See AgentTransitionBar.
        */
        AgentTransitionBar {
            Layout.fillWidth: true
            agent: root.agent
        }

        /*
          A newer release of what this agent was installed from is ready. Above
          the rail for the reason the strip above is: it is true whichever pane
          is open. Put away while Settings is open, which says it in full.
        */
        AgentUpdateBar {
            Layout.fillWidth: true
            agent: root.agent
            allowed: root.pane !== "settings"
            onReview: root.showSettings()
        }

        // ---- The rail, and what it opens --------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                Layout.preferredWidth: 208
                Layout.fillHeight: true

                Rectangle {
                    anchors.right: parent.right
                    height: parent.height
                    width: 1
                    color: Theme.borderSubtle
                }

                SideNav {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 18
                    heading: qsTr("THIS AGENT")
                    items: root.panes
                    currentIndex: root.indexOfPane(root.pane)
                    onSelected: function (index) { root.pane = root.panes[index].key; }
                }
            }

            /*
              All eight panes, always, whatever the rail is showing.

              See stackIndexOf: an agent's features move while its page is open,
              and rebuilding this from the filtered list would tear down the
              browser view in the pane next door every time one did.
            */
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.stackIndexOf(root.pane)

                // Each pane works out for itself whether there is an agent, from
                // the one object it is given. Handing down a second "is there
                // one" property would be two bindings that briefly disagree.
                AgentDashboard {
                    agent: root.agent
                    panes: root.panes
                    onOpenDocker: root.openDocker()
                    onOpenVirtualMachine: root.showVirtualMachine()
                    onOpenPane: function (key) { root.pane = key; }
                }

                /*
                  The agent's own two rooms, drawn by the same renderer and told
                  apart by one string. Each is given `active` rather than working
                  it out: a browser view costs a process, so exactly one exists
                  and only while somebody is looking at it.
                */
                AgentSurfacePane {
                    surface: "WORKBENCH"
                    title: qsTr("Workbench")
                    agentId: root.present ? root.agentId : 0
                    publicToken: root.present ? (root.agent.publicToken || "") : ""
                    active: root.pane === "workbench" && root.visible
                }

                AgentSurfacePane {
                    surface: "BRAIN"
                    title: qsTr("Brain")
                    agentId: root.present ? root.agentId : 0
                    publicToken: root.present ? (root.agent.publicToken || "") : ""
                    active: root.pane === "brain" && root.visible
                }

                AgentSurfacePane {
                    surface: "LANDING"
                    title: qsTr("Landing")
                    agentId: root.present ? root.agentId : 0
                    publicToken: root.present ? (root.agent.publicToken || "") : ""
                    active: root.pane === "landing" && root.visible
                }

                AgentVirtualMachinePane {
                    agent: root.agent
                }

                AgentAccessPane {
                    agentId: root.agentId
                    agentTitle: root.present ? root.agent.title : ""
                    onOpenMachineRules: root.openMachineRules()
                }

                AgentContainerLogs {
                    agent: root.agent
                    // Streaming is started and stopped by the pane itself, so a
                    // page left open on the dashboard costs nothing.
                    active: root.pane === "logs" && root.visible
                    onOpenDocker: root.openDocker()
                }

                AgentSettingsPane {
                    agent: root.agent
                    active: root.pane === "settings" && root.visible
                }
            }
        }
    }
}
