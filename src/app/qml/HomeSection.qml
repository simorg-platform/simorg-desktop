// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The landing page.
 *
 * What a desktop app should open on: where you are, what is running, and a way
 * into each of it — not a menu of places to go next. The three tiles are the
 * three sections beside this one, live and in the order the toolbar puts them,
 * so the page teaches the shape of the app by matching it rather than by
 * explaining it.
 *
 * The machine card below them is this computer at a glance, and the only place
 * in the app that describes the hardware, because everything else about the
 * machine is really about the agents. Home is a glance, never a second copy of
 * a section; Simorg CLI's `sim machine` in a
 * terminal prints the rest.
 */
Item {
    id: root

    /** Asks the shell to switch tabs — every tile is a way in. */
    signal openSection(int index)
    /**
     * Asks the shell for the Docker section by name rather than by number.
     *
     * A tile that navigated to `2` was correct until a tab was inserted before
     * it, at which point it silently opened a different screen. The shell owns
     * the order and is the only thing that should know it.
     */
    signal openDocker()
    /**
     * Asks for one agent's virtual machine page.
     *
     * A tile showing a count is a promise to show what was counted, and what
     * was counted is slices — each of which belongs to an agent and lives on
     * that agent's page. With one slice on this computer the tile goes straight
     * to it; with several it opens the agents, which is where choosing happens.
     * Zero is the id for "no particular agent".
     */
    signal openVirtualMachine(int agentId)
    /** Asks for one agent's own access screen, from the attention list. */
    signal openAgentAccess(int agentId)

    readonly property string firstName: {
        const name = Auth.user.displayName || "";
        const first = name.split(" ")[0];
        return first.length > 0 ? first : qsTr("there");
    }

    /** Local time, because "good evening" from a server's clock is worse than nothing. */
    readonly property string greeting: {
        const hour = new Date().getHours();
        if (hour < 5) return qsTr("Still up");
        if (hour < 12) return qsTr("Good morning");
        if (hour < 18) return qsTr("Good afternoon");
        return qsTr("Good evening");
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 1060
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 34
                Layout.bottomMargin: 34
                spacing: Theme.spaceLg

                // ---- Greeting ------------------------------------------
                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        GradientText {
                            Layout.fillWidth: true
                            text: qsTr("%1, %2").arg(root.greeting).arg(root.firstName)
                            pixelSize: 30
                            horizontalAlignment: Text.AlignLeft
                        }

                        ElidedText {
                            Layout.fillWidth: true
                            text: Auth.user.actingTitle.length > 0
                                  ? qsTr("Acting as %1 · connected to %2")
                                        .arg(Auth.user.actingTitle)
                                        .arg(App.apiEndpoint.replace(/^https?:\/\//, ""))
                                  : qsTr("Your workspace, connected to %1")
                                        .arg(App.apiEndpoint.replace(/^https?:\/\//, ""))
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                /*
                  ---- What is waiting for you ---------------------------

                  Above the tiles, and above the machine card, because it is the
                  only thing on this page that is *addressed to the person
                  reading it*. Everything else here is a readout; this is a
                  question somebody asked them, and an agent that cannot run
                  until it is answered.

                  It draws nothing at all when there is nothing to do — see
                  AttentionList. A section that sits there saying "0" is a
                  section people stop reading.
                */
                Reveal {
                    step: 1
                    Layout.fillWidth: true
                    visible: attention.visible

                    AttentionList {
                        id: attention
                        width: parent.width
                        onOpenAgentAccess: (agentId) => root.openAgentAccess(agentId)
                    }
                }

                // ---- Live tiles ----------------------------------------
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GridLayout {
                        width: parent.width
                        columns: root.width > 900 ? 3 : (root.width > 620 ? 2 : 1)
                        columnSpacing: Theme.spaceMd
                        rowSpacing: Theme.spaceMd

                        // Agents, which is what the whole platform is for.
                        HomeTile {
                            Layout.fillWidth: true
                            label: qsTr("AGENTS")
                            glyph: "robot"
                            tone: Theme.violet
                            accent: Theme.violet
                            value: Hub.agentCount >= 0 ? String(Hub.agentCount) : "—"
                            caption: Hub.agentCount === 1
                                     ? qsTr("agent running on your account")
                                   : Hub.agentCount >= 0
                                     ? qsTr("agents running on your account")
                                   : qsTr("Not reported yet")
                            detail: Hub.agentCount > 0
                                    ? qsTr("Open the section for what each is doing")
                                  : Hub.agentCount === 0
                                    ? qsTr("Nothing is placed on this computer yet")
                                  : qsTr("Waiting for the platform")
                            onActivated: root.openSection(1)
                        }

                        // What has been carved out of this computer for them.
                        HomeTile {
                            Layout.fillWidth: true
                            label: qsTr("VIRTUAL MACHINES")
                            glyph: "vm"
                            tone: Hub.state === HubState.Ready ? Theme.cyan : Theme.textFaint
                            accent: Theme.cyan
                            dotState: Hub.state === HubState.Ready ? "running" : "exited"
                            value: Hub.virtualMachineCount >= 0 ? String(Hub.virtualMachineCount) : "—"
                            caption: Hub.virtualMachineCount === 1
                                     ? qsTr("virtual machine connected")
                                   : Hub.virtualMachineCount > 1
                                     ? qsTr("virtual machines connected")
                                   : Hub.virtualMachineCount === 0
                                     ? qsTr("no virtual machines yet")
                                   : qsTr("No virtual machines reported yet")
                            /*
                              The machine's name once there is one, and otherwise
                              what is actually happening: a refused handshake, an
                              unreachable Hub and a token tied to another machine
                              are all worth telling apart, and `Hub.statusText`
                              is what tells them apart.
                            */
                            detail: Hub.machineTitle.length > 0 ? Hub.machineTitle
                                                                : Hub.statusText
                            /*
                              Straight to the slice when there is exactly one,
                              and to the agents when there is a choice to make.
                              A tile showing a count is a promise to show what
                              was counted, and one slice needs no menu in
                              between.
                            */
                            onActivated: {
                                const only = Hub.virtualMachines.count === 1
                                             ? Hub.virtualMachines.at(0) : null;
                                root.openVirtualMachine(only ? only.agentId : 0);
                            }
                        }

                        // Docker, as a way in rather than a readout to admire.
                        HomeTile {
                            Layout.fillWidth: true
                            label: qsTr("DOCKER")
                            glyph: "container"
                            tone: Docker.ready ? Theme.emerald : Theme.amber
                            accent: Docker.ready ? Theme.emerald
                                  : Docker.status === DockerStatus.Unknown ? Theme.blue
                                  : Theme.amber
                            value: Docker.ready
                                   ? String(Docker.containersRunning)
                                   : Docker.status === DockerStatus.Unknown
                                     ? qsTr("Checking…")
                                     : Docker.installed ? qsTr("Not running")
                                                        : qsTr("Not installed")
                            caption: Docker.ready
                                     ? (Docker.containersRunning === 1
                                        ? qsTr("container running")
                                        : qsTr("containers running"))
                                   : Docker.status === DockerStatus.Unknown
                                     ? qsTr("Looking for Docker on this computer")
                                     : Docker.installed
                                       ? qsTr("Open the Docker section to start it")
                                       : qsTr("Simorg can install it for you")
                            detail: Docker.ready
                                    ? qsTr("%1 images · %2 on disk")
                                          .arg(Docker.imageCount)
                                          .arg(Docker.diskMeasured
                                               ? Docker.formatBytes(Docker.diskTotal)
                                               : qsTr("measuring…"))
                                    : ""
                            onActivated: root.openDocker()
                        }
                    }
                }

                // ---- This computer, in brief ---------------------------
                // The one place the hardware is described. Deliberately brief:
                // what somebody needs from it here is "yes, that is my laptop,
                // and Simorg knows about it".
                Reveal {
                    step: 2
                    Layout.fillWidth: true

                    MachineCard {
                        width: parent.width
                    }
                }

                // ---- Ways out ------------------------------------------
                Reveal {
                    step: 3
                    Layout.fillWidth: true

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spaceSm

                        GhostButton {
                            text: qsTr("Open Simorg in browser")
                            onClicked: App.openWebApp()
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: qsTr("Simorg %1").arg(App.version)
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
