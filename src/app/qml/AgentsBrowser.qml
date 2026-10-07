// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The overview, and the page one of its cards opens.
 *
 * A drill-down rather than a route: the app has no address bar and needs none,
 * so "which agent is open" is one integer held here, and the tab strip above
 * stays put throughout. Somebody who opens an agent has not left Agents.
 *
 * There is one list of agents — the cards, on the overview — and this wraps it
 * so that the section stays what it is, a handful of peers in a StackLayout,
 * and the only place that knows an agent page exists is the one view that has
 * one.
 */
Item {
    id: root

    /** The agent whose page is open, or 0 for the overview. */
    property int openAgentId: 0

    signal openDocker()
    /** Asks the section for the machine-wide rules screen. */
    signal openMachineRules()
    /** Passed straight up from the overview; see {@link AgentsOverview}. */
    signal openDockerResources()

    /**
     * Opens one agent's page on its access screen.
     *
     * Where a permission notification lands. Both steps, in this order: the
     * page has to exist before it can be steered, and steering it before the
     * StackLayout has switched would put the rail on a page nobody is looking
     * at.
     */
    function showAgentAccess(agentId) {
        root.openAgentId = agentId;
        detail.showAccess();
    }

    /**
     * The same two steps, for the page that shows what an agent was given.
     *
     * A zero is the Home tile saying "the slices, and I cannot tell you whose"
     * — which happens when this computer holds several. That lands on the
     * overview, where the agents are, rather than on an arbitrary one of them.
     */
    function showVirtualMachine(agentId) {
        root.openAgentId = agentId > 0 ? agentId : 0;
        if (agentId > 0)
            detail.showVirtualMachine();
    }

    /** Opens one agent on its Settings, where an update is applied. Where the window's update bar lands. */
    function showSettings(agentId) {
        root.openAgentId = agentId > 0 ? agentId : 0;
        if (agentId > 0)
            detail.showSettings();
    }

    /*
      Closing the page when the agent leaves is deliberate, and it is why this
      is checked here rather than inside the page: an agent taken off this
      computer while somebody was reading its log has nothing left to show, and
      a page that lingered would be a screen about something that is not there.
      The page says so for a moment before this closes it, which is kinder than
      the view changing under a click.
    */
    Connections {
        target: Hub.agents
        function onCountChanged() {
            if (root.openAgentId > 0 && !Hub.agents.contains(root.openAgentId))
                closeTimer.start();
        }
    }

    Timer {
        id: closeTimer
        interval: 2500
        onTriggered: {
            if (root.openAgentId > 0 && !Hub.agents.contains(root.openAgentId))
                root.openAgentId = 0;
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: root.openAgentId > 0 ? 1 : 0

        AgentsOverview {
            onOpened: function (agentId) { root.openAgentId = agentId; }
            onOpenDockerResources: root.openDockerResources()
        }

        AgentDetail {
            id: detail
            agentId: root.openAgentId
            onClosed: root.openAgentId = 0
            onOpenDocker: root.openDocker()
            onOpenMachineRules: root.openMachineRules()
        }
    }
}
