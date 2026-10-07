// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One resource in an envelope: what is guaranteed, how far it may climb, and
 * how much of the machine that is.
 *
 * Two segments rather than one, because a virtual machine's envelope is two
 * numbers and drawing only the first would understate it while drawing only the
 * second would overstate it. The solid part is the **guarantee** — spent, held
 * for this agent whether or not it is busy — and the translucent part is
 * **headroom**, which several agents are allowed to want at the same time.
 *
 * A resource with no ceiling draws no headroom segment and says so in words.
 * Inventing a bar for "no limit" is the one thing a meter must never do: every
 * width it could pick is a lie about a number that does not exist.
 */
ColumnLayout {
    id: root

    property string label: ""
    property string glyph: ""
    property color tone: Theme.cyan

    /** The minimum, in the resource's own base unit. */
    property real guaranteed: 0
    /** The maximum. Meaningless unless {@link capped}. */
    property real ceiling: 0
    property bool capped: false
    /** False for a resource with no floor — a card's memory — whose guarantee is not drawn. */
    property bool hasGuarantee: true
    /** What no ceiling is, in this resource's words. */
    property string uncappedText: qsTr("no ceiling")

    /**
     * What there is to divide, in the same unit. Zero means "do not draw a bar".
     *
     * There is no honest denominator for disk — Docker reports what it is using,
     * never what it may use — so that meter is numbers and no bar rather than a
     * bar against a number nobody can defend.
     */
    property real available: 0
    /** False while the denominator is still being read; the bar waits. */
    property bool known: false

    /** How to render a value of this resource. `Docker.formatMegabytes`, usually. */
    property var format: function (value) { return String(value); }
    /** Appended after the share, when the unit is not already in the number. */
    property string unit: ""

    readonly property bool drawBar: root.known && root.available > 0

    spacing: 5

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Glyph {
            visible: root.glyph.length > 0
            name: root.glyph
            size: 13
            thickness: 1.7
            tone: Theme.alpha(root.tone, 0.9)
        }

        Text {
            text: root.label
            color: Theme.textFaint
            font.pixelSize: Theme.fontEyebrow
            font.weight: Font.ExtraBold
            font.letterSpacing: 1.2
        }

        Item { Layout.fillWidth: true }

        Text {
            visible: root.hasGuarantee
            text: root.format(root.guaranteed)
            color: Theme.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Text {
            // The unit rides on the ceiling rather than on both numbers:
            // "0.5 up to 2 cores" is a sentence, "0.5 cores up to 2 cores" is
            // the same word twice.
            text: root.capped
                  ? (root.unit.length > 0
                     ? qsTr("up to %1 %2").arg(root.format(root.ceiling)).arg(root.unit)
                     : qsTr("up to %1").arg(root.format(root.ceiling)))
                  : root.uncappedText
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }

    MeterBar {
        Layout.fillWidth: true
        visible: root.drawBar
        height: 8
        total: Math.max(root.available, root.capped ? root.ceiling : root.guaranteed)
        segments: [
            { value: root.guaranteed, tone: root.tone },
            { value: root.capped ? Math.max(0, root.ceiling - root.guaranteed) : 0,
              tone: Theme.alpha(root.tone, 0.3) }
        ]
    }

    ElidedText {
        Layout.fillWidth: true
        visible: root.drawBar
        text: root.unit.length > 0
              ? qsTr("of the %1 %2 Docker has here")
                    .arg(root.format(root.available)).arg(root.unit)
              : qsTr("of the %1 Docker has here").arg(root.format(root.available))
        color: Theme.textFaint
        font.pixelSize: 11
        elide: Text.ElideRight
    }
}
