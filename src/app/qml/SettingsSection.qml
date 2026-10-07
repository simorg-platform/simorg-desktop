// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * How Simorg itself behaves on this computer.
 *
 * Deliberately not the Docker section's settings, which are about an engine
 * this app happens to drive. These are about the app.
 *
 * Almost every setting here is a **fact about this machine**, not a preference
 * stored on an account, so almost none of it follows somebody to their other
 * computers. That is why each panel says where its answer is written — and why
 * the one exception says so loudest: the log cap under **Logging** is a
 * statement about how much scrollback a *person* wants, not about this box, so
 * it is stored on the account and travels with them.
 *
 * ## Six views, because it had become a scroll
 *
 * It was one page: startup, the menu bar, the cache folder, the agreement, and
 * eight version strings, in that order, and the only way to reach the last of
 * them was to scroll past all the others. A segmented control the way Agents,
 * Artifacts and Docker have one splits it by the question being asked:
 *
 * | | |
 * | --- | --- |
 * | **Overview** | What this installation is: versions, estate, agreement |
 * | **Files and folders** | Where things are kept, how much they come to, and emptying the cache |
 * | **Logging** | How much of a log is kept, and whether it is capped at all |
 * | **Execution** | When Simorg runs, and what closing the window does |
 * | **Access management** | What any agent placed here may ask this computer for |
 * | **Updates** | New versions of Simorg Desktop, the machine service and the agent runtime, each updated on a press |
 * | **Licences** | What Simorg is made of, and on what terms |
 * | **Uninstall** | Taking Simorg off this computer, with why, if the person says |
 *
 * Logging sits beside Files and folders because the two are one subject at two
 * speeds: what this computer is holding on disk, and what it is holding in
 * memory.
 *
 * ## Why the rules are here
 *
 * Access management could pass for a view of the **Agents** section, and is
 * not one: nothing on it names an agent. It is a default this machine keeps about every agent
 * placed on it, including the ones that have not arrived yet, and an agent's
 * own page may report it but never talk over it. That makes it the same sort of
 * thing as the folders and the startup behaviour — a fact about this computer,
 * not about anybody's account — so it is filed with them.
 *
 * What each agent has actually been allowed is where the question is asked: on
 * that agent's own page. See {@link AgentAccessPane}.
 *
 * Last of the four because it is the one somebody comes here on purpose for,
 * and the three before it are the ones they arrive at by wandering.
 */
Item {
    id: root

    property int view: 0

    readonly property var views: [
        { key: "overview", label: qsTr("Overview"), glyph: "info" },
        { key: "files", label: qsTr("Files and folders"), glyph: "folder" },
        { key: "logging", label: qsTr("Logging"), glyph: "terminal" },
        { key: "execution", label: qsTr("Execution"), glyph: "restart" },
        { key: "access", label: qsTr("Access management"), glyph: "shield" },
        { key: "updates", label: qsTr("Updates"), glyph: "download" },
        { key: "licences", label: qsTr("Licences"), glyph: "layers" },
        { key: "uninstall", label: qsTr("Uninstall"), glyph: "trash" }
    ]

    /** Opens the folders. Where the Artifacts section's link lands. */
    function showFiles() {
        root.view = 1;
    }

    /**
     * Opens the machine-wide rules.
     *
     * Where the tray's permission notification lands when it has no agent to
     * name, and where an agent's own page sends somebody who clicked "change
     * the rule" on a row a rule had already decided.
     */
    function showAccess() {
        root.view = 4;
    }

    /** Opens the updates. Where the bar's Review and update lands. */
    function showUpdates() {
        root.view = 5;
    }

    // A fresh check whenever the updates are opened, so they never show last hour's answer.
    onViewChanged: {
        if (root.view === 5) {
            updatesView.refresh();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ----------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 20
                spacing: 14

                Glyph {
                    name: "settings"
                    size: 18
                    thickness: 1.7
                    tone: Theme.sky
                }

                // The title gives way before any control does; see the same
                // arrangement in AgentsSection.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 90
                    spacing: 1

                    ElidedText {
                        Layout.fillWidth: true
                        text: qsTr("Settings")
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        elide: Text.ElideRight
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: root.view === 6
                              ? qsTr("What this program is licensed under, and whose work is inside it")
                            : root.view === 5
                              ? qsTr("New versions of Simorg for this computer, and installing them")
                            : root.view === 4
                              ? qsTr("What an agent can ask this computer for, and what it means")
                            : root.view === 3
                              ? qsTr("When Simorg runs, and what closing the window does")
                            : root.view === 2
                              ? qsTr("How much of a log is kept, and whether it is capped at all")
                            : root.view === 1
                              ? qsTr("Where this computer keeps what Simorg downloads and makes")
                            : qsTr("Settings for this machine, not for your account")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                SegmentedControl {
                    items: root.views
                    currentIndex: root.view
                    onSelected: function (index) { root.view = index; }
                }
            }
        }

        // ---- Views -------------------------------------------------------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.view

            SettingsOverview {}

            SettingsFiles {}

            SettingsLogging {}

            SettingsExecution {}

            AgentAccessManagement {}

            SettingsUpdates {
                id: updatesView
            }

            SettingsLicences {}

            SettingsUninstall {}
        }
    }
}
