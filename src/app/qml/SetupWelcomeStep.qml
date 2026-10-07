// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The first screen anybody sees on a computer they have just signed in on.
 *
 * ## What it is for
 *
 * Signing in on this computer added it to the account as a **machine**, and
 * that is a thing that has just happened to somebody without them asking for
 * it. Two sentences of explanation here are worth more than any amount of
 * documentation later: what a machine is, what it will be used for, and what
 * the next two screens are going to ask.
 *
 * ## The line that earns the screen
 *
 * "This computer will not appear on your account until you give it a name." It
 * is the platform's actual rule, and it is the reason to do the next screen rather than close the window. A
 * wizard that did not say it would be a wizard people dismiss, and then wonder
 * where their machine went.
 */
Item {
    id: root

    /*
      Sized by the column, which is anchored rather than filling.

      An Item is not a layout and does not take a height from what is anchored
      inside it, so without this the step measures zero — and the wizard's
      scrolling area, which is measured from the step, has nothing to scroll.
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
                spacing: Theme.spaceSm

                PulseHex {
                    Layout.alignment: Qt.AlignHCenter
                    size: 92
                }

                GradientText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: qsTr("This computer is now a machine")
                    pixelSize: 26
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Signing in here added %1 to your account. A machine is a computer you lend to your agents: they run on it, inside containers, using only the processor, memory and disk you allow them.")
                          .arg(MachineSetup.deviceName.length > 0
                               ? MachineSetup.deviceName
                               : qsTr("this computer"))
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.55
                }
            }
        }

        /*
          Three lines about what a machine actually is, laid out as a list
          rather than as a paragraph. Somebody meeting the idea for the first
          time reads three short claims; the same content as prose is read by
          nobody.
        */
        Reveal {
            step: 1
            Layout.fillWidth: true

            GlassPanel {
                width: parent.width
                implicitHeight: points.implicitHeight + 44

                ColumnLayout {
                    id: points
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 22
                    spacing: Theme.spaceMd

                    Repeater {
                        model: [
                            {
                                glyph: "robot",
                                tone: Theme.blue,
                                title: qsTr("Agents work here"),
                                body: qsTr("Anything you place on this machine runs on it, in a container of its own, and stops when you say so.")
                            },
                            {
                                glyph: "shield",
                                tone: Theme.emerald,
                                title: qsTr("You decide what it may touch"),
                                body: qsTr("An agent gets the folders and the resources you grant it here, and nothing else on this computer.")
                            },
                            {
                                glyph: "layers",
                                tone: Theme.violet,
                                title: qsTr("You say what it is for"),
                                body: qsTr("The name and the readme you write next are what your agents read to understand this machine.")
                            }
                        ]

                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                width: 34
                                height: 34
                                radius: 7
                                color: Theme.alpha(modelData.tone, 0.13)
                                border.width: 1
                                border.color: Theme.alpha(modelData.tone, 0.3)

                                Glyph {
                                    anchors.centerIn: parent
                                    name: modelData.glyph
                                    size: 18
                                    thickness: 1.65
                                    tone: modelData.tone
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.body
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSmall
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.5
                                }
                            }
                        }
                    }
                }
            }
        }

        Reveal {
            step: 2
            Layout.fillWidth: true

            InfoCallout {
                width: parent.width
                glyph: "info"
                tone: Theme.amber
                title: qsTr("Two short steps, and then you are done")
                body: qsTr("First give this machine a name and say what it is for. Then Simorg checks that it can run containers. This computer will not appear on your account until you have named it.")
            }
        }
    }
}
