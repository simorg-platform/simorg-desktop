// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What somebody sees when Docker is not on their computer.
 *
 * The audience for this screen is not a developer. It is somebody who signed up
 * for Simorg, opened the Docker tab because it was there, and has now been told
 * they need software they have never heard of. Everything here is written for
 * that person: no jargon, no "containerisation", no daemon, no images — and an
 * honest account of why it is needed.
 *
 * The bottom of the screen is {@link GetDockerCard}: Simorg installs no Docker,
 * so the person installs one of
 * their choosing, and Simorg finds it once it runs. Below it, the graphics
 * panel names the Docker that would also lend this computer's card.
 */
Item {
    id: root

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 900
                Layout.fillWidth: true
                Layout.margins: 36
                spacing: Theme.spaceLg

                // ---- Hero ----------------------------------------------
                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    RowLayout {
                        width: parent.width
                        spacing: 20

                        // The "beautiful info icon": a layered disc that reads
                        // as an explanation rather than a warning.
                        Item {
                            Layout.alignment: Qt.AlignTop
                            width: 76
                            height: 76

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Theme.alpha(Theme.cyan, 0.07)
                                border.width: 1
                                border.color: Theme.alpha(Theme.cyan, 0.22)
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 54
                                height: 54
                                radius: 8
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Theme.alpha(Theme.cyan, 0.22) }
                                    GradientStop { position: 1.0; color: Theme.alpha(Theme.violet, 0.16) }
                                }
                                border.width: 1
                                border.color: Theme.alpha(Theme.sky, 0.3)
                            }

                            Glyph {
                                anchors.centerIn: parent
                                name: "shield"
                                size: 30
                                thickness: 1.5
                                tone: Theme.sky
                            }

                            // One slow breath, so the icon reads as the thing to
                            // look at first without shouting.
                            SequentialAnimation on scale {
                                running: Theme.motion
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 1.035; duration: 2600; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1.035; to: 1.0; duration: 2600; easing.type: Easing.InOutQuad }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            GradientText {
                                Layout.fillWidth: true
                                text: qsTr("Simorg keeps your computer clean")
                                pixelSize: 27
                                horizontalAlignment: Text.AlignLeft
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Agents need tools to do their work — languages, databases, libraries, whole toolchains. Simorg never installs any of it onto your computer. Each one goes into a sealed box that can be thrown away without a trace.")
                                color: Theme.textBody
                                font.pixelSize: Theme.fontBody
                                wrapMode: Text.WordWrap
                                lineHeight: 1.55
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("The software that runs those boxes is Docker, and it is not on this computer yet.")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSmall
                                wrapMode: Text.WordWrap
                                lineHeight: 1.5
                            }
                        }
                    }
                }

                // ---- Why ------------------------------------------------
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GridLayout {
                        width: parent.width
                        columns: root.width > 800 ? 2 : 1
                        columnSpacing: Theme.spaceMd
                        rowSpacing: Theme.spaceMd

                        Repeater {
                            model: [
                                {
                                    glyph: "shield",
                                    tone: Theme.emerald,
                                    title: qsTr("Nothing lands on your computer"),
                                    body: qsTr("An agent might need Python, a database and twenty libraries. Every one of them lives inside the box, not on your machine. Delete the box and your computer is exactly as it was — nothing left behind, nothing to uninstall.")
                                },
                                {
                                    glyph: "lock",
                                    tone: Theme.sky,
                                    title: qsTr("It cannot reach your files"),
                                    body: qsTr("A box only sees what you hand it. Code you did not write runs without access to your documents, your photos, your passwords, or anything else on this computer. That is the boundary, and it is enforced by your operating system rather than by good manners.")
                                },
                                {
                                    glyph: "gauge",
                                    tone: Theme.amber,
                                    title: qsTr("You decide how much it may use"),
                                    body: qsTr("Set a ceiling on processor, memory and disk, and Docker never goes past it. The rest of your computer stays responsive while work runs, and you can change your mind whenever you like.")
                                },
                                {
                                    glyph: "layers",
                                    tone: Theme.violet,
                                    title: qsTr("The same here as anywhere"),
                                    body: qsTr("Because the box carries everything it needs, work that runs on this computer runs identically on a server. Nothing behaves differently because of what you happen to have installed.")
                                }
                            ]

                            delegate: GlassPanel {
                                id: card
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitHeight: benefit.implicitHeight + 40

                                ColumnLayout {
                                    id: benefit
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 20
                                    spacing: 10

                                    Rectangle {
                                        width: 34
                                        height: 34
                                        radius: 5
                                        color: Theme.alpha(card.modelData.tone, 0.12)
                                        border.width: 1
                                        border.color: Theme.alpha(card.modelData.tone, 0.28)

                                        Glyph {
                                            anchors.centerIn: parent
                                            name: card.modelData.glyph
                                            size: 17
                                            thickness: 1.7
                                            tone: card.modelData.tone
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.title
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.Bold
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.body
                                        color: Theme.textBody
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.5
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- What Docker is ------------------------------------
                Reveal {
                    step: 2
                    Layout.fillWidth: true

                    ColumnLayout {
                        width: parent.width
                        spacing: Theme.spaceSm

                        InfoCallout {
                            Layout.fillWidth: true
                            glyph: "info"
                            tone: Theme.sky
                            title: qsTr("So what is Docker, exactly?")
                            body: qsTr("Docker is the software that runs these sealed boxes — the same engine almost every software company runs, and around for over a decade. It comes in several forms, such as Docker Desktop, OrbStack, Rancher Desktop, Colima or Docker Engine on Linux, each under its own terms. Simorg works with whichever you install, and does not bundle, install or change any of them.")
                        }
                    }
                }

                // ---- Getting it --------------------------------------------
                Reveal {
                    step: 3
                    Layout.fillWidth: true

                    GetDockerCard {
                        width: parent.width
                        graphicsBelow: Preflight.remedy === "manual" && Preflight.graphics.state === "configurable"
                                       && ((Preflight.graphics.commands || []).length > 0
                                           || typeof Preflight.graphics.guide === "string")
                    }
                }

                // The same graphics panel as the checklist's, so the two pages recommend the same Docker.
                Reveal {
                    step: 3
                    Layout.fillWidth: true
                    visible: introGraphics.known

                    GpuOfferPanel {
                        id: introGraphics
                        width: parent.width
                        offer: Preflight.graphics
                    }
                }
            }
        }
    }
}
