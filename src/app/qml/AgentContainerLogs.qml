// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What this agent's container is printing, live.
 *
 * The container's own output, unedited — the other half of the pair, because
 * **Agents → Logs** is what the *platform* asked of this computer and this is
 * what the program it started had to say about it. Neither can answer the
 * other's question, which is why they are two screens rather than one merged
 * stream.
 *
 * The lines themselves are a {@link LogView}, which is the same component the
 * Docker section and the activity log use: dragging highlights, a right click
 * offers to copy, and every line is coloured by the level the engine wrote into
 * it — not by its stream, because the engine writes all of it to stderr. A
 * line that names no level and reached stderr is drawn as an error, because
 * outside the engine's own format that is a crash, almost always; and what an
 * agent had Simorg Desktop write — `userLog` — is drawn as the user's own.
 *
 * ## Its own stream, for as long as the page is open
 *
 * `Docker.agentLogs`, not the Docker section's log. Sharing that one, and
 * closing it whenever this pane left the screen, would empty it on every visit
 * to Logs and stream the backlog in again, the view running from the top to the
 * bottom in front of whoever had just opened it. So the stream is opened when
 * the agent's page is, whichever pane is showing, and closed when the page
 * closes or turns to another agent: coming back to Logs finds the lines where
 * they were, and the view where it was left.
 *
 * **Where the reader was is kept per agent.** Opening another agent's page
 * reloads the stream for that one; coming back to the first puts the view back
 * at its newest line if that is where it was, or on the line somebody had
 * scrolled to. See {@link LogView.captureState}.
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. Empty when the agent is gone. */
    required property var agent
    /** Whether there is an agent to draw. Derived, never passed in — see AgentDashboard. */
    readonly property bool present: root.agent !== undefined && root.agent.agentId > 0
    /** True while this pane is the visible one. Keys go to the lines when it opens. */
    property bool active: false

    signal openDocker()

    /*
      Read through a default, not through a guard.

      This pane is built before an agent is chosen and stays alive after one is
      taken away, and in both moments `agent` is an empty map — so a plain read
      hands `undefined` to a string property. See AgentDashboard, which does the
      same for the same reason.
    */
    readonly property string containerId: root.agent && root.agent.containerId
                                          ? root.agent.containerId : ""
    readonly property string containerName: root.agent && root.agent.containerName
                                            ? root.agent.containerName : ""
    readonly property int agentId: root.agent && root.agent.agentId ? root.agent.agentId : 0

    /** True while the agent page's stream is following *this* container. */
    readonly property bool mine: Docker.agentLogContainerId.length > 0
                                 && Docker.agentLogContainerId === root.containerId

    /** The agent and container whose lines are in the view now. */
    property int shownAgentId: 0
    property string shownContainerId: ""
    /** Where the reader was in each agent's log, by agent id. See LogView.captureState. */
    property var positions: ({})

    /*
      Written down as the reader moves, not when they leave.

      Leaving is an agent id or a container id changing, and by the time a
      handler for either runs the view may already have been handed nothing to
      show — so a position read then would be the empty view's, not theirs.
    */
    function remember() {
        if (root.shownAgentId > 0 && !logs.settling && logs.count > 0)
            root.positions[root.shownAgentId] = logs.captureState();
    }

    Connections {
        target: logs
        function onFollowingChanged() { root.remember(); }
        function onHeldYChanged() { root.remember(); }
    }

    // A word found in a GMT time may not be in the local one: the search reads again.
    Connections {
        target: LogSettings
        function onLocalTimesChanged() { logs.search.restart(); }
    }

    /** This computer's zone as an offset from GMT: `GMT+03:30`. */
    function zoneLabel() {
        const minutes = -new Date().getTimezoneOffset();
        const whole = Math.abs(minutes);
        const pad = function (n) { return n < 10 ? "0" + n : String(n); };
        return "GMT" + (minutes < 0 ? "-" : "+") + pad(Math.floor(whole / 60)) + ":" + pad(whole % 60);
    }

    /*
      Follows this agent's container for as long as its page is open.

      Another agent is a different log, and so is the same agent coming back to
      its page: where the reader was is put back. A container that changed — a
      reboot makes a new one — is a new log, and opens at its newest line.
    */
    function sync() {
        /*
          Read from the row, not from the bindings derived from it: this runs
          from `onContainerIdChanged`, and inside a change handler only the
          property that changed is certain to be current. `mine` still said
          "yes" about the previous agent's container, and the page kept showing
          that agent's log under the next one's name.
        */
        const containerId = root.containerId;
        const agentId = root.agent && root.agent.agentId ? root.agent.agentId : 0;
        if (containerId.length === 0) {
            if (Docker.agentLogContainerId.length > 0)
                Docker.closeAgentLogs();
            return;
        }
        if (Docker.agentLogContainerId === containerId)
            return;
        const newContainer = root.shownAgentId === agentId
                             && root.shownContainerId.length > 0
                             && root.shownContainerId !== containerId;
        if (newContainer)
            delete root.positions[agentId];
        root.shownAgentId = agentId;
        root.shownContainerId = containerId;
        Docker.openAgentLogs(containerId, agentId);
        logs.restoreState(root.positions[agentId]);
    }

    onActiveChanged: {
        // The keys go to the lines when the pane opens, so ⏎ and ⌘F work before
        // anybody has clicked into the log.
        if (root.active)
            logs.forceActiveFocus();
    }
    onContainerIdChanged: root.sync()
    Component.onCompleted: root.sync()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 11

                Glyph { name: "terminal"; size: 15; thickness: 1.7; tone: Theme.sky }

                /*
                  Elided rather than pushing the buttons off the edge.

                  The search box shares this row, and at the narrower window
                  sizes there is not room for it beside a long container name.
                  Never wider than the name itself, so the badge and the count
                  stay beside it; the whole name is its tooltip.
                */
                ElidedText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 60
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text: root.containerName.length > 0 ? root.containerName
                                                        : qsTr("No container")
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.family: Theme.monoFamily
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.mine && Docker.agentLogsFollowing
                    implicitWidth: liveLabel.implicitWidth + 14
                    implicitHeight: 17
                    radius: 4
                    color: Theme.alpha(Theme.emerald, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(Theme.emerald, 0.3)

                    Text {
                        id: liveLabel
                        anchors.centerIn: parent
                        text: qsTr("LIVE")
                        color: Theme.alpha(Theme.emerald, 0.95)
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }

                /*
                  How much is here, and whether that is all there was.

                  The second half is the point. This read "5000 lines" for ever
                  on any container that had printed more than five thousand,
                  with nothing anywhere saying that the beginning had been
                  dropped — so a number that had stopped moving looked like a
                  log that had stopped, rather than a window at its limit. The
                  limit is a setting now; this is where somebody finds out there
                  is one. See Settings → Logging.
                */
                Text {
                    readonly property bool full: Docker.agentLogs.capacity > 0
                                                 && Docker.agentLogs.count >= Docker.agentLogs.capacity

                    visible: root.mine
                    text: full ? qsTr("%1 lines · oldest dropped").arg(Docker.agentLogs.count)
                               : qsTr("%1 lines").arg(Docker.agentLogs.count)
                    color: full ? Theme.alpha(Theme.amber, 0.85) : Theme.textFaint
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                // Offered only when it does something: the button is how you
                // get back to following after scrolling away.
                GhostButton {
                    visible: root.mine && !logs.following
                    text: qsTr("Jump to newest")
                    implicitHeight: 28
                    implicitWidth: 130
                    font.pixelSize: 11
                    onClicked: logs.jumpToNewest()
                }

                /*
                  The search, in the header rather than behind a button.

                  Finding a word is most of why anybody reads a container's
                  output, so the box is always here, and ⌘F in the lines lands
                  in it too — see LogView.searchField. Usable whenever the
                  stream is this container's, before its first line as well: a
                  word typed while the log is still waiting is marked when it
                  arrives.
                */
                LogSearchBar {
                    id: findBox
                    objectName: "logSearchField"

                    Layout.fillWidth: true
                    Layout.minimumWidth: 160
                    Layout.preferredWidth: 280
                    Layout.maximumWidth: 280

                    toolbar: true
                    search: logs.search
                    enabled: root.mine
                    onCloseRequested: logs.forceActiveFocus()
                }

                CopyAction {
                    text: root.mine && Docker.agentLogs.count > 0
                          ? Docker.agentLogs.toPlainText(LogSettings.localTimes) : ""
                    tooltip: qsTr("Copy everything")
                    copiedLabel: qsTr("%1 lines copied").arg(Docker.agentLogs.count)
                    size: 28
                }

                IconButton {
                    glyph: "trash"
                    enabled: root.mine && Docker.agentLogs.count > 0
                    tooltip: qsTr("Clear this view")
                    size: 28
                    onClicked: Docker.agentLogs.clear()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }

        // ---- Times -------------------------------------------------------
        /*
          Which clock the times in the lines are on, and a box to change it.

          The engine stamps every line in GMT, which is right for comparing two
          computers and wrong for "what happened at ten past three". Ticking the
          box rewrites each line's time into this computer's own zone — on
          screen, in the search and on the clipboard alike, because what is
          copied is what was read. Only once there is a line with a time to move.
        */
        Item {
            objectName: "logTimesRow"
            visible: root.mine && Docker.agentLogs.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 34 : 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    objectName: "logTimesHint"
                    Layout.fillWidth: true
                    text: LogSettings.localTimes
                          ? qsTr("Log times are in your local timezone, %1.").arg(root.zoneLabel())
                          : qsTr("Log times are in the original GMT timezone.")
                    color: Theme.textFaint
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                SimorgCheckBox {
                    objectName: "logTimesBox"
                    checked: LogSettings.localTimes
                    text: qsTr("Show the log in my local timezone")
                    onToggled: function (checked) { LogSettings.localTimes = checked; }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }

        // ---- Lines -------------------------------------------------------
        LogView {
            id: logs

            Layout.fillWidth: true
            Layout.fillHeight: true

            // Only while the shared stream is ours. Somebody else's container's
            // output under this agent's name would be a lie.
            /*
              The page's own feed, whenever this agent has a container. Not only
              while it is `mine`: during the moment one agent's page turns into
              another's the lines are still the first one's, and that is when
              where the reader was is worth reading.
            */
            model: root.containerId.length > 0 ? Docker.agentLogs : null
            // Read through the times switch, so the search and every copy see
            // the line as it is drawn.
            textAt: function (index) {
                return LogSettings.localTimes ? Docker.agentLogs.localLineAt(index)
                                              : Docker.agentLogs.lineAt(index);
            }
            toneAt: function (index) { return Docker.agentLogs.toneAt(index); }
            allText: function () { return Docker.agentLogs.toPlainText(LogSettings.localTimes); }

            // The one log in this application somebody is most likely to be
            // reading in order to find something: a container's whole output,
            // as long as its cap allows. Searched from the box in the header.
            searchable: true
            searchField: findBox

            // Space somebody makes with ⏎, and space kept under the newest line
            // so the end of the log reads as the end.
            blankLineOnEnter: root.mine
            onBlankLineRequested: Docker.agentLogs.appendBlankLine()
            trailingLines: 3

            clearable: root.mine
            onClearRequested: Docker.agentLogs.clear()

            /*
              Every reason there is nothing to show, told apart.

              A container that has not printed anything yet, a container that
              does not exist, and an engine that is not running look identical
              on an empty screen — and only one of the three is something the
              person can do anything about.
            */
            emptyState: Component {
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 400)
                    spacing: 10

                    BusyRing {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.mine && Docker.agentLogsFollowing
                        running: root.mine && Docker.agentLogsFollowing
                        size: 20
                        tone: Theme.alpha(Theme.sky, 0.7)
                    }

                    Glyph {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.mine
                        name: !Docker.ready ? "alert" : "terminal"
                        size: 22
                        thickness: 1.5
                        tone: Theme.alpha(Theme.textMuted, 0.6)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: !root.present ? qsTr("This agent is not on this computer any more")
                            : !Docker.ready ? qsTr("Docker is not running")
                            : root.containerId.length === 0
                              ? qsTr("This agent has no container yet")
                            : qsTr("Waiting for output…")
                        color: Theme.textBody
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: !root.present ? ""
                            : !Docker.ready
                              ? qsTr("A container's output comes from the engine, so there is nothing to read until it is up.")
                            : root.containerId.length === 0
                              ? (root.present && root.agent.containerDetail
                                 ? root.agent.containerDetail
                                 : qsTr("Its container has not been created on this computer yet."))
                            : qsTr("The container is up and has not printed anything since it started.")
                        color: Theme.textFaint
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    GhostButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !Docker.ready
                        text: qsTr("Open Docker")
                        implicitHeight: 32
                        onClicked: root.openDocker()
                    }
                }
            }
        }
    }
}
