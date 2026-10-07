// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import Simorg

/**
 * Text somebody can drag across, and take away.
 *
 * ## Why this exists
 *
 * A `Text` in Qt Quick cannot be selected. That is fine for a label — nobody
 * highlights the word "MEMORY" over a meter — and wrong for anything the reader
 * might need to put somewhere else: the sentence saying why a container will not
 * start, the name Docker gave it, the image it was built from. Drawn with the
 * same component as the headings, the one screen somebody opens *because
 * something is wrong* would be the one screen they could not copy a word out of,
 * and the answer would be a photograph of the window.
 *
 * ## A drop-in, with the editor taken out of it
 *
 * It is a read-only `TextEdit`, which is the only thing in Qt Quick that can say
 * which character is under a point and draw part of itself as highlighted, set
 * up so that nothing about it reads as a field: no cursor, no frame, no
 * placeholder, and it never writes. Everything a call site already sets on a
 * `Text` — `text`, `color`, `font`, `wrapMode`, `lineHeight` — means the same
 * thing here, so a label becomes selectable by changing its type.
 *
 * What it does *not* do is elide. A `TextEdit` cannot, and the two ideas pull
 * against each other anyway: eliding hides characters, and this exists so that
 * every character can be taken. Where a value has to be cut to fit a row,
 * {@link ElidedText} is still the component — it hands the rest back through the
 * pointer's tooltip.
 *
 * ## Three ways to the clipboard, because people reach for different ones
 *
 * Dragging and then ⌘C is what a desktop has always done, and ⌘C with nothing
 * highlighted takes the whole of this text rather than nothing — a shortcut that
 * did nothing would be read as a shortcut that failed. ⌘A selects this text
 * rather than the window, which is what somebody who has just clicked into one
 * sentence means by it. And the right button opens the same menu every log in
 * this application shows, because that is where a reader looks when the keyboard
 * shortcut has not occurred to them.
 */
TextEdit {
    id: root

    /** What the right click menu calls taking the whole of this text. */
    property string allLabel: qsTr("Copy all")

    /*
      A reader, never an editor.

      `persistentSelection` is off on purpose: clicking one sentence should take
      the highlight off the last one, and two highlights in one card look like
      one selection with a hole in it.
    */
    readOnly: true
    selectByMouse: true
    selectByKeyboard: true
    cursorVisible: false
    activeFocusOnPress: true
    // Whatever is in here is a sentence from the service or a name from Docker;
    // it is drawn, never interpreted.
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.WordWrap

    color: Theme.textBody
    font.pixelSize: 12
    selectionColor: Theme.alpha(Theme.blue, 0.45)
    selectedTextColor: Theme.textPrimary

    /** Copies what is highlighted, or the whole text when nothing is. */
    function copySelection() {
        root.hand(root.selectedText.length > 0 ? root.selectedText : root.text);
    }

    function copyEverything() {
        root.hand(root.text);
    }

    /*
      Out through the bridge, never through the editor's own `copy()`.

      A `TextEdit` will put its selection on the system clipboard itself, and
      using that would be the one place in this interface where something leaves
      the process without going through `App` — which is the seam that makes what
      this application can push outward small enough to read. Nothing to copy is
      not a copy of nothing, either: a clipboard silently emptied is worse than a
      shortcut that visibly did nothing, because whatever was in there was
      somebody's.
    */
    function hand(taken) {
        if (taken.length > 0)
            App.copyToClipboard(taken);
    }

    /*
      ⌘C before the editor sees it, for the reason above. ⌘A is left to Qt: it
      selects the whole of this text, which is what somebody who has just clicked
      into one sentence means by it.
    */
    Keys.onPressed: function (event) {
        if (event.matches(StandardKey.Copy)) {
            root.copySelection();
            event.accepted = true;
        }
    }

    /*
      The right button, without taking the left one away.

      A `TapHandler` rather than a `MouseArea` over the top: a handler watches
      the button it is given and leaves every other press to the item, so the
      drag that selects still reaches the text underneath it.
    */
    TapHandler {
        acceptedButtons: Qt.RightButton
        onSingleTapped: {
            root.forceActiveFocus();
            menu.popup();
        }
    }

    LogContextMenu {
        id: menu

        hasSelection: root.selectedText.length > 0
        // One piece of text rather than a list of lines, so there is no "this
        // line" to offer and nothing to empty.
        hasLine: false
        everythingLabel: root.allLabel
        clearable: false

        onCopySelection: root.copySelection()
        onCopyEverything: root.copyEverything()
        onSelectEverything: root.selectAll()
    }
}
