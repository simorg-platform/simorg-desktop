// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * Where one agent stands with this computer's permissions, on its Dashboard.
 *
 * Three states, and the card says which one before anything else:
 *
 * | State | What it shows |
 * | --- | --- |
 * | **Waiting** | What the agent is waiting for an answer on — a question nobody has answered, or a folder an allowed request still needs chosen — and one button to the Access management pane, where it is answered |
 * | **All answered** | What was allowed and what was refused, a chip each, and which of those a rule for this computer decided |
 * | **Asks for nothing** | That, in one line |
 * | **Reading** | The agent's row says it asks for something and the answers have not arrived: the count, and that they are being read — never "nothing" |
 *
 * A summary and never the place to answer. What an agent asked for — the
 * folders, the ports, what happens on a no — is in the Access management pane,
 * and a card that could say yes without it would be the way people say yes
 * without reading. So its one action goes there.
 *
 * It is the one place on the Dashboard that counts the requests, and it says
 * which are waiting rather than only how many there are.
 */
GlassPanel {
    id: root

    /** Whose permissions. Zero draws the empty state, which is what a blank dashboard is. */
    property int agentId: 0
    /**
     * How many permissions the agent's own row says it asks for.
     *
     * The answers arrive on a second topic, and until they have the card must
     * not say the agent asks for nothing when its row says otherwise: it says it
     * is still reading them.
     */
    property int askedCount: 0

    /** The Access management pane, where each of these is read and answered. */
    signal review()

    /*
      Re-read rather than bound, as the Access management pane reads them: the
      rows are a join of what the socket said with what the platform stored, and
      neither is something a binding can depend on.
    */
    property var requests: []

    function reload() {
        root.requests = root.agentId > 0 ? AccessGrants.requestsFor(root.agentId) : [];
    }

    onAgentIdChanged: root.reload()
    Component.onCompleted: {
        root.reload();
        // The names and icons come from the catalogue; read it once if nothing has yet.
        if (!MachineCatalog.loaded && !MachineCatalog.loading)
            MachineCatalog.refresh("DESKTOP");
    }

    Connections {
        target: AccessGrants
        function onChanged() { root.reload(); }
    }

    /** The catalogue's name and icon for a permission; its key until the catalogue has been read. */
    function describe(accessKey) {
        const list = MachineCatalog.accessCategories;
        for (let i = 0; i < list.count; ++i) {
            const entry = list.at(i);
            if (entry.accessKey === accessKey)
                return entry;
        }
        return { accessKey: accessKey, label: accessKey, icon: "shield" };
    }

    /*
      What is waiting on the person reading this. A question still open, and an
      allowed folder request with a folder nobody has chosen, which grants
      nothing until one is — the Access management pane counts the two together
      for the same reason.
    */
    function needsFolder(request) {
        return request.effectiveDecision === "allowed" && request.unchosenFolderCount > 0;
    }

    readonly property var waiting: root.requests.filter(function (request) {
        return request.effectiveDecision === "pending" || root.needsFolder(request);
    })
    readonly property var allowed: root.requests.filter(function (request) {
        return request.effectiveDecision === "allowed" && !root.needsFolder(request);
    })
    readonly property var refused: root.requests.filter(function (request) {
        return request.effectiveDecision === "refused";
    })
    readonly property int ruled: root.requests.filter(function (request) {
        return request.ruledByMachine === true && request.effectiveDecision !== "pending";
    }).length

    readonly property string standing: root.requests.length === 0
                                       ? (root.askedCount > 0 ? "reading" : "nothing")
                                       : root.waiting.length > 0 ? "waiting" : "answered"
    readonly property color tone: root.standing === "waiting" ? Theme.amber
                                  : root.standing === "answered" ? Theme.emerald : Theme.textFaint

    accent: root.tone
    implicitHeight: content.implicitHeight + 40

    Behavior on implicitHeight {
        enabled: Theme.motion
        NumberAnimation { duration: Theme.duration(Theme.durBase); easing.type: Easing.OutCubic }
    }

    // The state, as a stripe down the left edge: seen before a word is read.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        radius: 1.5
        color: root.tone
        opacity: root.standing === "nothing" || root.standing === "reading" ? 0.35 : 0.9

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    /** One permission, as a chip: its icon, its name, and a lock when a rule for this computer decided it. */
    component PermissionChip: Rectangle {
        id: chip

        property var request: ({})
        /** The catalogue's entry for it, handed in: an inline component cannot reach the card's own functions. */
        property var meta: ({ label: "", icon: "shield" })
        property color tone: Theme.textMuted
        property string suffix: ""

        implicitWidth: chipRow.implicitWidth + 20
        implicitHeight: 28
        radius: 14
        color: Theme.alpha(chip.tone, 0.09)
        border.width: 1
        border.color: Theme.alpha(chip.tone, 0.28)

        Accessible.role: Accessible.StaticText
        Accessible.name: chipLabel.text

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                name: chip.meta.icon || "shield"
                size: 13
                thickness: 1.6
                tone: chip.tone
            }

            Text {
                id: chipLabel
                anchors.verticalCenter: parent.verticalCenter
                text: chip.suffix.length > 0 ? chip.meta.label + " · " + chip.suffix : chip.meta.label
                color: Theme.textBody
                font.pixelSize: 12
            }

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.request.ruledByMachine === true
                name: "lock"
                size: 11
                thickness: 1.6
                tone: Theme.textFaint
            }
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        anchors.leftMargin: 22
        spacing: Theme.spaceMd

        // ---- Heading: the state, before anything else ----------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 13

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 38
                implicitHeight: 38
                radius: Theme.radiusBase
                color: Theme.alpha(root.tone, 0.11)
                border.width: 1
                border.color: Theme.alpha(root.tone, 0.3)

                Glyph {
                    anchors.centerIn: parent
                    name: root.standing === "answered" ? "check" : "shield"
                    size: 18
                    thickness: 1.7
                    tone: root.tone
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Permissions")
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.standing === "nothing" ? qsTr("Asks for nothing on this computer")
                          : root.standing === "reading"
                            ? (root.askedCount === 1 ? qsTr("Asks for 1 permission · reading your answer…")
                                                     : qsTr("Asks for %1 permissions · reading your answers…").arg(root.askedCount))
                          : root.standing === "answered" ? qsTr("All answered")
                          : root.waiting.length === 1 ? qsTr("1 is waiting for your answer")
                          : qsTr("%1 are waiting for your answer").arg(root.waiting.length)
                    color: root.standing === "waiting" ? Theme.amber : Theme.textMuted
                    font.pixelSize: 12
                    font.weight: root.standing === "waiting" ? Font.DemiBold : Font.Normal
                    wrapMode: Text.WordWrap
                }
            }

            // Settled, or not read yet: the way to the details, where each answer is.
            LinkLabel {
                Layout.alignment: Qt.AlignTop
                visible: root.standing === "answered" || root.standing === "reading"
                text: qsTr("Manage")
                pixelSize: 12
                onActivated: root.review()
            }
        }

        // ---- Waiting: what, why it matters, and the one way to answer ------
        Flow {
            Layout.fillWidth: true
            visible: root.standing === "waiting"
            spacing: 8

            Repeater {
                model: root.waiting

                delegate: PermissionChip {
                    required property var modelData
                    request: modelData
                    meta: root.describe(modelData.accessKey)
                    tone: Theme.amber
                    suffix: root.needsFolder(modelData) ? qsTr("choose a folder") : ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.standing === "waiting"
            spacing: Theme.spaceMd

            Text {
                Layout.fillWidth: true
                text: qsTr("It cannot use these until you answer, so whatever it needs them for waits too. Each one says what it gives the agent before you decide.")
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            PrimaryButton {
                Layout.alignment: Qt.AlignVCenter
                text: qsTr("Review in Access management")
                onClicked: root.review()
            }
        }

        // ---- Settled, or settled beside what waits: allowed and refused -----
        Repeater {
            model: [
                { label: qsTr("ALLOWED"), requests: root.allowed, tone: Theme.emerald },
                { label: qsTr("REFUSED"), requests: root.refused, tone: Theme.textMuted }
            ]

            delegate: RowLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true
                visible: group.modelData.requests.length > 0
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 7
                    Layout.preferredWidth: 70
                    text: group.modelData.label
                    color: Theme.textFaint
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.1
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: group.modelData.requests

                        delegate: PermissionChip {
                            required property var modelData
                            request: modelData
                            meta: root.describe(modelData.accessKey)
                            tone: group.modelData.tone
                        }
                    }
                }
            }
        }

        // Said once, under the chips it explains, and only when a rule decided any of them.
        RowLayout {
            Layout.fillWidth: true
            visible: root.ruled > 0 && root.standing !== "nothing"
            spacing: 7

            Glyph {
                name: "lock"
                size: 11
                thickness: 1.6
                tone: Theme.textFaint
            }

            Text {
                Layout.fillWidth: true
                text: root.ruled === 1
                      ? qsTr("Decided by a rule for every agent on this computer.")
                      : qsTr("%1 decided by rules for every agent on this computer.").arg(root.ruled)
                color: Theme.textFaint
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        // ---- Nothing asked ---------------------------------------------------
        Text {
            Layout.fillWidth: true
            visible: root.standing === "nothing"
            text: qsTr("It works in its own container and reaches Simorg, plus whatever you give every agent under Settings, Access management.")
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }
    }
}
