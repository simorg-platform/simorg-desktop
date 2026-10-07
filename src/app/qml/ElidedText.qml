// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import Simorg

/**
 * A `Text` that hands back the part of itself it had to cut off.
 *
 * Every list in this application elides: a container name in a row, an image
 * digest in a table, a folder path in the access sheet, an error sentence in a
 * banner. An ellipsis is a promise that the rest is recoverable — otherwise the
 * longest names, which are the ones people are trying to tell apart, are the
 * ones the app refuses to show.
 *
 * A drop-in replacement: it *is* a `Text`, so a call site changes its type and
 * keeps every property it already set, `elide` included.
 *
 * ## Only when it is really cut
 *
 * `truncated` is Qt's own answer to "did this element have to elide", true for
 * a clipped `maximumLineCount` as well as a horizontal ellipsis. A tooltip that
 * repeated text already fully on screen would be noise, and noise is how people
 * learn to ignore the tooltip that mattered.
 *
 * ## Never in the way
 *
 * A `HoverHandler`, which observes the pointer without consuming it, so a label
 * inside a clickable row stays clickable and the row's own hover highlight
 * still works. The bubble itself is drawn in the window overlay and refuses
 * input — see `TipLayer.qml`.
 *
 * ## And it can be copied
 *
 * A right click offers **Copy**, which takes the whole of it — the part the
 * ellipsis hides included. An elided label cannot be dragged across, and the
 * values that get cut are the ones people need somewhere else: a container's
 * name for a `docker` command, an image, a path. The menu is the one every
 * selectable text in this application opens, built on the first right click
 * rather than once per label, since some lists hold hundreds of these.
 */
Text {
    id: root

    /** What the tooltip says. The whole text, unless a caller knows better. */
    property string tipText: root.text

    /**
     * Off for a label whose full text is already somewhere else on screen.
     *
     * Rare, and worth having: a heading elided beside a subtitle that repeats
     * it in full does not need a second copy under the pointer.
     */
    property bool tipEnabled: true

    /** Off where the words are the interface's own — a menu entry — rather than a value. */
    property bool copyable: true

    // What a screen reader says is the whole of it, cut or not.
    Accessible.role: Accessible.StaticText
    Accessible.name: root.tipText

    /*
      Deliberately not `hover.hovered && truncated` inline on the call to
      `Tip.show`. As a property it has a change signal, which is what makes
      leaving the label withdraw the request — an expression evaluated in a
      handler would only ever fire on the way in.
    */
    readonly property bool tipWanted:
        root.tipEnabled && root.truncated && hover.hovered && root.tipText.length > 0

    onTipWantedChanged: {
        if (root.tipWanted)
            Tip.show(root, root.tipText);
        else
            Tip.hide(root);
    }

    // A row destroyed under the pointer — a list refreshing, a dialog closing —
    // would otherwise leave its tooltip on screen with nothing behind it.
    Component.onDestruction: Tip.hide(root)

    HoverHandler {
        id: hover
        /*
          No `cursorShape`. This is a label, and a pointing hand over one is a
          promise that clicking does something.
        */
    }

    /*
      The right button only, and a handler rather than a `MouseArea`, so a left
      click still reaches the row this label sits on.
    */
    TapHandler {
        enabled: root.copyable && root.text.length > 0
        acceptedButtons: Qt.RightButton
        onSingleTapped: {
            copyMenu.active = true;
            copyMenu.item.popup();
        }
    }

    Loader {
        id: copyMenu
        objectName: "copyMenu"
        active: false
        sourceComponent: LogContextMenu {
            // The whole text is the one thing there is to copy.
            hasSelection: true
            hasLine: false
            offersEverything: false
            selectable: false
            clearable: false
            // `text`, not `tipText`: a caller may explain in the tooltip, and
            // what somebody pastes is the value.
            onCopySelection: App.copyToClipboard(root.text)
        }
    }
}
