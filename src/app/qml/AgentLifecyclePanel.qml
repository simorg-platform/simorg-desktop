// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Start, reboot and stop, on the computer the agent is running on.
 *
 * ## Why it is here as well as in the panel
 *
 * Because this is where somebody already is. The person watching an agent fail
 * to come up is watching it on the machine it failed on, and sending them to a
 * browser to press Start is asking them to change windows to answer a question
 * this window raised.
 *
 * ## Why it asks the platform rather than driving Docker
 *
 * Every button here is a request to the platform, and what comes back down this
 * computer's own socket is what moves the container. A Stop that took the
 * container down locally would leave the platform still holding the agent as
 * running, and the next reconcile would start it again. One decision, one
 * record, one audit row with a name against it. See AgentLifecycleControl.
 *
 * ## Why it is often not drawn at all
 *
 * Owning this computer does not make somebody the agent's owner. A machine lent
 * to a workspace hosts agents whose members its owner is not, and only the
 * platform knows the difference, so the whole panel hangs off `canManage` from
 * its answer. Somebody who may not act on this agent sees no controls rather
 * than controls that refuse them.
 *
 * ## A strip, not a card
 *
 * It sits inside the agent's header on its overview, under who the agent is and
 * beside what state it is in — a decision belongs next to the thing it decides
 * about. It was a card of its own at the top of the page, with a title saying
 * "Start and stop" above three buttons that said the same.
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. */
    required property var agent

    /** Asked before the two that interrupt whatever the agent is doing. */
    signal confirmNeeded(string action, string title, string body, string confirmText)

    /*
      The platform's state, read from the row rather than from the last REST
      answer. Both are the same fact, and only one of them is live: a lifecycle
      frame arriving on the socket updates this row within a second of somebody
      pressing Stop in a browser on the other side of the world.
    */
    readonly property var lifecycle: root.agent && root.agent.lifecycle
                                     ? root.agent.lifecycle : ({})
    readonly property bool online: root.lifecycle.online === true
    readonly property bool present: root.agent !== undefined && root.agent.agentId > 0

    visible: root.present && AgentLifecycle.canManage
    implicitHeight: visible ? body.implicitHeight : 0

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spaceSm

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            /*
              What the platform believes, in a sentence.

              Deliberately the platform's view and not this computer's: the
              buttons act on the platform, so the line beside them has to be the
              state they act on. What the container is doing is shown elsewhere
              on the page, and the two disagreeing is itself worth seeing.

              The reason in the platform's own words when there is one, and not
              wrapped in a sentence of this app's about it: "Stopped from the
              panel" already says who stopped it and why.
            */
            SelectableText {
                Layout.fillWidth: true
                text: root.online
                      ? qsTr("The platform has this agent running.")
                      : (root.lifecycle.reasonLabel && root.lifecycle.reasonLabel.length > 0
                         ? root.lifecycle.reasonLabel + "."
                         : qsTr("The platform has this agent stopped."))
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            BusyRing {
                visible: AgentLifecycle.busy
                running: AgentLifecycle.busy
                size: 16
            }

            PrimaryButton {
                text: qsTr("Start")
                // Nothing to start when the platform already has it running.
                // Reboot is the verb for that case, and it is next door.
                enabled: !root.online && !AgentLifecycle.busy
                busy: AgentLifecycle.busy
                implicitHeight: 34
                onClicked: AgentLifecycle.start()
            }

            GhostButton {
                text: qsTr("Reboot")
                enabled: !AgentLifecycle.busy
                implicitHeight: 34
                onClicked: root.confirmNeeded(
                    "REBOOT",
                    qsTr("Reboot this agent?"),
                    qsTr("Its container is taken down and started again on whichever machine is selected now, so anything it is part way through is lost. This is also how a change of machine takes effect."),
                    qsTr("Reboot"))
            }

            GhostButton {
                text: qsTr("Stop")
                enabled: root.online && !AgentLifecycle.busy
                implicitHeight: 34
                onClicked: root.confirmNeeded(
                    "STOP",
                    qsTr("Stop this agent?"),
                    qsTr("Its container is taken down and nothing starts it again until somebody presses Start. Whoever is talking to this agent will find it has gone quiet."),
                    qsTr("Stop"))
            }
        }

        /*
          The one sentence worth reading after a decision: the platform stored
          it and could not reach the computer holding the container. Nothing
          else here can say that, because only the platform knows which
          computers answered. What the platform said back, and what went wrong,
          are both sentences somebody takes somewhere else. See SelectableText.
        */
        SelectableText {
            Layout.fillWidth: true
            visible: AgentLifecycle.message.length > 0 && AgentLifecycle.lastError.length === 0
            text: AgentLifecycle.message
            color: Theme.textFaint
            font.pixelSize: 12
        }

        SelectableText {
            Layout.fillWidth: true
            visible: AgentLifecycle.lastError.length > 0
            text: AgentLifecycle.lastError
            color: Theme.rose
            font.pixelSize: 12
        }
    }
}
