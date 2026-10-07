// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What the agents on this computer have been promised, and what they are doing.
 *
 * The numbers are **the agents' virtual machines, measured against what Docker
 * is allowed to use** — not against the hardware. That distinction is the whole
 * point: an agent's container can only ever have what the engine has, so a
 * computer with 36 GB of memory and 8 GB offered to Docker has 8 GB to divide,
 * and showing the 36 would tell somebody they had room they do not.
 *
 * Committed means the sum of the **guaranteed minimums**. A maximum is headroom
 * several agents may want at once, so adding maxima up would report a machine
 * as full that is mostly idle.
 *
 * This is a page about the agents rather than about the machine: nobody carves
 * a slice out of a laptop for its own sake. A virtual machine exists because an agent needed one, so the
 * capacity question and the agent question are one question, and the meters
 * below are broken down per agent for exactly that reason.
 *
 * ## The agents first, and what they take under them
 *
 * The cards are the top of the page: who is here is the question somebody opens
 * this tab with, and each card is the way into that agent. The resources are
 * below them — the four meters of what has been promised, and then a row per
 * agent saying what it is **using right now** against what it was promised,
 * in the colour its segment has in the meters, so the split bars can be read.
 *
 * "Using right now" is sampled only while this page is on screen
 * (`Docker.watchResources`): it is the container statistics the Docker section
 * reads, added up per agent from the labels the service writes on every
 * container it starts for one.
 */
Item {
    id: root

    /** Asks the shell for Docker's resource settings, the one lever here. */
    signal openDockerResources()
    /** The agent somebody pressed. The browser above turns this into a page. */
    signal opened(int agentId)

    /** How many cards fit, at a minimum comfortable width of ~330. */
    readonly property int columns: Math.max(1, Math.floor((width - 48 + Theme.spaceMd)
                                                          / (330 + Theme.spaceMd)))

    readonly property var slots: Hub.virtualMachines

    // ---- What Docker is allowed to use ---------------------------------
    //
    // Read from the engine rather than from the settings file: this is what the
    // daemon reports it has, which is the number containers are actually
    // limited by, and it is right on Linux too — where there is no virtual
    // machine to size and the engine simply has the host.
    readonly property bool dockerKnown: Docker.ready && Docker.memoryTotal > 0
    readonly property int dockerCores: Docker.engineCpus
    readonly property real dockerMemoryMb: Docker.memoryTotal / (1024 * 1024)

    /**
     * Whether Docker's share is something this computer can change.
     *
     * True on macOS and Windows, where a Linux virtual machine has a size. On
     * Linux the engine runs on the host's own kernel — there is nothing to
     * resize, and offering a link to a slider that does not exist would be a
     * dead end.
     */
    readonly property bool dockerResizable: Docker.limits.managed === true

    /**
     * Whether the platform has said what is on this computer.
     *
     * The count and the list are two views of one answer and normally arrive
     * together; the list is consulted as well so that rows already on screen
     * are never contradicted by a tile claiming nothing has been reported.
     */
    readonly property bool slotsKnown: Hub.virtualMachineCount >= 0 || root.slots.count > 0

    /**
     * One meter segment per virtual machine, coloured by position.
     *
     * The palette is walked rather than hashed from a name: five slices of a
     * laptop want five distinguishable colours far more than they want the same
     * agent to be the same colour on two different machines.
     */
    // Not `palette`: QQuickItem already has one, and shadowing it is a warning
    // on every load and a trap for anything that later reads the real thing.
    readonly property var slotPalette: [Theme.cyan, Theme.violet, Theme.emerald,
                                        Theme.amber, Theme.sky, Theme.rose]

    /*
      The meters, rebuilt rather than bound.

      A binding that walked the rows would take its dependency on the row
      *count* alone: resizing a virtual machine changes every number in it and
      changes no count, so the meters would keep drawing yesterday's split. The
      model says when its contents moved, and that is what these listen to.
    */
    property var cpuSegments: []
    property var memorySegments: []

    function segmentsFor(field) {
        const out = [];
        for (let i = 0; i < root.slots.count; ++i) {
            const machine = root.slots.at(i);
            const value = machine.envelope ? machine.envelope[field] : 0;
            if (value > 0)
                out.push({ value: value, tone: root.slotPalette[i % root.slotPalette.length] });
        }
        return out;
    }

    function rebuildSegments() {
        root.cpuSegments = root.segmentsFor("cpuMin");
        root.memorySegments = root.segmentsFor("memoryMin");
    }

    /**
     * The colour an agent's segment has in the meters, for its row below them.
     *
     * By the position of its virtual machine, which is how the segments are
     * coloured; an agent with no virtual machine yet has no segment, and gets a
     * colour by its own position so its row still has one.
     */
    function swatchFor(agentId, agentRow) {
        for (let i = 0; i < root.slots.count; ++i) {
            if (root.slots.at(i).agentId === agentId)
                return root.slotPalette[i % root.slotPalette.length];
        }
        // A delegate being taken away is told its row is -1, and -1 % 6 is -1 in
        // JavaScript: it still needs a colour for the frame it has left.
        return root.slotPalette[(root.slots.count + (agentRow > 0 ? agentRow : 0)) % root.slotPalette.length];
    }

    /*
      Live statistics while this page is on screen, and not a moment longer.

      The window being hidden to the tray counts as off screen: sampling a
      container every three seconds for a page nobody can see is a laptop's
      battery spent on nothing.
    */
    readonly property bool watching: root.visible && Window.window !== null && Window.window.visible
    onWatchingChanged: Docker.watchResources("agents-overview", root.watching)
    Component.onDestruction: Docker.watchResources("agents-overview", false)

    /** What every agent's containers use now, added up. Zero while nothing is sampled. */
    readonly property var usageTotals: {
        const usage = Docker.agentUsage;
        let cores = 0;
        let memoryMb = 0;
        let sampled = false;
        for (const key in usage) {
            if (usage[key].sampled) {
                sampled = true;
                cores += usage[key].cpuPercent / 100;
                memoryMb += usage[key].memoryBytes / (1024 * 1024);
            }
        }
        return { cores: cores, memoryMb: memoryMb, sampled: sampled };
    }

    /** In hundredths of a core, and "under 0.01" rather than a zero that is not one. */
    function coresText(value) {
        if (value > 0 && value < 0.01)
            return qsTr("under 0.01");
        return Docker.formatCores(value);
    }

    Component.onCompleted: root.rebuildSegments()

    Connections {
        target: Hub.virtualMachines
        function onAggregateChanged() { root.rebuildSegments(); }
    }

    /** `2.5 of 8 cores`, and the same shape for every tile. */
    function ofText(used, total, unit) {
        return unit.length > 0 ? qsTr("%1 of %2 %3").arg(used).arg(total).arg(unit)
                               : qsTr("%1 of %2").arg(used).arg(total);
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
                Layout.margins: 24
                spacing: Theme.spaceMd

                /*
                  ---- One card per agent --------------------------------

                  First on the page: who is here is what somebody opens this
                  tab to find out, and every card is the way into that agent.
                  The resources they take are underneath.

                  The cards are here rather than behind a tab of their own.

                  Two lenses on one list, one click apart, would answer nearly
                  the same question twice. The cards are the ones with a page
                  behind them — what an agent was given, what its container is
                  doing, its log — and a page reachable only from the second of
                  two tabs is a page people do not find.

                  They reflow rather than scale: three across on a wide window,
                  two on a laptop, one on a narrow one, always the same card.
                */
                GridLayout {
                    Layout.fillWidth: true
                    visible: Hub.agents.count > 0
                    columns: root.columns
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    Repeater {
                        model: Hub.agents

                        delegate: AgentTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1 // equal shares, not content widths
                            // Capped, so one agent on a wide screen gets a card
                            // rather than a banner. A tile that stretches to
                            // half a window stops looking like something to
                            // press and starts looking like a section.
                            Layout.maximumWidth: 460

                            onOpened: root.opened(agentId)
                        }
                    }
                }

                // ---- Nothing here yet ----------------------------------
                ComingSoon {
                    Layout.fillWidth: true
                    visible: Hub.agentCount === 0 && Hub.agents.count === 0
                    glyph: "robot"
                    tone: Theme.violet
                    title: qsTr("No agents are placed on this computer")
                    body: qsTr("An agent runs here when it is set to run on a virtual machine backed by this machine. Create one in the browser and point it at a virtual machine on this computer. It appears here as a card with its container already started, and nobody has to sign in again.")
                    points: [
                        qsTr("Placement is decided on the platform, not here"),
                        qsTr("A container is started as soon as an agent arrives"),
                        qsTr("Open a card for that agent's own dashboard and log"),
                        qsTr("Nothing runs when you are signed out")
                    ]
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: Hub.agentCount < 0 && Hub.agents.count === 0
                    glyph: "info"
                    tone: Theme.sky
                    title: qsTr("Waiting for the platform")
                    body: qsTr("This computer has not been told what it is hosting yet. It arrives with the connection, and this page fills in by itself.")
                }
                // ---- What the agents take -------------------------------
                /*
                  The resources, under the agents they belong to.

                  A heading of its own, because this half of the page answers a
                  different question from the cards above it: not who is here,
                  but how much of this computer they have been promised and how
                  much they are using of it now.
                */
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Hub.agents.count > 0 ? Theme.spaceMd : 0
                    spacing: 10

                    Glyph { name: "gauge"; size: 15; thickness: 1.7; tone: Theme.cyan }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: qsTr("Resources")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontBody
                            font.weight: Font.Bold
                        }

                        ElidedText {
                            Layout.fillWidth: true
                            text: qsTr("What each agent has been promised and what it is using now, measured against what Docker may use.")
                            color: Theme.textFaint
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // Live only while the page is open, and it says so.
                    Rectangle {
                        visible: Docker.usageSampled && root.usageTotals.sampled
                        implicitWidth: liveText.implicitWidth + 14
                        implicitHeight: 18
                        radius: 4
                        color: Theme.alpha(Theme.emerald, 0.12)
                        border.width: 1
                        border.color: Theme.alpha(Theme.emerald, 0.3)

                        Text {
                            id: liveText
                            anchors.centerIn: parent
                            text: qsTr("LIVE")
                            color: Theme.alpha(Theme.emerald, 0.95)
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }
                    }
                }

                // ---- What the agents hold ------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    /*
                      Every tile the same height, set on the tiles rather than on
                      the grid.

                      A fixed height here was right at four across and wrong at
                      two: below 1080 the grid wraps to a second row and a
                      height that only ever described one row drew the two on
                      top of each other. Sizing the cells lets the grid be as
                      tall as the rows it actually has, and the four eyebrow
                      labels still sit on one line.
                    */
                    columns: root.width > 1080 ? 4 : (root.width > 640 ? 2 : 1)
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 164
                        label: qsTr("PROCESSOR")
                        glyph: "cpu"
                        tone: Theme.cyan
                        value: !root.dockerKnown
                               ? "—"
                               : root.ofText(Docker.formatCores(root.slots.committedCpuCores),
                                             root.dockerCores, qsTr("cores"))
                        caption: !root.dockerKnown
                                 ? qsTr("waiting for Docker")
                                 : root.slots.count === 0
                                   ? qsTr("no agent has been promised any yet")
                                   : qsTr("guaranteed across %1").arg(
                                         root.slots.count === 1
                                         ? qsTr("1 virtual machine")
                                         : qsTr("%1 virtual machines").arg(root.slots.count))

                        // The promise as a split bar, and under it what they are actually using.
                        Column {
                            spacing: 8

                            MeterBar {
                                width: parent.width
                                height: 8
                                total: Math.max(1, root.dockerCores)
                                segments: root.cpuSegments
                            }

                            ElidedText {
                                width: parent.width
                                text: root.usageTotals.sampled
                                      ? qsTr("%1 cores in use right now").arg(root.coresText(root.usageTotals.cores))
                                      : qsTr("measuring what they use…")
                                color: Theme.textFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 164
                        label: qsTr("MEMORY")
                        glyph: "memory"
                        tone: Theme.violet
                        value: !root.dockerKnown
                               ? "—"
                               : root.ofText(Docker.formatMegabytes(root.slots.committedMemoryMb),
                                             Docker.formatMegabytes(root.dockerMemoryMb), "")
                        caption: !root.dockerKnown
                                 ? qsTr("waiting for Docker")
                               : root.slots.count === 0
                                 ? qsTr("no agent has been promised any yet")
                               : root.slots.anyUncapped
                                 ? qsTr("some may take more while it is free")
                               : qsTr("up to %1 when the machine is quiet")
                                     .arg(Docker.formatMegabytes(root.slots.ceilingMemoryMb))

                        Column {
                            spacing: 8

                            MeterBar {
                                width: parent.width
                                height: 8
                                total: Math.max(1, root.dockerMemoryMb)
                                segments: root.memorySegments
                            }

                            ElidedText {
                                width: parent.width
                                text: root.usageTotals.sampled
                                      ? qsTr("%1 in use right now").arg(Docker.formatMegabytes(root.usageTotals.memoryMb))
                                      : qsTr("measuring what they use…")
                                color: Theme.textFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 164
                        label: qsTr("DISK")
                        glyph: "disk"
                        tone: Theme.amber
                        value: root.slots.committedStorageMb > 0
                               ? Docker.formatMegabytes(root.slots.committedStorageMb)
                               : "—"
                        caption: root.slots.committedStorageMb > 0
                                 ? qsTr("committed to these agents")
                                 : qsTr("no agent has been promised any yet")

                        ElidedText {
                            text: Docker.diskMeasured
                                  ? qsTr("Docker is using %1 on this computer")
                                        .arg(Docker.formatBytes(Docker.diskTotal))
                                  : qsTr("measuring what Docker is using…")
                            color: Theme.textFaint
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    StatTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 164
                        label: qsTr("RUNNING")
                        glyph: "container"
                        tone: Theme.emerald
                        value: Hub.agentCount >= 0 ? String(Hub.agents.runningCount) : "—"
                        caption: Hub.agentCount < 0
                                 ? qsTr("nothing reported yet")
                               : Hub.agents.count === 0
                                 ? qsTr("no agents are placed here")
                               : Hub.agents.runningCount === Hub.agents.count
                                 ? qsTr("every agent's container is up")
                               : qsTr("of %1 placed on this computer").arg(Hub.agents.count)

                        ElidedText {
                            text: !Docker.ready
                                  ? qsTr("Docker is not running")
                                  : root.slotsKnown && root.slots.onlineCount > 0
                                    ? qsTr("%1 with a runtime connected")
                                          .arg(root.slots.onlineCount)
                                    : qsTr("%1 virtual machines on this computer")
                                          .arg(Math.max(0, Hub.virtualMachineCount))
                            color: Theme.textFaint
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                // ---- One row per agent ----------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Hub.agents.count > 0
                    spacing: Theme.spaceSm

                    Repeater {
                        model: Hub.agents

                        delegate: AgentResourceRow {
                            required property int index

                            Layout.fillWidth: true
                            swatch: root.swatchFor(agentId, index)
                            usage: Docker.agentUsage[String(agentId)]
                            sampled: Docker.usageSampled
                            dockerCores: root.dockerCores
                            dockerMemoryMb: root.dockerMemoryMb
                            dockerKnown: root.dockerKnown

                            onOpened: root.opened(agentId)
                        }
                    }
                }

                // ---- Where the ceiling comes from ----------------------
                /*
                  One line naming the hardware, and the one lever that changes
                  what Simorg may use of it.

                  Under the tiles rather than in them: the tiles answer "how much
                  is spoken for", and the machine's own size is the *reason* the
                  denominator is what it is — context for the numbers above, not
                  a fifth number competing with them.
                */
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: ceiling.implicitHeight + 34

                    RowLayout {
                        id: ceiling
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 17
                        spacing: 13

                        Glyph {
                            Layout.alignment: Qt.AlignTop
                            name: "info"
                            size: 16
                            thickness: 1.7
                            tone: Theme.sky
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    const summary = Hub.machineSummary;
                                    if (!(summary.memoryMb > 0))
                                        return qsTr("Simorg can only give an agent what Docker has.");
                                    const size = qsTr("This computer has %1 of memory and %2 cores.")
                                                     .arg(Docker.formatMegabytes(summary.memoryMb))
                                                     .arg(summary.cpuCores);
                                    // The card an agent allowed the graphics card computes on.
                                    const card = summary.graphics.length > 0
                                                 ? " " + qsTr("Its graphics card: %1.").arg(summary.graphics)
                                                 : "";
                                    return size + card + " " + qsTr("Simorg can only give an agent what Docker has.");
                                }
                                color: Theme.textBody
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    visible: root.dockerResizable
                                    text: qsTr("Change its share in")
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }

                                LinkLabel {
                                    visible: root.dockerResizable
                                    text: qsTr("Docker Settings")
                                    pixelSize: 12
                                    onActivated: root.openDockerResources()
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.dockerResizable
                                    text: qsTr("On this system the engine runs on the host's own kernel. There is no share to resize, and a container is limited one at a time.")
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                Item { Layout.fillWidth: root.dockerResizable }

                                /*
                                  No link to a per-agent list, because there is
                                  no list: what each agent was given is a page
                                  of that agent, and the cards below are the way
                                  to it.
                                */
                                Text {
                                    visible: root.slots.count > 0
                                    text: qsTr("Open an agent to see and change its share.")
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
