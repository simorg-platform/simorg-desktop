// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * Finding a word in a log that is still being written.
 *
 * ## Why this is not one `indexOf` loop
 *
 * A log window can hold a hundred thousand lines, or every line there has ever
 * been if somebody has turned the cap off, and it is *live*: lines arrive while
 * the search is running and the oldest are dropped out from under it. Three
 * things follow, and each of them is a piece of this file.
 *
 * **Scanning is done in slices.** A loop over a million strings is a second of
 * frozen window, on the one screen where somebody is watching something happen.
 * A timer does a few thousand lines per tick instead, so the count climbs while
 * the log keeps scrolling, and a spinner beside it says the number is not final
 * yet. That is also why the count is a property rather than a return value.
 *
 * **Nothing is highlighted here.** Drawing is the delegate's job and a delegate
 * exists only for the rows on screen, so the cost of highlighting is bounded by
 * the window rather than by the log. What this holds is *where* the matches are;
 * what a row draws is the handful of them that are in it. Counting and jumping
 * see every match, painting sees a screenful.
 *
 * **Line numbers are absolute.** A capped log drops its oldest line every time
 * a new one arrives, so row 0 is a different line one second later — and a
 * search that stored row numbers would be pointing at the wrong text, silently,
 * on exactly the busy container somebody is searching *because* it is busy. So
 * every match is recorded against the line's absolute number since the search
 * began, and {@link offset} is how many have been dropped. A row is
 * `absolute - offset`.
 *
 * The stale matches at the front are not swept out when lines are dropped, for
 * the same reason the scan is sliced: a sweep per dropped line is work
 * proportional to the number of matches, on every line a busy container prints.
 * {@link first} walks forward past them instead, which is amortised nothing —
 * the matches are in ascending order, so the dead ones are always at the front.
 */
QtObject {
    id: root

    /** What to look for. Empty stops everything and clears the count. */
    property string term: ""

    /** How many lines the view holds right now. The host keeps this in step. */
    property int lineCount: 0

    /** One row's text by row number, the same function {@link LogView} takes. */
    property var textAt: function (index) { return ""; }

    /**
     * Lines per tick.
     *
     * Four thousand short lines is well under a frame on any machine this runs
     * on, and at sixty ticks a second it walks a quarter of a million lines
     * before somebody has finished reading the word they typed.
     */
    readonly property int chunk: 4000

    /** True while there is still log left to walk. The spinner reads this. */
    property bool scanning: false

    /** How many occurrences have been found so far. Climbs while scanning. */
    readonly property int count: root.total - root.first

    /** Which occurrence the view is sitting on, counted from one. 0 for none. */
    readonly property int position: root.current < root.first ? 0
                                    : root.current - root.first + 1

    /**
     * Bumped whenever the matches move, so a row's highlights can depend on it.
     *
     * The arrays below are mutated in place — pushing a match onto a JavaScript
     * array does not notify anything in QML — so this is what a delegate
     * actually binds to. One integer rather than reassigning an array of a
     * million entries on every tick.
     */
    property int revision: 0

    /* --------------------------------------------------------------- state */

    /** Lines dropped from the front of the view since this search began. */
    property int offset: 0
    /** The absolute line this has scanned up to. */
    property int scannedTo: 0
    /** Index of the first match that is still in the view. See the note above. */
    property int first: 0
    /** How many matches have been found in total, dead ones included. */
    property int total: 0
    /** The occurrence next/previous is sitting on, as an index into the arrays. */
    property int current: -1

    /** Absolute line number per match, ascending. */
    property var lines: []
    /** Character offset within that line, per match. */
    property var starts: []
    /** Absolute line number → the offsets in it, for the rows being drawn. */
    property var byLine: ({})

    /** Ask the view to put this row on screen. */
    signal jumpWanted(int row)

    /* ------------------------------------------------------------ the scan */

    function needle() {
        return root.term.toLowerCase();
    }

    /** Everything forgotten and started again. */
    function restart() {
        root.lines = [];
        root.starts = [];
        root.byLine = ({});
        root.offset = 0;
        root.scannedTo = 0;
        root.first = 0;
        root.total = 0;
        root.current = -1;
        root.revision += 1;

        // One character finds something in nearly every line of nearly every
        // log, which is a count nobody can use and a lot of work to produce.
        // Two is where a search starts being a search.
        if (root.term.length < 2) {
            root.scanning = false;
            ticker.stop();
            return;
        }
        root.resume();
    }

    /** Carries on from wherever the last slice stopped. */
    function resume() {
        if (root.term.length < 2)
            return;
        if (root.scannedTo >= root.offset + root.lineCount) {
            root.scanning = false;
            ticker.stop();
            return;
        }
        root.scanning = true;
        ticker.start();
    }

    function step() {
        const needle = root.needle();
        const last = root.offset + root.lineCount;
        // A line that was dropped before this search reached it is one nobody
        // can be shown, so the scan starts from whatever is still there.
        let at = Math.max(root.scannedTo, root.offset);
        const stop = Math.min(last, at + root.chunk);
        const before = root.lines.length;

        for (; at < stop; ++at) {
            const text = String(root.textAt(at - root.offset)).toLowerCase();
            if (text.length === 0)
                continue;

            let found = text.indexOf(needle);
            if (found < 0)
                continue;

            const here = [];
            while (found >= 0) {
                root.lines.push(at);
                root.starts.push(found);
                here.push(found);
                found = text.indexOf(needle, found + needle.length);
            }
            root.byLine[at] = here;
        }

        root.scannedTo = at;
        root.total = root.lines.length;

        /*
          Only when the slice actually found something.

          Every bump re-evaluates the highlight binding in every row on screen,
          and most slices of a long log contain no match at all — bumping
          regardless would be fifty recomputations a tick for a scan that found
          nothing to draw.
        */
        if (root.total !== before)
            root.revision += 1;

        // The first match found is the one the buttons start from, so somebody
        // can press Next immediately rather than after the whole log is walked.
        if (root.current < root.first && root.total > root.first)
            root.current = root.first;

        if (root.scannedTo >= root.offset + root.lineCount) {
            root.scanning = false;
            ticker.stop();
        }
    }

    /* ------------------------------------------------ the log moving under it */

    /** More lines arrived at the end — or fewer, which is a different story. */
    function grew(lineCount) {
        root.lineCount = lineCount;

        /*
          A view that has fewer lines than this has already scanned is a view
          that lost lines without saying so — a model swapped out from under
          the log rather than a capped one dropping from the front, which
          announces itself. Everything held here is about text that is no longer
          there, so it starts again.
        */
        if (root.offset + lineCount < root.scannedTo) {
            root.restart();
            return;
        }
        root.resume();
    }

    /**
     * `removed` lines were dropped from the front, which is what a capped log
     * does on every line it is given once it is full.
     */
    function droppedFromFront(removed) {
        if (removed <= 0)
            return;
        root.offset += removed;

        // Walk past the matches that have gone. Ascending order means they are
        // all at the front, so this is a pointer move rather than a sweep.
        let walked = root.first;
        while (walked < root.total && root.lines[walked] < root.offset) {
            const line = root.lines[walked];
            // The last match on a line takes the line's entry with it, or the
            // map would grow for as long as the window is open.
            if (walked + 1 >= root.total || root.lines[walked + 1] !== line)
                delete root.byLine[line];
            walked += 1;
        }
        if (walked !== root.first) {
            root.first = walked;
            if (root.current < root.first)
                root.current = root.total > root.first ? root.first : -1;
            root.revision += 1;
        }
    }

    /* ------------------------------------------------------- what a row draws */

    /** The offsets of every match in one row, or an empty list. */
    function matchesIn(row) {
        const found = root.byLine[row + root.offset];
        return found === undefined ? [] : found;
    }

    /** The row the current occurrence is on, or -1. */
    function currentRow() {
        if (root.current < root.first || root.current >= root.total)
            return -1;
        return root.lines[root.current] - root.offset;
    }

    /** Its offset within that row, or -1. */
    function currentStart() {
        if (root.current < root.first || root.current >= root.total)
            return -1;
        return root.starts[root.current];
    }

    /* ---------------------------------------------------------- next, previous */

    function goTo(index) {
        if (root.total <= root.first)
            return;
        root.current = index;
        root.revision += 1;
        const row = root.currentRow();
        if (row >= 0)
            root.jumpWanted(row);
    }

    /**
     * Forward one, wrapping.
     *
     * Wrapping rather than stopping at the end, and the end here is a moving
     * target: the log is still being written, and a button that went dead at
     * the last match would come back to life a second later when the container
     * printed the word again. Wrapping is one behaviour rather than two.
     */
    function next() {
        if (root.total <= root.first)
            return;
        const at = root.current < root.first ? root.first
                 : (root.current + 1 >= root.total ? root.first : root.current + 1);
        root.goTo(at);
    }

    function previous() {
        if (root.total <= root.first)
            return;
        const at = root.current <= root.first ? root.total - 1 : root.current - 1;
        root.goTo(at);
    }

    onTermChanged: root.restart()

    property Timer ticker: Timer {
        interval: 1
        repeat: true
        onTriggered: root.step()
    }
}
