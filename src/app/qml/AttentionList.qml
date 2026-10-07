// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What is waiting for the person sitting at this computer.
 *
 * ## Why the home screen has one at all
 *
 * An agent that has asked for a permission cannot run until somebody answers,
 * and a tray balloon alone is gone the moment it is dismissed, or missed
 * entirely if the app was started in the background. The question would survive
 * nowhere, and the agent would sit there not running with nothing on screen
 * saying why.
 *
 * This is the surviving copy. It appears when there is something to do and
 * disappears when there is not, which is the whole contract: **it is never a
 * section that sits there empty**. An interface that keeps a permanently
 * visible "Notifications (0)" teaches people to stop looking at it.
 *
 * ## One row per agent, not per request
 *
 * Somebody sits down once and answers everything one agent asked for. Four rows
 * for four permissions of the same agent would be four things to dismiss and
 * one thing to actually do. The count is on the row instead.
 *
 * ## Clicking goes to the agent's own screen
 *
 * Not to the machine-wide access list. An agent arriving for the first time is
 * a question about *that agent*, and landing somebody on a list of rules for
 * the whole computer would make them find it.
 */
ColumnLayout {
    id: root

    /** Asks the shell for one agent's access screen. */
    signal openAgentAccess(int agentId)

    /**
     * The agents with a question on screen, from the grant model.
     *
     * Re-read whenever the model says anything changed. `pendingAgents()` is a
     * function, and a binding that calls one is evaluated once and never again
     * — so the connection below is what keeps this honest, and it is the only
     * place the list is refreshed.
     */
    property var items: []

    function refresh() {
        root.items = AccessGrants.pendingAgents();
    }

    Component.onCompleted: refresh()

    Connections {
        target: AccessGrants
        function onChanged() { root.refresh(); }
    }

    // Gone entirely when there is nothing to do, rather than empty. See above.
    visible: root.items.length > 0
    Layout.fillWidth: true
    spacing: Theme.spaceSm

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        /*
          A bell rather than a warning triangle.

          Nothing has gone wrong: an agent asked its owner a question and the
          question is waiting. A triangle would say something is broken, and the
          next time one appeared for something that *was* broken nobody would
          look twice.
        */
        Glyph {
            name: "bell"
            size: 15
            thickness: 1.7
            tone: Theme.rose
        }

        Text {
            text: qsTr("NEEDS YOUR ATTENTION")
            color: Theme.rose
            font.pixelSize: Theme.fontEyebrow
            font.weight: Font.ExtraBold
            font.letterSpacing: 1.3
        }

        Item { Layout.fillWidth: true }
    }

    Repeater {
        model: root.items

        delegate: GlassPanel {
            id: card
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: line.implicitHeight + 28
            opaque: true

            /*
              The whole card is the target, not a button at the end of it.

              There is exactly one thing to do with this row, and a row that
              looks clickable and answers only at its right-hand edge is a row
              people click twice.
            */
            HoverHandler {
                id: cardHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.openAgentAccess(card.modelData.agentId)
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusBase
                color: cardHover.hovered ? Theme.alpha(Theme.rose, 0.07) : "transparent"
                border.width: 1
                border.color: Theme.alpha(Theme.rose, cardHover.hovered ? 0.4 : 0.22)

                Behavior on color {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }
            }

            RowLayout {
                id: line
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: Theme.spaceMd

                Avatar {
                    size: 30
                    // The agent's own face, and its initials until there is one
                    // — the same mark it carries on its card in the Agents
                    // section, so the two read as the same agent.
                    initials: (card.modelData.agentTitle || "?").trim().charAt(0).toUpperCase()
                    /*
                      Looked up on the roster rather than carried in the row:
                      this list comes from the access overview, which is about
                      permissions and knows nothing about pictures. The agent is
                      on this computer by definition — it is asking for
                      something here — so the roster has it.
                    */
                    remote: {
                        const agent = Hub.agents.byId(card.modelData.agentId);
                        return agent && agent.avatarUrl ? agent.avatarUrl : "";
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    ElidedText {
                        Layout.fillWidth: true
                        text: qsTr("%1 is waiting for permission")
                                .arg(card.modelData.agentTitle)
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        /*
                          The count, and what happens next. "1 request" alone
                          says what is waiting and not what it costs the agent —
                          and the second half is why anybody would stop what
                          they are doing to answer it.
                        */
                        text: card.modelData.pendingCount === 1
                              ? qsTr("It cannot run until you decide what it may do on this computer.")
                              : qsTr("%1 requests. It cannot run until you decide what it may do on this computer.")
                                    .arg(card.modelData.pendingCount)
                        color: Theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Glyph {
                    name: "arrow-right"
                    size: 15
                    thickness: 1.7
                    tone: cardHover.hovered ? Theme.rose : Theme.textFaint
                }
            }
        }
    }
}
