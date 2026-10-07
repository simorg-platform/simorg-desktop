// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import Simorg

/**
 * Lines of output that can be read, highlighted and copied.
 *
 * Every log surface in this application is this component: a container's
 * output, the Docker panel at the bottom of the containers list, and the
 * activity log. They behave identically because they *are* identical —
 * dragging highlights, a right click offers to copy, ⌘C and ⌃C do the same, and
 * the view follows the newest line until somebody scrolls away from it.
 *
 * ## A list, not a text box
 *
 * The obvious way to make a log selectable is to put it in one read only text
 * area, and it is the wrong way here: these logs hold ten thousand lines by
 * default and as many as somebody asks for, they arrive a line at a time, and
 * rebuilding one document per line is work proportional to the square of the
 * log's length. So the lines stay rows in a `ListView` — cheap to append to,
 * cheap to scroll — and the selection is built back on top of them by
 * {@link LogSelection} and {@link LogSelectionArea}.
 *
 * ## Searching without walking the log twice
 *
 * The same reasoning, one layer up. {@link LogSearch} walks every line in
 * slices to count the matches and to know where they are, and the *drawing* of
 * them happens in the row delegates — which exist only for the rows on screen.
 * So the count is about the whole log and the painting costs a screenful,
 * whether the log holds ten thousand lines or ten million. Searching is opt-in
 * per host — see {@link searchable} — and so is where the box goes: see
 * {@link searchField}.
 *
 * Each row is a `TextEdit` rather than a `Text` for one reason: only a
 * `TextEdit` can say which character is under a point, and can draw part of
 * itself as highlighted. Nothing is editable and nothing takes focus.
 *
 * ## Following, and when to stop
 *
 * The view stays pinned to the newest line until the reader scrolls away, and
 * resumes when they come back to the bottom. It also stops **while anything is
 * highlighted**, whatever the scroll position: a selection is somebody reading,
 * and a log that scrolls the ground out from under a half finished drag cannot
 * be copied from at all on a busy container.
 *
 * ## Never moving on its own
 *
 * A log opens **at its newest line**, or where the reader left it, and nowhere
 * in between. Three things would move it in front of them, and each is held
 * here rather than in every host:
 *
 * - **A backlog arriving.** A container's log is streamed in, a few hundred
 *   lines at once and then one at a time, and a view that chased the end as
 *   rows were measured scrolled from the top to the bottom every time it
 *   opened. While a burst lands on an empty view the lines are {@link settling}:
 *   kept pinned and out of sight, and shown once the burst has stopped.
 * - **A model replaced.** A host that rebuilds its rows — the activity log does
 *   on every entry — resets the list, which puts it back at the top. The
 *   position is put back where it was: the end if it was following, the same
 *   place if somebody had scrolled away.
 * - **Coming back.** A pane that was hidden and is shown again keeps its place;
 *   a following one is at the end, including lines that arrived while hidden.
 *
 * A host that shows several logs in one view — an agent's page, one agent after
 * another — keeps each one's place with {@link captureState} and
 * {@link restoreState}.
 *
 * ## What a host supplies
 *
 * A model to count rows, and functions to read them: {@link textAt} answers with
 * a row's text by index — including rows that are not on screen, which is most
 * of a long selection — and {@link toneAt} says how it is drawn. Small
 * functions rather than a fixed set of roles, because a log here can be a list
 * of plain strings as well as a C++ model.
 *
 * ## Coloured by level
 *
 * The engine writes a level at the head of every line — `[INFO]`, `[WARNING]`,
 * `[ERROR]` and the rest — and writes all of it to stderr, so the level is the
 * one thing worth colouring by. Each has its own colour from the shared palette
 * (`Theme.log*`); warnings and errors carry a wash and an edge as well, because
 * they are what somebody scrolling past ten thousand lines is looking for, and
 * a fatal line is a solid red row, because it is the last thing the agent said.
 */
Item {
    id: root

    /** The rows. Read for its count and its inserts; never for its contents. */
    property alias model: lines.model

    /** One row's text by index, on screen or off it. */
    property var textAt: function (index) { return ""; }
    /**
     * How that row is drawn: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `FATAL`,
     * `USER`, `USER_DEBUG`, or an empty string for plain output. A C++ log
     * answers with `DockerLogModel.toneAt`, which also decides what a line that
     * names no level is drawn as.
     */
    property var toneAt: function (index) { return ""; }

    /** The text colour for a tone, in whichever mode the theme is in. */
    function toneColor(tone) {
        switch (tone) {
        case "DEBUG": return Theme.logDebug;
        case "INFO": return Theme.logInfo;
        case "WARNING": return Theme.logWarning;
        case "ERROR": return Theme.logError;
        case "FATAL": return Theme.logOnFatal;
        case "USER": return Theme.logUser;
        case "USER_DEBUG": return Theme.logUserDebug;
        default: return Theme.alpha(Theme.textBody, 0.92);
        }
    }

    /** What is under a row of that tone, or transparent for a plain one. */
    function toneSurface(tone) {
        switch (tone) {
        case "WARNING": return Theme.logWarningSurface;
        case "ERROR": return Theme.logErrorSurface;
        case "FATAL": return Theme.logFatal;
        default: return "transparent";
        }
    }

    /** The edge down a row's left side, or transparent where it has none. */
    function toneEdge(tone) {
        switch (tone) {
        case "WARNING": return Theme.logWarningBorder;
        case "ERROR": return Theme.logErrorBorder;
        default: return "transparent";
        }
    }
    /**
     * The whole log as text, for "copy everything".
     *
     * Overridden where the model can hand it over in one go — a C++ model
     * joining five thousand strings beats this loop doing it — and correct as
     * it stands everywhere else.
     */
    property var allText: function () {
        const out = [];
        for (let index = 0; index < lines.count; ++index)
            out.push(root.textAt(index));
        return out.join("\n");
    }

    property int leftInset: 20
    property int rightInset: 20
    property int fontSize: 12
    /** Breathing room above and below each line, split between the two. */
    property int rowPadding: 4

    /**
     * Empty space after the last line, counted in lines.
     *
     * Without it the newest line sits on the bottom edge, where a line that has
     * arrived and a line that is cut off look the same, so somebody scrolls down
     * to check there is nothing under it. A few lines of nothing says the log
     * ends here.
     */
    property int trailingLines: 0

    /** True while the view is pinned to the newest line. */
    property bool following: true

    /**
     * True while a burst of lines is landing on a view that was empty.
     *
     * The lines are pinned where they will be and kept out of sight, and shown
     * once nothing has arrived for a moment — or after a second and a half,
     * whatever is still arriving, so a log that never stops is never hidden.
     */
    readonly property bool settling: settle.running || settleCap.running

    /** Where to put the view once it has settled; see {@link restoreState}. */
    property var pendingState: null

    /** The reader's last position away from the end, for a model that is replaced. */
    property real heldY: 0

    /**
     * Where the reader is, as something that survives the lines being reloaded.
     *
     * A line's text as well as its index: a log reloaded from its newest few
     * hundred lines numbers them differently, and the text is how the same line
     * is found again.
     */
    function captureState() {
        if (root.following || lines.count === 0)
            return { following: true };
        const top = Math.max(0, lines.indexAt(10, lines.contentY + 1));
        const item = lines.itemAtIndex(top);
        return {
            following: false,
            index: top,
            text: root.textAt(top),
            offset: item ? lines.contentY - item.y : 0
        };
    }

    /**
     * Puts the view where {@link captureState} said, once the lines are there.
     *
     * Following when it was following, or when the line it was on is no longer
     * in the log — a place that no longer exists is not somewhere to leave
     * somebody.
     */
    function restoreState(state) {
        root.pendingState = state || { following: true };
        if (!root.settling && lines.count > 0)
            root.applyPending();
    }

    function applyPending() {
        const state = root.pendingState;
        root.pendingState = null;
        if (!state || state.following || lines.count === 0) {
            root.jumpToNewest();
            return;
        }
        const row = root.findLine(state.index, state.text);
        if (row < 0) {
            root.jumpToNewest();
            return;
        }
        root.following = false;
        lines.positionViewAtIndex(row, ListView.Beginning);
        lines.contentY += state.offset || 0;
        root.heldY = lines.contentY;
    }

    /** The row nearest `index` whose text is `text`, or -1. */
    function findLine(index, text) {
        const count = lines.count;
        if (text === undefined || text === null)
            return Math.min(index, count - 1);
        for (let distance = 0; distance < count; ++distance) {
            const below = index + distance;
            const above = index - distance;
            if (below >= 0 && below < count && root.textAt(below) === text)
                return below;
            if (above >= 0 && above < count && above !== below && root.textAt(above) === text)
                return above;
            if (below >= count && above < 0)
                break;
        }
        return -1;
    }

    /** Starts, or extends, the quiet wait before the lines are shown. */
    function beginSettling() {
        if (!settleCap.running)
            settleCap.restart();
        settle.restart();
    }

    function finishSettling() {
        settle.stop();
        settleCap.stop();
        if (root.pendingState)
            root.applyPending();
        else
            root.followToEnd();
    }

    Timer {
        id: settle
        interval: 180
        onTriggered: root.finishSettling()
    }

    Timer {
        id: settleCap
        interval: 1500
        onTriggered: root.finishSettling()
    }

    /**
     * Whether this log can be searched, and answers ⌘F.
     *
     * On for the logs somebody reads to find something — a container's output,
     * the engine's — and off where a log is short enough to read whole. A
     * search box over a log that has never had more than one screenful in it is
     * a control that can only ever answer a question nobody asked.
     */
    property bool searchable: false

    /**
     * The search box, when the host draws it in its own header.
     *
     * Left null, the log keeps a strip of its own across its top, closed until
     * ⌘F opens it. A host with room in its header puts a {@link LogSearchBar}
     * there instead — `toolbar: true`, bound to {@link search} — and hands it
     * over here, so ⌘F in the lines puts the cursor in that box, Esc empties
     * it, and no second box ever opens under the first.
     */
    property LogSearchBar searchField: null

    /** The search itself, for a box drawn outside this item. See {@link searchField}. */
    readonly property LogSearch search: logSearch

    /**
     * Whether ⏎ in the lines asks for an empty one at the end.
     *
     * Space somebody makes on purpose, to see where new output starts. The log
     * only asks — see {@link blankLineRequested} — because a line belongs to
     * the host's model. ⏎ in a search box stays that box's own.
     */
    property bool blankLineOnEnter: false

    /** Whether the menu offers to empty this log, and what that is called. */
    property bool clearable: false
    property string clearLabel: qsTr("Clear this view")
    /** What one row is called in the menu. */
    property string lineLabel: qsTr("Copy this line")

    signal clearRequested()
    signal blankLineRequested()

    readonly property alias count: lines.count
    readonly property bool hasSelection: !logSelection.empty

    /**
     * What is highlighted, for a row that draws itself.
     *
     * Rows built from {@link rowDelegate} ask this where the highlight starts
     * and ends in them; see AgentActivityLog, the one log here whose rows are
     * columns rather than a line of text.
     */
    readonly property LogSelection selection: logSelection

    /**
     * The row, where a line of text is not the shape of one.
     *
     * Left null by every log that is plain output, which is all but one of
     * them. A delegate that replaces it has three things to provide, and the
     * default row below is the worked example: `positionAt(x, y)` and
     * `wordAt(x, y)` in its own coordinates, and a highlight that follows
     * {@link selection}.
     */
    property Component rowDelegate: null

    /** Room above the first row and below the last, inside the scroll. */
    property int listTopMargin: 0
    property int listBottomMargin: 0

    /**
     * What a host draws when there is nothing to read.
     *
     * A `Component`, built only while the log is empty: every one of these
     * says why it is empty, and the reasons are worth telling apart — a
     * container that has printed nothing, one that does not exist, and an
     * engine that is not running look identical on a blank screen and only one
     * of them is something the reader can act on.
     */
    property Component emptyState: null

    /** Puts the cursor in the search box, opening the strip first where the box is the log's own. */
    function beginSearch() {
        if (!root.searchable)
            return;
        if (!root.searchField)
            searchBar.open = true;
        root.searchBox().focusInput();
    }

    /** Whichever box this log is searched from: the host's, or its own strip. */
    function searchBox() {
        return root.searchField ? root.searchField : searchBar;
    }

    /** Back to the newest line, and following it again. */
    function jumpToNewest() {
        root.following = true;
        root.pinToEnd();
    }

    /**
     * The newest line on screen, and the space kept under it.
     *
     * `positionViewAtEnd` on its own lands short whenever the row that just
     * arrived has not been measured: a long line wraps to several, and the view
     * scrolls on an estimate of its height. So this goes to the true end of the
     * content, bottom margin included, and is asked again whenever the content
     * grows while the log is following. See `onContentHeightChanged`.
     */
    function pinToEnd() {
        lines.positionViewAtEnd();
        const end = lines.originY + lines.contentHeight + lines.bottomMargin - lines.height;
        lines.contentY = Math.max(lines.originY - lines.topMargin, end);
    }

    /** {@link pinToEnd}, unless somebody is reading. See the note at the top. */
    function followToEnd() {
        if (root.following && logSelection.empty)
            root.pinToEnd();
    }

    /**
     * One match in the middle of the view: the word, not the line it is in.
     *
     * A line that wraps can be taller than the whole view, and centring the line
     * put a word near its end below the edge. So the row is brought on screen
     * first, which is what creates it, and then the view is moved by where the
     * word sits inside it — once now, and once more after the rows around it
     * have been measured and stopped moving.
     */
    function revealMatch(row, start, length) {
        lines.positionViewAtIndex(row, ListView.Center);
        root.centreOnMatch(row, start, length);
        Qt.callLater(root.centreOnMatch, row, start, length);
    }

    function centreOnMatch(row, start, length) {
        const item = lines.itemAtIndex(row);
        if (!item || typeof item.rectangleFor !== "function" || start < 0)
            return;
        const band = item.rectangleFor(start, start + length);
        const top = lines.originY - lines.topMargin;
        const bottom = Math.max(top, lines.originY + lines.contentHeight
                                     + lines.bottomMargin - lines.height);
        const wanted = item.y + band.y + band.height / 2 - lines.height / 2;
        lines.contentY = Math.min(bottom, Math.max(top, wanted));
    }

    function copySelection() {
        const taken = logSelection.lastLine - logSelection.firstLine + 1;
        root.copy(logSelection.textOfRange(root.textAt),
                  taken === 1 ? qsTr("Copied") : qsTr("%1 lines copied").arg(taken));
    }

    function copyLine(index) {
        if (index < 0 || index >= lines.count)
            return;
        root.copy(root.textAt(index), qsTr("Copied"));
    }

    function copyEverything() {
        root.copy(root.allText(), qsTr("%1 lines copied").arg(lines.count));
    }

    function selectEverything() {
        if (lines.count === 0)
            return;
        const last = lines.count - 1;
        const text = root.textAt(last);
        logSelection.cover(0, 0, last, text ? text.length : 0);
    }

    function clearSelection() {
        logSelection.clear();
    }

    /*
      Copying is silent, so it is said out loud.

      The clipboard gives no sign that it changed, and somebody who is not sure
      whether a copy worked pastes twice to find out. The same reasoning, and
      the same wording, as CopyAction's tick.
    */
    function copy(text, message) {
        if (!text || text.length === 0)
            return;
        App.copyToClipboard(text);
        confirmation.text = message;
        confirmation.show();
    }

    Keys.onPressed: function (event) {
        if (root.searchable && event.matches(StandardKey.Find)) {
            root.beginSearch();
            event.accepted = true;
        } else if (root.searchable && event.key === Qt.Key_Escape && root.searchBox().searching
                   && logSelection.empty) {
            root.searchBox().finish();
            event.accepted = true;
        } else if (root.blankLineOnEnter
                   && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            // The line first, then the view: the space is only worth making if
            // it is on screen, under the newest line.
            root.blankLineRequested();
            root.jumpToNewest();
            event.accepted = true;
        } else if (event.matches(StandardKey.Copy)) {
            root.copySelection();
            event.accepted = true;
        } else if (event.matches(StandardKey.SelectAll)) {
            root.selectEverything();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && !logSelection.empty) {
            logSelection.clear();
            event.accepted = true;
        }
    }

    LogSelection { id: logSelection }

    /** One unwrapped row's text height, for space measured in lines. */
    FontMetrics {
        id: rowMetrics
        font.family: Theme.monoFamily
        font.pixelSize: root.fontSize
    }

    /*
      The search, and the three things that keep it honest about a live log.

      `lineCount` is pushed rather than bound so the scan resumes on the same
      tick the lines arrive; `rowsRemoved` from the front is what a capped log
      does on every line once it is full, and the search has to know or every
      match it holds points one line further back each second; and a reset is a
      cleared log, which is nothing to search at all. None of the three is
      observable from a count alone, which is why this is wired rather than
      derived.
    */
    LogSearch {
        id: logSearch
        lineCount: lines.count
        textAt: root.textAt
        onJumpWanted: function (row) {
            // A jump is somebody reading a particular line, so the view stops
            // chasing the newest one — exactly as a selection does.
            root.following = false;
            root.revealMatch(row, logSearch.currentStart(), logSearch.term.length);
        }
    }

    Connections {
        target: lines.model
        ignoreUnknownSignals: true
        function onRowsRemoved(parent, first, last) {
            if (first === 0)
                logSearch.droppedFromFront(last - first + 1);
        }
        function onModelReset() { logSearch.restart(); }
    }

    LogSearchBar {
        id: searchBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Given nothing to search where the host draws the box, so the one term
        // this log has is written from one place.
        search: root.searchField ? null : logSearch
        onCloseRequested: {
            searchBar.open = false;
            root.forceActiveFocus();
        }
    }

    ListView {
        id: lines
        // Named so a test can reach the rows: the interesting behaviour here is
        // a drag from one of them to another, which has to be driven through
        // real mouse events to be worth anything.
        objectName: "logLines"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        clip: true
        spacing: 0
        // Wrapped lines make every row a different height, and estimating that
        // for a scrollbar is cheaper than measuring thousands of them.
        cacheBuffer: 400

        topMargin: root.listTopMargin
        bottomMargin: root.listBottomMargin
                      + root.trailingLines * (rowMetrics.height + root.rowPadding)

        ScrollBar.vertical: ScrollBar { id: scrollBar }

        /*
          Out of sight at once while a burst settles, and back in a short fade:
          the view appears at its newest line rather than travelling there. The
          hiding is never animated — a fade still running when the next burst
          lands would show that burst half-drawn.
        */
        NumberAnimation {
            id: reveal
            target: lines
            property: "opacity"
            to: 1
            duration: Theme.durFast
        }

        Connections {
            target: root
            function onSettlingChanged() {
                if (root.settling) {
                    reveal.stop();
                    lines.opacity = 0;
                } else if (Theme.motion) {
                    reveal.restart();
                } else {
                    lines.opacity = 1;
                }
            }
        }

        property int previousCount: 0

        // A selection is somebody reading. See the note at the top.
        onCountChanged: {
            // Lines landing on an empty view are a backlog, not a reader's log growing.
            if (lines.previousCount === 0 && lines.count > 0)
                root.beginSettling();
            else if (root.settling)
                settle.restart();
            lines.previousCount = lines.count;
            // Deferred, so a burst of five hundred lines is one scroll rather
            // than five hundred.
            Qt.callLater(root.followToEnd);
            // New lines are new places the word could be. See LogSearch.grew.
            logSearch.grew(lines.count);
        }

        /*
          A model replaced — a host rebuilding its rows — puts a list back at its
          top. It goes back to where the reader was instead: the end when it was
          following, the same place when somebody had scrolled away.
        */
        onModelChanged: {
            const held = root.heldY;
            Qt.callLater(function () {
                // Closed meanwhile. Qt.callLater drops a destroyed object's own
                // functions, and a closure has no object for it to check.
                if (!root || !lines)
                    return;
                if (root.following || root.pendingState) {
                    root.followToEnd();
                    return;
                }
                const end = lines.originY + lines.contentHeight + lines.bottomMargin - lines.height;
                lines.contentY = Math.max(lines.originY - lines.topMargin, Math.min(held, end));
            });
        }

        // Shown again, it is where it was — and at the end if it was following there.
        onVisibleChanged: {
            if (lines.visible && root.following)
                Qt.callLater(root.followToEnd);
        }

        /*
          And again once the rows that arrived have been measured.

          A row's height is known only after its text is laid out, which is after
          the count changed, so a view that scrolled on the count alone stopped
          short by however much the newest lines wrapped: the last line of a log
          that had finished was below the edge.
        */
        onContentHeightChanged: Qt.callLater(root.followToEnd)
        onHeightChanged: Qt.callLater(root.followToEnd)

        // Any movement away from the bottom stops the follow; coming back to
        // the bottom resumes it. No mode switch to remember. The scroll bar's
        // handle is a reader's hand as much as a flick is.
        onContentYChanged: {
            if (!moving && !dragging && !flicking && !scrollBar.pressed)
                return;
            root.following = atYEnd;
            if (!root.following)
                root.heldY = contentY;
        }

        delegate: root.rowDelegate ? root.rowDelegate : plainLine

        Component {
            id: plainLine

            Item {
                id: line

                required property int index
                readonly property string lineText: root.textAt(line.index)
                readonly property string lineTone: root.toneAt(line.index)

                readonly property int selectionStart:
                    logSelection.startFor(line.index, line.lineText.length)
                readonly property int selectionEnd:
                    logSelection.endFor(line.index, line.lineText.length)

                width: lines.width
                implicitHeight: body.implicitHeight + root.rowPadding

                /** Which character is at that point, in this row's own coordinates. */
                function positionAt(x, y) {
                    return body.positionAt(x - body.x, y - body.y);
                }

                /** The word around that point, as a pair of offsets. */
                function wordAt(x, y) {
                    body.cursorPosition = body.positionAt(x - body.x, y - body.y);
                    body.selectWord();
                    return [body.selectionStart, body.selectionEnd];
                }

                function applySelection() {
                    if (line.selectionEnd > line.selectionStart)
                        body.select(line.selectionStart, line.selectionEnd);
                    else
                        body.deselect();
                }

                onSelectionStartChanged: line.applySelection()
                onSelectionEndChanged: line.applySelection()
                Component.onCompleted: line.applySelection()

                /*
                  Where the searched word is, in this row, in pixels.

                  Computed in the delegate on purpose: a delegate exists only
                  for the rows on screen, so the cost of highlighting is bounded
                  by the size of the window rather than by the length of the
                  log. LogSearch counts every match in a million lines; this
                  draws the handful that are being looked at.

                  `search.revision` is what makes it recompute. The match arrays
                  are mutated in place — pushing onto a JavaScript array
                  notifies nothing — so the integer is the dependency and the
                  arrays are the data.
                */
                readonly property var highlights: {
                    // Named so the binding takes a dependency on them. Each one
                    // genuinely moves the rectangles: a re-scan, a reflow, a
                    // different font size, different text.
                    const revision = logSearch.revision;
                    const width = body.width;
                    const size = root.fontSize;
                    const text = line.lineText;
                    if (revision < 0 || width <= 0 || logSearch.term.length < 2)
                        return [];

                    const found = logSearch.matchesIn(line.index);
                    if (found.length === 0)
                        return [];

                    const currentRow = logSearch.currentRow();
                    const currentStart = logSearch.currentStart();
                    const length = logSearch.term.length;
                    const out = [];
                    for (let i = 0; i < found.length; ++i) {
                        const at = found[i];
                        const active = line.index === currentRow && at === currentStart;
                        const boxes = line.boxesFor(at, at + length);
                        for (let b = 0; b < boxes.length; ++b) {
                            boxes[b].active = active;
                            out.push(boxes[b]);
                        }
                    }
                    return out;
                }

                /**
                 * One match as rectangles, in `body`'s coordinates.
                 *
                 * Usually one. A wrapped line is the reason it is a list: a
                 * match that straddles the fold is a box on the end of one
                 * visual line and a box on the start of the next, and drawing
                 * it as a single rectangle between two points on different rows
                 * would paint a band across the middle of the text.
                 */
                function boxesFor(start, end) {
                    const from = body.positionToRectangle(start);
                    const to = body.positionToRectangle(end);
                    if (Math.abs(to.y - from.y) < 0.5) {
                        return [{ x: from.x, y: from.y,
                                  w: Math.max(2, to.x - from.x), h: from.height }];
                    }

                    const out = [{ x: from.x, y: from.y,
                                   w: Math.max(2, body.width - from.x), h: from.height }];
                    if (to.y - from.y > from.height + 0.5) {
                        out.push({ x: 0, y: from.y + from.height, w: body.width,
                                   h: to.y - from.y - from.height });
                    }
                    out.push({ x: 0, y: to.y, w: Math.max(2, to.x), h: to.height });
                    return out;
                }

                /**
                 * A stretch of this row as one band across it, in the row's own
                 * coordinates: where to scroll to show it, not what to draw.
                 */
                function rectangleFor(start, end) {
                    const from = body.positionToRectangle(start);
                    const to = body.positionToRectangle(end);
                    return { y: body.y + from.y,
                             height: Math.max(from.height, to.y + to.height - from.y) };
                }

                Rectangle {
                    anchors.fill: parent
                    visible: color.a > 0
                    color: root.toneSurface(line.lineTone)
                }

                Rectangle {
                    visible: color.a > 0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: root.toneEdge(line.lineTone)
                }

                TextEdit {
                    id: body

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.leftInset
                    anchors.rightMargin: root.rightInset
                    anchors.verticalCenter: parent.verticalCenter

                    text: line.lineText
                    color: root.toneColor(line.lineTone)
                    font.family: Theme.monoFamily
                    font.pixelSize: root.fontSize
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText

                    /*
                      A text item that can be highlighted, and nothing else.

                      Not editable, never focused, and it does not drive its own
                      selection: the pointer is handled once for the whole list, or
                      a drag could never leave the row it started on. Selections are
                      drawn whether or not the item has focus, which no row here
                      ever has.
                    */
                    readOnly: true
                    activeFocusOnPress: false
                    selectByMouse: false
                    selectByKeyboard: false
                    persistentSelection: true
                    selectionColor: Theme.alpha(Theme.blue, 0.45)
                    selectedTextColor: Theme.textPrimary

                    /*
                      Behind the glyphs rather than over them.

                      A TextEdit draws one selection and this is not it — the
                      drag selection is the TextEdit's own, and a row can be
                      both dragged across and searched at the same time. So the
                      search marks are rectangles underneath, and the two
                      highlights layer instead of fighting over one mechanism.
                    */
                    Repeater {
                        model: line.highlights

                        delegate: Rectangle {
                            required property var modelData

                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 2
                            z: -1
                            // The one the arrows are sitting on is the one being
                            // looked for; the rest are where else it appears.
                            color: modelData.active ? Theme.alpha(Theme.amber, 0.5)
                                                    : Theme.alpha(Theme.amber, 0.2)
                            border.width: modelData.active ? 1 : 0
                            border.color: Theme.alpha(Theme.amber, 0.85)
                        }
                    }
                }
            }
        }
    }

    /*
      The empty state, over the lines and under the selection sheet.

      The sheet is switched off while there is nothing to select, which is what
      leaves the buttons in here — "Open Docker", most of all — clickable.
    */
    Loader {
        id: overlay
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        active: lines.count === 0 && root.emptyState !== null
        sourceComponent: root.emptyState
    }

    LogSelectionArea {
        id: area

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        // Clear of the scrollbar, which is the one thing in this box that still
        // wants a drag of its own.
        anchors.rightMargin: 12

        view: lines
        selection: logSelection
        textAt: root.textAt
        menu: contextMenu

        // Nothing to select, and an empty log is where a host puts its own
        // buttons. See LogSelectionArea.
        enabled: lines.count > 0

        onFocusWanted: root.forceActiveFocus()
    }

    LogContextMenu {
        id: contextMenu
        objectName: "logMenu"

        hasSelection: !logSelection.empty
        hasLine: area.pointerLine >= 0
        lineLabel: root.lineLabel
        clearable: root.clearable
        clearLabel: root.clearLabel
        clearEnabled: lines.count > 0

        onCopySelection: root.copySelection()
        onCopyLine: root.copyLine(area.pointerLine)
        onCopyEverything: root.copyEverything()
        onSelectEverything: root.selectEverything()
        onClearRequested: root.clearRequested()
    }

    /*
      Said in the corner of the log rather than beside a button, because there
      is no button: the copy came from a menu or from the keyboard, and the
      answer has to appear somewhere the eye already is.
    */
    Rectangle {
        id: confirmation

        property alias text: confirmationLabel.text

        function show() {
            confirmationTimer.restart();
        }

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 14
        implicitWidth: confirmationLabel.implicitWidth + 26
        implicitHeight: 26
        radius: Theme.radiusSmall
        color: Theme.alpha(Theme.emerald, 0.14)
        border.width: 1
        border.color: Theme.alpha(Theme.emerald, 0.34)
        visible: opacity > 0
        opacity: confirmationTimer.running ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durFast) }
        }

        Text {
            id: confirmationLabel
            anchors.centerIn: parent
            color: Theme.emerald
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Timer {
            id: confirmationTimer
            interval: 1400
        }
    }
}
