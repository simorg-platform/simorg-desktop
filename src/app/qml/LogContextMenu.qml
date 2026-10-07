// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The right click menu every log in this application shows.
 *
 * One component rather than a menu written at each of the places a log is
 * drawn, because the point of the exercise is that they cannot drift: the same
 * four words, in the same order, doing the same thing, whether the log is a
 * container's output, the engine's or the journal of what the platform has
 * asked this computer to do.
 *
 * ## Why a menu at all
 *
 * Because that is where a person looks. Selecting text and reaching for the
 * right button is how text is copied everywhere else on a desktop, and a log
 * that answered a right click with nothing would read as a picture of a log
 * rather than as text. The keyboard shortcut does the same thing and is faster
 * for anybody who knows it; the menu is how they find out it exists.
 *
 * ## Copy is two entries, never one
 *
 * "Copy" takes what is highlighted. **"Copy this line"** takes the line that was
 * right clicked, and shows only when nothing is highlighted — a line's copy
 * without a button on every one of five thousand rows, and without the reader having to select a line precisely
 * before they can have it. "Copy everything" is the third, because the reason
 * most logs are opened at all is to paste the lot into a bug report.
 */
Menu {
    id: root

    /** True when something is highlighted, which is what "Copy" acts on. */
    property bool hasSelection: false
    /** True when the right click landed on a row, which "Copy this line" acts on. */
    property bool hasLine: false
    /** What one row is called here. An entry in the journal, a line in a log. */
    property string lineLabel: qsTr("Copy this line")
    /**
     * What taking the lot is called.
     *
     * "Everything" is the log's word for it, and the wrong one where this menu
     * is opened on a single sentence — see {@link SelectableText}, which calls
     * it "Copy all". The entry is the same act either way, so it is one entry
     * with two names rather than two menus.
     */
    property string everythingLabel: qsTr("Copy everything")
    /** Whether this log can be emptied, and what that is called. */
    property bool clearable: false
    property string clearLabel: qsTr("Clear this view")
    property bool clearEnabled: true
    /** False where nothing can be highlighted — a label — so "Select all" is not offered. */
    property bool selectable: true
    /** False where the whole text is the one thing to copy, so "Copy" says it alone. */
    property bool offersEverything: true

    signal copySelection()
    signal copyLine()
    signal copyEverything()
    signal selectEverything()
    signal clearRequested()

    width: 232
    padding: 6

    background: GlassPanel {
        implicitWidth: root.width
        radius: Theme.radiusBase
        opaque: true
    }

    /*
      One shape for every row of the menu.

      Inline rather than in its own file: it is six lines of chrome that only
      this menu uses, and a separate component would be one more thing to keep
      in step with the rest of the application's menus for no reader's benefit.
    */
    component Entry: MenuItem {
        id: entry

        property string glyph: "copy"
        property color tone: Theme.sky

        implicitHeight: 36
        height: visible ? implicitHeight : 0

        contentItem: RowLayout {
            spacing: 10

            Glyph {
                name: entry.glyph
                size: 15
                thickness: 1.6
                tone: !entry.enabled ? Theme.alpha(Theme.textFaint, 0.5)
                    : entry.hovered ? entry.tone : Theme.textBody
            }

            /*
              A plain `Text`, not an `ElidedText`: that one opens this menu to
              copy itself, and the two naming each other is a cycle the QML
              engine refuses — every window of the application failed to load
              when this was an ElidedText as well. The entries are short words
              of this menu's own, with nothing to hand back or copy.
            */
            Text {
                Layout.fillWidth: true
                text: entry.text
                color: !entry.enabled ? Theme.alpha(Theme.textFaint, 0.6)
                     : entry.hovered ? Theme.textPrimary : Theme.textBody
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
            }
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: entry.hovered && entry.enabled
                   ? Theme.alpha(entry.tone, 0.1) : "transparent"
        }
    }

    Entry {
        text: qsTr("Copy")
        glyph: "copy"
        enabled: root.hasSelection
        onTriggered: root.copySelection()
    }

    Entry {
        text: root.lineLabel
        glyph: "copy"
        // Only while there is no highlight: with one, "Copy" is the entry that
        // means what the reader has already said, and two copies side by side
        // would make them stop and work out which.
        visible: !root.hasSelection && root.hasLine
        onTriggered: root.copyLine()
    }

    Entry {
        text: root.everythingLabel
        glyph: "layers"
        visible: root.offersEverything
        onTriggered: root.copyEverything()
    }

    Entry {
        text: qsTr("Select all")
        glyph: "check"
        visible: root.selectable
        onTriggered: root.selectEverything()
    }

    MenuSeparator {
        visible: root.clearable
        height: visible ? implicitHeight : 0

        contentItem: Rectangle {
            implicitHeight: 1
            color: Theme.borderSubtle
        }
    }

    Entry {
        text: root.clearLabel
        glyph: "trash"
        tone: Theme.rose
        visible: root.clearable
        enabled: root.clearEnabled
        onTriggered: root.clearRequested()
    }
}
