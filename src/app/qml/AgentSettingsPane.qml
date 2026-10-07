// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * One agent's Settings on this computer: updating it, what it uses, and
 * uninstalling it from here.
 *
 * ## Update
 *
 * An agent installed from a published agent is offered its publisher's newer
 * releases. This says which release it runs and, under **What's new**, every
 * release note since then — newest first and open, the rest one press away —
 * so whoever updates reads what they are taking. An admin of the agent moves it
 * there with one press, after a dialog saying what an update changes and what
 * it keeps. With nothing newer, the note of the release it runs is one press
 * away instead. A private artifact's notes are never shown here. The platform replaces its sources,
 * brings its features and the permissions it asks this computer for in line
 * with the new release, and reboots it with reboot type `UPDATE`, which is what
 * makes the new container here. Everybody else
 * reads the same section with the platform's reason they cannot press it.
 *
 * ## Dependencies
 *
 * The engine the agent runs on and the release of every artifact it uses, as
 * its lock holds them. An artifact whose
 * include allows a newer release says what **Update** would move it to, with
 * that release's note; Update moves them all after a dialog listing each change,
 * and a running agent restarts to fetch them. **Forget unused** drops what its code has
 * not included for the period chosen. Only an owner or admin may press either,
 * and everybody else reads why. The list is read again whenever the lock moves.
 *
 * ## Uninstall from this computer
 *
 * Takes the agent off this computer and nothing more: it stops running here,
 * the computer removes its container, and the agent itself stays on its Logos
 * with its members, files and settings. The platform
 * allows it to an admin of the agent and to this computer's owner. It asks
 * first, because an agent somebody else relies on stops answering.
 *
 * Both are requests to the platform through the service, as the signed-in
 * person: nothing here touches Docker, and what moves the container comes back
 * down this computer's own socket.
 */
Item {
    id: root

    /** The row from {@link HostedAgentModel}. */
    property var agent: ({})
    /** Whether the pane is on screen, which is when the platform is asked. */
    property bool active: false

    readonly property bool present: root.agent !== undefined && root.agent.agentId > 0
    readonly property var current: AgentSettings.current
    readonly property var available: AgentSettings.available
    readonly property bool offered: root.available.artifactTagId !== undefined
                                    && root.available.artifactTagId > 0
    readonly property var releases: AgentSettings.releases
    /** The release it runs, named, for "N releases since 1.0.0". */
    readonly property string since: root.current.tag && root.current.tag.length > 0
                                    ? root.current.tag : qsTr("the version it runs")
    readonly property string machineName: Hub.machineTitle.length > 0 ? Hub.machineTitle : qsTr("this computer")

    // Read when the pane comes on screen, so a page left on the dashboard asks nothing.
    onActiveChanged: {
        if (root.active) {
            AgentSettings.refresh();
            AgentDependencies.refresh();
        }
    }

    function releaseLabel(release) {
        return release && release.tag && release.tag.length > 0 ? release.tag : qsTr("a newer release");
    }

    /** The periods Forget unused offers, in days. */
    readonly property var unusedFor: [
        { key: 7, label: qsTr("7 days") },
        { key: 30, label: qsTr("30 days") },
        { key: 90, label: qsTr("90 days") },
        { key: 365, label: qsTr("a year") }
    ]
    property int unusedIndex: 1

    /** What the last Update or Forget unused did, as a sentence. */
    function dependenciesOutcome(outcome) {
        if (!outcome || !outcome.kind)
            return "";
        if (outcome.kind === "update") {
            if (outcome.moved === 0)
                return qsTr("Nothing moved: everything it uses was already on the newest release its code allows.");
            // Singular and plural written out: %n with no catalogue prints literally.
            const moved = outcome.moved === 1
                          ? qsTr("Moved one artifact to a newer release.")
                          : qsTr("Moved %1 artifacts to a newer release.").arg(outcome.moved);
            return moved + " " + (outcome.rebooted ? qsTr("It is restarting to fetch them.")
                                                   : qsTr("It fetches them when it next starts."));
        }
        const period = root.unusedFor.find(option => option.key === outcome.days);
        if (outcome.forgotten.length === 0)
            return qsTr("Nothing went unused for %1.").arg(period ? period.label : qsTr("%1 days").arg(outcome.days));
        return qsTr("Forgot %1. The next time its code includes one, it is resolved again.")
               .arg(outcome.forgotten.join(", "));
    }

    /** Each change Update would make, one per line, for its dialog. */
    function dependencyChanges() {
        const lines = [];
        for (const row of AgentDependencies.dependencies) {
            if (row.updateTag.length > 0)
                lines.push(qsTr("%1 %2 → %3").arg(row.specifier).arg(row.tag).arg(row.updateTag));
        }
        return lines.join("\n");
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

                // ---- Update ------------------------------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: updateBody.implicitHeight + 40

                    ColumnLayout {
                        id: updateBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "download"; size: 16; thickness: 1.7; tone: Theme.sky }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Update")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            BusyRing {
                                visible: AgentSettings.loading || AgentSettings.updating
                                running: visible
                                size: 16
                            }
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: !AgentSettings.loading && !AgentSettings.installed
                                     && AgentSettings.lastError.length === 0
                            text: qsTr("This agent was not installed from a published release, so there is no newer version for it.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentSettings.installed
                            text: root.current.artifactTagId > 0
                                  ? (AgentSettings.source.length > 0
                                     ? qsTr("Runs %1 of %2.").arg(root.releaseLabel(root.current)).arg(AgentSettings.source)
                                     : qsTr("Runs %1. The artifact it came from is private.").arg(root.releaseLabel(root.current)))
                                  : qsTr("The release it was installed from has been deleted.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        // A private artifact's notes stay with its publisher.
                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && root.offered && AgentSettings.sourcePrivate
                            text: qsTr("A newer release is ready. Its artifact is private, so its release notes stay with its publisher and are not shown here.")
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        /*
                          What's new: every release note since the release it runs,
                          newest first and open, the rest one press away — so an
                          agent several releases behind reads everything it is
                          about to get before anybody presses Update.
                        */
                        ColumnLayout {
                            objectName: "whatsNew"
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && root.offered && !AgentSettings.sourcePrivate
                                     && root.releases.length > 0
                            spacing: 6

                            Text {
                                text: qsTr("What’s new")
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                // Singular and plural written out: %n with no catalogue prints literally.
                                text: AgentSettings.releasesTotal === 1
                                      ? qsTr("One release since %1. Read what it changes before you update.").arg(root.since)
                                      : qsTr("%1 releases since %2. Read what they change before you update.")
                                            .arg(AgentSettings.releasesTotal).arg(root.since)
                                color: Theme.textMuted
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: root.releases
                                ReleaseNoteCard {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    release: modelData
                                    open: index === 0
                                    marker: index === 0 ? qsTr("Newest") : ""
                                }
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                visible: AgentSettings.releasesTotal > root.releases.length
                                text: qsTr("%1 earlier releases are not listed here; the artifact’s page in the catalogue has them all.")
                                      .arg(AgentSettings.releasesTotal - root.releases.length)
                                color: Theme.textFaint
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        // A platform that sends no list: the release on offer alone, open.
                        ReleaseNoteCard {
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && root.offered && !AgentSettings.sourcePrivate
                                     && root.releases.length === 0
                            release: root.available
                            open: true
                            marker: qsTr("Newest")
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && !root.offered && !AgentSettings.loading
                            text: qsTr("This is the newest release.")
                            color: Theme.textPrimary
                            font.pixelSize: 12
                        }

                        // The note of the release it runs, for an agent with nothing newer to read.
                        ReleaseNoteCard {
                            objectName: "installedReleaseNote"
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && !root.offered && !AgentSettings.sourcePrivate
                                     && root.current.artifactTagId > 0
                            release: root.current
                            marker: qsTr("Installed")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: AgentSettings.installed && root.offered
                            spacing: 10

                            PrimaryButton {
                                objectName: "applyAgentUpdate"
                                text: root.available.tag && root.available.tag.length > 0
                                      ? qsTr("Update to %1").arg(root.available.tag)
                                      : qsTr("Update")
                                enabled: AgentSettings.canUpdate && AgentSettings.blockedReason.length === 0
                                         && !AgentSettings.updating && !AgentSettings.uninstalling
                                busy: AgentSettings.updating
                                implicitHeight: 34
                                onClicked: updateConfirm.open()
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Why the button is closed, said on the page rather than hidden behind it.
                        SelectableText {
                            Layout.fillWidth: true
                            visible: root.offered && AgentSettings.blockedReason.length > 0
                            text: AgentSettings.blockedReason
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentSettings.message.length > 0 && AgentSettings.lastError.length === 0
                            text: AgentSettings.message
                            color: Theme.emerald
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: AgentSettings.warnings
                            SelectableText {
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData
                                color: Theme.amber
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentSettings.lastError.length > 0
                            text: AgentSettings.lastError
                            color: Theme.rose
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- Dependencies ------------------------------------------
                GlassPanel {
                    objectName: "dependencies"
                    Layout.fillWidth: true
                    implicitHeight: dependenciesBody.implicitHeight + 40

                    ColumnLayout {
                        id: dependenciesBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "layers"; size: 16; thickness: 1.7; tone: Theme.sky }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Dependencies")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            BusyRing {
                                visible: AgentDependencies.loading || AgentDependencies.busy
                                running: visible
                                size: 16
                            }
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            text: qsTr("The engine this agent runs on and the release of every artifact it uses.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: AgentDependencies.loaded
                            spacing: 8

                            Text {
                                text: qsTr("Engine")
                                color: Theme.textFaint
                                font.pixelSize: 12
                                Layout.maximumWidth: Math.ceil(implicitWidth)
                            }

                            SelectableText {
                                objectName: "dependenciesEngine"
                                Layout.fillWidth: true
                                text: AgentDependencies.engineVersion.length > 0
                                      ? AgentDependencies.engineVersion
                                      : qsTr("None. Its simorg.toml names no engine, so it cannot start.")
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.weight: AgentDependencies.engineVersion.length > 0 ? Font.Bold : Font.Normal
                                wrapMode: Text.WordWrap
                            }
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentDependencies.loaded && AgentDependencies.dependencies.length === 0
                            text: qsTr("No artifacts yet. Each artifact its code includes is listed here at the release it was given.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            objectName: "dependencyRows"
                            model: AgentDependencies.dependencies

                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: modelData.specifier
                                        color: Theme.textPrimary
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 12
                                        wrapMode: Text.WrapAnywhere
                                    }

                                    Text {
                                        text: modelData.tag
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        Layout.maximumWidth: Math.ceil(implicitWidth)
                                    }
                                }

                                // What Update would move it to, with that release's note.
                                ReleaseNoteCard {
                                    Layout.fillWidth: true
                                    visible: modelData.updateTag.length > 0
                                    release: ({ tag: modelData.updateTag, notes: modelData.updateNotes })
                                    marker: qsTr("Update")
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: AgentDependencies.dependencies.length > 0
                            spacing: 10

                            PrimaryButton {
                                objectName: "updateDependencies"
                                text: qsTr("Update")
                                enabled: AgentDependencies.canManage && AgentDependencies.movable > 0
                                         && AgentDependencies.engineVersion.length > 0 && !AgentDependencies.busy
                                busy: AgentDependencies.busy
                                implicitHeight: 34
                                onClicked: dependenciesConfirm.open()
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: qsTr("Not used for")
                                color: Theme.textFaint
                                font.pixelSize: 11
                                Layout.maximumWidth: Math.ceil(implicitWidth)
                            }

                            SegmentedControl {
                                objectName: "unusedFor"
                                enabled: AgentDependencies.canManage && !AgentDependencies.busy
                                items: root.unusedFor
                                currentIndex: root.unusedIndex
                                onSelected: function (index) {
                                    root.unusedIndex = index;
                                }
                            }

                            GhostButton {
                                objectName: "forgetUnused"
                                text: qsTr("Forget unused")
                                enabled: AgentDependencies.canManage && !AgentDependencies.busy
                                implicitHeight: 34
                                onClicked: AgentDependencies.forgetUnused(root.unusedFor[root.unusedIndex].key)
                            }
                        }

                        // Why the buttons are closed, said on the page rather than hidden behind them.
                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentDependencies.dependencies.length > 0 && AgentDependencies.loaded
                                     && !AgentDependencies.canManage
                            text: qsTr("Only an owner or admin of this agent can change what it uses, because that changes the code it runs.")
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentDependencies.dependencies.length > 0 && AgentDependencies.canManage
                                     && AgentDependencies.movable === 0
                            text: qsTr("Everything it uses is on the newest release its code allows, so there is nothing to update.")
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        SelectableText {
                            objectName: "dependenciesOutcome"
                            Layout.fillWidth: true
                            visible: text.length > 0 && AgentDependencies.lastError.length === 0
                            text: root.dependenciesOutcome(AgentDependencies.outcome)
                            color: Theme.emerald
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            visible: AgentDependencies.lastError.length > 0
                            text: AgentDependencies.lastError
                            color: Theme.rose
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- Uninstall from this computer ---------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: uninstallBody.implicitHeight + 40

                    ColumnLayout {
                        id: uninstallBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "trash"; size: 16; thickness: 1.7; tone: Theme.rose }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Uninstall from this computer")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            BusyRing {
                                visible: AgentSettings.uninstalling
                                running: visible
                                size: 16
                            }
                        }

                        SelectableText {
                            Layout.fillWidth: true
                            text: qsTr("It stops running on %1 and its container is removed. The agent itself stays on its Logos, with its members, files and settings.")
                                  .arg(root.machineName)
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            GhostButton {
                                objectName: "uninstallAgent"
                                text: qsTr("Uninstall")
                                glyph: "trash"
                                enabled: root.present && !AgentSettings.uninstalling && !AgentSettings.updating
                                spinning: AgentSettings.uninstalling
                                implicitHeight: 34
                                onClicked: uninstallConfirm.open()
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: updateConfirm
        objectName: "updateConfirm"
        anchors.fill: parent
        destructive: false
        title: qsTr("Update %1 to %2?").arg(root.present ? root.agent.title : "").arg(root.releaseLabel(root.available))
        body: qsTr("Its files are replaced with the new release's, and it may ask this computer for new permissions. Its name, members, settings and secrets stay as they are. If it is running, it restarts to run the new release.")
        confirmText: qsTr("Update")
        onAccepted: AgentSettings.applyUpdate()
    }

    ConfirmDialog {
        id: dependenciesConfirm
        objectName: "dependenciesConfirm"
        anchors.fill: parent
        destructive: false
        title: qsTr("Update what %1 uses?").arg(root.present ? root.agent.title : "")
        body: root.dependencyChanges() + "\n\n" + qsTr("If it is running, it restarts to fetch the new releases.")
        confirmText: qsTr("Update")
        onAccepted: AgentDependencies.update()
    }

    ConfirmDialog {
        id: uninstallConfirm
        anchors.fill: parent
        destructive: true
        title: qsTr("Uninstall %1 from %2?").arg(root.present ? root.agent.title : "").arg(root.machineName)
        body: qsTr("It stops running here and its container is removed, so anybody talking to it through this computer finds it has gone quiet. The agent itself is kept: it stays on its Logos with its members, files and settings, and runs again once it is given a machine.")
        confirmText: qsTr("Uninstall")
        onAccepted: AgentSettings.uninstall()
    }
}
