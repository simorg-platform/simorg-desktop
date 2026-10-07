// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Settings → Licences: what this program is, whose work is inside it, and
 * where its source is.
 *
 * The GNU Lesser General Public License, which Qt is used under, asks for a
 * prominent notice that the library is used and for its text to travel with
 * the program; the GNU General Public License, which this program is under,
 * asks that the source be offered to whoever receives a binary. This view is
 * where both are honoured on screen: the licences are read from the files
 * installed beside the program (cmake/SimorgNotices.cmake), not from a copy
 * compiled in, so the text shown is the text shipped.
 *
 * Selectable, like every text somebody might need somewhere else.
 */
Item {
    id: root

    readonly property string notices: App.thirdPartyNotices()
    readonly property string noticesPath: App.thirdPartyNoticesPath()

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 860
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 26
                Layout.bottomMargin: 34
                spacing: Theme.spaceLg

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Free software")
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.textBody
                    font.pixelSize: 12
                    lineHeight: 1.35
                    text: qsTr("Simorg Desktop is free software under the GNU General Public License, version 3 or any later version. You may use, study, share and change it under that licence, and its source code is published. It is built with Qt under the GNU Lesser General Public License, version 3, linked as separate libraries beside the program so that you can replace Qt and run the program with your copy.")
                }

                RowLayout {
                    spacing: Theme.spaceMd
                    Button {
                        text: qsTr("Source code")
                        onClicked: App.openExternal(App.sourceRepositoryUrl())
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        color: Theme.textFaint
                        font.pixelSize: 11
                        text: root.noticesPath.length > 0
                              ? qsTr("Notices: %1").arg(root.noticesPath)
                              : qsTr("The notices file was not installed beside this build.")
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Third-party notices")
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                TextArea {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    color: Theme.textBody
                    font.family: Theme.monoFamily
                    font.pixelSize: 11
                    text: root.notices.length > 0
                          ? root.notices
                          : qsTr("This build carries no THIRD-PARTY-NOTICES.txt. A release build writes one at configure time from packaging/notices/; see docs/packaging.md, Third-party notices.")
                    background: Rectangle {
                        color: Theme.inset
                        border.color: Theme.borderSubtle
                        radius: 6
                    }
                }
            }
        }
    }
}
