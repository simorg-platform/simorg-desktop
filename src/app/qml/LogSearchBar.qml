// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * A box to type in, a count, and two arrows: finding a word in a log.
 *
 * Two shapes. In a host's own header it is a box that is always there — see
 * {@link toolbar} — and anywhere else it is a strip across the top of the log
 * that ⌘F opens.
 *
 * The strip is deliberately not a dialog and not a popup. A log is read by
 * scrolling, and a window that covered part of it while somebody looked for
 * something in it would be hiding the answer. So it takes a row of the pane and
 * the log keeps the rest — and it stays open while the container goes on
 * printing, because "does this word come up again" is most of why anybody
 * searches a live log.
 *
 * ## What the count means while it is climbing
 *
 * Everything, not just what is on screen: {@link LogSearch} walks the whole log
 * in slices, so the number goes up for as long as the walk lasts. That is what
 * the spinner is for. A number that quietly stops being wrong is worse than one
 * that says it is not finished — somebody reading "3 of 12" has to know whether
 * twelve is the answer.
 */
Item {
    id: root

    /** The engine. Owned by the log, because the log owns the lines. */
    property LogSearch search: null

    /**
     * Drawn as a box in a host's header, always there, rather than as a strip.
     *
     * A header with room for the box is a better home for it than a button
     * that makes one appear: finding something is one click into it rather
     * than two. It loses the strip's ground and its leading glyph, and the
     * count and the way out move inside the box — beside it they would take
     * their width out of the box on the first letter typed, and a box whose
     * edge jumps under the cursor is a hard thing to type into.
     *
     * The log still has to be told where its search box is, or ⌘F would open
     * a strip under this one: see LogView.searchField.
     */
    property bool toolbar: false

    /** Whether the strip is open at all. Not read in a toolbar, where it always is. */
    property bool open: false

    /** True while there is a search for Esc to end: an open strip, or words in the box. */
    readonly property bool searching: root.toolbar ? field.text.length > 0 : root.open

    /** What the count says, wherever it is drawn. */
    readonly property string countText: {
        if (!root.search || root.search.term.length === 0)
            return "";
        if (root.search.term.length < 2)
            return qsTr("Two letters or more");
        if (root.search.count === 0)
            return root.search.scanning ? qsTr("Searching…") : qsTr("No matches");
        return qsTr("%1 of %2").arg(root.search.position).arg(root.search.count);
    }
    readonly property color countColor: root.search && root.search.count === 0
                                        && !root.search.scanning
                                        && root.search.term.length >= 2
                                        ? Theme.textFaint : Theme.textBody

    signal closeRequested()

    implicitHeight: root.toolbar ? 28 : root.open ? 40 : 0
    // Clipped for the way the strip opens. Not in a toolbar, where it would cut
    // away the tooltips its buttons draw above themselves.
    clip: !root.toolbar
    // A closed strip is not drawn at all, rather than drawn into no height:
    // clipped to nothing, its glyphs still came through the software renderer
    // over the first line of a narrow log.
    visible: root.toolbar || root.open || root.height > 0

    Behavior on implicitHeight {
        enabled: !root.toolbar
        NumberAnimation {
            duration: Theme.duration(Theme.durFast)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    function focusInput() {
        field.forceActiveFocus();
        field.selectAll();
    }

    /**
     * Done searching.
     *
     * The words go first, which is what takes the marks off the log, and the
     * host decides the rest: a strip closes, a box in a header hands the
     * keyboard back to the lines.
     */
    function finish() {
        field.text = "";
        root.closeRequested();
    }

    Rectangle {
        anchors.fill: parent
        color: root.toolbar ? "transparent" : Theme.alpha(Theme.sky, 0.05)

        Rectangle {
            visible: !root.toolbar
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.toolbar ? 0 : 16
            anchors.rightMargin: root.toolbar ? 0 : 10
            spacing: root.toolbar ? 4 : 8

            Glyph {
                visible: !root.toolbar
                name: "eye"
                size: 14
                thickness: 1.6
                tone: Theme.alpha(Theme.sky, 0.8)
            }

            Rectangle {
                id: box

                Layout.fillWidth: root.toolbar
                Layout.preferredWidth: root.toolbar ? -1 : 260
                Layout.preferredHeight: root.toolbar ? 28 : 26
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.textPrimary, 0.05)
                border.width: 1
                border.color: field.activeFocus ? Theme.alpha(Theme.blue, 0.6)
                                                : Theme.borderSubtle
                opacity: root.enabled ? 1 : 0.35

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: inside.visible ? inside.width + 10 : 9
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.monoFamily
                    selectionColor: Theme.alpha(Theme.blue, 0.45)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    // Straight through, with no debounce of its own: LogSearch
                    // restarts on every change and walks in slices, so a long
                    // word being typed costs a few slices of a scan that is
                    // abandoned rather than a frozen window.
                    onTextChanged: if (root.search) root.search.term = text

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Escape) {
                            root.finish();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.search) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    root.search.previous();
                                else
                                    root.search.next();
                            }
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text.length === 0
                        text: qsTr("Find in this log")
                        color: Theme.textFaint
                        font.pixelSize: 12
                    }
                }

                // The count and the way out, inside the box when it sits in a
                // header. See `toolbar` for why not beside it.
                Row {
                    id: inside
                    visible: root.toolbar && field.text.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    BusyRing {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.search !== null && root.search.scanning
                        running: visible
                        size: 12
                        tone: Theme.alpha(Theme.sky, 0.8)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.countText
                        color: root.countColor
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "close"
                        tooltip: qsTr("Stop searching  (Esc)")
                        size: 22
                        onClicked: root.finish()
                    }
                }
            }

            BusyRing {
                visible: !root.toolbar && root.search !== null && root.search.scanning
                running: visible
                size: 14
                tone: Theme.alpha(Theme.sky, 0.8)
            }

            Text {
                visible: !root.toolbar
                Layout.minimumWidth: 90
                text: root.countText
                color: root.countColor
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Item {
                visible: !root.toolbar
                Layout.fillWidth: true
            }

            IconButton {
                glyph: "arrow-left"
                tooltip: qsTr("Previous match  (⇧⏎)")
                size: root.toolbar ? 28 : 26
                enabled: root.search !== null && root.search.count > 0
                opacity: enabled ? 1 : 0.35
                onClicked: root.search.previous()
            }

            IconButton {
                glyph: "arrow-right"
                tooltip: qsTr("Next match  (⏎)")
                size: root.toolbar ? 28 : 26
                enabled: root.search !== null && root.search.count > 0
                opacity: enabled ? 1 : 0.35
                onClicked: root.search.next()
            }

            IconButton {
                visible: !root.toolbar
                glyph: "close"
                tooltip: qsTr("Stop searching  (Esc)")
                size: 26
                onClicked: root.finish()
            }
        }
    }

    // Emptied on the way out, so the highlights go with the strip rather than
    // staying on the log behind it.
    onOpenChanged: {
        if (root.open)
            root.focusInput();
        else
            field.text = "";
    }
}
