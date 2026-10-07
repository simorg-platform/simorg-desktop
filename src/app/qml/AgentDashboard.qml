// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "ActivityText.js" as ActivityText

/**
 * One agent's overview: who it is, how it is doing, and where to go next.
 *
 * Laid out the way an overview of one thing is read, top to bottom:
 *
 * | | |
 * | --- | --- |
 * | **The header** | Who the agent is, what state it is in, what it is made of, and — for somebody the platform lets act on it — start, reboot and stop beside that state |
 * | **Its permissions** | What it is waiting for an answer on, with the way to Access management; else what was allowed and refused. See {@link AgentPermissionsCard} |
 * | **Three figures** | Processor and memory **in use now**, each against its guarantee and with the last couple of minutes as a line, and the disk it was promised |
 * | **Its share** and **what runs for it** | The virtual machine as meters against what Docker has, and every container working for it — its runtime, its network gate — with what each is using |
 * | **Lately** and **go to** | The last few things that happened to it, and the rest of its page, one press each |
 *
 * It leads with what the agent is **using**, which is the question somebody
 * opens an agent's page with, and ends with the way from here to the rest of it.
 *
 * The share is the same arithmetic the Agents overview uses, against the same
 * denominator: what Docker has, not the hardware. A number that means something
 * different on two screens of one app is worse than one number.
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. Empty when the agent is gone. */
    required property var agent

    /**
     * The rail of this agent's page, `[{key, label, glyph}]`, for the ways out.
     *
     * Handed down rather than rebuilt, so this page offers exactly the rooms the
     * rail does and never one this agent does not have.
     */
    property var panes: []

    /**
     * Whether there is an agent to draw, derived here rather than passed in.
     *
     * Two bindings on one source do not update together: a parent handing down
     * both `agent` and `present` will, for one evaluation, have set the second
     * and not yet the first — and every read guarded by it then runs against
     * the *old* map. Deriving it from the same object it guards makes that
     * impossible rather than unlikely.
     */
    readonly property bool present: root.agent !== undefined && root.agent.agentId > 0

    signal openDocker()
    /**
     * The page that can change what this agent was given.
     *
     * The meters below are a summary and stay one: sizing is a decision, and it
     * has a page of its own where the form and the consequence — a container
     * that has to be replaced to take a new share — are on the same screen.
     */
    signal openVirtualMachine()
    /** Another pane of this agent's page, by its key. */
    signal openPane(string key)

    /**
     * The agent's row, with every field this page reads guaranteed to exist.
     *
     * Bindings evaluate before an agent is chosen and again after one is taken
     * away, and in both of those moments `agent` is an empty map. Guarding each
     * of the twenty reads individually is twenty chances to miss one — and a
     * missed one is not a wrong value on screen, it is `undefined` assigned to
     * a string property and a QML warning nobody sees until a test fails.
     */
    readonly property var row: root.present ? root.agent : root.blank

    readonly property var blank: ({
        agentId: 0, slug: "", title: "", tagline: "", avatarUrl: "",
        slotId: 0, slotCodename: "", slotTitle: "", resourcesText: "",
        containerName: "", containerStateName: "", containerId: "", containerDetail: "", containerImage: "",
        running: false, hasInitialScript: true, accessRequestCount: 0, envelope: ({}),
        featureKeys: [], lifecycle: ({})
    })

    readonly property var envelope: root.row.envelope || ({})

    /*
      What its container runs: the reference it was made from, as the service
      recorded it. A record that knows only Docker's content id — a container
      listed before the service had its own record of it — says that id, short,
      rather than borrow the name of an image it may not be running. With no
      container at all, the image this computer would run it from: the one the
      service resolved, which `GET /v1/version` names.
    */
    readonly property string imageText: {
        const recorded = root.row.containerImage;
        if (recorded.startsWith("sha256:"))
            return recorded.substring(0, 19);
        if (recorded.length > 0)
            return recorded;
        return App.agentImage.length > 0 ? App.agentImage : qsTr("not named yet");
    }

    // What the container is measured against: Docker's share, not the hardware.
    readonly property bool dockerKnown: Docker.ready && Docker.memoryTotal > 0
    readonly property int dockerCores: Docker.engineCpus
    readonly property real dockerMemoryMb: Docker.memoryTotal / (1024 * 1024)

    /*
      What its containers use, sampled only while this page is on screen.

      The window hidden to the tray counts as off screen. See
      `Docker.watchResources`, which the Agents overview holds the same way
      under its own name, so leaving one does not switch the other off.
    */
    readonly property bool watching: root.visible && root.present
                                     && Window.window !== null && Window.window.visible
    onWatchingChanged: Docker.watchResources("agent-dashboard", root.watching)
    Component.onDestruction: Docker.watchResources("agent-dashboard", false)

    readonly property var usage: root.present ? Docker.agentUsage[String(root.row.agentId)] : undefined
    readonly property bool measured: Docker.usageSampled && root.usage !== undefined && root.usage.sampled === true
    readonly property real usedCores: root.measured ? root.usage.cpuPercent / 100 : 0
    readonly property real usedMemoryMb: root.measured ? root.usage.memoryBytes / (1024 * 1024) : 0

    /** The runtime's own container, as the engine describes it: `Up 2 hours`. */
    readonly property var runtime: {
        const items = root.usage && root.usage.items ? root.usage.items : [];
        for (let i = 0; i < items.length; ++i) {
            if (items[i].type === "AGENT_RUNTIME")
                return items[i];
        }
        return items.length > 0 ? items[0] : null;
    }

    /** In hundredths of a core, and "under 0.01" rather than a zero that is not one. */
    function coresText(value) {
        if (value > 0 && value < 0.01)
            return qsTr("under 0.01");
        return Docker.formatCores(value);
    }

    /** What a container is to this agent, in words, from the label the service wrote. */
    function containerRole(type) {
        switch (type) {
        case "AGENT_RUNTIME": return qsTr("Runtime");
        case "NETWORK_GATE": return qsTr("Network gate");
        case "NESTING_PREPARATION": return qsTr("Preparing");
        case "": return qsTr("Container");
        default: return qsTr("Job");
        }
    }

    /** One line under each way out of this page. */
    function paneHint(key) {
        switch (key) {
        case "workbench": return qsTr("What it shows the people using it");
        case "brain": return qsTr("Its controls");
        case "landing": return qsTr("Its public face");
        case "virtual-machine": return qsTr("Its slice of this computer, and changing it");
        case "access": return qsTr("What it asked this computer for");
        case "logs": return qsTr("Its container's own output, live");
        default: return "";
        }
    }

    /** The rooms this agent is made of, for the header. */
    readonly property var roomNames: {
        const names = [];
        for (let i = 0; i < root.panes.length; ++i) {
            const key = root.panes[i].key;
            if (key === "workbench" || key === "brain" || key === "landing")
                names.push(root.panes[i].label);
        }
        return names;
    }

    readonly property bool wide: root.width > 980

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 22
                spacing: Theme.spaceMd

                // ---- The agent is no longer here ---------------------
                InfoCallout {
                    Layout.fillWidth: true
                    visible: !root.present
                    glyph: "alert"
                    tone: Theme.amber
                    title: qsTr("This agent is not on this computer any more")
                    body: qsTr("It was moved or removed on the platform while this page was open. Its container has been stopped and taken away, and there is nothing left here to show.")
                }

                // ---- Who it is, and the decision about it -------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.present
                    accent: root.row.running ? Theme.emerald : Theme.violet
                    implicitHeight: hero.implicitHeight + 40

                    ColumnLayout {
                        id: hero
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            Avatar {
                                Layout.alignment: Qt.AlignTop
                                initials: root.row.title.length > 0 ? root.row.title.charAt(0).toUpperCase() : "?"
                                remote: root.row.avatarUrl || ""
                                size: 58
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    /*
                                      Never wider than the name, so the state sits beside it, and never
                                      narrower when there is room. Rounded up: a layout places items on
                                      whole pixels, a name is rarely a whole number of them, and capping
                                      at the exact width had the layout round "Tron" down from 40.27 to
                                      40 pixels and elide it to "Tr…" beside a half-empty card.
                                    */
                                    ElidedText {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: Math.ceil(implicitWidth)
                                        text: root.row.title
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontTitle
                                        font.weight: Font.Bold
                                        font.letterSpacing: -0.3
                                        elide: Text.ElideRight
                                    }

                                    AgentStatePill {
                                        containerStateName: root.row.containerStateName
                                        running: root.row.running
                                        lifecycle: root.row.lifecycle
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                ElidedText {
                                    Layout.fillWidth: true
                                    text: "@" + root.row.slug
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                    font.family: Theme.monoFamily
                                    elide: Text.ElideRight
                                }

                                ElidedText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 3
                                    text: root.row.tagline.length > 0 ? root.row.tagline : qsTr("No tagline yet.")
                                    color: root.row.tagline.length > 0 ? Theme.textMuted
                                                                       : Theme.alpha(Theme.textMuted, 0.55)
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // The facts somebody checks first, each a chip.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { glyph: "vm", tone: Theme.cyan,
                                      text: root.row.slotCodename.length > 0
                                            ? qsTr("Runs in %1").arg(root.row.slotCodename)
                                            : qsTr("No virtual machine yet"),
                                      shown: true },
                                    { glyph: "clock", tone: Theme.emerald,
                                      text: root.runtime && root.runtime.status ? root.runtime.status : "",
                                      shown: root.runtime !== null && root.runtime.status.length > 0 },
                                    { glyph: "widgets", tone: Theme.violet,
                                      text: root.roomNames.join(" · "),
                                      shown: root.roomNames.length > 0 }
                                    // What it asked for is the card under this one, which says which are waiting.
                                ]

                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData

                                    visible: chip.modelData.shown
                                    implicitWidth: chipRow.implicitWidth + 18
                                    implicitHeight: 26
                                    radius: 13
                                    color: Theme.alpha(chip.modelData.tone, 0.08)
                                    border.width: 1
                                    border.color: Theme.alpha(chip.modelData.tone, 0.24)

                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Glyph {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: chip.modelData.glyph
                                            size: 12
                                            thickness: 1.6
                                            tone: chip.modelData.tone
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: chip.modelData.text
                                            color: Theme.textBody
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        /*
                          Why the container is in the state it is in, when there
                          is something to say. Not an error banner: most of these
                          are ordinary — an image that has not been fetched yet,
                          an engine that is off.

                          Selectable, because this is the sentence somebody
                          pastes into a search box or a bug report — and on the
                          screen they opened *because* something is wrong, it
                          was the one thing they could not take with them.
                        */
                        SelectableText {
                            Layout.fillWidth: true
                            visible: root.present && root.row.containerDetail.length > 0
                            text: root.row.containerDetail
                            color: AgentState.tone(root.row.containerStateName)
                            font.pixelSize: 12
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: root.present && !root.row.hasInitialScript
                            text: qsTr("This agent has no startup script yet, so its container has nothing to run.")
                            color: Theme.textFaint
                            font.pixelSize: 12
                        }

                        GhostButton {
                            visible: !Docker.ready
                            text: qsTr("Open Docker")
                            implicitHeight: 34
                            onClicked: root.openDocker()
                        }

                        // ---- Starting and stopping it ------------------
                        //
                        // Drawn only for somebody the platform says may act on
                        // this agent; see AgentLifecyclePanel.
                        Rectangle {
                            Layout.fillWidth: true
                            visible: lifecycle.visible
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        AgentLifecyclePanel {
                            id: lifecycle
                            Layout.fillWidth: true
                            agent: root.agent
                            onConfirmNeeded: function (action, title, body, confirmText) {
                                lifecycleConfirm.ask(action, title, body, confirmText);
                            }
                        }
                    }
                }

                // ---- Its permissions: waiting, or answered ------------
                //
                // Straight under who it is, because an unanswered question is
                // what stops an agent working here more often than anything below.
                AgentPermissionsCard {
                    Layout.fillWidth: true
                    visible: root.present
                    agentId: root.row.agentId
                    askedCount: root.row.accessRequestCount || 0
                    onReview: root.openPane("access")
                }

                // ---- Three figures -----------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.present
                    columns: root.width > 640 ? 3 : 1
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    StatTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        label: qsTr("PROCESSOR IN USE")
                        glyph: "cpu"
                        tone: Theme.cyan
                        value: root.measured ? qsTr("%1 cores").arg(root.coresText(root.usedCores)) : "—"
                        caption: !root.row.running ? AgentState.labelFor(root.row.containerStateName, root.row.lifecycle)
                               : !root.measured ? qsTr("measuring…")
                               : qsTr("of %1 guaranteed").arg(Docker.formatCores(root.envelope.cpuMin || 0))

                        Sparkline {
                            height: 30
                            values: root.usage ? root.usage.cpuHistory : []
                            maximum: Math.max(root.envelope.cpuCapped === true ? (root.envelope.cpuMax || 0) : 0,
                                              root.envelope.cpuMin || 0, 0.25)
                            tone: Theme.cyan
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        label: qsTr("MEMORY IN USE")
                        glyph: "memory"
                        tone: Theme.violet
                        value: root.measured ? Docker.formatMegabytes(root.usedMemoryMb) : "—"
                        caption: !root.row.running ? AgentState.labelFor(root.row.containerStateName, root.row.lifecycle)
                               : !root.measured ? qsTr("measuring…")
                               : qsTr("of %1 guaranteed").arg(Docker.formatMegabytes(root.envelope.memoryMin || 0))

                        Sparkline {
                            height: 30
                            values: root.usage ? root.usage.memoryHistory : []
                            maximum: Math.max(root.envelope.memoryCapped === true ? (root.envelope.memoryMax || 0) : 0,
                                              root.envelope.memoryMin || 0, root.usedMemoryMb * 1.2, 64)
                            tone: Theme.violet
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        label: qsTr("DISK PROMISED")
                        glyph: "disk"
                        tone: Theme.amber
                        value: (root.envelope.storageMin || 0) > 0 ? Docker.formatMegabytes(root.envelope.storageMin) : "—"
                        caption: root.envelope.storageCapped === true
                                 ? qsTr("up to %1").arg(Docker.formatMegabytes(root.envelope.storageMax || 0))
                                 : qsTr("no ceiling")
                    }

                }

                // ---- Two columns: what it holds, and what happened ----
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.present
                    columns: root.wide ? 2 : 1
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    // ---- Left: its share, and what runs for it -------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spaceMd

                        GlassPanel {
                            Layout.fillWidth: true
                            implicitHeight: share.implicitHeight + 40

                            ColumnLayout {
                                id: share
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 20
                                spacing: Theme.spaceMd

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Glyph { name: "vm"; size: 16; thickness: 1.7; tone: Theme.cyan }

                                    ElidedText {
                                        Layout.fillWidth: true
                                        text: qsTr("Its share of this computer")
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    // One click to the page that can change it. See the
                                    // signal's own note for why the form is not here.
                                    LinkLabel {
                                        visible: root.row.slotId > 0
                                        text: qsTr("Change")
                                        pixelSize: 12
                                        onActivated: root.openVirtualMachine()
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
                                    guaranteed: root.envelope.cpuMin || 0
                                    ceiling: root.envelope.cpuMax || 0
                                    capped: root.envelope.cpuCapped === true
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
                                    guaranteed: root.envelope.memoryMin || 0
                                    ceiling: root.envelope.memoryMax || 0
                                    capped: root.envelope.memoryCapped === true
                                    available: root.dockerMemoryMb
                                    known: root.dockerKnown
                                    format: function (value) { return Docker.formatMegabytes(value); }
                                }

                                ResourceMeter {
                                    Layout.fillWidth: true
                                    label: qsTr("DISK")
                                    glyph: "disk"
                                    tone: Theme.amber
                                    guaranteed: root.envelope.storageMin || 0
                                    ceiling: root.envelope.storageMax || 0
                                    capped: root.envelope.storageCapped === true
                                    // Docker reports what it is *using*, never what it
                                    // may use, so a disk meter has no honest ceiling to
                                    // draw against; the numbers stand on their own.
                                    available: 0
                                    known: false
                                    format: function (value) { return Docker.formatMegabytes(value); }
                                }
                            }
                        }

                        // ---- What runs for it --------------------------
                        GlassPanel {
                            Layout.fillWidth: true
                            implicitHeight: running.implicitHeight + 40

                            ColumnLayout {
                                id: running
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 20
                                spacing: Theme.spaceSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Glyph { name: "container"; size: 16; thickness: 1.7; tone: Theme.emerald }

                                    ElidedText {
                                        Layout.fillWidth: true
                                        text: qsTr("What runs for it on this computer")
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: root.usage !== undefined
                                        text: root.usage && root.usage.containers === 1
                                              ? qsTr("1 container")
                                              : qsTr("%1 containers").arg(root.usage ? root.usage.containers : 0)
                                        color: Theme.textFaint
                                        font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Theme.borderSubtle
                                }

                                /*
                                  Every container the service started for it, by
                                  the label it wrote: the runtime, the gate that
                                  holds its network, whatever it is preparing. A
                                  name, what it is to the agent, the engine's own
                                  word for how long it has been up, and what it
                                  uses — the four things `docker ps` and
                                  `docker stats` would have been opened for.
                                */
                                Repeater {
                                    model: root.usage && root.usage.items ? root.usage.items : []

                                    delegate: RowLayout {
                                        id: containerRow
                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: 10

                                        StateDot {
                                            state: containerRow.modelData.state === "running" ? "running"
                                                   : containerRow.modelData.state === "restarting" ? "restarting"
                                                   : "exited"
                                            size: 7
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                ElidedText {
                                                    Layout.fillWidth: true
                                                    Layout.maximumWidth: Math.ceil(implicitWidth)
                                                    text: containerRow.modelData.name
                                                    color: Theme.textBody
                                                    font.pixelSize: 12
                                                    font.family: Theme.monoFamily
                                                    elide: Text.ElideMiddle
                                                }

                                                Text {
                                                    text: root.containerRole(containerRow.modelData.type)
                                                    color: Theme.textFaint
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.6
                                                }

                                                Item { Layout.fillWidth: true }
                                            }

                                            ElidedText {
                                                Layout.fillWidth: true
                                                text: containerRow.modelData.status
                                                color: Theme.textFaint
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            visible: containerRow.modelData.sampled
                                            text: qsTr("%1 cores").arg(root.coresText(containerRow.modelData.cpuPercent / 100))
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.monoFamily
                                        }

                                        Text {
                                            visible: containerRow.modelData.sampled
                                            Layout.preferredWidth: 64
                                            horizontalAlignment: Text.AlignRight
                                            text: Docker.formatMegabytes(containerRow.modelData.memoryBytes / (1024 * 1024))
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.monoFamily
                                        }
                                    }
                                }

                                // Before the first reading, and on a computer where
                                // nothing is running for it: the runtime's own facts.
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.usage === undefined
                                    text: !Docker.ready ? qsTr("Docker is not running, so nothing runs for it.")
                                        : root.row.containerId.length === 0
                                          ? qsTr("Its container has not been created on this computer yet.")
                                        : qsTr("Reading what runs for it…")
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    implicitHeight: 1
                                    color: Theme.borderSubtle
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3
                                    columnSpacing: Theme.spaceLg
                                    rowSpacing: Theme.spaceSm

                                    Repeater {
                                        model: [
                                            // Generated by Docker, so it is only known
                                            // once the container exists. The em dash is
                                            // the same placeholder the id below uses.
                                            { label: qsTr("NAME"),
                                              value: root.row.containerName.length > 0
                                                     ? root.row.containerName : "—" },
                                            { label: qsTr("ID"),
                                              value: root.row.containerId.length > 0
                                                     ? root.row.containerId.substring(0, 12) : "—" },
                                            { label: qsTr("IMAGE"), value: root.imageText }
                                        ]

                                        delegate: ColumnLayout {
                                            id: fact
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            spacing: 2

                                            Text {
                                                text: fact.modelData.label
                                                color: Theme.textFaint
                                                font.pixelSize: Theme.fontEyebrow
                                                font.weight: Font.ExtraBold
                                                font.letterSpacing: 1.2
                                            }

                                            /*
                                              Selectable, because these three are the
                                              values somebody is here to take away: a
                                              container's name goes into a `docker`
                                              command, its id into a bug report, the
                                              image reference into a search. Wrapping
                                              shows the whole of it and lets it be
                                              dragged across.
                                            */
                                            SelectableText {
                                                Layout.fillWidth: true
                                                text: fact.modelData.value
                                                color: Theme.textBody
                                                font.pixelSize: 12
                                                font.family: Theme.monoFamily
                                                // An identifier has no spaces to break
                                                // at, so it breaks where it must.
                                                wrapMode: TextEdit.WrapAnywhere
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Right: lately, and the ways out ---------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spaceMd

                        GlassPanel {
                            Layout.fillWidth: true
                            implicitHeight: recent.implicitHeight + 40

                            ColumnLayout {
                                id: recent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 20
                                spacing: Theme.spaceSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Glyph { name: "clock"; size: 16; thickness: 1.7; tone: Theme.sky }

                                    Text {
                                        Layout.fillWidth: true
                                        text: qsTr("Lately")
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: qsTr("newest last")
                                        color: Theme.textFaint
                                        font.pixelSize: 11
                                    }

                                    /*
                                      The whole panel, in one press: the six lines
                                      that go into a bug report — timestamps and
                                      level tags included, which a drag across a
                                      sentence cannot give them.
                                    */
                                    CopyAction {
                                        text: ActivityText.asText(root.recentEntries)
                                        tooltip: qsTr("Copy these lines")
                                        copiedLabel: qsTr("Copied")
                                        size: 24
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Theme.borderSubtle
                                }

                                Repeater {
                                    model: root.recentEntries

                                    delegate: ActivityRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        // Six rows in a column with no selection sheet
                                        // over them, so each answers the pointer itself.
                                        selectable: true
                                        timeText: modelData.timeText
                                        dateText: modelData.dateText
                                        kind: modelData.kind
                                        level: modelData.level
                                        levelTag: modelData.levelTag
                                        message: modelData.message
                                        // The whole panel is about one agent, so
                                        // repeating its handle on every line would be
                                        // the same word forty times.
                                        showSubject: false
                                        agentSlug: ""
                                        virtualMachine: ""
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.recentEntries.length === 0
                                    text: qsTr("Nothing has been recorded for this agent yet.")
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // ---- The rest of its page ----------------------
                        GlassPanel {
                            Layout.fillWidth: true
                            implicitHeight: ways.implicitHeight + 24

                            ColumnLayout {
                                id: ways
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 2

                                Repeater {
                                    model: root.panes.filter(function (pane) { return pane.key !== "dashboard"; })

                                    delegate: Rectangle {
                                        id: way
                                        required property var modelData

                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: Theme.radiusBase
                                        color: wayHover.hovered ? Theme.alpha(Theme.sky, 0.07) : "transparent"

                                        Accessible.role: Accessible.Button
                                        Accessible.name: way.modelData.label

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 12

                                            Glyph {
                                                name: way.modelData.glyph
                                                size: 16
                                                thickness: 1.6
                                                tone: wayHover.hovered ? Theme.sky : Theme.textMuted
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                ElidedText {
                                                    Layout.fillWidth: true
                                                    text: way.modelData.label
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                ElidedText {
                                                    Layout.fillWidth: true
                                                    text: root.paneHint(way.modelData.key)
                                                    color: Theme.textFaint
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Glyph {
                                                name: "arrow-right"
                                                size: 14
                                                thickness: 1.6
                                                tone: wayHover.hovered ? Theme.sky : Theme.textFaint
                                            }
                                        }

                                        HoverHandler {
                                            id: wayHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler { onTapped: root.openPane(way.modelData.key) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * The last few journal entries about this agent.
     *
     * Recomputed on a signal rather than bound, for the reason every list in
     * this app is: a QML binding over a model takes its dependency on the row
     * count, and an entry arriving is a count change only until the journal
     * reaches its cap — after which the count never moves again and the panel
     * would freeze exactly on the machine that has been running longest.
     */
    property var recentEntries: []

    function rebuildRecent() {
        const out = [];
        /*
          Read off `agent`, not off `row` or `present`.

          This runs from `onAgentChanged`, and inside a change handler only the
          property that changed is guaranteed current: the bindings derived from
          it — `present`, and `row` through it — are re-evaluated in an order
          nothing here controls, and reading one of them first gives the value
          from before the agent arrived. The symptom is not a crash; it is a
          panel that is empty for exactly the agent somebody just opened.
        */
        const wanted = root.agent && root.agent.slug ? root.agent.slug : "";
        if (wanted.length === 0) {
            root.recentEntries = out;
            return;
        }
        for (let i = Activity.count - 1; i >= 0 && out.length < 6; --i) {
            const entry = Activity.at(i);
            if (entry.agentSlug === wanted)
                out.unshift(entry);
        }
        root.recentEntries = out;
    }

    onAgentChanged: root.rebuildRecent()
    Component.onCompleted: root.rebuildRecent()

    /*
      Asked before a stop or a reboot, and at the pane's own root rather than
      inside the header: a dialog anchored to a card inside a scrolling column
      would scroll away from the question it is asking.

      A start is not confirmed. It is the one of the three that interrupts
      nothing, and confirming everything is how people learn to click through
      confirmations.
    */
    ConfirmDialog {
        id: lifecycleConfirm
        anchors.fill: parent
        destructive: false

        property string action: ""

        function ask(which, heading, message, label) {
            lifecycleConfirm.action = which;
            lifecycleConfirm.title = heading;
            lifecycleConfirm.body = message;
            lifecycleConfirm.confirmText = label;
            lifecycleConfirm.open();
        }

        onAccepted: {
            if (lifecycleConfirm.action === "STOP")
                AgentLifecycle.stop();
            else if (lifecycleConfirm.action === "REBOOT")
                AgentLifecycle.reboot();
        }
    }

    Connections {
        target: Activity
        function onCountChanged() { root.rebuildRecent(); }
    }
}
