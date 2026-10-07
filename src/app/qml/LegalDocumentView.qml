// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * One legal document, laid out to be read rather than skimmed past.
 *
 * The text is not in this file. It comes from `config/legal/legal.json` through
 * the `Legal` singleton, which is the only copy of it in the product and the
 * one CMake bakes into the binary. A component that held its own paragraphs
 * would be a second edition of an agreement, and the two would drift.
 *
 * Deliberately plain: a measure capped near 760px because a line of legal text
 * that runs the width of a 1360px window is one nobody finishes, generous line
 * height, one weight for headings and one for body, and no card per section.
 * Cards were tried and they turned an agreement into a feed.
 */
Item {
    id: root

    /** One entry of `Legal.documents` — `{ title, summary, sections }`. */
    property var document: ({})

    /** Reading position, so the window can send a reader back to the top. */
    function scrollToTop() {
        pane.contentItem.contentY = 0;
    }

    readonly property var sections: root.document && root.document.sections
                                    ? root.document.sections : []

    ScrollView {
        id: pane
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 760
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 26
                Layout.bottomMargin: 40
                spacing: Theme.spaceLg

                // ---- What this document is about ---------------------------
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.document && root.document.summary ? root.document.summary : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                    lineHeight: 1.6
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.borderSubtle
                }

                // ---- The sections ------------------------------------------
                Repeater {
                    model: root.sections

                    delegate: ColumnLayout {
                        id: section
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.spaceSm

                        Text {
                            Layout.fillWidth: true
                            text: section.modelData.title
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: section.modelData.body
                            color: Theme.textBody
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.65
                        }

                        // Bullets, for the sections that list one thing per
                        // platform. Drawn rather than typed: a "-" in the JSON
                        // would leave the wrapped lines hanging under it.
                        Repeater {
                            model: section.modelData.points ? section.modelData.points : []

                            delegate: RowLayout {
                                id: point
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: 6
                                spacing: 11

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 8
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: Theme.alpha(Theme.sky, 0.85)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: point.modelData
                                    color: Theme.textBody
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.6
                                }
                            }
                        }

                        // The closing paragraph some sections carry, set apart
                        // because it qualifies everything above it.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: section.modelData.note && section.modelData.note.length > 0
                            implicitHeight: note.implicitHeight + 24
                            radius: Theme.radiusBase
                            color: Theme.inset
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Text {
                                id: note
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                text: section.modelData.note ? section.modelData.note : ""
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.6
                            }
                        }
                    }
                }
            }
        }
    }
}
