// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "SchemaRules.js" as Rules

/**
 * One permission request, in full, with the answer at the bottom.
 *
 * The row on the screen behind this has room for a sentence and two buttons,
 * which is enough to decide the easy ones and not enough for the rest. This is
 * where the whole question lives: what the permission covers, what this
 * particular agent asked for inside it, what happens if the answer is no, and
 * what Simorg will actually do with a yes.
 *
 * ## Why it is a sheet and not another screen
 *
 * Because it is a **question**, and a question keeps its context. Navigating
 * away and back would lose the list of everything else waiting, and answering
 * one of six permissions is a thing people do in one sitting. It dims what is
 * behind it, takes the keyboard, and closes on Escape.
 *
 * ## Choosing a folder is part of deciding, not a step before it
 *
 * A folder request can carry entries the agent's owner could not fill in,
 * because they do not own this computer and have never seen this disk. Those
 * are answered here, in the same sheet, immediately above the button that
 * grants them — so nobody is ever asked to allow something and then, separately,
 * to say what they allowed.
 *
 * **Allow is unavailable while one is unchosen**, and the reason is written out
 * rather than left to a greyed-out button. A grant with no folder in it would
 * be a row that says "Allowed" about an agent that was given nothing.
 */
Item {
    id: root

    /** One row of `AccessGrants`, as `at(row)` returns it. */
    property var request: ({})
    /** The catalogue entry for that permission. */
    property var meta: ({})

    readonly property bool pending: (root.request.decision || "pending") === "pending"
    readonly property int unchosen: root.request.unchosenFolderCount || 0
    readonly property bool blocked: root.pending && root.unchosen > 0
    /**
     * True when a machine-wide rule has already settled this.
     *
     * The sheet has to know, because it is now the only place a request is
     * answered: a pair of buttons offering to allow something the computer's
     * own rule forbids would be offering something that cannot happen.
     */
    readonly property bool ruled: root.request.ruledByMachine === true
    readonly property string machineRule: String(root.request.machineRule || "ASK")

    /** Refreshed rather than bound: the model has no per-folder signal. */
    property var folders: []
    property string problem: ""

    visible: opacity > 0
    opacity: 0
    z: 300

    function open(requestRow, categoryMeta) {
        root.request = requestRow;
        root.meta = categoryMeta;
        root.problem = "";
        root.reloadFolders();
        root.opacity = 1;
    }

    function close() {
        root.opacity = 0;
        root.problem = "";
    }

    /*
      Re-read rather than bound to a property.

      A folder list is assembled by joining what the agent asked for with what
      this computer's owner has stored on the platform, which is not something a
      QML binding can depend on.

      **And it is re-read on the model's signal, not after the call that
      changes it.** Choosing a folder starts a write to the platform and returns
      before it lands; the stored value updates when the reply arrives. Reading
      immediately after the call therefore read the value from *before* the
      choice — which is exactly the bug where a folder somebody had just picked
      appeared only once the sheet had been closed and opened again.
    */
    function reloadFolders() {
        root.folders = AccessGrants.folders(root.request.agentId || 0,
                                            root.request.accessKey || "");
        // And the request itself, for the count the footer reads.
        const row = AccessGrants.count > 0 ? root.request : root.request;
        root.request = Object.assign({}, row, {
            unchosenFolderCount: root.folders.filter(
                (folder) => folder.dynamic && !folder.chosen).length
        });
    }

    function chooseFor(index, purpose, current) {
        const picked = App.chooseFolder(
            qsTr("Choose the folder for “%1”").arg(purpose || qsTr("this agent")), current);
        // Cancelled. Nothing is chosen and nothing is said about it.
        if (!picked)
            return;
        root.applyFolder(index, picked);
    }

    function applyFolder(index, path) {
        if (!AccessGrants.chooseFolder(root.request.agentId, root.request.accessKey, index, path)) {
            root.problem = AccessGrants.lastError();
            return;
        }
        root.problem = "";
        /*
          No reload here. `chooseFolder` returning true means the write was
          *started*, and what is stored does not move until the platform
          answers — so reading now would read what was there before. The
          Connections below reloads when it actually changes.
        */
    }

    /**
     * The stored settings moved, so what is on screen is rebuilt.
     *
     * Covers the folder somebody just chose, and equally a choice made from
     * another computer while this sheet happened to be open.
     */
    Connections {
        target: AccessGrants
        enabled: root.visible

        function onChanged() {
            root.reloadFolders();
        }
    }

    function answer(allowed) {
        if (!AccessGrants.decide(root.request.agentId, root.request.accessKey, allowed)) {
            root.problem = AccessGrants.lastError();
            return;
        }
        root.close();
    }

    Behavior on opacity {
        NumberAnimation { duration: Theme.duration(Theme.durFast) }
    }

    /*
      Swallows everything behind it, and darkens it in both themes.

      Deliberately not `Theme.base` at an alpha, which is what the rest of this
      app's overlays use: on the light palette that is a **white** veil, and a
      white veil over white does not read as a layer above the page — it reads
      as the page having gone slightly pale. A scrim's whole job is to say "this
      is in front", and shadow is the only thing that says it on both palettes.
    */
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        TapHandler { onTapped: root.close() }
    }

    focus: root.opacity > 0
    Keys.onEscapePressed: root.close()

    GlassPanel {
        anchors.centerIn: parent
        width: Math.min(root.width - 72, 660)
        height: Math.min(root.height - 72, 720)
        // In front of the page, not blended with it. See GlassPanel.opaque.
        opaque: true

        scale: root.opacity > 0 ? 1 : 0.97
        Behavior on scale {
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }

        TapHandler { onTapped: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 0

            // ---- Header ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 13

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 42
                    height: 42
                    radius: 5
                    color: Theme.alpha(sheet.tone, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(sheet.tone, 0.3)

                    Glyph {
                        anchors.centerIn: parent
                        name: root.meta.icon || "shield"
                        size: 20
                        thickness: 1.6
                        tone: sheet.tone
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: root.meta.label || root.request.accessKey || ""
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("%1 is asking for this on this computer")
                                  .arg(root.request.agentTitle || qsTr("An agent"))
                        color: Theme.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: sensitivityText.implicitWidth + 20
                    implicitHeight: 24
                    radius: 5
                    color: Theme.alpha(sheet.tone, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(sheet.tone, 0.3)

                    Text {
                        id: sensitivityText
                        anchors.centerIn: parent
                        text: sheet.sensitivityLabel
                        color: sheet.tone
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }
                }

                IconButton {
                    Layout.alignment: Qt.AlignTop
                    glyph: "close"
                    size: 28
                    tooltip: qsTr("Close")
                    onClicked: root.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 16
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            // ---- Body -----------------------------------------------------
            ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 4
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    // The ScrollView's own available width, not a walk up the
                    // parent chain: `parent.parent` is the content item today
                    // and is not a promise Qt makes.
                    width: bodyScroll.availableWidth
                    spacing: Theme.spaceLg

                    // ---- Why -----------------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        visible: String(root.request.reason || "").length > 0
                        spacing: 5

                        Text {
                            text: qsTr("WHY THEY SAY THEY NEED IT")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("“%1”").arg(root.request.reason || "")
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Written by whoever set this agent up. It is their explanation, not something Simorg checked.")
                            color: Theme.textFaint
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ---- What the permission covers ------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: String(root.request.reason || "").length > 0 ? 0 : 14
                        spacing: 5

                        Text {
                            text: qsTr("WHAT THIS PERMISSION COVERS")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.meta.description || ""
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                        }
                    }

                    // ---- The folders ---------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.folders.length > 0
                        spacing: Theme.spaceSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: qsTr("THE FOLDERS IT IS ASKING FOR")
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontEyebrow
                                font.weight: Font.ExtraBold
                                font.letterSpacing: 1.3
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                visible: root.unchosen > 0
                                text: root.unchosen === 1
                                      ? qsTr("1 still needs a folder")
                                      : qsTr("%1 still need a folder").arg(root.unchosen)
                                color: Theme.amber
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        Repeater {
                            model: root.folders

                            delegate: RequestedFolderRow {
                                required property var modelData
                                Layout.fillWidth: true
                                folder: modelData
                                editable: root.pending
                                onChooseRequested: root.chooseFor(modelData.index,
                                                                 modelData.purpose,
                                                                 modelData.path)
                                onClearRequested: root.applyFolder(modelData.index, "")
                            }
                        }

                        /*
                          Where the path goes, corrected.

                          This said the choice was written to an encrypted file
                          on this computer and never sent to Simorg, which was
                          true of the vault and stopped being true when the
                          answers moved to `machine_configuration` on the
                          platform — the change that lets them survive a
                          reinstall and be carried to the next machine. A screen
                          promising a stronger guarantee than the system gives is
                          the one kind of inaccuracy that is worse than saying
                          nothing, so it says what is actually the case.
                        */
                        InfoCallout {
                            Layout.fillWidth: true
                            visible: root.folders.some((folder) => folder.dynamic)
                            glyph: "lock"
                            tone: Theme.sky
                            title: qsTr("Your choice is yours, and it does leave this computer")
                            body: qsTr("A folder you pick is kept with this machine's record on Simorg, under your account, so it survives a reinstall and can be carried to your next computer. Nobody else can read it, and that includes the agent's owner. What the agent gets is the folder itself, mounted into its container at this same path.")
                        }
                    }

                    // ---- Everything else it asked for ----------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: settingsRepeater.count > 0
                        spacing: Theme.spaceSm

                        Text {
                            text: qsTr("THE REST OF WHAT IT ASKED FOR")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        Repeater {
                            id: settingsRepeater
                            model: sheet.otherSettings

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    Layout.preferredWidth: 210
                                    Layout.alignment: Qt.AlignTop
                                    text: modelData.label
                                    color: Theme.textMuted
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }

                                // A value somebody may need elsewhere — a folder, a port — so it can be taken.
                                SelectableText {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: Theme.textBody
                                    font.pixelSize: 13
                                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                }
                            }
                        }
                    }

                    // ---- If you say no -------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: String(root.meta.deniedBehaviour || "").length > 0
                        spacing: 5

                        Text {
                            text: qsTr("IF YOU SAY NO")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.meta.deniedBehaviour || ""
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                        }
                    }
                }
            }

            // ---- Footer ---------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                spacing: 8

                // The reason, written out. A greyed-out button that does not
                // say why is a button somebody clicks four times.
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.blocked || root.problem.length > 0
                    spacing: 8

                    Glyph {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        name: "alert"
                        size: 13
                        thickness: 1.7
                        tone: Theme.amber
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.problem.length > 0
                              ? root.problem
                              : qsTr("Choose a folder for each one above before you allow this.")
                        color: Theme.amber
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    // Answered already: the verdict, and a way back to pending.
                    Rectangle {
                        visible: !root.pending && !root.ruled
                        implicitWidth: verdictText.implicitWidth + 22
                        implicitHeight: 26
                        radius: 5
                        readonly property color tone: root.request.decision === "allowed"
                                                      ? Theme.emerald : Theme.textMuted
                        color: Theme.alpha(tone, 0.12)
                        border.width: 1
                        border.color: Theme.alpha(tone, 0.3)

                        Text {
                            id: verdictText
                            anchors.centerIn: parent
                            text: root.request.decision === "allowed" ? qsTr("Allowed")
                                                                      : qsTr("Refused")
                            color: parent.tone
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                        }
                    }

                    LinkLabel {
                        visible: !root.pending && !root.ruled
                        text: qsTr("Ask me again")
                        onActivated: {
                            AccessGrants.reset(root.request.agentId, root.request.accessKey);
                            root.close();
                        }
                    }

                    Item { Layout.fillWidth: true }

                    /*
                      What the rule already decided, where the answer would be.

                      Reported rather than offered. A per-agent screen that
                      could quietly override a machine-wide rule would make the
                      rule advice, and somebody who set "no agent on this laptop
                      gets a terminal" set it about agents they had not met.
                    */
                    RowLayout {
                        visible: root.ruled
                        Layout.fillWidth: true
                        spacing: 8

                        Glyph { name: "lock"; size: 14; thickness: 1.7; tone: Theme.textMuted }

                        Text {
                            Layout.fillWidth: true
                            text: root.machineRule === "NEVER_ALLOW"
                                  ? qsTr("A rule on this computer refuses this for every agent.")
                                  : qsTr("A rule on this computer allows this for every agent.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    GhostButton {
                        visible: root.ruled
                        implicitHeight: 36
                        text: qsTr("Close")
                        onClicked: root.close()
                    }

                    GhostButton {
                        visible: root.pending && !root.ruled
                        implicitHeight: 36
                        implicitWidth: 96
                        text: qsTr("Refuse")
                        onClicked: root.answer(false)
                    }

                    /*
                      Allow is drawn plainly and Refuse is not drawn as a danger.

                      Neither answer is the one to nudge somebody towards: this
                      is their computer, and the interface's job is to make the
                      question legible rather than to have an opinion about it.
                      The only thing it is opinionated about is refusing to let
                      Allow mean nothing.
                    */
                    GhostButton {
                        visible: root.pending && !root.ruled
                        implicitHeight: 36
                        implicitWidth: 96
                        text: qsTr("Allow")
                        enabled: !root.blocked
                        onClicked: root.answer(true)
                    }

                    GhostButton {
                        visible: !root.pending && !root.ruled
                        implicitHeight: 36
                        text: qsTr("Close")
                        onClicked: root.close()
                    }
                }
            }
        }
    }

    // ---- Derived values ------------------------------------------------
    QtObject {
        id: sheet

        readonly property color tone: {
            switch (root.meta.sensitivity) {
            case "HIGH": return Theme.rose;
            case "MEDIUM": return Theme.amber;
            default: return Theme.sky;
            }
        }

        readonly property string sensitivityLabel: {
            switch (root.meta.sensitivity) {
            case "HIGH": return qsTr("High impact");
            case "MEDIUM": return qsTr("Moderate");
            default: return qsTr("Low impact");
            }
        }

        /**
         * Every setting except the folders, as label and value in plain words.
         *
         * Drawn from the catalogue's own description of the permission rather
         * than from anything compiled in, so a field added on the server appears
         * here without a release. The folders are excluded because they have a
         * section of their own above, with an action attached to each one.
         */
        readonly property var otherSettings: {
            const fields = root.meta.fields || [];
            const settings = root.request.settings || {};
            const rows = [];

            for (const field of fields) {
                if (root.request.accessKey === "FILES" && field.key === "paths")
                    continue;
                // A field whose condition is not met is not part of this request:
                // the sites of a request for the whole internet decide nothing.
                if (field.showWhenField) {
                    const held = settings[field.showWhenField] !== undefined && settings[field.showWhenField] !== ""
                                 ? settings[field.showWhenField]
                                 : sheet.topDefault(fields, field.showWhenField);
                    if (String(held) !== field.showWhenEquals)
                        continue;
                }
                rows.push({
                    label: field.label,
                    value: sheet.describeValue(field, settings[field.key])
                });
            }
            return rows;
        }

        /** One value, in the words somebody deciding would use. */
        function describeValue(field, value) {
            if (value === undefined || value === null || value === "")
                return qsTr("Not set");

            switch (field.type) {
            case "BOOLEAN":
                return value === true ? qsTr("Yes") : qsTr("No");
            case "ENUM":
                return sheet.optionLabel(field, String(value));
            case "MULTI_ENUM":
                // Normalised for the same reason a rule list is: what came
                // through C++ is list-shaped without being an `Array`.
                return Rules.toArray(value)
                            .map((entry) => sheet.optionLabel(field, String(entry)))
                            .join(qsTr(", "));
            case "STRING_LIST":
                return Rules.toArray(value).join(qsTr(", "));
            case "RULE_LIST":
                return sheet.describeRules(field, value);
            default:
                return String(value);
            }
        }

        function optionLabel(field, value) {
            for (const option of (field.optionList || [])) {
                if (option.value === value)
                    return option.label;
            }
            // The raw value rather than a blank: an option added after this
            // build shipped still has to be readable by somebody deciding.
            return value;
        }

        /** Each row of a rule list as `a · b · c`, one line per rule. */
        function describeRules(field, rules) {
            /*
              Normalised rather than type-checked.

              These settings have been through C++, so a list arrives as a
              sequence wrapper and not an `Array`. Guarding with
              `Array.isArray` reported "Nothing listed" over the top of a real
              set of firewall rules — on the one screen whose whole job is to
              show somebody what they are about to allow.
            */
            const given = Rules.toArray(rules);
            if (given.length === 0)
                return qsTr("Nothing listed");

            const lines = [];
            for (const rule of given) {
                const parts = [];
                for (const nested of (field.fields || [])) {
                    // A field whose condition is not met is not part of this
                    // rule at all, and showing it empty would invent a question.
                    if (nested.showWhenField) {
                        const held = rule[nested.showWhenField] !== undefined
                                     && rule[nested.showWhenField] !== ""
                                     ? rule[nested.showWhenField]
                                     : sheet.defaultOf(field, nested.showWhenField);
                        if (String(held) !== nested.showWhenEquals)
                            continue;
                    }
                    const value = sheet.describeValue(nested, rule[nested.key]);
                    if (value !== qsTr("Not set"))
                        parts.push(value);
                }
                lines.push(parts.join(qsTr(" · ")));
            }
            return lines.join("\n");
        }

        /** A top-level field's default, which an absent value holds (showWhen). */
        function topDefault(fields, key) {
            for (const field of fields) {
                if (field.key === key)
                    return field.defaultValue;
            }
            return undefined;
        }

        function defaultOf(field, key) {
            for (const nested of (field.fields || [])) {
                if (nested.key === key)
                    return nested.defaultValue;
            }
            return undefined;
        }
    }
}
