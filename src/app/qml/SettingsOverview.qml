// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What this installation *is*: its versions, the estate it points at, and the
 * agreement it was installed under.
 *
 * Everything on this page is a fact rather than a control, which is what makes
 * it the overview. The things somebody can change are in the views beside it.
 *
 * The versions are shown together, each under its program's name, because they
 * move separately: simorg-desktop, which is this program; simorg-cli, which is
 * looked for on this computer and is either a version or not installed; simorgm,
 * the machine service; the container an agent runs in, and the engine inside
 * that container. The last three are what the service was built with rather than
 * what Docker holds, so this page says the same thing whether or not the engine
 * is running.
 */
Item {
    id: root

    // Looked for each time the page is shown, so a Simorg CLI installed since is found.
    Component.onCompleted: {
        if (root.visible)
            App.checkCli();
    }
    onVisibleChanged: {
        if (root.visible)
            App.checkCli();
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
                Layout.maximumWidth: 860
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 26
                Layout.bottomMargin: 34
                spacing: Theme.spaceLg

                /*
                  This machine, and the way back into its setup.

                  First on the page because it is about the computer somebody is
                  sitting at rather than about the installation, and because it
                  is the only thing here that does anything. The promise the
                  wizard makes on its last screen — "install Docker whenever
                  suits you and run setup again" — is this button; without it
                  that sentence would name a place that does not exist.
                */
                Reveal {
                    step: 0
                    Layout.fillWidth: true
                    /*
                      This computer as the Hub knows it — the same name the machine
                      card and the Overview show, set by every handshake and moved by
                      every rename. The setup wizard's copy is only read while a
                      wizard is open, so a machine set up long ago had no card here.
                    */
                    visible: Hub.machineId > 0

                    GlassPanel {
                        width: parent.width
                        implicitHeight: machine.implicitHeight + 40

                        ColumnLayout {
                            id: machine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "server"; size: 16; thickness: 1.7; tone: Theme.blue }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("This machine")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                /*
                                  Renamed where it is read: the pencil, or the name
                                  itself. Only the name is sent; the platform moves a
                                  handle it made from the old name and keeps one
                                  somebody chose, and the new name and handle arrive
                                  over the service's Hub socket, as they do on every
                                  other screen showing this machine.
                                */
                                EditableName {
                                    objectName: "machineName"
                                    Layout.fillWidth: true
                                    name: Hub.machineTitle
                                    busy: Hub.renaming
                                    error: Hub.renameError
                                    fieldLabel: qsTr("Machine name")
                                    fieldGlyph: "server"
                                    onRenameRequested: (name) => Hub.renameMachine(name)
                                }

                                ElidedText {
                                    objectName: "machineHandle"
                                    Layout.fillWidth: true
                                    text: Hub.machineCodename
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                    font.family: Theme.monoFamily
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Change what this computer is called, rewrite the readme your agents read, or tell Simorg about a container engine you have installed since.")
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: Theme.spaceSm

                                GhostButton {
                                    text: qsTr("Set this machine up again")
                                    implicitHeight: 34
                                    onClicked: MachineSetup.reopen()
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ---- About -----------------------------------------------
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: about.implicitHeight + 40

                        ColumnLayout {
                            id: about
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "info"; size: 16; thickness: 1.7; tone: Theme.violet }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("About this installation")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.width > 720 ? 2 : 1
                                columnSpacing: Theme.spaceLg
                                rowSpacing: Theme.spaceMd

                                Repeater {
                                    /*
                                      PINNED TO is the content digest the image
                                      name above is checked against before any
                                      container starts. A version says which
                                      image was meant; this says which image it
                                      is, and it is what to compare when two
                                      machines on the same version behave
                                      differently.

                                      It is marked optional because a build may
                                      legitimately ship no pin — the platform is
                                      allowed to name an image this build has
                                      never seen — and a row reading "unknown"
                                      would look like a fault rather than a
                                      choice.

                                      SIMORG-CLI is a fact only once it has been
                                      looked for: blank until then, like every
                                      version the service has not answered yet,
                                      and then its version or not installed,
                                      which there is nothing to copy of.
                                    */
                                    model: [
                                        { label: qsTr("SIMORG-DESKTOP"), value: App.version },
                                        { key: "cli", label: qsTr("SIMORG-CLI"), value: App.cliVersion,
                                          missing: App.cliChecked && !App.cliVersion },
                                        { label: qsTr("SIMORGM"), value: App.serviceVersion },
                                        { label: qsTr("AGENT IMAGE"), value: App.agentImage },
                                        { label: qsTr("PINNED TO"), value: App.agentImageDigest, optional: true },
                                        { label: qsTr("ENGINE"), value: App.engineVersion },
                                        { label: qsTr("ENVIRONMENT"), value: App.environment },
                                        { label: qsTr("PLATFORM API"), value: App.apiEndpoint },
                                        { label: qsTr("HUB"), value: App.hubEndpoint },
                                        { label: qsTr("WEBSITE"), value: App.websiteUrl }
                                    ].filter(fact => !fact.optional || fact.value)

                                    delegate: ColumnLayout {
                                        id: fact
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: fact.modelData.label
                                            color: Theme.textFaint
                                            font.pixelSize: Theme.fontEyebrow
                                            font.weight: Font.ExtraBold
                                            font.letterSpacing: 1.2
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            // The copy button's height, kept when it is hidden, so a row stays level with the one beside it.
                                            Layout.minimumHeight: 24
                                            spacing: 8

                                            ElidedText {
                                                objectName: fact.modelData.key ? "fact-" + fact.modelData.key : ""
                                                Layout.fillWidth: true
                                                text: fact.modelData.missing ? qsTr("Not installed") : fact.modelData.value
                                                color: fact.modelData.missing ? Theme.textFaint : Theme.textBody
                                                font.pixelSize: 12
                                                font.family: Theme.monoFamily
                                                elide: Text.ElideMiddle
                                            }

                                            IconButton {
                                                visible: !fact.modelData.missing
                                                glyph: "copy"
                                                size: 24
                                                tooltip: qsTr("Copy")
                                                onClicked: App.copyToClipboard(fact.modelData.value)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                /*
                  ---- Terms and privacy -----------------------------------

                  Here as well as on the sign-in window, because the sign-in
                  window is the one screen somebody only sees when they are
                  trying to get somewhere else. An agreement they can only
                  reach on the way past is one they cannot go back and read.
                */
                Reveal {
                    step: 2
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: legal.implicitHeight + 40

                        ColumnLayout {
                            id: legal
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "shield"; size: 16; thickness: 1.7; tone: Theme.emerald }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Terms and privacy")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: qsTr("Edition %1").arg(Legal.version)
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    font.family: Theme.monoFamily
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Legal.accepted
                                      ? qsTr("Accepted on this computer on %1. The whole of both documents is in the app, so it can be read again at any time, with or without a network.").arg(
                                            Qt.formatDateTime(Legal.acceptedAt, "d MMMM yyyy"))
                                      : qsTr("This edition has not been accepted on this computer yet. Both documents can be read here in full, with or without a network.")
                                color: Theme.textBody
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Simorg collects anonymous diagnostics to make the product faster and easier to use. They carry no name, no address and no identifier for you or this computer, and paths are removed before anything leaves. A random number links the records made during one run of the application so a fault can be followed; it is kept only in memory and two runs cannot be connected. The privacy notice lists exactly what is measured and what is never included.")
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: Theme.spaceSm

                                GhostButton {
                                    text: qsTr("Agreement")
                                    implicitHeight: 34
                                    onClicked: App.openLegal("terms")
                                }

                                GhostButton {
                                    text: qsTr("Privacy notice")
                                    implicitHeight: 34
                                    onClicked: App.openLegal("privacy")
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
