// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
pragma Singleton

import QtQuick

/**
 * Which elided label, if any, is currently asking to be read in full.
 *
 * One object for the whole application, and one bubble drawn from it — see
 * `TipLayer.qml`. That is the entire reason this exists rather than each label
 * carrying its own `ToolTip`: a container list has thirty rows, an artifact list
 * has more, and a Controls popup per row is a popup per row. Here the rows hold
 * nothing; they set two properties on a singleton and let one visual follow.
 *
 * ## The delay lives here too
 *
 * A tooltip that appears the instant a pointer crosses a label makes a list
 * flicker as somebody moves the mouse across it. So the first one waits. Once
 * one *is* up, moving to another label switches immediately — the person has
 * already said they are reading tooltips, and making them wait again for each
 * is the behaviour every desktop toolkit decided against decades ago.
 */
QtObject {
    id: tip

    /** The label being shown right now, or null. */
    property Item target: null
    /** Its full text. */
    property string text: ""

    /** What the delay is counting towards, which is not yet on screen. */
    property Item pending: null
    property string pendingText: ""

    /** Milliseconds a first tooltip waits before appearing. */
    readonly property int delay: 420

    readonly property Timer timer: Timer {
        interval: tip.delay
        onTriggered: {
            tip.target = tip.pending;
            tip.text = tip.pendingText;
        }
    }

    /**
     * Asks for `item`'s full text to be shown.
     *
     * Safe to call for a label that is already showing: it just updates the
     * text, which is what a label whose content changed under the pointer
     * needs.
     */
    function show(item, value) {
        if (!item || !value)
            return;
        tip.pending = item;
        tip.pendingText = value;
        if (tip.target !== null) {
            // Something is already up, so this is a move rather than a start.
            tip.target = item;
            tip.text = value;
        } else {
            tip.timer.restart();
        }
    }

    /**
     * Withdraws `item`'s request.
     *
     * Guarded on identity rather than clearing unconditionally, because pointer
     * enter on the next label arrives before leave on this one. Clearing blind
     * would cancel the tooltip that had just been asked for.
     */
    function hide(item) {
        if (tip.pending === item) {
            tip.pending = null;
            tip.pendingText = "";
            tip.timer.stop();
        }
        if (tip.target === item) {
            tip.target = null;
            tip.text = "";
        }
    }
}
