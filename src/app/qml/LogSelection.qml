// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * Where a highlight in a log starts and where it ends.
 *
 * Every log in this application shows its lines through a `ListView`, because a
 * container that writes a megabyte a second cannot be held in one text
 * document. That buys the scrolling and costs the selection: rows are separate
 * items, and Qt has no idea that dragging from one into the next means anything.
 * This is the thing that knows.
 *
 * ## Two points, not a set of rows
 *
 * A selection is an **anchor** — where the drag started — and a **head**, where
 * the pointer is now, each of them a row and a character offset inside that
 * row's text. Everything else is derived: which of the two comes first, which
 * rows are covered, how much of the first and last rows are in. Storing it as a
 * list of selected rows instead would lose the two half-rows at the ends, which
 * is the whole point of dragging rather than clicking.
 *
 * The head may come *before* the anchor. Dragging upwards is how anybody
 * selects the line above the one they are looking at, so it is normalised here
 * rather than being something each caller has to remember.
 *
 * ## Offsets are into the row's text, whatever that row draws
 *
 * A plain log row draws exactly its own line, so its offsets are the ones you
 * would expect. An activity row draws five columns and only one of them can be
 * highlighted by character, so it maps its message into the same coordinates by
 * adding the width of the prefix — see AgentActivityLog. Both then answer the
 * same question the same way, which is what lets one selection serve both.
 */
QtObject {
    id: root

    /** The row the drag started on. Negative when there is no selection. */
    property int anchorLine: -1
    /** The character offset in that row where it started. */
    property int anchorPos: 0
    /** The row the pointer is on now. */
    property int headLine: -1
    /** The character offset in that row. */
    property int headPos: 0

    /** True when nothing is highlighted, including a bare caret. */
    readonly property bool empty: root.anchorLine < 0 || root.headLine < 0
                                  || (root.anchorLine === root.headLine
                                      && root.anchorPos === root.headPos)

    /** True when the head is before the anchor, i.e. the drag went upwards. */
    readonly property bool backwards: root.headLine < root.anchorLine
                                      || (root.headLine === root.anchorLine
                                          && root.headPos < root.anchorPos)

    readonly property int firstLine: root.empty ? -1
                                   : root.backwards ? root.headLine : root.anchorLine
    readonly property int firstPos: root.backwards ? root.headPos : root.anchorPos
    readonly property int lastLine: root.empty ? -1
                                  : root.backwards ? root.anchorLine : root.headLine
    readonly property int lastPos: root.backwards ? root.anchorPos : root.headPos

    /** Starts a selection, throwing away whatever was highlighted before. */
    function begin(line, position) {
        root.anchorLine = line;
        root.anchorPos = position;
        root.headLine = line;
        root.headPos = position;
    }

    /** Moves the head. Begins one where there was nothing to extend. */
    function extend(line, position) {
        if (root.anchorLine < 0) {
            root.begin(line, position);
            return;
        }
        root.headLine = line;
        root.headPos = position;
    }

    /** Highlights a known range outright, for "select all" and a double click. */
    function cover(fromLine, fromPos, toLine, toPos) {
        root.anchorLine = fromLine;
        root.anchorPos = fromPos;
        root.headLine = toLine;
        root.headPos = toPos;
    }

    function clear() {
        root.anchorLine = -1;
        root.anchorPos = 0;
        root.headLine = -1;
        root.headPos = 0;
    }

    /** Whether any part of that row is highlighted. */
    function covers(line) {
        return !root.empty && line >= root.firstLine && line <= root.lastLine;
    }

    /** Where the highlight starts in that row, given how long the row's text is. */
    function startFor(line, length) {
        if (!root.covers(line))
            return 0;
        return line === root.firstLine ? Math.max(0, Math.min(root.firstPos, length)) : 0;
    }

    /** Where it ends. Equal to {@link startFor} when nothing of the row is in. */
    function endFor(line, length) {
        if (!root.covers(line))
            return 0;
        return line === root.lastLine ? Math.max(0, Math.min(root.lastPos, length)) : length;
    }

    /**
     * Whether the whole of that row is in, ends included.
     *
     * A row drawn as columns cannot highlight itself by character, so it draws a
     * wash across the whole row instead — but only when the whole row really is
     * taken, or the wash would claim more than has been selected.
     */
    function whole(line, length) {
        return length > 0 && root.covers(line)
               && root.startFor(line, length) === 0 && root.endFor(line, length) === length;
    }

    /**
     * What is highlighted, as text, ready for the clipboard.
     *
     * `textAt` answers with one row's text by index, and has to answer for rows
     * that are not on screen: a selection dragged across a thousand lines is
     * mostly rows no delegate was ever built for.
     */
    function textOfRange(textAt) {
        if (root.empty)
            return "";

        const out = [];
        for (let line = root.firstLine; line <= root.lastLine; ++line) {
            const text = textAt(line);
            if (text === undefined || text === null)
                continue;
            out.push(text.substring(root.startFor(line, text.length),
                                    root.endFor(line, text.length)));
        }
        return out.join("\n");
    }
}
