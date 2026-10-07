// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * The pointer half of a log selection: drag to highlight, right click to copy.
 *
 * One sheet over the whole list rather than a handler on every row, because a
 * selection is a thing that happens *between* rows — the press is on one, the
 * release is on another, and the interesting part is everything in between.
 * Rows below stay pure: they draw what {@link LogSelection} says is highlighted
 * and know nothing about the mouse.
 *
 * ## What it does not take
 *
 * It takes the left button and the right one, and nothing else. The wheel goes
 * straight through to the list underneath, so scrolling still scrolls; only
 * dragging changes meaning, from flicking the list to highlighting it, which is
 * what dragging means in every other place text is shown on a desktop.
 *
 * It is also switched off while there is nothing to select, which is what
 * leaves an empty log's own buttons — "Open Docker", and the like — clickable
 * underneath. A sheet that swallowed those clicks would break the one screen
 * where somebody most needs a way out.
 *
 * ## Rows are found through the list, not through the pointer
 *
 * A drag that leaves the box still has to mean something, so the row is
 * resolved by asking the `ListView` what is at that point in its content, with
 * the point clamped into the content first. That is what makes dragging past
 * the bottom edge select to the end rather than stop at the last row the
 * pointer happened to be over, and it is why {@link autoScroll} can keep
 * extending the selection with no pointer movement at all.
 *
 * Each row is asked for the character offset itself, through two functions the
 * delegate provides — `positionAt(x, y)` and `wordAt(x, y)`, both in the
 * delegate's own coordinates. A row that draws columns can then map a point
 * onto the one column it lets you highlight without this having to know.
 */
MouseArea {
    id: root

    /** The list being selected in. */
    required property ListView view
    /** The selection this drives. */
    required property LogSelection selection
    /** One row's plain text by index, for rows on screen and off it. */
    property var textAt: function (index) { return ""; }
    /** Opened by a right click, if there is one. */
    property var menu: null

    /** The row the last right click landed on, for "copy this line". */
    property int pointerLine: -1

    /** Asked for before anything else, so the keyboard shortcuts reach the log. */
    signal focusWanted()

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.IBeamCursor
    // The list underneath is a Flickable, and a Flickable will take a drag away
    // from whatever started it once the finger has moved far enough. Here the
    // drag *is* the gesture, so it is not given up.
    preventStealing: true

    /** True while a drag is laying down a selection. */
    property bool dragging: false
    /** -1 while dragging above the box, 1 below it, 0 inside. Drives the scroll. */
    property int edge: 0
    property real dragX: 0
    property real dragY: 0

    /*
      ---- Multiple clicks ------------------------------------------------

      Counted here rather than through onDoubleClicked, because the third click
      is the one that matters most in a log — it takes the whole line, which is
      what somebody pasting one line into a bug report wants — and Qt has no
      signal for it.
    */

    /** How long after a click a second one still counts as part of it. */
    readonly property int multiClickInterval: 400

    property int clicks: 0
    property double lastClickAt: 0
    property int lastClickLine: -1
    property real lastClickX: 0
    property real lastClickY: 0

    onPressed: function (mouse) {
        /*
          A finger scrolls; a pointer selects.

          Dragging means two different things on the two devices, and on a
          touchscreen it has only ever meant scrolling. A touch arrives here as
          a synthesised mouse press, so it is turned down and left to the list
          underneath rather than being turned into a highlight nobody asked for.
        */
        if (mouse.source !== Qt.MouseEventNotSynthesized) {
            mouse.accepted = false;
            return;
        }

        root.focusWanted();

        const line = root.lineAt(mouse.x, mouse.y);
        if (line < 0)
            return;

        if (mouse.button === Qt.RightButton) {
            /*
              A right click inside the highlight keeps it.

              Anywhere else it is a click first and a menu second, which is what
              makes "right click that line, copy this line" work without having
              to left click it first.
            */
            if (!root.selection.covers(line))
                root.selection.clear();
            root.pointerLine = line;
            if (root.menu)
                root.menu.popup();
            return;
        }

        const now = Date.now();
        const nearby = Math.abs(mouse.x - root.lastClickX) < 6
                       && Math.abs(mouse.y - root.lastClickY) < 6;
        root.clicks = (nearby && line === root.lastClickLine
                       && now - root.lastClickAt < root.multiClickInterval)
                      ? root.clicks + 1 : 1;
        root.lastClickAt = now;
        root.lastClickLine = line;
        root.lastClickX = mouse.x;
        root.lastClickY = mouse.y;
        root.dragX = mouse.x;
        root.dragY = mouse.y;

        // Three clicks: the whole line.
        if (root.clicks >= 3) {
            const text = root.textAt(line);
            root.selection.cover(line, 0, line, text ? text.length : 0);
            root.dragging = false;
            return;
        }

        // Two: the word under the pointer.
        if (root.clicks === 2) {
            const word = root.wordAt(line, mouse.x, mouse.y);
            root.selection.cover(line, word[0], line, word[1]);
            root.dragging = false;
            return;
        }

        const position = root.positionAt(line, mouse.x, mouse.y);
        if ((mouse.modifiers & Qt.ShiftModifier) && !root.selection.empty)
            root.selection.extend(line, position);
        else
            root.selection.begin(line, position);
        root.dragging = true;
    }

    onPositionChanged: function (mouse) {
        if (!root.dragging)
            return;
        root.dragX = mouse.x;
        root.dragY = mouse.y;
        root.edge = mouse.y < 0 ? -1 : (mouse.y > root.height ? 1 : 0);
        root.extendTo(mouse.x, mouse.y);
    }

    onReleased: {
        root.dragging = false;
        root.edge = 0;
    }

    onCanceled: {
        root.dragging = false;
        root.edge = 0;
    }

    onEnabledChanged: if (!enabled) root.selection.clear()

    /** Moves the head of the selection to a point in this sheet's coordinates. */
    function extendTo(x, y) {
        const line = root.lineAt(x, y);
        if (line < 0)
            return;
        root.selection.extend(line, root.positionAt(line, x, y));
    }

    /**
     * Which row is under that point, with the point pulled into the content
     * first: above the first row means the first row, below the last means the
     * last, which is what makes a drag out of the box select to the end.
     */
    function lineAt(x, y) {
        const view = root.view;
        if (!view || view.count === 0)
            return -1;

        const contentY = view.contentY + y;
        const clampedY = Math.max(view.originY,
                                  Math.min(contentY, view.originY + view.contentHeight - 1));
        const clampedX = Math.max(0, Math.min(x, view.width - 2));
        const index = view.indexAt(view.contentX + clampedX, clampedY);
        if (index >= 0)
            return index;
        // Past the whole content: its first row or its last.
        if (contentY < view.originY)
            return 0;
        if (contentY >= view.originY + view.contentHeight)
            return view.count - 1;
        /*
          Inside the content, on a row the list has not built: it keeps rows
          only a little way past the box (`cacheBuffer`), so a drag out of the
          top or the bottom points at rows that do not exist yet. The nearest
          row on screen in that direction is the answer, and the auto scroll
          walks on from it as the list moves and builds the next. Answering the
          far end of the list here — as this did — made every drag out of the
          top jump to the last line of the log, which looked like the selection
          letting go: from the bottom up, nothing could be selected past one
          screen, while from the top down the same answer happened to be right.
        */
        const above = contentY < view.contentY;
        const edgeY = above ? view.contentY : view.contentY + view.height - 1;
        const nearest = view.indexAt(view.contentX + clampedX,
                                     Math.max(view.originY,
                                              Math.min(edgeY, view.originY + view.contentHeight - 1)));
        if (nearest >= 0)
            return nearest;
        return above ? 0 : view.count - 1;
    }

    /** The character offset at that point, asked of the row that is drawn there. */
    function positionAt(line, x, y) {
        const item = root.view ? root.view.itemAtIndex(line) : null;
        if (!item || !item.positionAt) {
            // The row is not built, so the pointer is past an edge of the box:
            // above it, the head is the start of that row; below it, the end.
            const text = root.textAt(line);
            return y < 0 ? 0 : (text ? text.length : 0);
        }
        const point = root.mapToItem(item, x, y);
        return item.positionAt(point.x, point.y);
    }

    /** The word under that point, as a pair of offsets. */
    function wordAt(line, x, y) {
        const item = root.view ? root.view.itemAtIndex(line) : null;
        if (!item || !item.wordAt)
            return [0, 0];
        const point = root.mapToItem(item, x, y);
        return item.wordAt(point.x, point.y);
    }

    /*
      Dragging past the edge keeps going.

      Without this a selection can never be longer than the box is tall, which
      for a log is most selections anybody wants. The list is moved rather than
      the pointer, and the head of the selection is dragged along with it, so
      holding still at the bottom edge walks steadily down the log.

      How fast follows how far past the edge the pointer is, because one fixed
      speed is wrong twice: fast enough to cross a long log is far too fast to
      stop on a line, and slow enough to aim with is not worth having.
    */
    Timer {
        id: autoScroll
        interval: 24
        repeat: true
        running: root.dragging && root.edge !== 0
        onTriggered: {
            const view = root.view;
            if (!view)
                return;
            const overshoot = root.edge < 0 ? -root.dragY : root.dragY - root.height;
            const step = Math.max(3, Math.min(20, overshoot * 0.3));
            const lowest = view.originY - view.topMargin;
            const highest = Math.max(lowest,
                                     view.originY + view.contentHeight
                                     + view.bottomMargin - view.height);
            view.contentY = Math.max(lowest,
                                     Math.min(view.contentY + root.edge * step, highest));
            root.extendTo(root.dragX, root.dragY);
        }
    }
}
