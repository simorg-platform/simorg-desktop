// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The one question an application raises: may it attach?
 *
 * An application always runs on this computer, never inside an agent's container.
 * A person started it, it connected to the Simorg machine service, and until its
 * owner answers it is held — working on its own, with nothing it offers reachable
 * by any agent. The sheet names the application, its specifier and whether the
 * program was verified against what this computer downloaded, and asks once; the
 * answer is kept for the machine on the platform.
 *
 * Closing it without answering puts the question aside: the application keeps
 * waiting, and Artifacts → Applications still offers the answer.
 */
Item {
    id: root

    readonly property var request: Peers.request
    readonly property bool asking: request.peerId !== undefined && request.peerId !== ""

    visible: opacity > 0
    opacity: asking ? 1 : 0
    z: 210

    Behavior on opacity {
        NumberAnimation { duration: Theme.duration(Theme.durFast) }
    }

    function verificationSentence() {
        switch (root.request.verification) {
        case "verified":
            return qsTr("It is the program this computer downloaded for this application.");
        case "mismatch":
            return qsTr("It is not the program this computer downloaded for this application.");
        default:
            return qsTr("Simorg could not confirm which program this is.");
        }
    }

    // Swallows clicks and keys so nothing behind the sheet can be operated while it is up.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.base, 0.72)
        TapHandler { onTapped: Peers.dismissRequest() }
    }

    Keys.onEscapePressed: Peers.dismissRequest()
    focus: root.asking

    GlassPanel {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 480)
        implicitHeight: content.implicitHeight + 44

        TapHandler { onTapped: {} }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            spacing: Theme.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: 13

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 34
                    height: 34
                    radius: 5
                    color: Theme.alpha(root.request.verification === "verified" ? Theme.sky : Theme.amber, 0.13)
                    border.width: 1
                    border.color: Theme.alpha(root.request.verification === "verified" ? Theme.sky : Theme.amber, 0.3)

                    Glyph {
                        anchors.centerIn: parent
                        name: root.request.verification === "verified" ? "info" : "alert"
                        size: 17
                        thickness: 1.7
                        tone: root.request.verification === "verified" ? Theme.sky : Theme.amber
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Allow %1 to connect to Simorg?").arg(root.request.title || "")
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.request.reason === "verification_changed"
                      ? qsTr("You allowed this application before, when its program was verified. The program connecting now is not.")
                      : qsTr("Agents on this computer that include it will be able to send it requests and read its answers.")
                color: Theme.textBody
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.5
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: root.request.specifier || ""
                    color: Theme.textMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
                Text {
                    Layout.fillWidth: true
                    text: root.verificationSentence()
                    color: root.request.verification === "verified" ? Theme.textMuted : Theme.amber
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.fillWidth: true
                visible: Peers.error !== ""
                text: Peers.error
                color: Theme.rose
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: Theme.spaceSm

                Item { Layout.fillWidth: true }

                GhostButton {
                    text: qsTr("Refuse")
                    implicitHeight: 38
                    enabled: !Peers.deciding
                    onClicked: Peers.decide(root.request.peerId, false)
                }

                PrimaryButton {
                    text: qsTr("Allow")
                    implicitHeight: 38
                    enabled: !Peers.deciding
                    onClicked: Peers.decide(root.request.peerId, true)
                }
            }
        }
    }
}
