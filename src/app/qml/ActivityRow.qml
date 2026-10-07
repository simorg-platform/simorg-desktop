// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg
import "ActivityText.js" as ActivityText

/**
 * One line of what this computer has been asked to do.
 *
 * Five columns, always in the same places, because a log is read by scanning
 * down one of them: when it happened, **how loudly it is said**, what sort of
 * thing it was, who it was about, and what happened. The message is already a
 * sentence — see {@link simorg::ActivityJournal}, which is the only place a
 * frame from the platform is turned into words — so nothing here decodes
 * anything.
 *
 * ## Level and kind are two columns, not one
 *
 * One column — the kind's icon painted in the level's colour — would mean a
 * glance tells you *either* that something was a container event *or* that it
 * needed attention, never both, and the amber would be easy to miss in a column
 * of icons that are all different shapes anyway. So the level gets its own
 * labelled pill in a fixed-width column — `WARN` and `ERROR` are read as words
 * before any colour is — and the kind icon keeps a colour that means the kind.
 *
 * The tag text comes from {@link simorg::activityLevelTag} rather than from a
 * table here, because Simorg CLI's `sim logs` prints the same five words and a log that
 * disagreed with itself across two front ends would be two products.
 */
Item {
    id: root

    required property string timeText
    /** Empty for an entry from today, which is most of them. */
    required property string dateText
    /** `session`, `agent`, `prompt`, `virtual-machine`, `container`. */
    required property string kind
    /** `debug`, `info`, `notice`, `warning`, `error`. */
    required property string level
    /** `DEBUG`, `INFO`, `NOTICE`, `WARN`, `ERROR` — from the journal, not from here. */
    required property string levelTag
    required property string message
    required property string agentSlug
    required property string virtualMachine
    /** False on a page that is already about one agent. */
    property bool showSubject: true

    /**
     * Whether this row answers the pointer itself.
     *
     * Off in a log, where the whole list is one selection: the rows are drawn
     * by {@link LogSelection} and a sheet over the top handles every press, so a
     * row that also selected itself would be two highlights fighting over one
     * drag. On in the few lines shown on an agent's own page, where there is no
     * sheet and no list — six rows in a column — and a sentence that cannot be
     * dragged across is a sentence somebody photographs instead of copying.
     */
    property bool selectable: false

    implicitHeight: Math.max(30, text.implicitHeight + 12)

    /**
     * Which character of the message is at that point in this row, or -1 for a
     * point in the columns before it.
     *
     * The columns are not text a highlight can start inside — they are a
     * timestamp, a pill and an icon — so a drag that begins on one of them is
     * a drag that begins on the row, and saying -1 rather than 0 is what lets
     * the caller tell those two apart. See AgentActivityLog: a drag from the
     * timestamp takes the whole entry, timestamp and all, which is what
     * somebody dragging from the left edge of a row has asked for.
     */
    function messagePositionAt(x, y) {
        const point = root.mapToItem(text, x, y);
        if (point.x < 0)
            return -1;
        return text.positionAt(point.x, point.y);
    }

    /** The word of the message around that point. `[-1, -1]` before the column. */
    function messageWordAt(x, y) {
        const point = root.mapToItem(text, x, y);
        if (point.x < 0)
            return [-1, -1];
        text.cursorPosition = text.positionAt(point.x, point.y);
        text.selectWord();
        return [text.selectionStart, text.selectionEnd];
    }

    /**
     * This row as the line `sim logs` prints, timestamp and level and all.
     *
     * What ⌘C takes when nothing is highlighted: somebody who has clicked a line
     * and pressed copy means the line, not the part of it their pointer happened
     * to be over — and the columns beside the sentence are half of what a bug
     * report needs.
     */
    function asText() {
        return ActivityText.oneLine({
            timeText: root.timeText, dateText: root.dateText, levelTag: root.levelTag,
            message: root.message, agentSlug: root.agentSlug, virtualMachine: root.virtualMachine
        });
    }

    /** Highlights part of the message. An empty range clears it. */
    function selectMessage(from, to) {
        if (to > from)
            text.select(from, to);
        else
            text.deselect();
    }

    /** The level's colour. Everything in the pill is drawn from this one value. */
    readonly property color levelTone: {
        switch (root.level) {
        case "error": return Theme.rose;
        case "warning": return Theme.amber;
        case "notice": return Theme.emerald;
        case "debug": return Theme.textFaint;
        default: return Theme.sky;
        }
    }

    readonly property string levelGlyph: {
        switch (root.level) {
        case "error": return "close-circle";
        case "warning": return "alert";
        case "notice": return "check-circle";
        case "debug": return "bug";
        default: return "info";
        }
    }

    /*
      The kind's own colour, which is the point of it having a column.

      One hue per category and nothing else in this app uses them for anything
      else: violet is what an agent is drawn in on its card, and blue is the
      containers section. A row can be placed by its icon without being read.
    */
    readonly property color kindTone: {
        switch (root.kind) {
        case "agent": return Theme.violet;
        case "prompt": return Theme.cyan;
        case "virtual-machine": return Theme.indigo;
        case "container": return Theme.blue;
        default: return Theme.sky;
        }
    }

    readonly property string kindGlyph: {
        switch (root.kind) {
        case "agent": return "robot";
        case "prompt": return "spark";
        case "virtual-machine": return "vm";
        case "container": return "container";
        default: return "network";
        }
    }

    /** True for the two levels that mean somebody has to look. */
    readonly property bool loud: root.level === "warning" || root.level === "error"

    readonly property string subject: root.agentSlug.length > 0 ? root.agentSlug
                                    : root.virtualMachine.length > 0 ? root.virtualMachine
                                    : ""

    /*
      A wash behind the loud rows, and a bar down their left edge.

      The pill alone is enough to *find* a warning once you are looking at it;
      this is what makes one findable while scrolling past a hundred rows, and
      it is the same treatment a stderr line gets in AgentContainerLogs, for the
      same reason and in the same colours.
    */
    Rectangle {
        anchors.fill: parent
        visible: root.loud
        color: Theme.alpha(root.levelTone, 0.05)
    }

    Rectangle {
        visible: root.loud
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: Theme.alpha(root.levelTone, 0.5)
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        ElidedText {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            Layout.preferredWidth: 96
            text: root.dateText.length > 0
                  ? root.dateText + " " + root.timeText
                  : root.timeText
            color: Theme.textFaint
            font.pixelSize: 11
            font.family: Theme.monoFamily
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }

        // ---- How loudly it is said ---------------------------------------
        /*
          A fixed width, so the messages start in the same column.

          The pill inside is only as wide as its own contents; the *column* is
          the width of the widest tag. A log where `ERROR` pushed its sentence
          two characters right of every `INFO` beside it would be harder to
          scan than one with no levels at all.
        */
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 74
            Layout.preferredHeight: 18

            Rectangle {
                width: pill.implicitWidth + 14
                height: parent.height
                radius: 3
                color: Theme.alpha(root.levelTone, root.level === "debug" ? 0.08 : 0.13)
                border.width: 1
                border.color: Theme.alpha(root.levelTone, root.level === "debug" ? 0.18 : 0.3)

                RowLayout {
                    id: pill
                    anchors.centerIn: parent
                    spacing: 5

                    Glyph {
                        name: root.levelGlyph
                        size: 11
                        thickness: 1.7
                        tone: root.levelTone
                    }

                    Text {
                        text: root.levelTag
                        color: root.levelTone
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                        font.family: Theme.monoFamily
                    }
                }
            }
        }

        Glyph {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            name: root.kindGlyph
            size: 13
            thickness: 1.6
            tone: Theme.alpha(root.kindTone, 0.75)
        }

        ElidedText {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 128
            visible: root.showSubject
            text: root.subject
            color: root.subject.length > 0 ? Theme.textBody : "transparent"
            font.pixelSize: 12
            font.family: Theme.monoFamily
            elide: Text.ElideRight
        }

        /*
          The one column that can be highlighted by character.

          A row is five columns and a selection is a run of characters, so the
          two only meet in one place: the sentence. Dragging across whole rows
          takes the whole entry, timestamp and level and all — see
          AgentActivityLog, which is what maps this column's offsets into the
          entry's — and dragging inside one row takes exactly the words under
          the pointer, which is how an identifier gets out of here and into a
          search box.
        */
        TextEdit {
            id: text
            Layout.fillWidth: true
            text: root.message
            color: root.loud ? root.levelTone
                 : root.level === "debug" ? Theme.textFaint
                 : Theme.textBody
            font.pixelSize: 12
            wrapMode: TextEdit.WordWrap
            textFormat: TextEdit.PlainText

            /*
              Read only, and in charge of its own selection only where nothing
              else is: in a log the pointer is handled once for the whole list
              — see LogView — and here it is handled by nobody, so the row does
              it. `persistentSelection` keeps a highlight drawn either way,
              because in the log the selection is driven from outside and this
              editor never holds focus at all.
            */
            readOnly: true
            activeFocusOnPress: root.selectable
            selectByMouse: root.selectable
            selectByKeyboard: root.selectable
            persistentSelection: true
            selectionColor: Theme.alpha(Theme.blue, 0.45)
            selectedTextColor: Theme.textPrimary

            /*
              ⌘C, where this row is the one holding the pointer.

              Through `App` rather than through the editor's own `copy()`, which
              is the seam everything this application pushes outward goes
              through — and in a log this never runs at all, because there the
              row has no focus and the whole list answers the keyboard at once.
            */
            Keys.onPressed: function (event) {
                if (!root.selectable || !event.matches(StandardKey.Copy))
                    return;
                App.copyToClipboard(text.selectedText.length > 0 ? text.selectedText : root.asText());
                event.accepted = true;
            }
        }
    }
}
