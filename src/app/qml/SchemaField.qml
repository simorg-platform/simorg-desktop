// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "SchemaRules.js" as Rules

/**
 * One setting, drawn from the catalogue's description of it.
 *
 * The interface has no idea what a shell command or a firewall port is. It
 * is handed a field — a label, a type, a hint, some choices — and draws the
 * control that type asks for. That is what makes adding a setting to a
 * permission a row on the server rather than a release of this app.
 *
 * ## Leaves only
 *
 * Everything except `RULE_LIST`, which is {@link SchemaRuleList} and which
 * builds its rows out of *this*. Splitting them that way is deliberate: it
 * means no component here refers to itself or to something that refers back,
 * so the one level of nesting the schema language allows is the only level
 * that can exist, structurally rather than by convention.
 *
 * ## The type is never shown
 *
 * `ENUM`, `STRING_LIST` and the rest decide which control appears and are not
 * words anybody deciding what an agent may read has any use for. The label, the
 * hint and the choices are, and those are what the screen carries.
 */
ColumnLayout {
    id: root

    /** One entry of a category's `fields`, or of a rule row's nested fields. */
    property var field: ({})
    /** What it currently holds. */
    property var value: undefined
    /** False while a request has already been answered; the form goes flat. */
    property bool editable: true
    /** Shown smaller inside a rule row, where the label is already close by. */
    property bool compact: false

    signal edited(var value)

    readonly property string type: String(root.field.type || "TEXT")
    readonly property var options: root.field.optionList || []
    /** A folder on the machine this setting is about, not merely some text. */
    readonly property bool hostPath: String(root.field.format || "") === "HOST_PATH"

    /**
     * Why the number in the box is not one the catalogue accepts.
     *
     * Shown rather than silently corrected. The platform drops a value outside
     * the declared range, so without this a port of 70000 would be typed,
     * applied, and quietly vanish — which looks like the app losing the setting
     * rather than like the setting being wrong.
     */
    readonly property string problem: {
        if (root.type !== "NUMBER")
            return "";
        const held = Number(root.value);
        if (root.value === undefined || root.value === null || isNaN(held))
            return "";
        const low = root.field.minimum;
        const high = root.field.maximum;
        if (low !== undefined && low !== null && held < Number(low))
            return qsTr("Must be %1 or more.").arg(low);
        if (high !== undefined && high !== null && held > Number(high))
            return qsTr("Must be %1 or less.").arg(high);
        return "";
    }

    spacing: 5

    // ---- What it is ---------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        visible: root.type !== "BOOLEAN"
        spacing: 8

        Text {
            text: String(root.field.label || root.field.key || "")
            color: Theme.textBody
            font.pixelSize: root.compact ? 11 : 13
            font.weight: Font.DemiBold
        }

        Rectangle {
            visible: root.field.required === true && !root.compact
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

    // ---- The control --------------------------------------------------

    /*
      A `Loader` per type rather than one control that switches.

      Six controls with nothing in common was, when it was one item, six sets of
      bindings all evaluating on every field and five of them meaningless. It
      also made a text field's `text` binding fight an enum's `currentIndex` for
      the same property.
    */
    SimorgCheckBox {
        Layout.fillWidth: true
        visible: root.type === "BOOLEAN"
        enabled: root.editable
        checked: root.value === true
        text: String(root.field.label || "")
        onToggled: (on) => root.edited(on)
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.type === "TEXT" || root.type === "NUMBER"
        spacing: Theme.spaceSm

        SimorgTextField {
            id: textInput
            Layout.fillWidth: true
            // A folder is picked, never typed, so the box beside the picker is a
            // readout: the two cannot then disagree about what was chosen.
            readOnly: !root.editable || root.hostPath
            errorText: root.problem
            label: String(root.field.placeholder || root.field.label || "")
            /*
              Bound, not initialised.

              A folder picked by the button beside this arrives as a change to
              `value` from outside, and a one-time assignment would leave the
              box showing what was there before somebody chose. The guard is
              what stops the binding fighting a person's own typing.
            */
            text: {
                const held = root.value;
                const shown = (held === undefined || held === null) ? "" : String(held);
                return textInput.editing && textInput.text !== shown ? textInput.text : shown;
            }
            onTextChanged: {
                if (!textInput.editing)
                    return;
                if (root.type === "NUMBER") {
                    const parsed = Number(text);
                    root.edited(text.length === 0 || isNaN(parsed) ? undefined : parsed);
                } else {
                    root.edited(text);
                }
            }
        }

        /*
          A folder is picked, not typed.

          The one thing the operating system is better at than a text box: it
          knows what exists, it knows what this account may read, and it does
          not let somebody mistype the path to a folder they are standing next
          to. The field is read-only while this button is there so the two
          cannot disagree about what was chosen.
        */
        GhostButton {
            visible: root.hostPath
            enabled: root.editable
            implicitHeight: 34
            font.pixelSize: 12
            text: String(root.value || "").length > 0 ? qsTr("Change…") : qsTr("Choose…")
            onClicked: {
                const picked = App.chooseFolder(
                                 qsTr("Choose a folder for %1").arg(String(root.field.label || "")),
                                 String(root.value || ""));
                if (picked.length > 0)
                    root.edited(picked);
            }
        }

        IconButton {
            visible: root.hostPath && String(root.value || "").length > 0
            enabled: root.editable
            glyph: "close"
            size: 26
            tooltip: qsTr("Clear")
            onClicked: root.edited("")
        }
    }

    // A folder picked on Windows is somewhere else inside the agent, and that
    // is the spelling its settings want: `D:\x` is `/d/x` in there.
    AgentPathLine {
        objectName: "fieldAgentPath"
        Layout.fillWidth: true
        path: root.hostPath && root.type === "TEXT" ? String(root.value || "") : ""
    }

    /*
      ---- One of a few ------------------------------------------------

      A segmented control up to three choices and a stack of rows beyond it.
      Three is where the labels stop fitting side by side, and a segmented
      control with its labels elided is worse than a list: somebody choosing
      between "Read only" and "Read and write" has to be able to read both.
    */
    SegmentedControl {
        // Sized to its choices rather than to the panel: a track stretched to
        // the full width with two labels at one end of it reads as a control
        // that is missing something.
        Layout.alignment: Qt.AlignLeft
        visible: root.type === "ENUM" && root.options.length > 0 && root.options.length <= 3
        enabled: root.editable
        items: root.options.map((option) => ({ label: option.label }))
        currentIndex: Math.max(0, root.options.findIndex((option) => option.value === root.value))
        onSelected: (index) => root.edited(root.options[index].value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.type === "ENUM" && root.options.length > 3
        spacing: 4

        Repeater {
            model: root.type === "ENUM" && root.options.length > 3 ? root.options : []

            delegate: Rectangle {
                id: choice
                required property var modelData
                readonly property bool current: choice.modelData.value === root.value

                Layout.fillWidth: true
                implicitHeight: choiceBody.implicitHeight + 18
                radius: Theme.radiusBase
                color: choice.current ? Theme.alpha(Theme.cyan, 0.1) : Theme.inset
                border.width: 1
                border.color: choice.current ? Theme.alpha(Theme.cyan, 0.4) : Theme.borderSubtle

                RowLayout {
                    id: choiceBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 9
                    spacing: 9

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 15
                        implicitHeight: 15
                        radius: 4
                        color: "transparent"
                        border.width: choice.current ? 5 : 1
                        border.color: choice.current ? Theme.cyan : Theme.borderStrong
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: String(choice.modelData.label || choice.modelData.value)
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: String(choice.modelData.description || "").length > 0
                            text: String(choice.modelData.description || "")
                            color: Theme.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.editable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.edited(choice.modelData.value)
                }
            }
        }
    }

    // ---- Several of a few ---------------------------------------------
    Flow {
        Layout.fillWidth: true
        visible: root.type === "MULTI_ENUM"
        spacing: 6

        Repeater {
            model: root.type === "MULTI_ENUM" ? root.options : []

            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool picked:
                    Rules.toArray(root.value).indexOf(chip.modelData.value) >= 0

                implicitWidth: chipLabel.implicitWidth + 22
                implicitHeight: 28
                radius: 6
                color: chip.picked ? Theme.alpha(Theme.cyan, 0.14) : Theme.inset
                border.width: 1
                border.color: chip.picked ? Theme.alpha(Theme.cyan, 0.45) : Theme.borderSubtle

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: String(chip.modelData.label || chip.modelData.value)
                    color: chip.picked ? Theme.cyan : Theme.textBody
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.editable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const held = Rules.toArray(root.value);
                        const at = held.indexOf(chip.modelData.value);
                        if (at >= 0)
                            held.splice(at, 1);
                        else
                            held.push(chip.modelData.value);
                        root.edited(held);
                    }
                }
            }
        }
    }

    // ---- A list of plain text ------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.type === "STRING_LIST"
        spacing: 5

        Repeater {
            model: root.type === "STRING_LIST" ? Rules.toArray(root.value).length : 0

            delegate: RowLayout {
                id: entry
                required property int index
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                SimorgTextField {
                    id: entryInput
                    Layout.fillWidth: true
                    readOnly: !root.editable
                    label: String(root.field.placeholder || "")
                    text: String(Rules.toArray(root.value)[entry.index] || "")
                    onTextChanged: {
                        if (!entryInput.editing)
                            return;
                        const held = Rules.toArray(root.value);
                        held[entry.index] = text;
                        root.edited(held);
                    }
                }

                IconButton {
                    enabled: root.editable
                    glyph: "trash"
                    size: 28
                    tooltip: qsTr("Remove")
                    hoverTone: Theme.rose
                    onClicked: {
                        const held = Rules.toArray(root.value);
                        held.splice(entry.index, 1);
                        root.edited(held);
                    }
                }
            }
        }

        GhostButton {
            visible: root.editable
            implicitHeight: 30
            font.pixelSize: 12
            text: qsTr("Add")
            onClicked: {
                const held = Rules.toArray(root.value);
                held.push("");
                root.edited(held);
            }
        }
    }

    // ---- Why it is here -------------------------------------------------
    Text {
        Layout.fillWidth: true
        visible: String(root.field.hint || "").length > 0
        text: String(root.field.hint || "")
        color: Theme.textMuted
        font.pixelSize: root.compact ? 10 : 11
        wrapMode: Text.WordWrap
    }
}
