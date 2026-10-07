// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The last screen: can anything actually run here.
 *
 * ## Why this is a step of the wizard rather than a tab somebody finds later
 *
 * A machine that cannot run a container is a machine that will accept an agent
 * and never start it. That failure is invisible from the panel — the machine is
 * online, it is named, it looks fine — and the only place it is knowable is
 * here, on the computer itself. So it is asked once, at the moment somebody is
 * setting the machine up, and the answer is sent to the platform: see
 * `machine_setup.runtime_state`, which is what the panel later shows as *"this
 * machine has no container runtime"* instead of leaving an agent stuck at
 * "starting".
 *
 * ## Nobody is trapped on it
 *
 * "Finish anyway" is always offered. Somebody who cannot install Docker tonight
 * still ends the evening with a named machine, a dashboard and every local part
 * of this application, and the platform records exactly why nothing will run
 * there yet. A wizard whose last step could not be passed would be an
 * application people uninstall.
 *
 * ## It does no checking of its own
 *
 * Everything on this screen comes from {@link PreflightModel}, which is the
 * same check the app runs before the sign-in window and the same one the Docker
 * tab reports. A second opinion here would be a second thing to disagree with
 * the first. That includes the graphics card, which the check looks at after
 * each pass and which never decides whether the machine is ready.
 */
Item {
    id: root

    /** True when this computer can run an agent right now. */
    readonly property bool ready: Preflight.ready

    /** What the platform will be told, phrased for whoever reads it later. */
    readonly property string runtimeDetail: {
        if (root.ready) {
            return Docker.engineVersion.length > 0
                ? qsTr("Docker %1 is running here, and the agent image is on this computer.")
                      .arg(Docker.engineVersion)
                : qsTr("A container engine is running here, and the agent image is on this computer.");
        }
        if (Docker.detail.length > 0)
            return Docker.detail;
        return qsTr("This computer has no container engine that Simorg could reach.");
    }

    /** Sends the answer. Either answer finishes the wizard. */
    function submit() {
        if (MachineSetup.busy)
            return;
        MachineSetup.reportRuntime(root.ready ? SetupState.Ready : SetupState.Unavailable,
                                   Docker.engineVersion,
                                   root.ready ? App.agentImage : "",
                                   root.runtimeDetail);
    }

    /*
      Sized by the column, which is anchored rather than filling. See the note
      on the welcome step: an Item takes no height from an anchored child, and
      the wizard measures its scrolling area from the step it is showing.
    */
    implicitHeight: body.implicitHeight

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spaceLg

        Reveal {
            step: 0
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.spaceXs

                GradientText {
                    Layout.fillWidth: true
                    text: root.ready
                          ? qsTr("This machine is ready")
                          : qsTr("One thing left")
                    pixelSize: 24
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.ready
                          ? qsTr("Everything your agents need to run on %1 is in place.")
                                .arg(MachineSetup.title.length > 0
                                     ? MachineSetup.title
                                     : qsTr("this computer"))
                          : qsTr("Agents run inside containers, so this computer needs an engine to run them in. You can sort it out now or later.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }
        }

        // ---- Everything is in place --------------------------------------
        Reveal {
            step: 1
            Layout.fillWidth: true
            visible: root.ready

            InfoCallout {
                width: parent.width
                glyph: "check-circle"
                tone: Theme.emerald
                title: qsTr("Docker is set up and the agent image is here")
                body: root.runtimeDetail + "\n"
                      + qsTr("Nothing else is needed. Finish, and this machine is ready to be given work.")
            }
        }

        // ---- What is missing, and what can be done about it ---------------
        Reveal {
            step: 1
            Layout.fillWidth: true
            visible: !root.ready

            GlassPanel {
                width: parent.width
                implicitHeight: checks.implicitHeight + 44
                accent: Theme.amber

                ColumnLayout {
                    id: checks
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 22
                    spacing: Theme.spaceMd

                    Repeater {
                        // The rows themselves, so a step that changes is the
                        // same row with new values rather than a new row.
                        model: Preflight.stepList

                        delegate: PreflightStepRow {
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spaceXs
                        spacing: Theme.spaceSm

                        /*
                          One action, chosen by the check rather than here.
                          `PreflightModel::remedy` is the only place that
                          decides what is worth offering, so the button and the
                          line of text above it cannot disagree. A missing
                          Docker is the person's to install, drawn below.
                        */
                        PrimaryButton {
                            visible: Preflight.remedy === "start"
                            text: qsTr("Start Docker")
                            onClicked: Docker.startEngine()
                        }

                        PrimaryButton {
                            visible: Preflight.remedy === "fetch"
                            text: qsTr("Download the agent image")
                            onClicked: Preflight.fetchMissingImages()
                        }

                        GhostButton {
                            visible: Preflight.remedy === "cancel"
                            text: qsTr("Cancel the download")
                            onClicked: Preflight.cancelFetch()
                        }

                        GhostButton {
                            text: qsTr("Check again")
                            enabled: !Preflight.running
                            onClicked: Preflight.run()
                        }
                    }
                }
            }
        }

        // ---- No Docker: the person installs one ------------------------------
        Reveal {
            step: 1
            Layout.fillWidth: true
            visible: !root.ready && Preflight.remedy === "manual"

            GetDockerCard {
                width: parent.width
                graphicsBelow: Preflight.graphics.state === "configurable"
                               && ((Preflight.graphics.commands || []).length > 0
                                   || typeof Preflight.graphics.guide === "string")
            }
        }

        // ---- The graphics card: here, what would make it so, or why not ----
        Reveal {
            step: 1
            Layout.fillWidth: true
            visible: graphicsPanel.known

            GpuOfferPanel {
                id: graphicsPanel
                width: parent.width
                offer: Preflight.graphics
            }
        }

        // ---- What finishing without it means ------------------------------
        Reveal {
            step: 2
            Layout.fillWidth: true
            visible: !root.ready

            InfoCallout {
                width: parent.width
                glyph: "info"
                tone: Theme.amber
                title: qsTr("You can finish without it")
                body: qsTr("This machine will be on your account and you can use the rest of Simorg. Your account will show that it cannot run agents yet, and the reason. Install Docker whenever suits you and run setup again from Settings.")
            }
        }

        Reveal {
            step: 2
            Layout.fillWidth: true
            visible: MachineSetup.lastError.length > 0

            InfoCallout {
                width: parent.width
                glyph: "alert"
                tone: Theme.danger
                title: qsTr("That did not save")
                body: MachineSetup.lastError
            }
        }
    }
}
