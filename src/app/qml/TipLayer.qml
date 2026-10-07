// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
// Explicit, for the `Window` attached property below: it does not come with a
// bare `import QtQuick` on the Qt 6.4 that Ubuntu LTS still ships.
import QtQuick.Window

/**
 * The one bubble that shows what an elided label actually says.
 *
 * Declared once per window and reparented to that window's overlay, which buys
 * the two things a tooltip cannot do without. It is **above** everything,
 * including a dialog; and it is **outside** every clipping container, so a name
 * in the last row of a scrolling list is not cut off by the list it lives in —
 * which is precisely where the longest names are.
 *
 * Input is refused outright. A tooltip appears under the pointer, over things
 * somebody is about to click, and one that swallowed the click would be worse
 * than the truncation it was helping with.
 */
Item {
    id: layer

    parent: Overlay.overlay
    anchors.fill: parent
    z: 10000

    /*
      Never a target. `enabled: false` stops the item and its children taking
      focus or keys; the null accepted-buttons handler below is what stops the
      mouse, since an Item with no handlers is already transparent to it.
    */
    enabled: false

    /**
     * Whether the label asking for a tooltip is in *this* window.
     *
     * There are six windows in the application and a layer in each, so without
     * this every one of them would draw the same bubble at coordinates that
     * mean nothing outside the window the label is actually in.
     */
    readonly property bool mine:
        Tip.target !== null
        && Tip.target.Window.window === layer.Window.window

    onMineChanged: layer.place()

    /*
      Mirrored onto local properties rather than watched with a `Connections`.

      A `Connections` block has a `target` property of its own, so a handler
      named `onTargetChanged` in it is ambiguous — it reads as an override of
      that property's change signal as much as of the singleton's. Qt 6.5 and
      later resolve it in favour of the singleton; the Qt 6.4 that current
      Ubuntu LTS ships calls it a duplicate method and refuses to load the
      file, taking the whole interface down with it. Two aliases and their own
      change handlers say the same thing on every version.
    */
    readonly property Item watchedTarget: Tip.target
    readonly property string watchedText: Tip.text

    onWatchedTargetChanged: layer.place()
    onWatchedTextChanged: layer.place()

    /**
     * Puts the bubble above the label, or below it when there is no room.
     *
     * Set imperatively rather than bound. The position depends on a
     * `mapToItem` — a function call, not a property — so a binding would be
     * evaluated once and then never again, which is the classic way a tooltip
     * ends up pinned to wherever the first one appeared.
     */
    function place() {
        if (!layer.mine || !Tip.target)
            return;

        const origin = Tip.target.mapToItem(layer, 0, 0);
        const w = bubble.implicitWidth;
        const h = bubble.implicitHeight;

        let y = origin.y - h - 6;
        // Flipped below when the label is near the top of the window, rather
        // than clamped, which would put the bubble on top of the label.
        if (y < 4)
            y = origin.y + Tip.target.height + 6;

        bubble.x = Math.max(
            4,
            Math.min(origin.x + Tip.target.width / 2 - w / 2, layer.width - w - 4),
        );
        bubble.y = Math.max(4, Math.min(y, layer.height - h - 4));
    }

    Rectangle {
        id: bubble
        objectName: "tipBubble"

        visible: opacity > 0
        opacity: layer.mine && Tip.text.length > 0 ? 1 : 0
        implicitWidth: Math.min(label.implicitWidth + 18, layer.width - 24)
        implicitHeight: label.implicitHeight + 12
        radius: Theme.radiusSmall
        color: Theme.baseHigh
        border.width: 1
        border.color: Theme.borderStrong

        // A late-arriving font or a longer string changes the width, and the
        // bubble has to move with it or it drifts off its label.
        onImplicitWidthChanged: layer.place()
        onImplicitHeightChanged: layer.place()

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durFast) }
        }

        Text {
            id: label
            objectName: "tipLabel"
            anchors.centerIn: parent
            /*
              Wrapped rather than elided. This is the thing that exists to show
              text another element could not fit; eliding it here would be the
              same failure one layer up.
            */
            width: Math.min(implicitWidth, layer.width - 42)
            wrapMode: Text.Wrap
            text: Tip.text
            color: Theme.textBody
            font.pixelSize: 11
        }
    }
}
