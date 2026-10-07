// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "SchemaRules.js" as Rules

/**
 * A whole permission's settings, drawn from the catalogue.
 *
 * Nothing about files, terminals or firewalls is compiled in. The form is handed
 * a category's `fields` and a record, and it draws one control per field —
 * which is what lets the platform add a setting to a permission without this
 * app being rebuilt.
 *
 * ## The same schema, two audiences
 *
 * A field can say **who is being asked**. `scope` picks which of them this form
 * is for:
 *
 * | `scope` | Who is filling it in | Where |
 * | --- | --- | --- |
 * | `REQUEST` | the agent's owner, describing what it needs | the web console |
 * | `MACHINE` | the owner of a computer, for every agent on it | this screen |
 *
 * A field with no scope of its own is asked in both, which is nearly all of
 * them. The one that is not is how a folder gets chosen — a question that means
 * nothing to somebody who is *at* the disk, because they are the "later" it
 * defers to.
 *
 * ## Edits are collected, not saved
 *
 * This emits {@link edited} and stores nothing. The screen above decides when a
 * record is worth writing, which on a machine-wide form is when somebody says
 * so: a folder list that saved itself on every keystroke would broadcast three
 * half-typed paths to every agent on the computer on the way to one real one.
 */
ColumnLayout {
    id: root

    /** A category's `fields`, exactly as the catalogue gave them. */
    property var fields: []
    /** The record being edited. Replaced on every change, never mutated. */
    property var values: ({})
    /** Which half of the schema to draw. See the table above. */
    property string scope: "MACHINE"
    property bool editable: true

    signal edited(var values)

    /** What is actually asked: in scope, and with its condition met. */
    readonly property var shown: Rules.visibleFields(root.fields, root.values, root.scope)

    /**
     * The record as it should be saved.
     *
     * Not the raw values: a path typed and then hidden by a condition is an
     * answer to a question that is no longer on the screen, and saving it would
     * put a folder in the record that nobody chose. The platform applies the
     * same rule on the way in — this is so the screen and the stored value
     * agree about what was set.
     */
    function trimmed() {
        return Rules.trim(root.values, root.fields, root.scope);
    }

    /** A noun for one row of a list, taken from its own label. */
    function nounFor(field) {
        const label = String(field.label || "").trim().toLowerCase();
        // "Folders" → "folder", "Outbound rules" → "outbound rule". A label
        // that is already singular is left alone rather than mangled.
        return label.endsWith("s") ? label.slice(0, -1) : label;
    }

    spacing: Theme.spaceMd

    Repeater {
        model: root.shown

        delegate: ColumnLayout {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            spacing: 6

            /*
              A rule list carries its own heading, because its label names the
              collection ("Folders") while each row inside it is one of them.
              Everything else is a single control and {@link SchemaField} labels
              it.
            */
            RowLayout {
                Layout.fillWidth: true
                visible: entry.modelData.type === "RULE_LIST"
                spacing: 8

                Text {
                    text: String(entry.modelData.label || "")
                    color: Theme.textBody
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                visible: entry.modelData.type === "RULE_LIST"
                         && String(entry.modelData.hint || "").length > 0
                text: String(entry.modelData.hint || "")
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            SchemaRuleList {
                objectName: "ruleList_" + entry.modelData.key
                Layout.fillWidth: true
                visible: entry.modelData.type === "RULE_LIST"
                field: entry.modelData
                value: root.values[entry.modelData.key]
                scope: root.scope
                editable: root.editable
                noun: root.nounFor(entry.modelData)
                onEdited: (value) => root.edited(
                              Rules.withValue(root.values, entry.modelData.key, value))
            }

            SchemaField {
                Layout.fillWidth: true
                visible: entry.modelData.type !== "RULE_LIST"
                field: entry.modelData
                value: root.values[entry.modelData.key]
                editable: root.editable
                onEdited: (value) => root.edited(
                              Rules.withValue(root.values, entry.modelData.key, value))
            }
        }
    }
}
