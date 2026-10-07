// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * This computer, as Simorg now knows it.
 *
 * The one thing on the dashboard that is about the machine rather than the
 * account, and it earns the space because it is the only place a person can see
 * what was registered on their behalf. Signing in enrolled this box; the least
 * the app can do is show what it said about it.
 *
 * The codename is shown beside the title because it is what an agent's
 * configuration will name, and because it was derived rather than chosen — the
 * first time somebody sees `adas-macbook-pro` it should be here, not in an
 * error message.
 */
GlassPanel {
    id: root

    readonly property bool online: Hub.connected

    implicitHeight: body.implicitHeight + 36

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            /*
              The platform, not a generic server box.

              Every machine card looked identical until this: the same outline
              whether the host was a Mac, a Windows desktop or a Raspberry Pi.
              What the box actually is is the first thing somebody wants from a
              machine card, and the machine reports it. A host that has never
              reported one still gets the plain computer.
            */
            OsLogo {
                osName: Hub.machineSummary.osName
                size: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                ElidedText {
                    Layout.fillWidth: true
                    text: Hub.machineTitle.length > 0 ? Hub.machineTitle
                                                      : qsTr("This machine")
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                ElidedText {
                    Layout.fillWidth: true
                    visible: Hub.machineCodename.length > 0
                    text: Hub.machineCodename
                    color: Theme.textFaint
                    font.family: Theme.monoFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // A dot and a word, not a dot alone: "green" means nothing to
            // somebody who has not been told what green means here.
            RowLayout {
                spacing: 6

                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: root.online ? Theme.emerald : Theme.textFaint

                    SequentialAnimation on opacity {
                        running: root.online && Theme.motion
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.35; duration: 1100; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.35; to: 1; duration: 1100; easing.type: Easing.InOutQuad }
                    }
                }

                Text {
                    text: root.online ? qsTr("Online") : Hub.statusText
                    color: root.online ? Theme.emerald : Theme.textFaint
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderSubtle
        }

        /*
          The spec, exactly as it was reported.

          Read off the same object the handshake sends, so what is on screen and
          what the platform was told cannot drift — the commonest support
          conversation about a machine page starts with somebody comparing the
          two.
        */
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 24
            rowSpacing: 8

            Repeater {
                model: {
                    const summary = Hub.machineSummary;
                    const rows = [
                        { label: qsTr("Operating system"),
                          value: summary.osName + " " + summary.osVersion },
                        { label: qsTr("Architecture"), value: summary.architecture },
                        { label: qsTr("Processor"),
                          value: summary.cpuModel.length > 0
                                 ? summary.cpuModel
                                 : qsTr("%1 cores").arg(summary.cpuCores) },
                        { label: qsTr("Memory"), value: summary.memory }
                    ];
                    /*
                      A row per graphics card, its memory under its name — the
                      card decides what a model can run here more than anything
                      else on this card. Numbered only when there is more than
                      one; "None" only when the service asked and found none,
                      never for a service too old to ask.
                    */
                    const cards = summary.gpus || [];
                    for (let index = 0; index < cards.length; ++index) {
                        rows.push({ label: cards.length === 1 ? qsTr("Graphics card")
                                                              : qsTr("Graphics card %1").arg(index + 1),
                                    value: cards[index].model,
                                    hint: cards[index].memory });
                    }
                    if (cards.length === 0 && summary.gpusKnown)
                        rows.push({ label: qsTr("Graphics card"), value: qsTr("None") });
                    rows.push({ label: qsTr("Storage"), value: summary.storage },
                              { label: qsTr("Location"), value: summary.timezone });
                    return rows;
                }

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    // Top-aligned: a cell with a line under its value is taller than the one beside it.
                    Layout.alignment: Qt.AlignTop
                    visible: String(modelData.value).trim().length > 0
                    spacing: 1

                    Text {
                        text: modelData.label
                        color: Theme.textFaint
                        font.pixelSize: 10
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.1
                        font.capitalization: Font.AllUppercase
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: modelData.value
                        color: Theme.textBody
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // The caveat a value needs: a graphics card's memory.
                    ElidedText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: modelData.hint || ""
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
