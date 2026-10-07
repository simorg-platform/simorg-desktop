// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The slice of this computer one agent runs in, and the form that resizes it.
 *
 * ## Why this is a page of the agent rather than a list under Agents
 *
 * Every slice on this computer is really a fact about the agent holding it, and
 * a list of slices would mean finding your agent in a list you had just come
 * from — so it is here, on the agent, where the question is asked: *what does
 * this one get, and can I give it more?*
 *
 * ## Why the sizing happens on the machine
 *
 * Because the numbers are meaningless anywhere else. Two cores is generous on a
 * laptop and nothing on a build server, and the only place that can say which
 * is the computer itself — which is why every meter here is drawn against what
 * **Docker on this machine** is allowed to use rather than against the hardware
 * or against nothing at all. A slider in a browser is a number typed into a
 * form; a slider here is a share of something you can see.
 *
 * ## Two things happen when it is applied
 *
 * The envelope is saved, and the agent is rebooted onto it. The second is not a
 * convenience: Docker fixes a container's limits when it is created and never
 * revisits them, so an agent whose slot was resized goes on running the old
 * share until its container is *replaced*. See {@link AgentVirtualMachineModel}.
 *
 * ## Named `…Pane` rather than `AgentVirtualMachine`
 *
 * Because `AgentVirtualMachine` is the singleton this file drives, and a QML
 * module cannot hold a component and a singleton under one name — the
 * singleton wins, and the component becomes "not creatable" with no
 * explanation at the point it is used. `AgentAccessPane` next door is named
 * for the same reason.
 *
 * ## Who may
 *
 * Owner or admin of the agent — the platform's answer, read from
 * `AgentLifecycle.canManage`, which is the same predicate the route enforces.
 * Everybody else gets the meters, which is the half that is about *this
 * computer* and belongs to whoever is sitting at it.
 */
Item {
    id: root

    /** The agent's row, handed down by {@link AgentDetail}. */
    property var agent: ({})

    readonly property var row: root.agent && root.agent.agentId > 0
                               ? root.agent
                               : ({
                                     agentId: 0, title: "", slotId: 0, slotCodename: "",
                                     slotTitle: "", envelope: ({})
                                 })

    readonly property bool present: root.row.agentId > 0
    readonly property bool hasSlot: root.present && root.row.slotId > 0

    /**
     * The envelope as the platform last said it, or an empty one.
     *
     * A function rather than a chain of `var` bindings, and read as a function
     * everywhere below. A `var` property bound to another `var` property is
     * evaluated lazily, so reading it from `Component.onCompleted` — which is
     * exactly when this form fills itself in — can land before the binding has
     * ever run and hand back `undefined`. A binding that calls this still takes
     * its dependency on `agent`, because a binding depends on what it *reads*,
     * whichever function does the reading.
     */
    function savedEnvelope() {
        const row = root.agent;
        return row && row.envelope ? row.envelope : ({});
    }

    /** What the meters draw. */
    readonly property var saved: root.savedEnvelope()

    /** Whether this person may change it. The platform's answer, not ours. */
    readonly property bool mayEdit: AgentLifecycle.agentId === root.row.agentId
                                    && AgentLifecycle.canManage

    readonly property bool dockerKnown: Docker.ready && Docker.memoryTotal > 0
    readonly property int dockerCores: Docker.engineCpus
    readonly property real dockerMemoryMb: Docker.memoryTotal / (1024 * 1024)

    // ---- The draft ------------------------------------------------------
    //
    // A copy, not a binding. The sliders move numbers that nobody has agreed to
    // yet, and a form bound straight to the model would either refuse to move
    // or would show a share the agent does not have.

    property real cpuMin: 0.25
    property real cpuMax: 1
    property bool cpuCapped: true
    property real memoryMin: 512
    property real memoryMax: 2048
    property bool memoryCapped: true
    property real storageMin: 2048
    property real storageMax: 10240
    property bool storageCapped: true
    // The graphics card's memory: a ceiling alone, since nothing reserves a card's memory.
    property real gpuMax: 4096
    property bool gpuCapped: false

    /**
     * Whether the graphics card's memory is shown at all: for an agent that
     * asks for the card, or one given a ceiling on it before. A limit on a card
     * the agent is never given limits nothing, and would only be one more
     * slider to wonder about.
     *
     * Recomputed when the requests move rather than bound, as AgentAccessPane
     * does: they are a join of the socket and the platform, which a binding
     * cannot depend on.
     */
    property bool asksForTheCard: false
    readonly property bool showsGraphics: root.asksForTheCard
                                          || root.savedEnvelope().gpuCapped === true

    function readRequests() {
        // From `agent` itself, as savedEnvelope() reads it: `row` may not have run yet.
        const agentId = root.agent && root.agent.agentId > 0 ? root.agent.agentId : 0;
        const requests = agentId > 0 ? AccessGrants.requestsFor(agentId) : [];
        let gpu = false;
        for (let i = 0; i < requests.length; ++i)
            gpu = gpu || requests[i].accessKey === "GPU";
        root.asksForTheCard = gpu;
    }

    /** True once the draft says something different from the saved envelope. */
    readonly property bool dirty: {
        if (!root.hasSlot)
            return false;
        const saved = root.savedEnvelope();
        if (root.cpuMin !== (saved.cpuMin || 0) || root.cpuCapped !== (saved.cpuCapped === true))
            return true;
        if (root.cpuCapped && root.cpuMax !== (saved.cpuMax || 0))
            return true;
        if (root.memoryMin !== (saved.memoryMin || 0)
            || root.memoryCapped !== (saved.memoryCapped === true))
            return true;
        if (root.memoryCapped && root.memoryMax !== (saved.memoryMax || 0))
            return true;
        if (root.storageMin !== (saved.storageMin || 0)
            || root.storageCapped !== (saved.storageCapped === true))
            return true;
        if (root.storageCapped && root.storageMax !== (saved.storageMax || 0))
            return true;
        if (root.gpuCapped !== (saved.gpuCapped === true))
            return true;
        return root.gpuCapped && root.gpuMax !== (saved.gpuMax || 0);
    }

    /**
     * Copies the saved envelope into the draft.
     *
     * Called when the page opens and whenever the platform says the slot has
     * moved — but never over an edit somebody is in the middle of. A resize
     * made in a browser while this form was half filled in would otherwise wipe
     * what they had typed, which is the one thing a form must never do.
     */
    function loadFromAgent() {
        const envelope = root.savedEnvelope();
        root.cpuMin = envelope.cpuMin || 0.25;
        root.cpuCapped = envelope.cpuCapped === true;
        root.cpuMax = envelope.cpuMax || 1;
        root.memoryMin = envelope.memoryMin || 512;
        root.memoryCapped = envelope.memoryCapped === true;
        root.memoryMax = envelope.memoryMax || 2048;
        root.storageMin = envelope.storageMin || 2048;
        root.storageCapped = envelope.storageCapped === true;
        root.storageMax = envelope.storageMax || 10240;
        root.gpuCapped = envelope.gpuCapped === true;
        root.gpuMax = envelope.gpuMax || 4096;
    }

    /** The draft in the vocabulary the meters and the control both speak. */
    function draftEnvelope() {
        return {
            cpuMin: root.cpuMin, cpuMax: root.cpuMax, cpuCapped: root.cpuCapped,
            memoryMin: root.memoryMin, memoryMax: root.memoryMax,
            memoryCapped: root.memoryCapped,
            storageMin: root.storageMin, storageMax: root.storageMax,
            storageCapped: root.storageCapped,
            gpuMax: root.gpuMax, gpuCapped: root.gpuCapped
        };
    }

    onAgentChanged: {
        if (!root.dirty)
            root.loadFromAgent();
        root.readRequests();
    }

    Component.onCompleted: {
        root.loadFromAgent();
        root.readRequests();
        AgentVirtualMachine.forget();
    }

    Connections {
        target: AccessGrants
        function onChanged() { root.readRequests(); }
    }

    /*
      The saved envelope arriving from the platform, which is what an apply
      produces: the PATCH lands, the Hub tells this computer, and the model
      moves under the form. Re-reading it is what turns the sliders from "what
      I asked for" back into "what this agent has".
    */
    Connections {
        target: AgentVirtualMachine
        function onApplied() { resync.start(); }
    }

    Timer {
        id: resync
        // Long enough for the frame to land, and harmless if it already has.
        interval: 400
        onTriggered: root.loadFromAgent()
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: Theme.spaceMd

                // ---- What it has ---------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.hasSlot
                    implicitHeight: has.implicitHeight + 40

                    ColumnLayout {
                        id: has
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "vm"; size: 16; thickness: 1.7; tone: Theme.cyan }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 80
                                spacing: 1

                                ElidedText {
                                    Layout.fillWidth: true
                                    text: root.row.slotTitle.length > 0
                                          ? root.row.slotTitle
                                          : qsTr("Its share of this computer")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                ElidedText {
                                    Layout.fillWidth: true
                                    text: qsTr("A virtual machine is a slice of %1 that this agent's container runs inside.")
                                          .arg(Hub.machineTitle.length > 0
                                               ? Hub.machineTitle : qsTr("this computer"))
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: root.row.slotCodename.length > 0
                                implicitWidth: codename.implicitWidth + 14
                                implicitHeight: 18
                                radius: 4
                                color: Theme.alpha(Theme.cyan, 0.11)
                                border.width: 1
                                border.color: Theme.alpha(Theme.cyan, 0.3)

                                Text {
                                    id: codename
                                    anchors.centerIn: parent
                                    text: root.row.slotCodename
                                    color: Theme.alpha(Theme.cyan, 0.95)
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.family: Theme.monoFamily
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        ResourceMeter {
                            Layout.fillWidth: true
                            label: qsTr("PROCESSOR")
                            glyph: "cpu"
                            tone: Theme.cyan
                            guaranteed: root.saved.cpuMin || 0
                            ceiling: root.saved.cpuMax || 0
                            capped: root.saved.cpuCapped === true
                            available: root.dockerCores
                            known: root.dockerKnown
                            format: function (value) { return Docker.formatCores(value); }
                            unit: qsTr("cores")
                        }

                        ResourceMeter {
                            Layout.fillWidth: true
                            label: qsTr("MEMORY")
                            glyph: "memory"
                            tone: Theme.violet
                            guaranteed: root.saved.memoryMin || 0
                            ceiling: root.saved.memoryMax || 0
                            capped: root.saved.memoryCapped === true
                            available: root.dockerMemoryMb
                            known: root.dockerKnown
                            format: function (value) { return Docker.formatMegabytes(value); }
                        }

                        ResourceMeter {
                            Layout.fillWidth: true
                            label: qsTr("DISK")
                            glyph: "disk"
                            tone: Theme.amber
                            guaranteed: root.saved.storageMin || 0
                            ceiling: root.saved.storageMax || 0
                            capped: root.saved.storageCapped === true
                            // Docker reports what it is *using*, never what it
                            // may use, so a disk bar has no honest denominator.
                            available: 0
                            known: false
                            format: function (value) { return Docker.formatMegabytes(value); }
                        }

                        ResourceMeter {
                            Layout.fillWidth: true
                            visible: root.showsGraphics
                            label: qsTr("GRAPHICS MEMORY")
                            glyph: "gpu"
                            tone: Theme.emerald
                            // Nothing reserves a card's memory, so nothing is guaranteed.
                            hasGuarantee: false
                            uncappedText: qsTr("all the card has")
                            ceiling: root.saved.gpuMax || 0
                            capped: root.saved.gpuCapped === true
                            // Neither Docker nor this service knows the card's size.
                            available: 0
                            known: false
                            format: function (value) { return Docker.formatMegabytes(value); }
                        }
                    }
                }

                // ---- Changing it ---------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.hasSlot && root.mayEdit
                    implicitHeight: form.implicitHeight + 40

                    ColumnLayout {
                        id: form
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceLg

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Change what it gets")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("The guarantee is held for this agent whether or not it is busy. The ceiling is how far it may climb while the machine is quiet, and several agents are allowed to want their ceiling at the same time.")
                                color: Theme.textFaint
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }
                        }

                        ResourcePair {
                            Layout.fillWidth: true
                            label: qsTr("Processor")
                            glyph: "cpu"
                            tone: Theme.cyan
                            steps: AgentVirtualMachine.cpuSteps
                            enabled: !AgentVirtualMachine.busy
                            minimumValue: root.cpuMin
                            maximumValue: root.cpuMax
                            capped: root.cpuCapped
                            format: function (value) { return Docker.formatCores(value); }
                            onMinimumChosen: function (value) { root.cpuMin = value; }
                            onMaximumChosen: function (value, isCapped) {
                                root.cpuMax = value;
                                root.cpuCapped = isCapped;
                            }
                        }

                        ResourcePair {
                            Layout.fillWidth: true
                            label: qsTr("Memory")
                            glyph: "memory"
                            tone: Theme.violet
                            steps: AgentVirtualMachine.memorySteps
                            enabled: !AgentVirtualMachine.busy
                            minimumValue: root.memoryMin
                            maximumValue: root.memoryMax
                            capped: root.memoryCapped
                            format: function (value) { return Docker.formatMegabytes(value); }
                            onMinimumChosen: function (value) { root.memoryMin = value; }
                            onMaximumChosen: function (value, isCapped) {
                                root.memoryMax = value;
                                root.memoryCapped = isCapped;
                            }
                        }

                        ResourcePair {
                            Layout.fillWidth: true
                            label: qsTr("Disk")
                            glyph: "disk"
                            tone: Theme.amber
                            steps: AgentVirtualMachine.storageSteps
                            enabled: !AgentVirtualMachine.busy
                            minimumValue: root.storageMin
                            maximumValue: root.storageMax
                            capped: root.storageCapped
                            format: function (value) { return Docker.formatMegabytes(value); }
                            onMinimumChosen: function (value) { root.storageMin = value; }
                            onMaximumChosen: function (value, isCapped) {
                                root.storageMax = value;
                                root.storageCapped = isCapped;
                            }
                        }

                        ResourcePair {
                            Layout.fillWidth: true
                            visible: root.showsGraphics
                            label: qsTr("Graphics memory")
                            glyph: "gpu"
                            tone: Theme.emerald
                            steps: AgentVirtualMachine.gpuSteps
                            enabled: !AgentVirtualMachine.busy
                            hasGuarantee: false
                            maximumValue: root.gpuMax
                            capped: root.gpuCapped
                            /*
                              Why it is worth capping, and what it cannot do,
                              in one breath: past it the work moves to the
                              processor rather than stopping, Simorg keeps to it
                              because no operating system can divide a card,
                              and a program built to get around it could.
                            */
                            ceilingHint: qsTr("The most of the graphics card's memory it may use. Past it, its work runs on the processor instead — slower, never stopped. Simorg holds it to this, because no operating system can divide a card; a program built to get around it could.")
                            uncappedText: qsTr("all the card has")
                            format: function (value) { return Docker.formatMegabytes(value); }
                            onMaximumChosen: function (value, isCapped) {
                                root.gpuMax = value;
                                root.gpuCapped = isCapped;
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spaceSm

                            Text {
                                Layout.fillWidth: true
                                /*
                                  What the button is about to do, said before it
                                  is pressed rather than apologised for after.
                                  Restarting is not a side effect here: a
                                  container keeps the limits it was built with,
                                  so it is the half that makes the new size real.
                                */
                                text: AgentVirtualMachine.stage === VirtualMachineStage.Saving
                                      ? qsTr("Saving the new size…")
                                    : AgentVirtualMachine.stage === VirtualMachineStage.Rebooting
                                      ? qsTr("Restarting this agent onto it…")
                                    : root.dirty
                                      ? qsTr("Applying this restarts the agent: a container keeps the share it was started with.")
                                      : qsTr("This is what the agent has now.")
                                color: root.dirty ? Theme.textMuted : Theme.textFaint
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }

                            GhostButton {
                                text: qsTr("Reset")
                                visible: root.dirty && !AgentVirtualMachine.busy
                                onClicked: root.loadFromAgent()
                            }

                            PrimaryButton {
                                text: qsTr("Apply and reboot")
                                enabled: root.dirty && !AgentVirtualMachine.busy
                                busy: AgentVirtualMachine.busy
                                onClicked: AgentVirtualMachine.applyAndReboot(
                                               root.row.agentId, root.row.slotId,
                                               root.draftEnvelope())
                            }
                        }
                    }
                }

                // ---- How it went ---------------------------------------
                InfoCallout {
                    Layout.fillWidth: true
                    visible: AgentVirtualMachine.lastError.length > 0
                    glyph: "alert"
                    tone: Theme.danger
                    title: qsTr("That did not apply")
                    body: AgentVirtualMachine.lastError
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: AgentVirtualMachine.lastError.length === 0
                             && AgentVirtualMachine.message.length > 0
                    glyph: "check"
                    tone: Theme.emerald
                    title: qsTr("Applied")
                    body: AgentVirtualMachine.message
                }

                // ---- Not yours to change -------------------------------
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.hasSlot && !root.mayEdit
                    glyph: "shield"
                    tone: Theme.sky
                    title: qsTr("Only an owner or admin can change this")
                    body: qsTr("You are looking at an agent somebody placed on this computer. What it has been given is shown here because it is your machine being used; changing it is a decision for the people who run the agent.")
                }

                /*
                  ---- Nothing to show -----------------------------------

                  Shown whenever there is no slice, which includes the page
                  being open on an agent that has just been taken off this
                  computer. A pane that drew *nothing* in that moment would be
                  a blank screen with a rail beside it, which reads as broken
                  rather than as empty — and the header above has already said
                  the agent has gone.
                */
                InfoCallout {
                    Layout.fillWidth: true
                    visible: !root.hasSlot
                    glyph: "vm"
                    tone: Theme.sky
                    title: root.present
                           ? qsTr("This agent has no slice of this computer")
                           : qsTr("Nothing to show here")
                    /*
                      Not a "coming soon" panel, which is what stood here while
                      this page could only be read. Sizing works now, so the
                      empty state is about *this agent* rather than about the
                      feature: give it a virtual machine on this machine and
                      everything above appears, ready to change.
                    */
                    body: root.present
                          ? qsTr("An agent runs inside a virtual machine: a fixed share of a computer's processor, memory and disk. Give this one a virtual machine on this computer in the browser, and it appears here with everything it was promised.")
                          : qsTr("An agent runs inside a virtual machine: a fixed share of a computer's processor, memory and disk. Open an agent this computer is running to see the share it was given.")
                }
            }
        }
    }
}
