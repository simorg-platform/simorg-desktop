// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * A vertical list of peers, one of which is open.
 *
 * The third and last navigation shape in the app, and the one with the narrowest
 * remit: {@link SectionTabs} changes what the window is about, {@link
 * SegmentedControl} changes the lens on one subject, and this changes which of a
 * long list of same-shaped things is being edited. Seven permissions do not fit
 * in a segmented control and would not read as a list if they did.
 *
 * The active row carries a left accent bar rather than a filled pill, because a
 * rail this narrow needs its selection legible from the corner of the eye while
 * somebody is reading the pane beside it.
 */
Item {
    id: root

    /** `[{ key, label, glyph }]`. */
    property var items: []
    property int currentIndex: 0
    /** Optional heading above the list. */
    property string heading: ""

    signal selected(int index)

    implicitWidth: 224
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 2

        ElidedText {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.bottomMargin: 6
            visible: root.heading.length > 0
            text: root.heading
            color: Theme.textFaint
            font.pixelSize: Theme.fontEyebrow
            font.weight: Font.ExtraBold
            font.letterSpacing: 1.3
            elide: Text.ElideRight
        }

        Repeater {
            model: root.items

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property bool current: root.currentIndex === index

                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Theme.radiusSmall
                color: row.current ? Theme.alpha(Theme.sky, 0.1)
                     : hover.hovered ? Theme.alpha(Theme.sky, 0.05)
                     : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2.5
                    height: row.current ? parent.height - 14 : 0
                    radius: 1.25
                    color: Theme.cyan

                    Behavior on height {
                        enabled: Theme.motion
                        NumberAnimation {
                            duration: Theme.durFast
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.easeOut
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 11
                    spacing: 10

                    Glyph {
                        name: row.modelData.glyph
                        size: 15
                        thickness: 1.6
                        tone: row.current ? Theme.sky
                            : hover.hovered ? Theme.textBody
                            : Theme.textMuted

                        Behavior on tone {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    ElidedText {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: row.current ? Theme.textPrimary : Theme.textBody
                        font.pixelSize: 12
                        font.weight: row.current ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight

                        Behavior on color {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler { onTapped: root.selected(row.index) }
            }
        }
    }
}
