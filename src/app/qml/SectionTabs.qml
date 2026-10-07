// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * The dashboard's section switcher.
 *
 * A tab strip rather than a sidebar, because this is a desktop application and
 * not a web console: the sections are few, they are peers, and none of them is
 * a place you navigate *into*. A rail down the left would spend 230 pixels of a
 * 1240-pixel window restating that — and on a laptop screen those pixels belong
 * to a container list.
 *
 * The active pill slides rather than jumping, which is the one piece of motion
 * here that carries information: it says which way you moved.
 */
Item {
    id: root

    /**
     * `[{ key, label, glyph, ready, soon }]`.
     *
     * `ready: false` cannot be opened at all. `soon: true` opens normally but is
     * marked as still being built — which is the honest state of a section that
     * has a real screen behind it and placeholders inside it.
     *
     * `badge: n` puts a red dot on the tab when `n` is above zero: something in
     * that section is waiting for the person, and they may be looking at a
     * different one.
     */
    property var items: []
    property int currentIndex: 0

    signal selected(int index)

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 8

    // The sliding pill. It lives behind the row so a tab's own hover tint can
    // sit on top of it without fighting for the same pixel.
    Rectangle {
        id: pill
        y: 0
        height: root.height
        radius: Theme.radiusBase
        color: Theme.alpha(Theme.blue, 0.16)
        border.width: 1
        border.color: Theme.alpha(Theme.blue, 0.34)
        visible: width > 0

        Behavior on x {
            enabled: Theme.motion
            NumberAnimation {
                duration: Theme.durBase
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }
        Behavior on width {
            enabled: Theme.motion
            NumberAnimation {
                duration: Theme.durBase
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }

        // A hairline of accent along the bottom, the way a selected tab reads
        // in a native toolbar.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            width: parent.width * 0.5
            height: 2
            radius: 1
            color: Theme.cyan
        }
    }

    function syncPill() {
        const item = row.children[root.currentIndex];
        if (!item || item.width === undefined)
            return;
        pill.x = item.x + row.x;
        pill.width = item.width;
    }

    onCurrentIndexChanged: syncPill()
    onWidthChanged: syncPill()
    Component.onCompleted: syncPill()

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: root.items

            delegate: Item {
                id: tab
                required property var modelData
                required property int index

                readonly property bool current: root.currentIndex === index
                readonly property bool interactive: modelData.ready
                /** How many things in that section are waiting for somebody. */
                readonly property int badge: modelData.badge === undefined
                                             ? 0 : modelData.badge
                /** Marked as unfinished, whether or not it can be opened. */
                readonly property bool upcoming: !modelData.ready || modelData.soon === true

                Layout.preferredWidth: content.implicitWidth + 28
                Layout.preferredHeight: root.height

                onWidthChanged: if (current) root.syncPill()

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusBase
                    color: !tab.current && hover.hovered && tab.interactive
                           ? Theme.alpha(Theme.sky, 0.07)
                           : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.duration(Theme.durFast) }
                    }
                }

                RowLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: 8

                    Glyph {
                        name: tab.modelData.glyph
                        size: 16
                        thickness: 1.6
                        tone: tab.current ? Theme.sky
                            : tab.interactive ? Theme.textBody
                            : Theme.alpha(Theme.textMuted, 0.45)

                        Behavior on tone {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    Text {
                        text: tab.modelData.label
                        color: tab.current ? Theme.textPrimary
                             : tab.interactive ? Theme.textBody
                             : Theme.alpha(Theme.textMuted, 0.5)
                        font.pixelSize: Theme.fontSmall
                        font.weight: tab.current ? Font.DemiBold : Font.Medium

                        Behavior on color {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    // A dot rather than a "soon" chip: at this size the word is
                    // wider than the tab it is attached to.
                    Rectangle {
                        visible: tab.upcoming && tab.badge === 0
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Theme.alpha(Theme.violet, 0.7)
                    }

                    /*
                      Something in that section is waiting for you.

                      Red, and bigger than the "soon" dot, because it is the one
                      mark in this strip that is asking for something rather
                      than describing something. It takes the place of the soon
                      dot when both would apply: two dots on one tab is a
                      puzzle, and this is the one that matters.

                      A dot rather than a number. The count is on the row inside
                      the section, where it is beside the agent it belongs to;
                      out here the useful signal is only "there is something",
                      and a growing number on a tab is a thing people learn to
                      ignore.
                    */
                    Rectangle {
                        id: attentionDot
                        visible: tab.badge > 0
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Theme.rose

                        // A slow halo, the same one an online agent's dot uses.
                        // Fast enough to notice on the way past, slow enough
                        // never to compete with the section being read.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            radius: parent.radius
                            color: Theme.rose
                            z: -1

                            SequentialAnimation on opacity {
                                running: attentionDot.visible && Theme.motion
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.55; to: 0; duration: 1800 }
                                PauseAnimation { duration: 400 }
                            }
                            SequentialAnimation on scale {
                                running: attentionDot.visible && Theme.motion
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 2.4; duration: 1800 }
                                PauseAnimation { duration: 400 }
                            }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                    enabled: tab.interactive
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: tab.interactive
                    onTapped: root.selected(tab.index)
                }
            }
        }
    }
}
