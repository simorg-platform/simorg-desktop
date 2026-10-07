// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * A section that is coming, said plainly.
 *
 * Shown rather than hidden, because somebody evaluating this app deserves to
 * know where it is going — and because a tab that is visibly not finished is
 * more honest than one that quietly does not exist. It says what the section
 * will do and points at the place that already does it today.
 */
Item {
    id: root

    property string title: ""
    property string glyph: "cube"
    property string body: ""

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: Theme.spaceLg

        Reveal {
            step: 0
            Layout.alignment: Qt.AlignHCenter

            /*
              Implicit size, not width/height.

              Reveal measures itself from its child's *implicit* size, and a
              plain Rectangle has none — so this arrived as a zero-high item and
              the title below it was laid out on top of the icon. An item sized
              this way still gets its width and height from the same numbers.
            */
            Rectangle {
                implicitWidth: 72
                implicitHeight: 72
                radius: 8
                color: Theme.alpha(Theme.violet, 0.09)
                border.width: 1
                border.color: Theme.alpha(Theme.violet, 0.24)

                Glyph {
                    anchors.centerIn: parent
                    name: root.glyph
                    size: 32
                    thickness: 1.5
                    tone: Theme.alpha(Theme.violet, 0.85)
                }
            }
        }

        Reveal {
            step: 1
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.body
                    color: Theme.textBody
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.55
                }
            }
        }

        Reveal {
            step: 2
            Layout.alignment: Qt.AlignHCenter

            GhostButton {
                text: qsTr("Open it in the browser")
                onClicked: App.openWebApp()
            }
        }
    }
}
