// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What is stored, and what it costs.
 *
 * Sorted biggest first, because the only reason anyone opens this list is to
 * find out where the disk went. Images nothing is built on are marked, since
 * those are the ones that can go without consequence.
 */
Item {
    id: root

    property string pendingId: ""
    property string pendingName: ""
    property bool pendingInUse: false

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Summary -----------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 24
                spacing: 18

                Glyph { name: "layers"; size: 16; thickness: 1.7; tone: Theme.blue }

                Text {
                    text: qsTr("%1 images").arg(Docker.images.count)
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    // The figure Docker's own `system df` reports: layers on
                    // disk, with shared ones counted once.
                    text: qsTr("%1 on disk").arg(Docker.formatBytes(Docker.diskImages))
                    color: Theme.textMuted
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: qsTr("largest first")
                    color: Theme.textFaint
                    font.pixelSize: 11
                }
            }
        }

        // ---- The list ----------------------------------------------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Docker.images
            reuseItems: true

            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: row

                required property string imageId
                required property string shortId
                required property string repository
                required property string tag
                required property string sizeText
                required property real size
                required property int containers
                required property string age
                required property bool dangling
                required property bool inUse

                width: list.width
                implicitHeight: 52

                Rectangle {
                    anchors.fill: parent
                    color: hover.hovered ? Theme.alpha(Theme.sky, 0.045) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.duration(Theme.durFast) }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 28
                    anchors.rightMargin: 24
                    height: 1
                    color: Theme.alpha(Theme.borderSubtle, 0.6)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 28
                    anchors.rightMargin: 24
                    spacing: 14

                    // A proportion-of-the-largest bar behind the name, so the
                    // list reads as a chart without becoming one.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 320
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ElidedText {
                                    text: row.dangling ? qsTr("untagged layer") : row.repository
                                    color: row.dangling ? Theme.textMuted : Theme.textPrimary
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.italic: row.dangling
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }

                                Rectangle {
                                    visible: !row.dangling
                                    implicitWidth: tagLabel.implicitWidth + 12
                                    implicitHeight: 16
                                    radius: 3
                                    color: Theme.alpha(Theme.blue, 0.12)
                                    border.width: 1
                                    border.color: Theme.alpha(Theme.blue, 0.26)

                                    Text {
                                        id: tagLabel
                                        anchors.centerIn: parent
                                        text: row.tag
                                        color: Theme.alpha(Theme.sky, 0.95)
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            ElidedText {
                                Layout.fillWidth: true
                                text: qsTr("%1  ·  %2").arg(row.shortId).arg(row.age)
                                color: Theme.textFaint
                                font.pixelSize: 11
                                font.family: Theme.monoFamily
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 84
                        implicitHeight: 18
                        radius: 4
                        color: row.inUse ? Theme.alpha(Theme.emerald, 0.11)
                                         : Theme.alpha(Theme.amber, 0.1)
                        border.width: 1
                        border.color: row.inUse ? Theme.alpha(Theme.emerald, 0.28)
                                                : Theme.alpha(Theme.amber, 0.26)

                        Text {
                            anchors.centerIn: parent
                            text: row.inUse ? qsTr("in use") : qsTr("unused")
                            color: row.inUse ? Theme.alpha(Theme.emerald, 0.95)
                                             : Theme.alpha(Theme.amber, 0.95)
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    Text {
                        Layout.preferredWidth: 90
                        horizontalAlignment: Text.AlignRight
                        text: row.sizeText
                        color: Theme.textBody
                        font.pixelSize: 13
                        font.family: Theme.monoFamily
                        font.weight: Font.DemiBold
                    }

                    Item {
                        Layout.preferredWidth: 36
                        Layout.fillHeight: true

                        IconButton {
                            anchors.centerIn: parent
                            glyph: "trash"
                            tooltip: row.inUse ? qsTr("A container is built on this")
                                               : qsTr("Remove")
                            size: 28
                            hoverTone: Theme.rose
                            enabled: !row.inUse
                            opacity: hover.hovered ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.duration(Theme.durFast) }
                            }

                            onClicked: imageConfirm.ask(row.imageId,
                                                        row.dangling ? row.shortId : row.repository,
                                                        row.sizeText)
                        }
                    }
                }

                HoverHandler { id: hover }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 380)
                visible: Docker.images.count === 0
                spacing: Theme.spaceMd

                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    name: "layers"
                    size: 40
                    thickness: 1.4
                    tone: Theme.alpha(Theme.textMuted, 0.4)
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("No images yet")
                    color: Theme.textBody
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("An image is the template a container is made from. They arrive the first time something needs one.")
                    color: Theme.textFaint
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }
        }
    }

    ConfirmDialog {
        id: imageConfirm
        anchors.fill: parent

        function ask(id, name, size) {
            root.pendingId = id;
            imageConfirm.title = qsTr("Remove %1?").arg(name);
            imageConfirm.body = qsTr("This frees %1. Nothing is built on it right now, and anything that needs it later downloads or rebuilds it again — which takes time and bandwidth but loses nothing.")
                                    .arg(size);
            imageConfirm.confirmText = qsTr("Remove");
            imageConfirm.open();
        }

        onAccepted: Docker.removeImage(root.pendingId, false)
    }
}
