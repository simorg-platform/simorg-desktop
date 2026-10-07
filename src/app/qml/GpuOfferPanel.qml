// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * What an agent allowed the graphics card computes on here.
 *
 * The service's answer to `GET /v1/docker/gpu`, drawn once for the two places
 * that need it: the Docker page, where somebody looks at what this computer
 * offers, and above an agent's request for the card, where somebody is about
 * to decide on it.
 *
 * ## Why it says so much when there is nothing
 *
 * "No graphics card" on a Mac with an M-series chip reads as a bug. Nearly
 * always it is how Docker runs there — Colima's machine is not a krunkit one,
 * or Docker Desktop cannot lend the Mac's card at all — so the sentence says
 * which, and the commands that would change it are shown exactly as they are
 * typed, selectable and copyable. Simorg never runs them: installing software
 * and replacing somebody's virtual machine is theirs to do.
 *
 * The same panel sits in the check window and the setup wizard, fed by the
 * check's own look, because a computer being set up is
 * the moment to choose a Docker that can lend the card — before there are
 * containers and volumes worth losing to a machine made again.
 */
GlassPanel {
    id: root

    /**
     * `DockerModel.gpu` or `Preflight.graphics`: `state`, `available`, `name`,
     * `detail`, `commands`, `guide`, `deletes_machine`, `at_stake`.
     */
    property var offer: ({})

    /**
     * The service has answered. A screen shows the panel only then: a service
     * older than the graphics card never answers, and a panel waiting forever
     * would be a wait nobody explained.
     */
    readonly property bool known: root.offer !== undefined && root.offer !== null && root.offer.detail !== undefined
    readonly property bool available: root.known && root.offer.available === true
    /**
     * `available`, `configurable`, `unavailable` or `unknown`; a service from
     * before the states is read by `available`.
     */
    readonly property string offerState: !root.known ? "" : typeof root.offer.state === "string"
                                                         ? root.offer.state
                                                         : root.available ? "available" : "unavailable"
    readonly property var commands: root.known && root.offer.commands ? root.offer.commands : []
    /**
     * The commands delete Docker's machine: what of the person's own is
     * in it, said before the commands rather than discovered after them.
     */
    readonly property bool deletesMachine: root.known && root.offer.deletes_machine === true
    readonly property var atStake: root.deletesMachine && root.offer.at_stake ? root.offer.at_stake : null
    readonly property var lost: {
        if (!root.atStake)
            return [];
        const rows = [];
        const add = (names, one, many) => {
            if (names && names.length > 0)
                rows.push((names.length === 1 ? one : many).arg(names.length) + " " + names.join(", "));
        };
        add(root.atStake.containers, qsTr("%1 container:"), qsTr("%1 containers:"));
        add(root.atStake.volumes, qsTr("%1 volume:"), qsTr("%1 volumes:"));
        add(root.atStake.images, qsTr("%1 image:"), qsTr("%1 images:"));
        return rows;
    }

    implicitHeight: content.implicitHeight + 34

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 17
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Colour is status: given, can be set up, or not here.
            Glyph {
                Layout.alignment: Qt.AlignVCenter
                name: "gpu"
                size: 18
                thickness: 1.6
                tone: root.offerState === "available" ? Theme.emerald
                                                 : root.offerState === "configurable" ? Theme.amber : Theme.textFaint
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: qsTr("GRAPHICS CARD")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.3
                }

                /*
                  The card by name, as the service writes it inside a sentence
                  ("the NVIDIA GeForce RTX 4090") and so capitalised to stand on
                  its own. With none to lend, what agents compute on instead:
                  the sentence below says why — a PC with no dedicated card, a
                  Mac with an Intel processor.
                */
                Text {
                    Layout.fillWidth: true
                    text: root.offerState === "available" ? root.offer.name.charAt(0).toUpperCase() + root.offer.name.slice(1)
                          : root.offerState === "configurable" ? qsTr("Can be set up")
                          : root.offerState === "unknown" ? qsTr("Not known yet")
                          : qsTr("None — agents use the processor")
                    color: root.offerState === "available" ? Theme.textPrimary : Theme.textBody
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
            }
        }

        SelectableText {
            Layout.fillWidth: true
            visible: root.known
            text: root.known ? root.offer.detail : ""
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        /*
          What goes with the machine, before the commands that delete it. Only
          the person's own: Simorg's containers and images come back by
          themselves, and an agent's files live on this computer, not in it.
        */
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.deletesMachine
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.atStake === null
                      ? qsTr("These commands delete Docker's machine, and everything in it goes with it.")
                      : root.lost.length === 0
                        ? qsTr("These commands delete Docker's machine. Nothing of yours is in it: Simorg's own containers and images come back by themselves.")
                        : qsTr("These commands delete Docker's machine, and these of yours go with it. Simorg's own come back by themselves; yours do not, so keep what you need first.")
                color: root.lost.length > 0 ? Theme.amber : Theme.textMuted
                font.pixelSize: 12
                font.weight: root.lost.length > 0 ? Font.DemiBold : Font.Normal
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.lost

                delegate: SelectableText {
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    text: modelData
                    color: Theme.textBody
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }

        // One line per command, in order, as typed: no prompt in front, so it pastes whole.
        Repeater {
            model: root.commands

            delegate: Rectangle {
                required property string modelData

                Layout.fillWidth: true
                // A long command wraps rather than hiding its end: the end is usually the part that matters.
                implicitHeight: Math.max(32, line.implicitHeight + 14)
                radius: Theme.radiusSmall
                color: Theme.inset
                border.width: 1
                border.color: Theme.borderSubtle

                SelectableText {
                    id: line
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: copy.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: Theme.alpha(Theme.emerald, 0.95)
                    font.family: Theme.monoFamily
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                }

                CopyAction {
                    id: copy
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    tooltip: qsTr("Copy this command")
                    size: 24
                }
            }
        }

        LinkLabel {
            visible: root.known && typeof root.offer.guide === "string" && root.offer.guide.length > 0
            // Homebrew's page is where the commands above start, not how the card is set up.
            text: root.known && root.offer.guide === "https://brew.sh" ? qsTr("Install Homebrew first")
                                                                     : qsTr("How to set it up")
            onActivated: Qt.openUrlExternally(root.offer.guide)
        }
    }
}
