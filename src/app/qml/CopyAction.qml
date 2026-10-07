// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * Copy this, and say so.
 *
 * A copy button whose whole job is the second half. Copying is silent — the
 * clipboard gives no sign it changed — so a button that only copies leaves
 * somebody with no way to tell a successful click from a missed one, and the
 * usual answer is to click again and paste twice.
 *
 * So it swaps to a tick for a moment. That is the entire feature, and it is why
 * this exists as its own component rather than as an {@link IconButton} with an
 * `onClicked` handler at each of the four places logs are shown.
 *
 * ## Two sizes of the same idea
 *
 * The header copies everything and is always visible. A row copies one line and
 * appears on hover — a permanent button on every row of a five-thousand-line
 * log is five thousand buttons. {@link revealOnHover} is which of the two this
 * is; the behaviour is otherwise identical, deliberately, so that copying a line
 * and copying the lot look like the same act.
 *
 * ## Nothing to copy
 *
 * An empty {@link text} disables it rather than copying an empty string. A
 * clipboard silently emptied is worse than a button that visibly did nothing:
 * whatever was in there was somebody's.
 */
Item {
    id: root

    /** What lands on the clipboard. Empty disables the button. */
    property string text: ""
    /** Shown before the click. After it, the label below takes over. */
    property string tooltip: qsTr("Copy")
    /** What it says once it has copied. */
    property string copiedLabel: qsTr("Copied")
    property int size: 26
    property color tone: Theme.textFaint
    property color hoverTone: Theme.sky
    /**
     * Fade in on hover instead of standing there.
     *
     * For a button that sits on a row. The row is responsible for saying when it
     * is hovered — see {@link hovered} — because a `HoverHandler` on the button
     * alone would only notice once the pointer had already found an invisible
     * target.
     */
    property bool revealOnHover: false
    /** Whether the thing this sits on is under the pointer. */
    property bool hovered: false

    /** True for the moment after a copy. Drawn, and readable from outside. */
    readonly property bool justCopied: confirmation.running

    signal copied()

    implicitWidth: size
    implicitHeight: size
    enabled: root.text.length > 0

    /*
      Visible while it is confirming, whatever the pointer is doing.

      Somebody who clicks a row's copy button and moves the mouse away in the
      same motion is the common case, and a tick that vanishes with the pointer
      is a tick nobody sees.
    */
    opacity: !enabled ? 0
           : !root.revealOnHover ? 1
           : (root.hovered || root.justCopied) ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: Theme.duration(Theme.durFast) }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: root.justCopied
               ? Theme.alpha(Theme.emerald, 0.14)
               : (hover.hovered && root.enabled ? Theme.alpha(root.hoverTone, 0.13) : "transparent")
        border.width: 1
        border.color: root.justCopied
                      ? Theme.alpha(Theme.emerald, 0.34)
                      : (hover.hovered && root.enabled ? Theme.alpha(root.hoverTone, 0.36) : "transparent")

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    Glyph {
        anchors.centerIn: parent
        name: root.justCopied ? "check" : "copy"
        size: Math.round(root.size * 0.52)
        thickness: 1.7
        tone: root.justCopied
              ? Theme.emerald
              : (hover.hovered && root.enabled ? root.hoverTone : root.tone)

        Behavior on tone {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.enabled
        onTapped: {
            App.copyToClipboard(root.text);
            confirmation.restart();
            root.copied();
        }
    }

    Timer {
        id: confirmation
        interval: 1400
    }

    /*
      Hand-rolled rather than Controls' ToolTip, for the same reason
      {@link IconButton} does it: this sits inside a list delegate, and a
      Controls popup per row is a popup per row.
    */
    Rectangle {
        id: label
        visible: opacity > 0
        opacity: (hover.hovered || root.justCopied) && root.enabled ? 1 : 0
        anchors.bottom: parent.top
        anchors.bottomMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: labelText.implicitWidth + 14
        implicitHeight: 22
        radius: Theme.radiusSmall
        color: Theme.baseHigh
        border.width: 1
        border.color: Theme.borderStrong
        z: 100

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durFast) }
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: root.justCopied ? root.copiedLabel : root.tooltip
            color: root.justCopied ? Theme.emerald : Theme.textBody
            font.pixelSize: 11
        }
    }
}
