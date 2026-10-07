// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Everything about the agents this computer runs.
 *
 * Not "the agents on your account" — that is a different list and belongs in
 * the browser. What is here is what this machine is *responsible for*: an agent
 * appears because its runtime selects a virtual machine that points at this box,
 * and while it is here this app keeps a container up for it.
 *
 * ## Why this is the whole section
 *
 * There is no tab for the machine beside this one, because almost everything
 * about the machine is really about an agent. A virtual machine exists because
 * an agent needed one. A capacity
 * reading is only interesting as "how much have the agents been promised". A
 * permission an agent asked for is a question about *that agent*. Filed under
 * the hardware, all three read as facts about a laptop; filed here, they read
 * as what each agent has and may do, which is the question anybody actually
 * has. The one part that is a fact about the computer — the rules covering
 * every agent at once — is under Settings; see below.
 *
 * Two lenses on one subject, so a segmented control rather than more tabs:
 *
 * | | |
 * | --- | --- |
 * | **Overview** | What the agents hold, then a card each, and a page behind every card |
 * | **Logs** | What the platform has asked this computer to do |
 *
 * The agents are cards on the Overview, not a second list one click away. Each
 * agent's slice of this computer is a page of that agent — see
 * {@link AgentDetail} — where it can also be *changed*, which a list of
 * everybody's slices could never offer.
 *
 * Access management is not here, because it is the one screen that is not
 * about the agents. It sets rules this *computer* keeps about every agent placed
 * on it, including the ones that have not arrived yet — written once, and not
 * something an agent's own page may talk over. That is a setting for this
 * machine, so it sits under Settings beside the folders and the startup
 * behaviour; see {@link SettingsSection}. What is here is per agent, on the
 * agent's own page.
 *
 * ## The header belongs to the list
 *
 * Opening an agent takes this header away. The page underneath carries the
 * agent's name, its state, its own refresh and its way back, and a strip above
 * it announcing "2 agents on this computer" beside a control for two views that
 * page is not one of would be two headers where the page needs none.
 */
Item {
    id: root

    property int view: 0

    readonly property var views: [
        { key: "overview", label: qsTr("Overview"), glyph: "gauge" },
        { key: "logs", label: qsTr("Logs"), glyph: "clock" }
    ]

    /**
     * Asks the shell for the machine-wide rules, which are a Settings screen.
     *
     * A signal rather than a view of its own: this section does not hold that
     * page, and the only thing here that links to it is a row saying a rule
     * already decided the question in front of it.
     */
    signal openMachineRules()

    /**
     * Whether one agent's own page is open, which is what silences the header.
     *
     * Read from the browser rather than tracked here, so there is one answer to
     * "is an agent open" and it is the one the StackLayout is acting on.
     */
    readonly property bool detailOpen: root.view === 0 && browser.openAgentId > 0

    /** The agent whose page is open, or 0. Its own bar says what the window's would. */
    readonly property int openAgentId: root.detailOpen ? browser.openAgentId : 0

    /**
     * Opens one agent's own access screen. Where a notification lands.
     *
     * Not the machine-wide list: an agent arriving for the first time is a
     * question about *that agent*, and the screen headed "rules for this
     * computer" is about something else.
     */
    function showAgentAccess(agentId) {
        root.view = 0;
        browser.showAgentAccess(agentId);
    }

    /**
     * Opens one agent's virtual machine. Where the Home tile lands.
     *
     * An agent id rather than a list, because there is no list any more: the
     * slice is a page of the agent that holds it. Both steps, in this order —
     * the page has to exist before it can be steered.
     */
    function showVirtualMachine(agentId) {
        root.view = 0;
        browser.showVirtualMachine(agentId);
    }

    /** Opens one agent on its Settings. Where the window's update bar lands. */
    function showAgentSettings(agentId) {
        root.view = 0;
        browser.showSettings(agentId);
    }

    /**
     * Nothing has been said yet — which is not the same as nothing being here.
     *
     * The count is negative until a handshake answers, and empty afterwards for
     * the many computers that host nothing. The list is consulted as well as the
     * count so that rows already on screen are never contradicted by a banner
     * saying we are still waiting to hear.
     */
    readonly property bool waiting: Hub.agentCount < 0 && Hub.agents.count === 0

    /** Asks the shell for the Docker section — the one fix this page can offer. */
    signal openDocker()
    /** The same, landing on Docker's resource settings. */
    signal openDockerResources()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ----------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            // A layout leaves out what is invisible, so the agent's page takes
            // the height back rather than opening under a 64-pixel gap.
            visible: !root.detailOpen

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 20
                spacing: 14

                Glyph {
                    name: "robot"
                    size: 18
                    thickness: 1.7
                    tone: Hub.agentCount > 0 ? Theme.violet : Theme.textFaint
                }

                /*
                  The title column absorbs the slack, and gives it back.

                  Two segments and a refresh button still have to share this
                  row with a title, and this window is allowed down to 940
                  pixels. Letting the title be the flexible one — rather than a
                  spacer between it and the control — means the header narrows
                  by eliding a subtitle nobody is reading rather than by pushing
                  a control off the edge.
                */
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 90
                    spacing: 1

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.waiting ? qsTr("Agents")
                            : Hub.agents.count === 1 ? qsTr("1 agent on this computer")
                            : qsTr("%1 agents on this computer").arg(Hub.agents.count)
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        elide: Text.ElideRight
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.view === 1
                              ? qsTr("Written for a person, and never a payload")
                            : root.waiting
                              ? Hub.statusText
                            : qsTr("Each one runs in its own container, started from %1")
                                  .arg(App.agentImage.length > 0
                                       ? App.agentImage
                                       : qsTr("the platform's image"))
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                SegmentedControl {
                    items: root.views
                    currentIndex: root.view
                    onSelected: function (index) { root.view = index; }
                }

                IconButton {
                    glyph: "refresh"
                    tooltip: qsTr("Check the containers again")
                    busy: AgentContainers.reconciling
                    enabled: Hub.agents.count > 0
                    visible: root.view === 0
                    onClicked: AgentContainers.reconcile()
                }
            }
        }

        // ---- Views -------------------------------------------------------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.view

            AgentsBrowser {
                id: browser
                onOpenDocker: root.openDocker()
                onOpenMachineRules: root.openMachineRules()
                onOpenDockerResources: root.openDockerResources()
            }

            AgentActivityLog {}
        }
    }
}
