// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "SchemaRules.js" as Rules

/**
 * A setting that is a **list of records**: folders, firewall rules, programs.
 *
 * The only field type with a shape inside it, and the reason the schema
 * language has a nesting level at all. One row is one folder an agent may read,
 * or one destination it may connect to — a set of values that only mean
 * anything together.
 *
 * ## One level, structurally
 *
 * The rows are built out of {@link SchemaField}, which draws every type
 * *except* this one. So a rule list can contain fields and a field can never
 * contain a rule list, and the single level of nesting the catalogue allows is
 * the only level that can be expressed here — not by convention, but because
 * there is no component that would draw a second one.
 *
 * ## An empty list is a real answer
 *
 * It is drawn as a stated emptiness rather than as a blank, because on this
 * screen "no folders" is a decision somebody made about every agent on their
 * computer, and it should read like one.
 */
ColumnLayout {
    id: root

    /** The `RULE_LIST` field itself. */
    property var field: ({})
    /** The rows it holds. Always an array; an absent value reads as none. */
    property var value: []
    /** Which half of the schema is being asked. See `SchemaRules.inScope`. */
    property string scope: "MACHINE"
    property bool editable: true
    /** What one row is called, for the button and the empty state. */
    property string noun: qsTr("entry")

    signal edited(var value)

    readonly property var rows: Rules.toArray(root.value)
    readonly property var rowFields: root.field.fields || []

    /** Replaces one row, leaving the rest alone. */
    function replaceRow(index, record) {
        const next = root.rows.slice();
        next[index] = record;
        root.edited(next);
    }

    spacing: Theme.spaceSm

    // ---- The rows ------------------------------------------------------
    Repeater {
        model: root.rows.length

        delegate: Rectangle {
            id: card
            required property int index
            readonly property var record: root.rows[card.index] || ({})

            Layout.fillWidth: true
            implicitHeight: rowBody.implicitHeight + 26
            radius: Theme.radiusBase
            color: Theme.inset
            border.width: 1
            border.color: Theme.borderSubtle

            ColumnLayout {
                id: rowBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 13
                spacing: Theme.spaceSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: qsTr("%1 %2").arg(root.noun.charAt(0).toUpperCase() + root.noun.slice(1))
                                           .arg(card.index + 1)
                        color: Theme.textFaint
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        visible: root.editable
                        glyph: "trash"
                        size: 26
                        tooltip: qsTr("Remove this %1").arg(root.noun)
                        hoverTone: Theme.rose
                        onClicked: {
                            const next = root.rows.slice();
                            next.splice(card.index, 1);
                            root.edited(next);
                        }
                    }
                }

                /*
                  The fields of one row, re-filtered per row.

                  Per row rather than once for the list, because a condition is
                  answered inside the row it belongs to: one folder named
                  outright and the next left to be chosen ask for different
                  things, and the list has no single answer to give.
                */
                Repeater {
                    model: Rules.visibleFields(root.rowFields, card.record, root.scope)

                    delegate: SchemaField {
                        required property var modelData
                        Layout.fillWidth: true
                        compact: true
                        editable: root.editable
                        field: modelData
                        value: card.record[modelData.key]
                        onEdited: (value) => root.replaceRow(
                                      card.index, Rules.withValue(card.record, modelData.key, value))
                    }
                }
            }
        }
    }

    // ---- Nothing in it yet ---------------------------------------------
    Rectangle {
        Layout.fillWidth: true
        visible: root.rows.length === 0
        implicitHeight: emptyLabel.implicitHeight + 24
        radius: Theme.radiusBase
        color: "transparent"
        border.width: 1
        border.color: Theme.borderSubtle

        Text {
            id: emptyLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 14
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No %1 yet. Nothing is added to any agent until you add one.").arg(root.noun + "s")
            color: Theme.textFaint
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    GhostButton {
        visible: root.editable
        implicitHeight: 32
        font.pixelSize: 12
        text: qsTr("Add a %1").arg(root.noun)
        onClicked: {
            const next = root.rows.slice();
            // From the schema's own defaults, so a new row arrives with the
            // choices it declares rather than with blanks the person has to
            // discover are meaningful.
            next.push(Rules.defaults(root.rowFields, root.scope));
            root.edited(next);
        }
    }
}
