// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * A compact switch between views of one thing — the Docker section's
 * Overview / Containers / Images / Resources.
 *
 * Distinct from {@link SectionTabs} on purpose: these are lenses on a single
 * subject and are drawn inside a recessed track, where the tabs above them
 * change what the window is about and are drawn on the surface.
 */
Item {
    id: root

    /** `[{ key, label, glyph, badge }]`. `badge` is optional and may be 0. */
    property var items: []
    property int currentIndex: 0

    signal selected(int index)

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 8

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusBase
        color: Theme.inset
        border.width: 1
        border.color: Theme.borderSubtle
    }

    Rectangle {
        id: thumb
        y: 4
        height: root.height - 8
        radius: Theme.radiusSmall
        color: Theme.alpha(Theme.sky, 0.14)
        border.width: 1
        border.color: Theme.alpha(Theme.sky, 0.3)
        visible: width > 0

        Behavior on x {
            enabled: Theme.motion
            NumberAnimation {
                duration: Theme.durFast
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }
        Behavior on width {
            enabled: Theme.motion
            NumberAnimation { duration: Theme.durFast }
        }
    }

    function syncThumb() {
        const item = row.children[root.currentIndex];
        if (!item || item.width === undefined)
            return;
        thumb.x = item.x + row.x;
        thumb.width = item.width;
    }

    onCurrentIndexChanged: syncThumb()
    onWidthChanged: syncThumb()
    Component.onCompleted: syncThumb()

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: root.items

            delegate: Item {
                id: segment
                required property var modelData
                required property int index

                readonly property bool current: root.currentIndex === index

                Layout.preferredWidth: inner.implicitWidth + 22
                Layout.preferredHeight: root.height - 8

                onWidthChanged: if (current) root.syncThumb()

                RowLayout {
                    id: inner
                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        visible: segment.modelData.glyph !== undefined
                        name: segment.modelData.glyph || ""
                        size: 13
                        thickness: 1.6
                        tone: segment.current ? Theme.sky : Theme.textMuted

                        Behavior on tone {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    Text {
                        text: segment.modelData.label
                        color: segment.current ? Theme.textPrimary : Theme.textMuted
                        font.pixelSize: 12
                        font.weight: segment.current ? Font.DemiBold : Font.Medium

                        Behavior on color {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    Rectangle {
                        visible: (segment.modelData.badge || 0) > 0
                        implicitWidth: badgeText.implicitWidth + 10
                        implicitHeight: 15
                        radius: 4
                        color: segment.current ? Theme.alpha(Theme.cyan, 0.2)
                                               : Theme.alpha(Theme.textMuted, 0.15)

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: segment.modelData.badge || 0
                            color: segment.current ? Theme.cyan : Theme.textMuted
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selected(segment.index) }
            }
        }
    }
}
