// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One of the three doors on the landing page.
 *
 * Agents, this machine and Docker are the three things the app is about, so on
 * Home they are three identical shapes side by side: a name, a live count, and
 * one line of context. Identical on purpose — the moment one of them is drawn a
 * little larger or a little richer it stops being a peer, and the page starts
 * arguing for a section instead of reporting on one.
 *
 * The count is the largest thing on the tile. A tile that has no count yet shows
 * an em dash rather than a zero: "nothing is running" and "nothing has told us"
 * are different, and only one of them should worry anybody.
 */
GlassPanel {
    id: root

    property string label: ""
    property string glyph: ""
    property color tone: Theme.blue
    /** The headline reading. Pass "—" when there is nothing to report. */
    property string value: ""
    property string caption: ""
    /** A second, quieter line under the caption. Optional. */
    property string detail: ""
    /** A {@link StateDot} state, or empty for no dot. */
    property string dotState: ""

    signal activated()

    implicitHeight: 132
    interactive: true
    hovered: hover.hovered

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Glyph {
                name: root.glyph
                size: 15
                thickness: 1.7
                tone: root.tone
            }

            ElidedText {
                Layout.fillWidth: true
                text: root.label
                color: Theme.textFaint
                font.pixelSize: Theme.fontEyebrow
                font.weight: Font.ExtraBold
                font.letterSpacing: 1.3
                elide: Text.ElideRight
            }

            StateDot {
                visible: root.dotState.length > 0
                state: root.dotState
                size: 7
            }

            Glyph {
                name: "arrow-right"
                size: 14
                thickness: 1.6
                tone: hover.hovered ? Theme.sky : Theme.textFaint

                Behavior on tone {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }
            }
        }

        ElidedText {
            Layout.fillWidth: true
            text: root.value
            color: Theme.textPrimary
            font.pixelSize: 24
            font.weight: Font.Bold
            font.letterSpacing: -0.5
            elide: Text.ElideRight
        }

        ElidedText {
            Layout.fillWidth: true
            visible: root.caption.length > 0
            text: root.caption
            color: Theme.textMuted
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        ElidedText {
            Layout.fillWidth: true
            visible: root.detail.length > 0
            text: root.detail
            color: Theme.textFaint
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler { onTapped: root.activated() }
}
