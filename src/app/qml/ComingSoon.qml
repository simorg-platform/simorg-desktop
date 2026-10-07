// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * A screen that is designed but not built yet, said once and said properly.
 *
 * Every unfinished surface in the app uses this one component rather than
 * inventing its own empty state, for the reason empty states usually go wrong:
 * a dozen hand-written "coming soon" panels drift into a dozen different tones,
 * and a person who meets three of them stops believing any of them.
 *
 * It always says three things — what the screen will be, what it will let you
 * do, and that it is not here yet — because a placeholder that only says the
 * last one is indistinguishable from a bug.
 */
GlassPanel {
    id: root

    property string glyph: "clock"
    property string title: ""
    property string body: ""
    /** What the finished screen will let somebody do; one short line each. */
    property var points: []
    property color tone: Theme.violet

    implicitHeight: layout.implicitHeight + 44

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 22
        spacing: Theme.spaceMd

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                Layout.alignment: Qt.AlignTop
                width: 44
                height: 44
                radius: 6
                color: Theme.alpha(root.tone, 0.1)
                border.width: 1
                border.color: Theme.alpha(root.tone, 0.26)

                Glyph {
                    anchors.centerIn: parent
                    name: root.glyph
                    size: 21
                    thickness: 1.6
                    tone: Theme.alpha(root.tone, 0.9)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    font.letterSpacing: -0.2
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.body.length > 0
                    text: root.body
                    color: Theme.textBody
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }

            // The status, kept out of the sentence so it can be scanned. Top
            // aligned: it belongs to the panel, not to the line beside it.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: statusRow.implicitWidth + 20
                implicitHeight: 24
                radius: 5
                color: Theme.alpha(root.tone, 0.12)
                border.width: 1
                border.color: Theme.alpha(root.tone, 0.3)

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        name: "clock"
                        size: 12
                        thickness: 1.8
                        tone: root.tone
                    }

                    Text {
                        text: qsTr("Available soon")
                        color: root.tone
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.points.length > 0
            implicitHeight: 1
            color: Theme.borderSubtle
        }

        GridLayout {
            Layout.fillWidth: true
            visible: root.points.length > 0
            columns: root.width > 700 ? 2 : 1
            columnSpacing: Theme.spaceLg
            rowSpacing: Theme.spaceSm

            Repeater {
                model: root.points

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 9

                    // A hollow marker, not a tick: nothing on this list is done.
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        width: 7
                        height: 7
                        radius: 3.5
                        color: "transparent"
                        border.width: 1.4
                        border.color: Theme.alpha(root.tone, 0.65)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData
                        color: Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }
                }
            }
        }
    }
}
