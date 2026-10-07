// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * A name, renamed where it is read.
 *
 * The name with a pencil beside it. Pressing either opens a field on the name,
 * all of it selected, so typing replaces it: Enter or clicking away keeps what
 * was typed, Escape puts the name back, and a blank name is not a name. The same
 * gesture as a zone's or a machine's name on the Logos, so renaming something is
 * one thing across Simorg.
 *
 * ## Between asking and hearing
 *
 * A rename is asked of the platform, and the new name comes back as news (for
 * a machine, over the service's Hub socket). What was kept is shown at once and
 * stays shown until `name` changes, so the name never flicks back to the old one
 * in the moment between the platform's answer and that news; the pencil turns
 * into a wheel while the platform is asked. A refusal opens the field again on
 * what was typed, with the platform's sentence under it.
 */
Item {
    id: root

    /** The name as it stands, from wherever it is kept. */
    property string name: ""
    /** Whether it may be renamed here. Otherwise it is only read. */
    property bool editable: true
    /** A rename is being asked. */
    property bool busy: false
    /** Why the last rename was refused, in the platform's words; empty when it was not. */
    property string error: ""
    /** The field's label while it is open. */
    property string fieldLabel: qsTr("Name")
    property string fieldGlyph: ""
    property int maximumLength: 255
    property int pixelSize: Theme.fontBody
    property int fontWeight: Font.DemiBold

    /** Somebody kept `name` as the new name. */
    signal renameRequested(string name)

    /** The field is open. */
    readonly property bool editing: root._open
    /** What is shown: a name asked for, until `name` is news of it. */
    readonly property string shown: root._kept.length > 0 ? root._kept : root.name

    property bool _open: false
    property string _kept: ""

    implicitWidth: root._open ? field.implicitWidth : line.implicitWidth
    implicitHeight: root._open ? field.implicitHeight : line.implicitHeight

    /** Opens the field on the name. */
    function open() {
        if (!root.editable || root.busy || root._open)
            return;
        field.text = root.shown;
        root._open = true;
        field.selectAllText();
    }

    function finish(keep) {
        if (!root._open)
            return;
        const next = field.text.trim();
        root._open = false;
        if (!keep || next.length === 0 || next === root.shown)
            return;
        root._kept = next;
        root.renameRequested(next);
    }

    // News of a name — this rename's or anybody's — is the name from now on.
    onNameChanged: root._kept = ""

    onErrorChanged: {
        if (root.error.length === 0 || root._kept.length === 0)
            return;
        const typed = root._kept;
        root._kept = "";
        field.text = typed;
        root._open = true;
        field.selectAllText();
    }

    RowLayout {
        id: line
        objectName: "editableNameLine"
        width: parent.width
        visible: !root._open
        spacing: 6

        /*
          Never wider than the name, so the pencil sits beside it, and never
          narrower when there is room: rounded up, because a layout places items
          on whole pixels and capping at the exact width elides a name that fits.
        */
        ElidedText {
            objectName: "editableNameText"
            Layout.fillWidth: true
            Layout.maximumWidth: Math.ceil(implicitWidth)
            text: root.shown
            color: Theme.textPrimary
            font.pixelSize: root.pixelSize
            font.weight: root.fontWeight
            elide: Text.ElideRight

            HoverHandler {
                enabled: root.editable && !root.busy
                cursorShape: Qt.IBeamCursor
            }
            TapHandler {
                enabled: root.editable && !root.busy
                onTapped: root.open()
            }
        }

        IconButton {
            objectName: "editableNameRename"
            visible: root.editable
            glyph: "pencil"
            size: 24
            tone: Theme.textFaint
            busy: root.busy
            tooltip: qsTr("Rename")
            onClicked: root.open()
        }

        Item { Layout.fillWidth: true }
    }

    SimorgTextField {
        id: field
        objectName: "editableNameField"
        width: parent.width
        visible: root._open
        label: root.fieldLabel
        glyph: root.fieldGlyph
        maximumLength: root.maximumLength
        cancelOnEscape: true
        errorText: root._open ? root.error : ""
        onAccepted: root.finish(true)
        onEscaped: root.finish(false)
        // Clicking away keeps what was typed, as Enter does.
        onEditingChanged: if (!editing) root.finish(true)
    }
}
