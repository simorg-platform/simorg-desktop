// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * An explanation, marked as one.
 *
 * The icon is doing real work here: it tells someone scanning the page that
 * this block is context rather than an instruction or a warning, so they can
 * choose to read it. Warnings use the same shape in amber, and errors in rose,
 * so the three read as one family with the colour carrying the severity.
 */
Rectangle {
    id: root

    property string glyph: "info"
    property color tone: Theme.sky
    property string title: ""
    property string body: ""
    /** Optional trailing content — a button, usually. */
    default property alias trailing: trailingHolder.data

    radius: Theme.radiusBase
    color: Theme.alpha(tone, 0.07)
    border.width: 1
    border.color: Theme.alpha(tone, 0.22)

    implicitHeight: layout.implicitHeight + 28

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        spacing: 13

        // Given its own tinted disc so it reads as a mark rather than as the
        // first character of the sentence beside it.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 30
            height: 30
            radius: 6
            color: Theme.alpha(root.tone, 0.14)
            border.width: 1
            border.color: Theme.alpha(root.tone, 0.3)

            Glyph {
                anchors.centerIn: parent
                name: root.glyph
                size: 16
                thickness: 1.7
                tone: root.tone
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                visible: root.title.length > 0
                text: root.title
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: root.body.length > 0
                text: root.body
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                color: Theme.textBody
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.45
            }
        }

        Item {
            id: trailingHolder
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
