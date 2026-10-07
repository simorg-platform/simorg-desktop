// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "SchemaRules.js" as SchemaRules

/**
 * What an agent can be allowed to touch on this computer.
 *
 * The **machine-wide** half, and the stronger of the two: one answer per
 * permission, applying to every agent placed here including the ones that have
 * not arrived yet. What a *particular* agent asked for, and what it was told,
 * is {@link AgentAccessPane} on that agent's own page — which is where the
 * questions are actually answered.
 *
 * ## Under Settings
 *
 * It was a view of **Agents**, beside the list of the agents this computer
 * runs, and it read as one of them while naming none. It is a fact about this
 * computer, the same sort of thing as where the cache is kept and whether
 * Simorg starts at login, so it is filed with those. The rows here are the
 * defaults a machine keeps; the agents are somewhere else.
 *
 * ## The list is not in this file
 *
 * It comes from `GET /machine-access-categories?machineCategory=DESKTOP` and is
 * rendered from the schema each row carries — including the settings each
 * permission takes. That is what makes adding a permission, or a field inside
 * one, a row on the server rather than a release of this app. See
 * `MachineCatalogClient`.
 *
 * The narrowing to `DESKTOP` matters: a laptop must never be offered a
 * permission a laptop cannot have.
 */
Item {
    id: root

    property int topic: 0

    readonly property var categories: MachineCatalog.accessCategories
    /**
     * Whether there is a list to draw, which is not the same as a fetch having
     * just succeeded.
     *
     * Keyed on the rows rather than on `loaded`: the previous list is kept when
     * a refresh fails, and a screen that blanked itself because a laptop lost
     * its wifi would be throwing away the answer it already had. The failure is
     * reported separately, above the list it did not replace.
     */
    readonly property bool ready: categories.count > 0

    /*
      Fetched when the screen is first shown rather than at startup.

      It is a handful of rows that change with the product, and nobody needs
      them until they open this tab. Re-fetched on each visit so an operator's
      edit reaches an app that has been open for a week.
    */
    onVisibleChanged: if (visible) { MachineCatalog.refresh("DESKTOP"); ++root.storedRevision; }
    Component.onCompleted: if (visible) { MachineCatalog.refresh("DESKTOP"); ++root.storedRevision; }

    /** The row the rail has open, as a plain map. Empty before anything loads. */
    readonly property var current: root.ready
                                   ? categories.at(Math.max(0, Math.min(topic, categories.count - 1)))
                                   : ({})

    /** One colour per sensitivity, so a wall of permissions can be scanned. */
    function sensitivityTone(level) {
        switch (level) {
        case "HIGH": return Theme.rose;
        case "MEDIUM": return Theme.amber;
        default: return Theme.sky;
        }
    }

    /**
     * Half-finished machine-wide settings, keyed by permission.
     *
     * Keyed rather than single so the rail stays usable: somebody who has added
     * two folders and clicks Network to check something has not thrown their
     * two folders away. A permission with no entry here is simply showing what
     * the platform holds.
     */
    property var drafts: ({})

    /**
     * Bumped whenever the stored settings may have moved.
     *
     * `AccessGrants.machineSettings()` is a function, and a binding that calls
     * one is evaluated once and never again. This is the dependency that makes
     * {@link stored} re-read — cheaper and more honest than a notifying
     * property per permission, and it is the only place the value is refreshed.
     */
    property int storedRevision: 0

    /** What the platform holds for the permission the rail has open. */
    readonly property var stored: {
        /*
          The revision is *used*, not merely mentioned.

          A bare `root.storedRevision;` statement reads as dead code and is
          optimised out, taking the binding's only dependency on it with it —
          which left this showing what was stored when the screen opened and
          never once after. Folding it into the condition keeps it real.
        */
        const revision = root.storedRevision;
        return revision >= 0 && root.ready
                ? AccessGrants.machineSettings(root.current.accessKey)
                : ({});
    }

    /** What is on screen: the draft if there is one, otherwise what is stored. */
    readonly property var draft: root.drafts[root.current.accessKey] !== undefined
                                 ? root.drafts[root.current.accessKey]
                                 : root.stored

    /** True while the draft says something other than what the platform holds. */
    readonly property bool settingsDirty:
        root.ready && !SchemaRules.same(root.draft, root.stored)

    /** The permission whose settings are in flight, so a refusal can be undone. */
    property string applying: ""
    property var applyingValues: ({})
    /** A refusal from the platform, in the words it used. */
    property string saveProblem: ""

    function editDraft(values) {
        root.drafts = SchemaRules.withValue(root.drafts, root.current.accessKey, values);
    }

    /** Drops the draft, so the screen goes back to showing what is stored. */
    function resetDraft() {
        root.drafts = SchemaRules.without(root.drafts, root.current.accessKey);
    }

    /**
     * Sends the settings for every agent on this computer.
     *
     * The draft is dropped as it goes rather than when it lands, so the screen
     * settles immediately — and put back by {@link saveProblem} if the platform
     * refuses, because a refusal that also discarded what somebody typed would
     * be the app losing their work to report a failure.
     */
    function applySettings(values) {
        root.saveProblem = "";
        root.applying = root.current.accessKey;
        root.applyingValues = values;
        AccessGrants.setMachineSettings(root.applying, values);
        root.drafts = SchemaRules.without(root.drafts, root.applying);
    }

    Connections {
        target: AccessGrants

        function onChanged() {
            ++root.storedRevision;
            if (!AccessGrants.saving)
                root.applying = "";
        }

        function onSaveFailed(message) {
            root.saveProblem = message;
            // Straight back onto the screen, under the reason it did not save.
            if (root.applying.length > 0)
                root.drafts = SchemaRules.withValue(root.drafts, root.applying,
                                                    root.applyingValues);
        }
    }

    /** How many agents on this computer have asked for one permission. */
    function askingCount(accessKey) {
        let count = 0;
        for (let i = 0; i < AccessGrants.count; ++i) {
            if (AccessGrants.at(i).accessKey === accessKey)
                ++count;
        }
        return count;
    }

    function sensitivityLabel(level) {
        switch (level) {
        case "HIGH": return qsTr("High impact");
        case "MEDIUM": return qsTr("Moderate");
        default: return qsTr("Low impact");
        }
    }

    /**
     * The catalogue row for a permission an agent asked for.
     *
     * A request carries a key and nothing readable; the words come from the
     * catalogue. Falls back to the bare key rather than to nothing, so an agent
     * asking for something this build has never heard of is still *shown* to be
     * asking — a request rendered as blank is how somebody allows more than they
     * read.
     */
    function describe(accessKey) {
        for (let i = 0; i < categories.count; ++i) {
            const entry = categories.at(i);
            if (entry.accessKey === accessKey)
                return entry;
        }
        return { label: accessKey, icon: "shield", sensitivity: "MEDIUM",
                 description: "", deniedBehaviour: "" };
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 20
        anchors.bottomMargin: 24
        spacing: Theme.spaceLg

        // ---- The rail ---------------------------------------------------
        GlassPanel {
            Layout.preferredWidth: 236
            Layout.fillHeight: true

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: Theme.spaceSm

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 6
                    text: qsTr("PERMISSIONS")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.3
                }

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        id: row
                        required property string label
                        required property string icon
                        required property int index

                        readonly property bool current: root.topic === index

                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: Theme.radiusSmall
                        color: row.current ? Theme.alpha(Theme.sky, 0.1)
                             : hover.hovered ? Theme.alpha(Theme.sky, 0.05)
                             : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 1
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2.5
                            height: row.current ? parent.height - 14 : 0
                            radius: 1.25
                            color: Theme.cyan

                            Behavior on height {
                                enabled: Theme.motion
                                NumberAnimation {
                                    duration: Theme.durFast
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Theme.easeOut
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 11
                            spacing: 10

                            Glyph {
                                // The icon name is a row on the server, so a
                                // permission this build has never heard of draws
                                // a plain shape rather than nothing.
                                name: row.icon
                                size: 15
                                thickness: 1.6
                                tone: row.current ? Theme.sky
                                    : hover.hovered ? Theme.textBody
                                    : Theme.textMuted
                            }

                            ElidedText {
                                Layout.fillWidth: true
                                text: row.label
                                color: row.current ? Theme.textPrimary : Theme.textBody
                                font.pixelSize: 12
                                font.weight: row.current ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler {
                            id: hover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler { onTapped: root.topic = row.index }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.topMargin: 8
                    visible: MachineCatalog.loading && root.categories.count === 0
                    text: qsTr("Loading…")
                    color: Theme.textFaint
                    font.pixelSize: 11
                }
            }

            // Anchored to the bottom of the rail rather than added to the list:
            // it is a statement about the whole page, not an eighth permission.
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 14
                text: qsTr("A rule here covers every agent on this computer. Without one, each agent is asked for itself.")
                color: Theme.textFaint
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                lineHeight: 1.35
            }
        }

        // ---- The pane ---------------------------------------------------
        ScrollView {
            id: pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: pane.availableWidth
                spacing: Theme.spaceMd


                /*
                  ---- What this screen is ------------------------------

                  First, and unmissable: this is where **rules for the whole
                  computer** are set, not where individual requests are
                  answered, and somebody has to be told that before they touch
                  a control that applies to every agent at once.
                */
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: preamble.implicitHeight + 36

                    ColumnLayout {
                        id: preamble
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "shield"; size: 16; thickness: 1.7; tone: Theme.cyan }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Rules for every agent on this computer")
                                color: Theme.textPrimary
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                visible: AccessGrants.ruleCount > 0
                                implicitWidth: ruleTally.implicitWidth + 18
                                implicitHeight: 22
                                radius: 5
                                color: Theme.alpha(Theme.cyan, 0.12)
                                border.width: 1
                                border.color: Theme.alpha(Theme.cyan, 0.3)

                                Text {
                                    id: ruleTally
                                    anchors.centerIn: parent
                                    text: AccessGrants.ruleCount === 1
                                          ? qsTr("1 RULE SET") : qsTr("%1 RULES SET").arg(AccessGrants.ruleCount)
                                    color: Theme.cyan
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Anything you set here applies to every agent running on this machine, including agents that arrive later. A rule is stronger than an answer given on an agent's own page: where a rule is in force, that page reports it and cannot override it.")
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("To answer one agent's own request, open that agent and use its Access management page. This screen is only for the rules that cover all of them.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            lineHeight: 1.45
                        }

                        // Saved where, and why that matters. Somebody setting a
                        // rule for a machine deserves to know it outlives it.
                        SelectableText {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            visible: MachineConfig.lastError.length > 0
                            text: qsTr("These could not be reached just now: %1").arg(MachineConfig.lastError)
                            color: Theme.amber
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- What this permission is --------------------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.ready
                    implicitHeight: detail.implicitHeight + 40

                    ColumnLayout {
                        id: detail
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 44
                                implicitHeight: 44
                                radius: 6
                                color: Theme.alpha(root.sensitivityTone(root.current.sensitivity), 0.1)
                                border.width: 1
                                border.color: Theme.alpha(root.sensitivityTone(root.current.sensitivity), 0.26)

                                Glyph {
                                    anchors.centerIn: parent
                                    name: root.current.icon || "shield"
                                    size: 21
                                    thickness: 1.6
                                    tone: root.sensitivityTone(root.current.sensitivity)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text: root.current.label || ""
                                    color: Theme.textPrimary
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: -0.2
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.current.description || ""
                                    color: Theme.textBody
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.5
                                }
                            }

                            // The half people actually decide on, given its own
                            // pill so it is scannable rather than buried.
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: sensitivity.implicitWidth + 20
                                implicitHeight: 24
                                radius: 5
                                color: Theme.alpha(root.sensitivityTone(root.current.sensitivity), 0.12)
                                border.width: 1
                                border.color: Theme.alpha(root.sensitivityTone(root.current.sensitivity), 0.3)

                                Text {
                                    id: sensitivity
                                    anchors.centerIn: parent
                                    text: root.sensitivityLabel(root.current.sensitivity)
                                    color: root.sensitivityTone(root.current.sensitivity)
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                }
                            }
                        }

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
                                name: "shield"
                                size: 14
                                thickness: 1.7
                                tone: Theme.textMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("While it is not granted: %1")
                                          .arg(root.current.deniedBehaviour || "")
                                color: Theme.textMuted
                                font.pixelSize: 12.5 - 0.5
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }
                        }
                    }
                }

                /*
                  ---- The rule for this computer -----------------------

                  The only control on this screen, and the reason it exists.
                  Everything above describes a permission; this decides what
                  happens when *any* agent placed here asks for it.

                  Three states rather than a switch, because "off" is two
                  different things: nobody has decided yet, and somebody decided
                  no. Collapsing them would either nag about settled questions
                  or silently refuse under the appearance of a default.
                */
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.ready
                    implicitHeight: ruleBox.implicitHeight + 40

                    ColumnLayout {
                        id: ruleBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph {
                                name: "lock"
                                size: 16
                                thickness: 1.7
                                tone: AccessGrants.rule(root.current.accessKey) === "ASK"
                                      ? Theme.textMuted : Theme.cyan
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("The rule for this computer")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            BusyRing {
                                visible: AccessGrants.saving
                                size: 14
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        Repeater {
                            model: [
                                {
                                    value: "ASK",
                                    label: qsTr("Ask me for each agent"),
                                    body: qsTr("The ordinary way. Each agent that asks appears on its own page and gets its own answer.")
                                },
                                {
                                    value: "ALWAYS_ALLOW",
                                    label: qsTr("Always allow"),
                                    body: qsTr("Every agent placed on this computer is granted this without being asked, including agents that arrive later.")
                                },
                                {
                                    value: "NEVER_ALLOW",
                                    label: qsTr("Never allow"),
                                    body: qsTr("No agent on this computer may have this, and it cannot be granted on an agent's own page.")
                                }
                            ]

                            delegate: Item {
                                id: choice
                                required property var modelData

                                readonly property bool current:
                                    AccessGrants.rule(root.current.accessKey) === modelData.value
                                readonly property color tone: modelData.value === "NEVER_ALLOW"
                                                              ? Theme.rose
                                                            : modelData.value === "ALWAYS_ALLOW"
                                                              ? Theme.emerald
                                                              : Theme.sky

                                Layout.fillWidth: true
                                implicitHeight: option.implicitHeight + 22

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusBase
                                    color: choice.current ? Theme.alpha(choice.tone, 0.09)
                                         : optionHover.hovered ? Theme.alpha(Theme.sky, 0.05)
                                         : "transparent"
                                    border.width: 1
                                    border.color: choice.current ? Theme.alpha(choice.tone, 0.4)
                                                                 : Theme.borderSubtle

                                    Behavior on color {
                                        ColorAnimation { duration: Theme.duration(Theme.durFast) }
                                    }
                                }

                                RowLayout {
                                    id: option
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 11
                                    spacing: 11

                                    // A ring rather than a checkbox: these are
                                    // three answers to one question, and only
                                    // one of them can hold.
                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 1
                                        width: 16
                                        height: 16
                                        radius: 4
                                        color: "transparent"
                                        border.width: choice.current ? 5 : 1.5
                                        border.color: choice.current ? choice.tone
                                                                     : Theme.borderStrong

                                        Behavior on border.width {
                                            NumberAnimation { duration: Theme.duration(Theme.durFast) }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: choice.modelData.label
                                            color: Theme.textPrimary
                                            font.pixelSize: 13
                                            font.weight: choice.current ? Font.DemiBold
                                                                        : Font.Normal
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: choice.modelData.body
                                            color: Theme.textMuted
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            lineHeight: 1.4
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: optionHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: AccessGrants.setRule(root.current.accessKey,
                                                                   choice.modelData.value)
                                }
                            }
                        }

                        // What the rule is doing right now, in agents.
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            visible: root.askingCount(root.current.accessKey) > 0
                            text: {
                                const asking = root.askingCount(root.current.accessKey);
                                const rule = AccessGrants.rule(root.current.accessKey);
                                if (rule === "ASK") {
                                    return asking === 1
                                        ? qsTr("One agent here is asking for this. Answer it on that agent's own page.")
                                        : qsTr("%1 agents here are asking for this. Answer each on its own page.").arg(asking);
                                }
                                return asking === 1
                                    ? qsTr("One agent here asked for this, and this rule answers it.")
                                    : qsTr("%1 agents here asked for this, and this rule answers all of them.").arg(asking);
                            }
                            color: Theme.textFaint
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                /*
                  ---- What every agent gets ----------------------------

                  The other half of a machine-wide rule, and the half that was
                  missing: the rule above says *whether* agents may have a
                  permission, and this says **what**. Two controls because they
                  are two decisions — "may agents read folders on this
                  computer" and "which folders" have different answers, and a
                  machine can have settled the second while still being asked
                  about the first.

                  Drawn from the permission's own schema, narrowed to the
                  fields somebody sitting at this computer can answer. For
                  files that is a folder and whether an agent may write to it;
                  for the network it is the destinations that are open; for
                  applications it is which installed programs may be run. The
                  form is the same one either way, because the catalogue is
                  what differs and not this file.
                */
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.ready && machineForm.shown.length > 0
                    implicitHeight: machineBox.implicitHeight + 40

                    ColumnLayout {
                        id: machineBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph {
                                name: "sliders"
                                size: 16
                                thickness: 1.7
                                tone: root.settingsDirty ? Theme.amber : Theme.cyan
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("What every agent gets here")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            BusyRing {
                                visible: AccessGrants.saving
                                size: 14
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Set once, for every agent on this computer, including agents that have not arrived yet. An agent does not have to ask for any of this and is not consulted about it.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        // Whatever is set here for every agent, Simorg Desktop is theirs already.
                        AlwaysAllowedApplication {
                            Layout.fillWidth: true
                            visible: root.current.accessKey === "APPLICATIONS"
                                     && AccessGrants.alwaysAllowedApplications.length > 0
                        }

                        SchemaForm {
                            id: machineForm
                            // Named so the interface tests can ask what the form is
                            // drawn from, rather than inferring it from pixels.
                            objectName: "machineSettingsForm"
                            Layout.fillWidth: true
                            fields: root.current.fields || []
                            scope: "MACHINE"
                            values: root.draft
                            editable: !AccessGrants.saving
                            onEdited: (values) => root.editDraft(values)
                        }

                        /*
                          Saved when somebody says so, not as they type.

                          A folder list that wrote itself on every keystroke
                          would hand three half-typed paths to every agent on
                          the computer on the way to one real one — and each of
                          those is a round trip that another machine could read
                          in between.
                        */
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: root.settingsDirty
                            spacing: Theme.spaceSm

                            Glyph { name: "info"; size: 13; thickness: 1.6; tone: Theme.amber }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Not applied yet")
                                color: Theme.amber
                                font.pixelSize: 12
                            }

                            LinkLabel {
                                text: qsTr("Discard")
                                onActivated: root.resetDraft()
                            }

                            PrimaryButton {
                                implicitHeight: 32
                                text: qsTr("Apply to every agent")
                                busy: AccessGrants.saving
                                onClicked: root.applySettings(machineForm.trimmed())
                            }
                        }
                    }
                }

                // ---- What it takes, drawn from the schema --------------
                GlassPanel {
                    Layout.fillWidth: true
                    visible: root.ready && (root.current.fields || []).length > 0
                    implicitHeight: settings.implicitHeight + 40

                    ColumnLayout {
                        id: settings
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph { name: "sliders"; size: 16; thickness: 1.7; tone: Theme.cyan }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("What an agent can ask for on top of this")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.borderSubtle
                        }

                        /*
                          One row per field the platform declared.

                          Read-only, and honestly so: granting happens against a
                          *request* from a particular agent, and there are no
                          requests to grant yet. What this does show is exactly
                          what will be asked — drawn from the same schema the
                          form will be built from.

                          **The field's type is deliberately not shown.**
                          `ENUM`, `RULE_LIST` and `STRING_LIST` are how this
                          client knows which control to draw; they are not
                          something the person deciding whether an agent may
                          read their Documents folder has any use for. What that
                          person needs is the label, whether it is required, the
                          hint, and the choices — and every one of those is
                          below, in words. The type still arrives on the model
                          and is still what the editor will be built from.
                        */
                        Repeater {
                            model: root.current.fields || []

                            delegate: ColumnLayout {
                                id: field
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: field.modelData.label
                                        color: Theme.textBody
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        visible: field.modelData.required
                                        implicitWidth: requiredLabel.implicitWidth + 12
                                        implicitHeight: 16
                                        radius: 4
                                        color: Theme.alpha(Theme.amber, 0.12)

                                        Text {
                                            id: requiredLabel
                                            anchors.centerIn: parent
                                            text: qsTr("required")
                                            color: Theme.amber
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: String(field.modelData.hint || "").length > 0
                                    text: field.modelData.hint
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: String(field.modelData.options || "").length > 0
                                    text: qsTr("Choices: %1").arg(field.modelData.options)
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: String(field.modelData.rowFields || "").length > 0
                                    text: qsTr("Each entry: %1").arg(field.modelData.rowFields)
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.saveProblem.length > 0
                    glyph: "alert"
                    tone: Theme.rose
                    title: qsTr("That could not be saved")
                    body: root.saveProblem
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: MachineCatalog.lastError.length > 0
                    glyph: "alert"
                    tone: Theme.amber
                    title: qsTr("The permission list could not be refreshed")
                    body: MachineCatalog.lastError
                }

                ComingSoon {
                    Layout.fillWidth: true
                    visible: !root.ready && MachineCatalog.lastError.length === 0
                    glyph: "shield"
                    tone: Theme.violet
                    title: MachineCatalog.loading
                           ? qsTr("Loading what agents can ask for")
                           : qsTr("No permissions are defined for this computer")
                    body: qsTr("Permissions are defined by the platform, so this list arrives from the server rather than being built into the app. That is what lets a new permission appear here without an update.")
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.ready
                    glyph: "shield"
                    tone: Theme.sky
                    title: qsTr("These rules are kept with this computer's record")
                    body: qsTr("A rule you set here is saved against this machine on the platform, so it survives a reinstall and can be carried to your next computer. It applies to every agent placed here, including agents that have not arrived yet.")
                }

                /*
                  What each answer does, in the order somebody reads this screen.

                  All three permissions are enforced now, and each in a way a
                  person should know before they set a rule: folders are mounts,
                  the network is a firewall in front of every container, and
                  applications are passed messages or not. The interruption is
                  stated here rather than discovered: a container's mounts and
                  its network are fixed when it is made, so a change reaches a
                  working agent only by making its container again.
                */
                InfoCallout {
                    Layout.fillWidth: true
                    visible: root.ready
                    glyph: "shield"
                    tone: Theme.amber
                    title: qsTr("What you allow here is what agents get")
                    // On Windows the path inside is another one — a Linux
                    // container has no drive letters — so it is not promised.
                    body: (Qt.platform.os === "windows"
                           ? qsTr("A folder on this list is mounted into every agent's container, D:\\data as /d/data as it says under the folder, read only or read and write as you say, and nothing else on this disk is reachable.")
                           : qsTr("A folder on this list is mounted into every agent's container at the same path it has on this computer, read only or read and write as you say, and nothing else on this disk is reachable."))
                          + " " + qsTr("The network is a firewall in front of every container: Simorg itself is always reachable, cloud metadata never is, and everything else only as allowed. An application is usable only by the agents allowed it. Changing any of this while an agent is working restarts its container, because a container cannot be given a folder or a network after it has started.")
                }
            }
        }
    }
}
