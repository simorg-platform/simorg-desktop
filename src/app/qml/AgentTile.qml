// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One agent, as a card you can open.
 *
 * The tile answers three questions and stops: who is this, is it up, and what
 * was it given. Everything else — the container id, the image, the permissions
 * it asked for, its log — is a click away on the agent's own page, because a
 * grid whose cards each carry twelve facts is a table with worse alignment.
 *
 * The whole card is the target, not a button in the corner of it. A card that
 * looks like a link and only works in one small place is a card people learn to
 * distrust.
 *
 * ## Start, where the agent waits for it
 *
 * An agent placed on this computer does nothing until somebody presses Start,
 * so a card whose agent is not running offers Start for
 * a person who may give it — an owner or admin of the agent, as the Hub says on
 * the row and moves the moment a role changes. It goes through the platform like
 * the agent's own page does; the control stays busy until the platform's frame
 * says the agent runs, and a refusal is said on the card in the platform's words.
 */
GlassPanel {
    id: root

    required property int agentId
    required property string slug
    required property string title
    required property string tagline
    /** The agent's picture, as the platform addresses it; empty for one with none. */
    required property string avatarUrl
    required property string slotCodename
    required property string resourcesText
    required property string containerStateName
    required property bool running
    required property int accessRequestCount
    /** The row's lifecycle: whether the platform means it to run, and why not. */
    required property var lifecycle
    /** Whether the person signed in here may start and stop it. */
    required property bool canManage

    signal opened()

    implicitHeight: 196
    accent: root.running ? Theme.emerald : Theme.violet
    // GlassPanel already knows how to look pressable; this is the one place
    // that has to say it is.
    interactive: true
    hovered: hover.hovered
    // Lifted a shade on hover, so a grid of them reads as a set of things to
    // press rather than a set of things to look at.
    scale: hover.hovered ? 1.012 : 1

    Behavior on scale {
        enabled: Theme.motion
        NumberAnimation {
            duration: Theme.durFast
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    /** The state's colour and wording; see {@link AgentState}. */
    readonly property color stateTone: AgentState.tone(root.containerStateName)
    readonly property string stateText: AgentState.labelFor(root.containerStateName, root.lifecycle)

    /** Start is offered where the platform does not have the agent running and this person may start it. */
    readonly property bool offersStart: root.canManage && !root.running
                                        && !!root.lifecycle && root.lifecycle.online !== true
    readonly property bool startBusy: AgentContainers.starting.indexOf(root.agentId) >= 0
    readonly property string startError: AgentContainers.startErrors[String(root.agentId)] || ""

    Accessible.role: Accessible.Button
    Accessible.name: root.title
    Accessible.description: qsTr("Open this agent")

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Avatar {
                initials: root.title.length > 0 ? root.title.charAt(0).toUpperCase() : "?"
                remote: root.avatarUrl
                size: 38
                glow: hover.hovered ? 1 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                ElidedText {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: "@" + root.slug
                    color: Theme.textFaint
                    font.pixelSize: 11
                    font.family: Theme.monoFamily
                    elide: Text.ElideRight
                }
            }

            StateDot {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 4
                state: root.running ? "running" : AgentState.dot(root.containerStateName)
                size: 8
            }
        }

        ElidedText {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            text: root.tagline.length > 0
                  ? root.tagline
                  : qsTr("No tagline yet.")
            color: root.tagline.length > 0 ? Theme.textMuted
                                           : Theme.alpha(Theme.textMuted, 0.55)
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Glyph { name: "vm"; size: 13; thickness: 1.6; tone: Theme.alpha(Theme.cyan, 0.85) }

            Text {
                text: root.slotCodename.length > 0 ? root.slotCodename : qsTr("no slot")
                color: Theme.textBody
                font.pixelSize: 11
                font.family: Theme.monoFamily
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.resourcesText
                color: Theme.textFaint
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            // The state as a word, not a colour alone: green means nothing to
            // somebody who has not been told what green means here.
            Text {
                text: root.stateText
                color: root.stateTone
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        /*
          Always drawn, including when the answer is "nothing".

          An empty request list means the agent asked for *nothing* — a bare
          container and no more. It is not "unspecified", and a card that simply
          omitted the line would leave somebody to guess which of the two it
          was. It also keeps every card the same height, which is what makes a
          grid of them read as a grid.
        */
        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Glyph {
                name: root.accessRequestCount > 0 ? "shield" : "check"
                size: 12
                thickness: 1.6
                tone: root.accessRequestCount > 0 ? Theme.violet : Theme.textFaint
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.startError.length > 0
                      ? root.startError
                    : root.accessRequestCount === 0
                      ? qsTr("Asks for nothing on this computer")
                    : root.accessRequestCount === 1
                      ? qsTr("Asks for 1 permission on this computer")
                    : qsTr("Asks for %1 permissions on this computer")
                          .arg(root.accessRequestCount)
                color: root.startError.length > 0 ? Theme.rose
                     : root.accessRequestCount > 0 ? Theme.alpha(Theme.violet, 0.9)
                     : Theme.textFaint
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            PrimaryButton {
                objectName: "agentTileStart"
                visible: root.offersStart || root.startBusy
                text: qsTr("Start")
                busy: root.startBusy
                implicitHeight: 26
                implicitWidth: 78
                font.pixelSize: 12
                Accessible.name: qsTr("Start %1").arg(root.title)
                onClicked: AgentContainers.start(root.agentId)
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler { onTapped: root.opened() }
}
