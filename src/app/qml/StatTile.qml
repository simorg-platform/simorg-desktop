// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * One reading, at a glance: a label, the number, and what the number means.
 *
 * The value is the largest thing on the tile and the label is the smallest,
 * which is the right way round for a panel somebody glances at rather than
 * reads. Anything extra — a history line, a breakdown bar — goes in `extra`,
 * below the number and never beside it.
 */
GlassPanel {
    id: root

    property string label: ""
    property string value: ""
    property string caption: ""
    property string glyph: ""
    property color tone: Theme.blue
    /** Rendered under the caption; a Sparkline or a MeterBar, usually. */
    default property alias extra: extraHolder.data

    implicitHeight: column.implicitHeight + 34

    // Content sits at the top: when a row of tiles is stretched to match its
    // tallest member, the shorter ones grow downwards rather than drifting
    // their labels out of line with the others.

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 17
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Glyph {
                visible: root.glyph.length > 0
                name: root.glyph
                size: 14
                thickness: 1.7
                tone: Theme.alpha(root.tone, 0.9)
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
        }

        ElidedText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text: root.value
            color: Theme.textPrimary
            font.pixelSize: 26
            font.weight: Font.Bold
            font.letterSpacing: -0.6
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

        Item {
            id: extraHolder
            Layout.fillWidth: true
            Layout.topMargin: children.length > 0 ? 8 : 0
            implicitHeight: childrenRect.height

            // Anything dropped in fills the tile's width without the caller
            // having to know how wide the tile turned out to be.
            onChildrenChanged: {
                for (let i = 0; i < children.length; ++i)
                    children[i].width = Qt.binding(() => extraHolder.width);
            }
        }
    }
}
