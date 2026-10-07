// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What **this** agent may do on this computer.
 *
 * The per-agent half of access management, and the half where questions are
 * answered. The machine-wide screen under **Settings → Access management** sets
 * rules that apply to everything placed here; this is where one agent's own
 * requests are read and decided, and where the folders it asked for are chosen.
 *
 * ## Why the notification lands here
 *
 * An agent arriving on this computer for the first time is a question about
 * *that agent*. Opening the machine-wide list instead would put somebody on a
 * screen headed "rules for this computer", which is about something else, and
 * make them find the thing they were told about.
 *
 * ## A rule is reported, never overridden
 *
 * Where a machine-wide rule is in force, the row says so and offers no buttons.
 * That is the difference between a rule and a suggestion, and the link goes to
 * the one screen where it can be changed.
 */
Item {
    id: root

    /**
     * Which agent this is about. Zero is a real state, not an unset one.
     *
     * Deliberately not `required`: zero means no agent is open, which is what
     * this renders as "nothing has been asked", and that is exactly the state
     * the interface test instantiates every screen in. A required property
     * would make the pane unloadable there and cost the coverage.
     */
    property int agentId: 0
    property string agentTitle: ""

    /** Asks the shell for the machine-wide rules screen. */
    signal openMachineRules()

    /*
      Re-read rather than bound.

      The rows are a join of what the socket said with what the platform stored,
      and neither is something a QML binding can depend on. One explicit reload
      per change is honest about that; a binding would go stale silently.
    */
    property var requests: []
    property string problem: ""

    /**
     * Which permissions this agent's requests are about.
     *
     * What decides which notes are drawn: each says what an answer to that
     * permission does to the agent's container, and only above a screen that
     * asks for it — a note about folders above a request for the network would
     * be about something nobody is deciding.
     *
     * Recomputed in reload() rather than bound, for the same reason the list is:
     * `requests` is a join of the socket and the platform, and neither is
     * something a binding can depend on.
     */
    property bool hasFolderRequest: false
    property bool hasNetworkRequest: false
    property bool hasApplicationsRequest: false
    property bool hasGpuRequest: false

    function reload() {
        root.requests = AccessGrants.requestsFor(root.agentId);

        let folders = false;
        let network = false;
        let applications = false;
        let gpu = false;
        for (let i = 0; i < root.requests.length; ++i) {
            const request = root.requests[i];
            folders = folders || request.aboutFolders;
            network = network || request.accessKey === "NETWORK";
            applications = applications || request.accessKey === "APPLICATIONS";
            gpu = gpu || request.accessKey === "GPU";
        }
        root.hasFolderRequest = folders;
        root.hasNetworkRequest = network;
        root.hasApplicationsRequest = applications;
        root.hasGpuRequest = gpu;
        if (gpu)
            Docker.refreshGpu();
    }

    onAgentIdChanged: root.reload()

    // One handler: QML allows a single `onVisibleChanged` per object, and two
    // declarations silently keep only the last.
    onVisibleChanged: {
        if (!visible)
            return;
        MachineCatalog.refresh("DESKTOP");
        root.reload();
    }

    Component.onCompleted: root.reload()

    Connections {
        target: AccessGrants
        function onChanged() { root.reload(); }
        function onSaveFailed(message) { root.problem = message; }
    }

    /** The catalogue row for a permission, for its words and its icon. */
    function describe(accessKey) {
        const list = MachineCatalog.accessCategories;
        for (let i = 0; i < list.count; ++i) {
            const entry = list.at(i);
            if (entry.accessKey === accessKey)
                return entry;
        }
        // A permission the catalogue has not been fetched for yet, or one this
        // build is behind on. The key is shown rather than a blank row.
        return { accessKey: accessKey, label: accessKey, icon: "shield", sensitivity: "MEDIUM" };
    }

    function toneFor(level) {
        switch (level) {
        case "HIGH": return Theme.rose;
        case "MEDIUM": return Theme.amber;
        default: return Theme.sky;
        }
    }

    ScrollView {
        id: pane
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: pane.availableWidth
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 820
                Layout.fillWidth: true
                Layout.margins: 26
                spacing: Theme.spaceLg

                // ---- Heading -------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("What this agent may do here")
                        color: Theme.textPrimary
                        font.pixelSize: 19
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Answers you give here are about this agent on this computer, and nothing else. They do not follow it onto anybody else's machine.")
                        color: Theme.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        lineHeight: 1.45
                    }
                }

                /*
                  What answering a folder request actually does, said before it
                  is done rather than after.

                  Two facts a person needs at the moment they press Allow, and
                  both are consequences of a container's mounts being fixed when
                  it is created. The folder is real, at a path they will
                  recognise; and the agent stops and starts again to get it,
                  because there is no way to hand a folder to a container that
                  is already running.

                  Only for a screen that has a folder request on it.
                */
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.hasFolderRequest
                    glyph: "folder"
                    tone: Theme.amber
                    title: qsTr("A folder you allow is given to this agent")
                    // A Linux container has no drive letters, so on Windows the
                    // path inside is another one, and the sentence says which.
                    body: (Qt.platform.os === "windows"
                           ? qsTr("It is mounted into the container under the name a Linux container gives a Windows folder, so D:\\project is /d/project inside, as it says under each folder, and read only or read and write is enforced by Docker.")
                           : qsTr("It is mounted into the container at the same path it has on this computer, so /Users/you/project is /Users/you/project inside as well, and read only or read and write is enforced by Docker."))
                          + " " + qsTr("Nothing else on this disk is reachable. If the agent is working when you answer, its container is made again so the change reaches it, and whatever it was in the middle of stops.")
                }

                /*
                  What answering a network request does, for the same reasons.

                  The agent's container is behind a firewall of its own — a gate
                  container it shares a network with, which holds the rules and
                  the DNS — and the one thing that is never a question is Simorg
                  itself, so it is said first. A network is fixed when a
                  container is made, exactly like its folders.
                */
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.hasNetworkRequest
                    glyph: "network"
                    tone: Theme.amber
                    title: qsTr("The network you allow is this agent's firewall")
                    body: qsTr("Simorg itself is always reachable, or the agent could not work. Everything else it reaches is what you allow here: the sites it names, the whole internet, your local network, the ports others may connect to. Cloud metadata addresses are never reachable, and neither is anything you did not allow, jobs and builds the agent starts included. If the agent is working when you answer, its container is made again so the change reaches it.")
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.hasApplicationsRequest
                    glyph: "logos"
                    tone: Theme.sky
                    title: qsTr("An application you allow is one this agent can use")
                    body: qsTr("Only Simorg applications you installed and connected on this computer, and only those this answer allows. Whatever this agent sends to any other application is not passed on, and nothing another application says reaches it.")
                }

                /*
                  What answering a request for the graphics card does, and —
                  because the answer is worth nothing on a computer that has
                  no card to lend — what this computer would give it.
                */
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.hasGpuRequest
                    glyph: "gpu"
                    tone: Theme.sky
                    title: qsTr("The graphics card you allow is one this agent computes on")
                    body: qsTr("It is given to the agent's container for calculation only, so a model it runs answers several times faster; it cannot see or draw on your screen. Without it the agent uses the processor and everything still works, more slowly. If the agent is working when you answer, its container is made again so the change reaches it.")
                }

                GpuOfferPanel {
                    Layout.fillWidth: true
                    visible: root.hasGpuRequest && known
                    offer: Docker.gpu
                }

                /*
                  And the one it may always use, asked for or not.

                  On every agent's screen rather than only above a request for
                  applications: an agent that asked for none still uses Simorg
                  Desktop, and this is the screen somebody reads to find out
                  what an agent may touch here.
                */
                AlwaysAllowedApplication {
                    Layout.fillWidth: true
                }

                // ---- Something went wrong ------------------------------
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.problem.length > 0
                    glyph: "alert"
                    tone: Theme.amber
                    title: qsTr("That could not be saved")
                    body: root.problem
                }

                // ---- Nothing asked -------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 30
                    visible: root.requests.length === 0
                    spacing: Theme.spaceMd

                    Glyph {
                        Layout.alignment: Qt.AlignHCenter
                        name: "shield"
                        size: 30
                        thickness: 1.4
                        tone: Theme.textFaint
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("This agent has not asked for anything")
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        /*
                          Not "nothing else of this computer": the machine-wide
                          folder list is given to every agent placed here,
                          including the ones that never asked. An empty screen
                          that implied otherwise would be the app hiding a mount
                          from the person who set it.
                        */
                        text: qsTr("It runs in a container with its own working folder and reaches Simorg and nothing else, plus whatever you give every agent under Settings, Access management. What an agent needs is decided when its virtual machine is set up, so if that changes it will appear here.")
                        color: Theme.textMuted
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.5
                    }
                }

                // ---- The requests --------------------------------------
                Repeater {
                    model: root.requests

                    delegate: GlassPanel {
                        id: card
                        required property var modelData
                        required property int index

                        readonly property var meta: root.describe(modelData.accessKey)
                        readonly property bool ruled: modelData.ruledByMachine === true
                        readonly property bool pending: modelData.effectiveDecision === "pending"
                        readonly property bool allowed: modelData.effectiveDecision === "allowed"

                        Layout.fillWidth: true
                        implicitHeight: body.implicitHeight + 38

                        ColumnLayout {
                            id: body
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 19
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 13

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    width: 38
                                    height: 38
                                    radius: 5
                                    color: Theme.alpha(root.toneFor(card.meta.sensitivity), 0.11)
                                    border.width: 1
                                    border.color: Theme.alpha(root.toneFor(card.meta.sensitivity), 0.28)

                                    Glyph {
                                        anchors.centerIn: parent
                                        name: card.meta.icon || "shield"
                                        size: 18
                                        thickness: 1.6
                                        tone: root.toneFor(card.meta.sensitivity)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: card.meta.label || modelData.accessKey
                                        color: Theme.textPrimary
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: String(modelData.reason || "").length > 0
                                        text: qsTr("“%1”").arg(modelData.reason)
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // The verdict, whoever gave it.
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    visible: !card.pending
                                    implicitWidth: verdict.implicitWidth + 20
                                    implicitHeight: 24
                                    radius: 5
                                    readonly property color tone: card.allowed ? Theme.emerald
                                                                               : Theme.textMuted
                                    color: Theme.alpha(tone, 0.12)
                                    border.width: 1
                                    border.color: Theme.alpha(tone, 0.3)

                                    Text {
                                        id: verdict
                                        anchors.centerIn: parent
                                        text: card.allowed ? qsTr("Allowed") : qsTr("Refused")
                                        color: parent.tone
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.6
                                    }
                                }
                            }

                            /*
                              ---- Decided for this agent by a rule ---------

                              Reported rather than offered. A machine-wide rule
                              that a per-agent screen could talk over would be a
                              suggestion, and the link goes to the one place it
                              can actually be changed.
                            */
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: card.ruled
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Theme.borderSubtle
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 9

                                    Glyph {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 2
                                        name: "lock"
                                        size: 14
                                        thickness: 1.7
                                        tone: Theme.textMuted
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.machineRule === "ALWAYS_ALLOW"
                                              ? qsTr("A rule for this computer allows this for every agent, so this one was not asked.")
                                              : qsTr("A rule for this computer refuses this for every agent, so this one cannot be granted here.")
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.45
                                    }

                                    LinkLabel {
                                        Layout.alignment: Qt.AlignTop
                                        text: qsTr("Change the rule")
                                        onActivated: root.openMachineRules()
                                    }
                                }

                                /*
                                  A rule answers *may it*, not *which*.

                                  An allowed folder request whose folders nobody
                                  has chosen still has nothing in it, and saying
                                  so is the difference between a screen that is
                                  finished and one that looks finished.
                                */
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 23
                                    visible: modelData.machineRule === "ALWAYS_ALLOW"
                                             && modelData.unchosenFolderCount > 0
                                    text: modelData.unchosenFolderCount === 1
                                          ? qsTr("It still needs a folder, which the rule cannot choose for you. Open the details to pick one.")
                                          : qsTr("It still needs %1 folders, which the rule cannot choose for you. Open the details to pick them.")
                                                .arg(modelData.unchosenFolderCount)
                                    color: Theme.amber
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                /*
                                  Never allow, and what the agent will do about
                                  it.

                                  The rule above says the decision; this says the
                                  consequence, and only for folders because
                                  folders are the only permission this computer
                                  actually withholds. An agent given no folder at
                                  all behaves as though the disk is empty, which
                                  is a deliberate setting doing exactly what it
                                  says and looks identical to a broken agent from
                                  the outside.
                                */
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 23
                                    visible: modelData.machineRule === "NEVER_ALLOW"
                                             && modelData.aboutFolders
                                    text: qsTr("You chose Never allow for files and folders, so this agent is given no folder on this computer, not even the ones shared with every agent. It may not work as expected.")
                                    color: Theme.amber
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.45
                                }
                            }

                            // ---- The answer, when it is this screen's ----
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceSm

                                Text {
                                    Layout.fillWidth: true
                                    visible: !card.pending && !card.ruled
                                    text: qsTr("You answered this. It is not asked again.")
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                }

                                Item { Layout.fillWidth: card.pending || card.ruled }

                                /*
                                  One way in, and it goes through the details.

                                  No **Allow** or **Refuse** here, on a card that
                                  shows a permission's name and a line about it.
                                  That is not enough to decide on: what the agent
                                  actually asked for — the folders, the ports,
                                  the programs, and what happens if the answer is
                                  no — is in the sheet, and a person who can say
                                  yes without opening it will. So the answer
                                  lives beside the thing being answered, and this
                                  button's whole job is to get somebody there.

                                  The label follows what it does rather than
                                  staying fixed: **Review** on a question still
                                  waiting, because that is what pressing it
                                  starts, and **More details** on one already
                                  settled, because there is nothing left to
                                  answer.

                                  Both are ordinary buttons. The brand call to
                                  action here would put a gradient capsule in
                                  every row of a list — an advertisement where a
                                  control belongs.
                                */
                                GhostButton {
                                    visible: !(card.pending && !card.ruled)
                                    implicitHeight: 32
                                    font.pixelSize: 12
                                    text: qsTr("More details")
                                    onClicked: sheet.open(modelData, card.meta)
                                }

                                GhostButton {
                                    visible: card.pending && !card.ruled
                                    implicitHeight: 32
                                    font.pixelSize: 12
                                    text: qsTr("Review")
                                    onClicked: sheet.open(modelData, card.meta)
                                }

                                LinkLabel {
                                    visible: !card.pending && !card.ruled
                                    text: qsTr("Ask me again")
                                    onActivated: AccessGrants.reset(modelData.agentId,
                                                                    modelData.accessKey)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function answer(request, allowed) {
        root.problem = "";
        if (!AccessGrants.decide(request.agentId, request.accessKey, allowed))
            root.problem = AccessGrants.lastError();
    }

    AccessRequestSheet {
        id: sheet
        anchors.fill: parent
    }
}
