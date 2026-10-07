// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * A heading painted across the brand gradient.
 *
 * Qt Quick fills text with one colour, and the alternative — a shader effect —
 * would pull the Qt Shader Tools module into the build for one visual flourish.
 * Instead each glyph is drawn separately and coloured by its position along the
 * line, which lands on the same result for the short headings this is meant for.
 *
 * Not for body copy: use a solid colour there, both for legibility and because
 * this lays out one Text item per character.
 */
Item {
    id: root

    /** Newlines split into separately-graded lines. */
    property string text: ""
    property var stops: Theme.headingGradientStops
    property int pixelSize: Theme.fontDisplay
    property int weight: Font.ExtraBold
    property real letterSpacing: -0.3
    property real lineHeight: 1.22
    property int horizontalAlignment: Text.AlignLeft

    readonly property var lines: text.split("\n")

    // Read as one heading and the whole line, not as a row of single letters:
    // a screen reader, or UI Automation, would otherwise spell it out.
    Accessible.role: Accessible.Heading
    Accessible.name: root.text

    // Sizing comes from one ordinary Text laid out with the same font. Deriving
    // it from the glyph rows instead would put the item's own width on both
    // sides of the binding — the rows are positioned relative to it.
    implicitWidth: metrics.implicitWidth
    implicitHeight: metrics.implicitHeight

    Text {
        id: metrics
        visible: false
        Accessible.ignored: true
        text: root.text
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
        font.family: Theme.fontFamily
        lineHeight: root.lineHeight
        lineHeightMode: Text.ProportionalHeight
    }

    Column {
        width: root.width

        Repeater {
            model: root.lines

            delegate: Item {
                id: line
                required property string modelData

                width: root.width
                height: metrics.implicitHeight / Math.max(1, root.lines.length)

                Row {
                    id: glyphs
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.horizontalAlignment === Text.AlignHCenter
                       ? Math.max(0, (line.width - width) / 2)
                       : root.horizontalAlignment === Text.AlignRight
                         ? Math.max(0, line.width - width)
                         : 0

                    Repeater {
                        model: line.modelData.length

                        delegate: Text {
                            required property int index

                            Accessible.ignored: true

                            text: line.modelData.charAt(index)
                            color: root.colorAt(line.modelData.length <= 1
                                                ? 0.5
                                                : index / (line.modelData.length - 1))
                            font.pixelSize: root.pixelSize
                            font.weight: root.weight
                            font.letterSpacing: root.letterSpacing
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }
        }
    }

    /** Colour `position` (0 → 1) of the way along the gradient. */
    function colorAt(position) {
        const list = root.stops;
        if (list.length === 0)
            return Theme.textPrimary;
        if (list.length === 1)
            return list[0];

        const scaled = Math.max(0, Math.min(1, position)) * (list.length - 1);
        const index = Math.min(Math.floor(scaled), list.length - 2);
        return Theme.mix(list[index], list[index + 1], scaled - index);
    }
}
