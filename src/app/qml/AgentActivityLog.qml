// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "ActivityText.js" as ActivityText

/**
 * What the Simorg platform has asked this computer to do, in words.
 *
 * ## No payloads, ever
 *
 * A frame from the Hub carries a prompt, a chat id and the sender's bearer
 * token. **None of it appears here.** What appears is that a turn arrived, for
 * which agent, when, and whether there was anything here able to take it —
 * which is the whole of what somebody watching wants to know, and none of what
 * a screen or a log file should ever hold. The same entries are written to a
 * file that any process on this computer can read, so the rule is not a
 * preference: it is what makes the file safe to have.
 *
 * That also makes the entries useful. "A new turn arrived, but its container is
 * not running" is a sentence somebody can act on; a pretty-printed JSON frame
 * is a thing they have to decode before they know whether their machine is
 * working.
 *
 * ## Two filters, because a log is asked two questions
 *
 * *What sort of thing* and *how badly do I need to know*. They are orthogonal —
 * a container event can be routine or the reason nothing works — so they are
 * two controls rather than one list of combinations. The level filter is a
 * **floor**, not a selection: "Problems" means warnings and worse, which is the
 * question anybody actually has, and it does not have to be re-taught a list of
 * level names each time one is added.
 *
 * DEBUG is below the floor by default. It exists so that a machine where
 * nothing is happening can still prove it is working — the reconcile passes,
 * the connection being opened, the roster at startup — and none of that is
 * worth a line on the screen somebody opened because an agent is not answering.
 *
 * ## The same log the terminal shows
 *
 * Simorg CLI's `sim logs -f` prints these exact entries, with the same five
 * level tags and the same default floor, because both read one
 * {@link simorg::ActivityJournal}. A screen and a terminal that described the
 * same event differently would be two products.
 *
 * ## Reading it out of the window
 *
 * The entries sit in a {@link LogView}, the same component every other log in
 * this application uses, so they answer a drag, a right click and ⌘C the way
 * the container output two tabs away does. What comes out is the line
 * {@link entryAsText} writes, timestamp and level tag and all, whether it was
 * taken from here or from Simorg CLI's `sim logs`.
 */
Item {
    id: root

    /** Which kinds are shown. Empty means all of them. */
    property string filter: ""

    readonly property var filters: [
        { key: "", label: qsTr("Everything"), glyph: "layers" },
        { key: "prompt", label: qsTr("Turns"), glyph: "spark" },
        { key: "agent", label: qsTr("Agents"), glyph: "robot" },
        { key: "container", label: qsTr("Containers"), glyph: "container" }
    ]

    property int filterIndex: 0

    /**
     * The quietest level shown, as a rank — see {@link simorg::activityLevelRank}.
     *
     * Ranks rather than names, so this and the journal cannot drift: 0 is
     * DEBUG and 3 is WARN, and every row carries its own rank rather than
     * having its level name compared against a list kept here.
     */
    readonly property var levels: [
        { key: 0, label: qsTr("Debug"), glyph: "bug" },
        { key: 1, label: qsTr("Info"), glyph: "info" },
        { key: 3, label: qsTr("Problems"), glyph: "alert", badge: root.problemCount }
    ]

    /** Starts on Info, which is what hides the housekeeping. */
    property int levelIndex: 1
    readonly property int minimumRank: root.levels[root.levelIndex].key

    /** Warnings and errors held right now, whatever else is filtered. */
    property int problemCount: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- What this is, and how to narrow it -------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20
                spacing: 12

                Glyph {
                    name: root.problemCount > 0 ? "alert" : "clock"
                    size: 15
                    thickness: 1.7
                    tone: root.problemCount > 0 ? Theme.amber : Theme.sky
                }

                /*
                  One line that says what is here, and what is wrong with it.

                  The count of problems belongs beside the title rather than
                  only on the filter, because somebody who has not touched the
                  filter is the person most likely to need telling.
                */
                ElidedText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 60
                    text: Activity.count === 0
                          ? qsTr("Nothing has happened here yet")
                        : root.problemCount === 1
                          ? qsTr("1 thing needs a look")
                        : root.problemCount > 1
                          ? qsTr("%1 things need a look").arg(root.problemCount)
                        : qsTr("What Simorg has asked this computer to do")
                    color: Theme.textBody
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                SegmentedControl {
                    items: root.filters
                    currentIndex: root.filterIndex
                    onSelected: function (index) {
                        root.filterIndex = index;
                        root.filter = root.filters[index].key;
                        root.rebuild();
                        // A different set of entries: the place somebody was in the
                        // last one means nothing here, so it opens at the newest.
                        entries.jumpToNewest();
                    }
                }

                SegmentedControl {
                    items: root.levels
                    currentIndex: root.levelIndex
                    onSelected: function (index) {
                        root.levelIndex = index;
                        root.rebuild();
                        entries.jumpToNewest();
                    }
                }

                CopyAction {
                    text: root.rows.length > 0 ? root.asText() : ""
                    tooltip: qsTr("Copy what is shown")
                    copiedLabel: qsTr("%1 entries copied").arg(root.rows.length)
                    size: 28
                }

                IconButton {
                    glyph: "trash"
                    enabled: Activity.count > 0
                    tooltip: qsTr("Clear this view")
                    size: 28
                    onClicked: Activity.clear()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }

        // ---- The entries -------------------------------------------------
        LogView {
            id: entries
            objectName: "entries"

            Layout.fillWidth: true
            Layout.fillHeight: true

            model: root.rows
            /*
              One entry as one line, which is what a selection copies.

              The same layout {@link simorg::ActivityEntry::oneLine} uses, so a
              row copied from here, the log copied from the header and the line
              `sim logs` prints are the same text. See entryAsText.
            */
            textAt: function (index) { return root.entryAsText(root.rows[index]); }
            allText: function () { return root.asText(); }

            listTopMargin: 8
            listBottomMargin: 8
            lineLabel: qsTr("Copy this entry")
            clearable: true
            onClearRequested: Activity.clear()

            /*
              A row of columns rather than a line of text.

              The pill and the timestamp are the whole point of this log, so it
              keeps its own row and takes the selection instead of the other way
              round: highlighting inside a row takes the words under the pointer
              and highlighting across rows takes whole entries, which is the
              shape somebody pasting into a bug report wants anyway.
            */
            rowDelegate: Component {
                Item {
                    id: line

                    required property var modelData
                    required property int index

                    /** The entry as one line: the text this row's offsets index into. */
                    readonly property string canonical: root.entryAsText(line.modelData)
                    /** Where the message begins in it. It is the last column. */
                    readonly property int offset:
                        line.canonical.length - line.modelData.message.length

                    /** True when the whole entry is taken, which is what the wash says. */
                    readonly property bool whole:
                        entries.selection.whole(line.index, line.canonical.length)
                    readonly property int selectionStart:
                        entries.selection.startFor(line.index, line.canonical.length)
                    readonly property int selectionEnd:
                        entries.selection.endFor(line.index, line.canonical.length)

                    width: ListView.view.width
                    implicitHeight: row.implicitHeight

                    /*
                      The columns before the message belong to the row.

                      A drag that starts on the timestamp is a drag that starts
                      on the entry, so it begins at the entry's first character
                      rather than at the sentence's — otherwise dragging across
                      a row from its left edge would quietly copy it without the
                      time it happened, which is the half a bug report needs.
                    */
                    function positionAt(x, y) {
                        const position = row.messagePositionAt(x, y);
                        return position < 0 ? 0 : line.offset + position;
                    }

                    function wordAt(x, y) {
                        const word = row.messageWordAt(x, y);
                        if (word[0] < 0)
                            return [0, line.canonical.length];
                        return [line.offset + word[0], line.offset + word[1]];
                    }

                    /*
                      Either the wash or the highlight, never both: a row that is
                      wholly in says so across its whole width, and one that is
                      partly in says exactly which characters.
                    */
                    function applySelection() {
                        if (line.whole) {
                            row.selectMessage(0, 0);
                            return;
                        }
                        row.selectMessage(Math.max(0, line.selectionStart - line.offset),
                                          Math.max(0, line.selectionEnd - line.offset));
                    }

                    onWholeChanged: line.applySelection()
                    onSelectionStartChanged: line.applySelection()
                    onSelectionEndChanged: line.applySelection()
                    Component.onCompleted: line.applySelection()

                    Rectangle {
                        anchors.fill: parent
                        color: line.whole ? Theme.alpha(Theme.blue, 0.3)
                             : hover.hovered ? Theme.alpha(Theme.sky, 0.04)
                             : "transparent"
                    }

                    ActivityRow {
                        id: row
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 24
                        timeText: line.modelData.timeText
                        dateText: line.modelData.dateText
                        kind: line.modelData.kind
                        level: line.modelData.level
                        levelTag: line.modelData.levelTag
                        message: line.modelData.message
                        agentSlug: line.modelData.agentSlug
                        virtualMachine: line.modelData.virtualMachine
                    }

                    HoverHandler { id: hover }
                }
            }

            // ---- Nothing here yet ---------------------------------------
            emptyState: Component {
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 460)
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 46
                        implicitHeight: 46
                        radius: 6
                        color: Theme.alpha(Theme.textMuted, 0.06)
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Glyph {
                            anchors.centerIn: parent
                            name: root.levelIndex === 2 ? "check-circle" : "clock"
                            size: 22
                            thickness: 1.5
                            tone: Theme.alpha(Theme.textMuted, 0.6)
                        }
                    }

                    /*
                      Four reasons this list is empty, told apart.

                      Nothing has ever happened; nothing of that kind; nothing that
                      loud; and — the one worth being pleased about — nothing wrong.
                      They look identical on a blank screen and only one of them is
                      a reason to go and check something.
                    */
                    Text {
                        Layout.fillWidth: true
                        text: Activity.count === 0
                              ? qsTr("Nothing has been recorded yet")
                            : root.levelIndex === 2
                              ? qsTr("Nothing has gone wrong")
                            : root.filter.length > 0
                              ? qsTr("Nothing of that kind yet")
                            : qsTr("Nothing at this level yet")
                        color: Theme.textBody
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Activity.count === 0
                              ? qsTr("This is where an agent arriving, a turn being delivered and a container coming up are written down as they happen. Nothing that arrives here is a payload: what a turn said stays between the platform and the agent.")
                            : root.levelIndex === 2
                              ? qsTr("No warnings and no errors have been recorded on this computer. Everything this computer has been asked to do is still here under the other two.")
                            : qsTr("Everything this computer has been asked to do is still here; only this filter is empty.")
                        color: Theme.textFaint
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }
                }
            }
        }

    }

    /**
     * The entries to draw, rebuilt rather than bound.
     *
     * A `ListView` could take the journal as its model directly, and would, if
     * the filters did not exist: Qt has no sort-filter proxy exposed to QML
     * without writing one in C++, and one more C++ class for seven buttons is
     * the wrong trade. Rebuilding a list of at most five hundred small maps
     * costs nothing on any machine that can run a compositor.
     */
    property var rows: []

    function rebuild() {
        const before = root.rows.length;
        const out = [];
        let problems = 0;
        for (let i = 0; i < Activity.count; ++i) {
            const entry = Activity.at(i);
            // Counted over the whole journal, not over what survives the
            // filters: a badge that went to zero because somebody was looking
            // at Turns would be a badge that lies at the only moment it matters.
            if (entry.levelRank >= 3)
                ++problems;
            if (root.filter.length > 0 && entry.kind !== root.filter)
                continue;
            if (entry.levelRank < root.minimumRank)
                continue;
            out.push(entry);
        }
        root.problemCount = problems;
        /*
          A shorter list is a different list.

          Entries are appended, so a selection keeps meaning what it meant while
          the list only grows. It stops meaning anything the moment rows leave —
          a filter narrowing, the journal dropping its oldest, somebody emptying
          it — because every row after the gap has moved up by one and the
          highlight would silently be over other entries than the ones it was
          drawn around.
        */
        if (out.length < before)
            entries.clearSelection();
        root.rows = out;
    }

    /**
     * One entry, as plain text.
     *
     * Laid out the way {@link simorg::ActivityEntry::oneLine} lays a line out,
     * padded tag and all, so a line copied from a row, a log copied from the
     * header and one piped from the terminal are all the same text. A row that
     * spelled itself differently would make a bug report say two things about
     * one event — which is why the layout is in `ActivityText.js` and not here:
     * an agent's own page shows the last few of these too.
     */
    function entryAsText(entry) {
        return ActivityText.oneLine(entry);
    }

    /** Everything on screen, as plain text — what the header's copy hands over. */
    function asText() {
        return ActivityText.asText(root.rows);
    }

    Component.onCompleted: root.rebuild()

    Connections {
        target: Activity
        function onCountChanged() { root.rebuild(); }
    }
}
