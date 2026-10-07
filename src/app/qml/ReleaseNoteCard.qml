// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One release and its **release note**, which opens in place.
 *
 * The header is the release as somebody scans a list of them — its number, its
 * title, when it came out, and a word beside the number when it is the newest,
 * the one installed, or was deprecated — and pressing it opens the note under
 * it: the publisher's Markdown, drawn by Qt's own Markdown reader and
 * selectable like every other sentence here. A release published before every
 * release was asked for a note says so rather than opening onto nothing.
 *
 * Links in a note open in the browser, and only web links: a note is somebody
 * else's text, and nothing in it gets to open a file or a scheme on this
 * computer.
 */
Item {
    id: root

    /** `{artifactTagId, tag, title, notes, publishedAt, isDeprecated}` from AgentSettingsModel. */
    property var release: ({})
    property bool open: false
    /** A word beside the number: "Newest", "Installed". Empty for none. */
    property string marker: ""

    readonly property bool deprecated: root.release && root.release.isDeprecated === true
    readonly property string notes: root.release && root.release.notes ? root.release.notes : ""
    readonly property string title: root.release && root.release.title ? root.release.title : ""

    implicitHeight: frame.implicitHeight

    function publishedOn(iso) {
        if (!iso || iso.length === 0)
            return "";
        return new Date(iso).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    Rectangle {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: body.implicitHeight + 20
        radius: 8
        color: Theme.alpha(Theme.sky, root.open ? 0.06 : 0.03)
        border.width: 1
        border.color: Theme.alpha(Theme.sky, root.open ? 0.3 : 0.18)

        Behavior on color {
            ColorAnimation { duration: Theme.duration(Theme.durFast) }
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 6

            // The header: the whole row opens and closes the note.
            Item {
                Layout.fillWidth: true
                implicitHeight: header.implicitHeight

                RowLayout {
                    id: header
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 8

                    Text {
                        text: root.release && root.release.tag && root.release.tag.length > 0
                              ? root.release.tag : qsTr("A newer release")
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                    }

                    Text {
                        visible: root.marker.length > 0
                        text: root.marker
                        color: Theme.sky
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                    }

                    Text {
                        visible: root.deprecated
                        text: qsTr("Deprecated")
                        color: Theme.amber
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.publishedOn(root.release ? root.release.publishedAt : "")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Glyph {
                        name: "chevron-down"
                        size: 14
                        thickness: 1.6
                        tone: Theme.textMuted
                        rotation: root.open ? 180 : 0

                        Behavior on rotation {
                            enabled: Theme.motion
                            NumberAnimation { duration: Theme.durFast }
                        }
                    }
                }

                MouseArea {
                    objectName: "releaseNoteToggle"
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open = !root.open
                }
            }

            SelectableText {
                Layout.fillWidth: true
                visible: root.title.length > 0
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            SelectableText {
                objectName: "releaseNoteText"
                Layout.fillWidth: true
                visible: root.open && root.notes.length > 0
                textFormat: TextEdit.MarkdownText
                text: root.notes
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                onLinkActivated: function (link) {
                    if (/^https?:\/\//i.test(link))
                        Qt.openUrlExternally(link);
                }
            }

            SelectableText {
                Layout.fillWidth: true
                visible: root.open && root.notes.length === 0
                text: qsTr("No release note was written for this release. It came out before every release was asked for one.")
                color: Theme.textFaint
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
