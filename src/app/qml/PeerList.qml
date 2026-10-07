// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The applications connected to Simorg on this computer, and the decisions kept for
 * them, as `Peers` reads them off the service.
 *
 * An application always runs on this computer, never in an agent's container. One
 * card per open connection: its title and specifier, where it stands, and whether
 * its program was verified. **Allow** answers a question put aside, **Detach**
 * closes the connection and keeps the decision, **Forget** drops the decision so
 * the application is asked again. Below them, every decision kept for a specifier
 * that is not connected now.
 */
ColumnLayout {
    id: root

    spacing: 8

    function stateSentence(state) {
        switch (state) {
        case "attached": return qsTr("Connected");
        case "awaiting_consent": return qsTr("Waiting for you to allow it");
        case "declaring": return qsTr("Connecting");
        case "refused": return qsTr("Refused");
        default: return qsTr("Starting");
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 40
        Layout.topMargin: 14
        text: qsTr("CONNECTED")
        color: Theme.textFaint
        font.pixelSize: Theme.fontEyebrow
        font.weight: Font.ExtraBold
        font.letterSpacing: 1.2
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 40
        Layout.rightMargin: 40
        visible: Peers.count === 0
        text: Peers.listening
              ? qsTr("No application is connected. Applications you run on this computer appear here when they connect to Simorg.")
              : qsTr("Simorg is not accepting applications on this computer.")
        color: Theme.textMuted
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: Peers

        delegate: GlassPanel {
            id: card

            required property string peerId
            required property string title
            required property string specifier
            required property string state
            required property string verification
            required property string verificationDetail

            Layout.fillWidth: true
            Layout.leftMargin: 28
            Layout.rightMargin: 28
            implicitHeight: 62

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: Theme.spaceMd

                Glyph {
                    name: "cube"
                    size: 18
                    thickness: 1.5
                    tone: card.state === "attached" ? Theme.sky : Theme.textMuted
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    ElidedText {
                        Layout.fillWidth: true
                        text: card.title
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    ElidedText {
                        Layout.fillWidth: true
                        text: card.specifier
                        color: Theme.textFaint
                        font.pixelSize: 11
                        font.family: Theme.monoFamily
                        elide: Text.ElideMiddle
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 190
                    spacing: 1

                    Text {
                        text: root.stateSentence(card.state)
                        color: card.state === "awaiting_consent" ? Theme.amber : Theme.textBody
                        font.pixelSize: 12
                    }
                    Text {
                        text: card.verification === "verified" ? qsTr("Verified")
                              : card.verification === "mismatch" ? qsTr("Not the downloaded program")
                                                                 : qsTr("Not verified")
                        color: card.verification === "mismatch" ? Theme.amber : Theme.textFaint
                        font.pixelSize: 11
                    }
                }

                GhostButton {
                    visible: card.state === "awaiting_consent"
                    text: qsTr("Allow")
                    implicitHeight: 30
                    enabled: !Peers.deciding
                    onClicked: Peers.decide(card.peerId, true)
                }
                GhostButton {
                    text: qsTr("Detach")
                    implicitHeight: 30
                    onClicked: Peers.detach(card.peerId)
                }
                GhostButton {
                    // Reading `pairings` makes the binding follow the decisions; `hasDecision` alone would not.
                    visible: Peers.pairings.length > 0 && Peers.hasDecision(card.specifier)
                    text: qsTr("Forget")
                    implicitHeight: 30
                    onClicked: Peers.forget(card.specifier)
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 40
        Layout.topMargin: 10
        visible: Peers.unconnectedPairings.length > 0
        text: qsTr("DECIDED")
        color: Theme.textFaint
        font.pixelSize: Theme.fontEyebrow
        font.weight: Font.ExtraBold
        font.letterSpacing: 1.2
    }

    Repeater {
        model: Peers.unconnectedPairings

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            Layout.leftMargin: 40
            Layout.rightMargin: 40
            spacing: Theme.spaceMd

            ElidedText {
                Layout.fillWidth: true
                text: modelData.specifier
                color: Theme.textBody
                font.pixelSize: 12
                font.family: Theme.monoFamily
                elide: Text.ElideMiddle
            }
            Text {
                text: modelData.allowed ? qsTr("Allowed") : qsTr("Refused")
                color: modelData.allowed ? Theme.textMuted : Theme.rose
                font.pixelSize: 12
            }
            GhostButton {
                text: qsTr("Forget")
                implicitHeight: 28
                onClicked: Peers.forget(modelData.specifier)
            }
        }
    }

    // An error is what gets pasted into a message asking for help.
    SelectableText {
        Layout.fillWidth: true
        Layout.leftMargin: 40
        Layout.rightMargin: 40
        visible: Peers.error !== ""
        text: Peers.error
        color: Theme.rose
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }
}
