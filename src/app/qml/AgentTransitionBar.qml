// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The strip that says an agent is on its way up or down.
 *
 * ## The ten seconds nothing was said in
 *
 * Pressing Reboot sends a decision to the platform; the platform writes it, the
 * frame comes back down this computer's socket, the container is taken down and
 * created again, and the agent comes back. That is about ten seconds of real
 * work, and until this existed the interface spent them looking exactly as it
 * had before — the same pane, the same rail, a state pill that had not moved
 * yet. Ten silent seconds after pressing a button reads as a button that did
 * nothing, which is how somebody comes to press it three times.
 *
 * So the whole of the agent's space says what is happening, once, across the
 * top. Not the lifecycle panel, which is on one pane of six: whoever pressed
 * Reboot may well have walked over to the Logs to watch it come back, and the
 * answer has to follow them.
 *
 * ## What opens it, and what closes it
 *
 * It opens on a decision this application sent — {@link
 * AgentLifecycleControl::acted} — and also on a container this computer merely
 * *observed* starting, which is what a start pressed in a browser on the other
 * side of the world looks like from here. Both are "this agent is moving", and
 * a person watching does not care which.
 *
 * It closes when the container reaches the state the decision asked for, and
 * that is the part worth being careful about: a reboot passes through `stopped`
 * on its way to `running`, so closing on "anything changed" would flash the
 * strip away halfway through and leave the second half of the wait silent
 * again. Each verb therefore names the state that ends it.
 *
 * Two other things close it. A container state that is a *failure* — Docker
 * refused, the image is not here — ends the wait, because what happens next is
 * an error somebody has to read rather than a spinner. And a timeout, because a
 * strip that waits forever for a frame that is never coming is worse than one
 * that goes away and leaves the state pill to tell the truth.
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. Empty when the agent is gone. */
    property var agent: ({})

    readonly property int agentId: root.agent && root.agent.agentId ? root.agent.agentId : 0
    readonly property string containerStateName:
        root.agent && root.agent.containerStateName ? root.agent.containerStateName : ""
    readonly property string containerId: root.agent && root.agent.containerId ? root.agent.containerId : ""

    /**
     * The container the agent had when a reboot was pressed.
     *
     * A reboot ends in `running`, which is also where it starts, so its state
     * alone cannot say it is over: the old container reads `running` until the
     * decision reaches this computer, and closing on that would say the reboot
     * had finished before it began. It is over when a *different* container is
     * running.
     */
    property string containerBefore: ""

    /**
     * The decision being waited on: `START`, `STOP`, `REBOOT`, or empty.
     *
     * `OBSERVED` is the fourth value and the one nobody asked for: a container
     * that went to `starting` without this application having sent anything.
     */
    property string pending: ""

    /** Seconds since the wait began, for the line that says how long it takes. */
    property int elapsed: 0

    /**
     * How long to wait before giving up on a decision.
     *
     * Generous on purpose. A reboot on a machine that has to pull an image is
     * minutes, not seconds, and a strip that vanished at thirty would be
     * telling somebody their reboot had finished when it had not started.
     */
    readonly property int patienceSeconds: 180

    readonly property bool shown: root.pending.length > 0

    /** The container state that means this decision has landed. */
    function settledState(action) {
        return action === "STOP" ? "stopped" : "running";
    }

    /** States that end the wait because they are something to read, not to await. */
    function isFailure(stateName) {
        return stateName === "failed" || stateName === "conflict"
            || stateName === "image-missing" || stateName === "image-untrusted";
    }

    /**
     * The five decisions this strip knows how to wait for. Anything else is a mistake.
     *
     * `UPDATE` is a reboot of reboot type `UPDATE`: the
     * platform replaced the agent's sources with a newer release and the new
     * container is the one that runs it. It is waited for exactly as a reboot is,
     * and only its words differ.
     */
    readonly property var known: ["START", "STOP", "REBOOT", "UPDATE", "OBSERVED"]

    /** The container's own sentence while it is replaced, which says `Updating:` for an update. */
    readonly property string containerDetail: root.agent && root.agent.containerDetail ? root.agent.containerDetail : ""

    /*
      A decision it does not recognise opens nothing.

      Falling through to the default wording, which says *starting*, would put
      "This agent is starting…" across the page for a decision it did not know —
      a Stop announced in another case than the one compared here, say — and
      wait three minutes for a container that had just been told to stop. A
      strip that says nothing is a missing strip; a strip that says the opposite
      of what is happening is a reason not to believe the next one either.
    */
    function begin(action) {
        if (root.known.indexOf(action) < 0) {
            console.warn("the agent transition strip was given a decision it does not know:", action);
            return;
        }
        root.pending = action;
        root.containerBefore = root.containerId;
        root.elapsed = 0;
        clock.restart();
    }

    function end() {
        root.pending = "";
        root.elapsed = 0;
        clock.stop();
    }

    /*
      Re-asked on every change rather than only on the ones that look relevant.

      The three inputs — the decision, the container's state and the clock —
      move independently and any of them can be the one that ends the wait, so
      there is one function and three things that call it. Three conditions
      spread across three handlers is how one of them ends up missing a case.
    */
    function reconsider() {
        if (root.pending.length === 0)
            return;
        if (root.agentId === 0) {
            root.end();
            return;
        }
        if (root.elapsed >= root.patienceSeconds) {
            root.end();
            return;
        }
        if (root.isFailure(root.containerStateName)) {
            root.end();
            return;
        }
        /*
          A decision is not finished the moment the container reaches the right
          state — it has to have *left* the old one first. A stop pressed on a
          running container would otherwise close this strip on the reading
          taken before the frame had even arrived.

          `starting` is never a settled state, so the guard only has to cover
          the first instant, and one second of grace covers it without the page
          having to model which frame it is waiting for.
        */
        if (root.elapsed < 1)
            return;
        if ((root.pending === "REBOOT" || root.pending === "UPDATE") && root.containerId === root.containerBefore)
            return;
        if (root.containerStateName === root.settledState(root.pending))
            root.end();
    }

    onContainerStateNameChanged: {
        /*
          A container going to `starting` with nothing pending is somebody else
          starting this agent — from a browser, from another machine's panel, or
          this computer reconciling after a reconnect. Worth the same strip.
        */
        if (root.pending.length === 0 && root.containerStateName === "starting")
            root.begin("OBSERVED");
        else
            root.reconsider();
    }

    // A reboot's new container can arrive as a new id on a state that did not move.
    onContainerIdChanged: root.reconsider()

    // A different agent is a different wait. Nothing about the last one carries.
    onAgentIdChanged: root.end()

    Connections {
        target: AgentLifecycle
        function onActed(agentId, action) {
            if (agentId === root.agentId)
                root.begin(action);
        }
    }

    /*
      An update applied from this computer's Settings pane. Only when the
      platform is rebooting the agent to run it: an agent that was stopped stays
      stopped, and there is nothing to wait for.
    */
    Connections {
        target: AgentSettings
        function onUpdated(agentId, rebooted) {
            if (agentId === root.agentId && rebooted)
                root.begin("UPDATE");
        }
    }

    Timer {
        id: clock
        interval: 1000
        repeat: true
        running: root.shown
        onTriggered: {
            root.elapsed += 1;
            root.reconsider();
        }
    }

    readonly property string title: {
        switch (root.pending) {
        case "START":  return qsTr("Starting this agent…");
        case "STOP":   return qsTr("Stopping this agent…");
        case "REBOOT": return qsTr("Restarting this agent…");
        case "UPDATE": return qsTr("Updating this agent…");
        // `OBSERVED`, the one nobody here asked for: a container coming up
        // because somebody started it somewhere else, or updated it from the
        // panel, which the service's own sentence on the row says.
        default:       return root.containerDetail.indexOf("Updating") === 0
                              ? qsTr("This agent is being updated…")
                              : qsTr("This agent is starting…");
        }
    }

    readonly property string detail: {
        switch (root.pending) {
        case "STOP":
            return qsTr("Its container is being taken down. Whoever is talking to it will find it has gone quiet.");
        case "REBOOT":
            return qsTr("Its container is being taken down and created again, which usually takes about ten seconds.");
        case "UPDATE":
            return qsTr("Its container is being made again to run the new release, which usually takes about ten seconds.");
        case "OBSERVED":
            return root.containerDetail.indexOf("Updating") === 0
                   ? qsTr("Somebody updated it to a newer release, and its container is being made again to run it.")
                   : qsTr("Its container is coming up on this computer. Nothing here asked for it, so somebody else did.");
        default:
            return qsTr("Its container is being created and started on this computer, which usually takes about ten seconds.");
        }
    }

    // Stopping is the one that is not amber: nothing is being waited *for*, and
    // a warning colour on an ordinary stop reads as something having gone wrong.
    readonly property color accent: root.pending === "STOP" ? Theme.textMuted : Theme.amber

    /**
     * True only while the closing animation has to run. See `ConnectionBanner`:
     * this strip's height is layout too, and a height left mid-animation by a
     * window that is not being rendered is a band of nothing that never closes.
     * Leaving the layout is a timer's job, because timers do not need a
     * renderer.
     */
    property bool closing: false

    implicitHeight: root.shown ? 52 : 0
    clip: true
    visible: root.shown || root.closing

    onShownChanged: {
        if (root.shown) {
            root.closing = false;
            shut.stop();
        } else {
            root.closing = true;
            shut.restart();
        }
    }

    Timer {
        id: shut
        interval: Theme.duration(Theme.durBase) + 250
        onTriggered: root.closing = false
    }

    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.title + " " + root.detail

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.duration(Theme.durBase)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    Rectangle {
        id: surface
        width: parent.width
        height: 52
        color: Theme.alpha(root.accent, 0.09)
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.alpha(root.accent, 0.3)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            BusyRing {
                Layout.alignment: Qt.AlignVCenter
                running: root.shown
                size: 18
                tone: root.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 80
                spacing: 1

                ElidedText {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                ElidedText {
                    Layout.fillWidth: true
                    text: root.detail
                    color: Theme.textFaint
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            /*
              The clock, once it has been long enough to be worth reading.

              Held back for the first ten seconds because that is how long this
              is *supposed* to take: a counter from zero invites somebody to
              watch it, and what it would be telling them for most of its life
              is that everything is normal.
            */
            Text {
                visible: root.elapsed >= 10
                text: qsTr("%1s").arg(root.elapsed)
                color: Theme.alpha(root.accent, 0.9)
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.family: Theme.monoFamily
            }
        }
    }
}
