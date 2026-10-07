// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The application every agent may always use, as a fixed entry of the
 * **Applications** permission.
 *
 * Simorg Desktop is what makes this computer somewhere agents run, and every
 * agent placed here needs it, so the machine service allows it whatever an
 * agent's Applications answer says — `Only these`, `All`, `None`, a rule of
 * Never allow, or no request at all. This is that fact on screen, wherever the
 * permission is.
 *
 * Named by the platform and never by this build: the specifier is
 * `AccessGrants.alwaysAllowedApplications`, which the service read from the
 * platform's `simorg_desktop_artifact_specifier`. Until it has, nothing is
 * drawn, rather than a name guessed at.
 */
Rectangle {
    id: root

    readonly property var applications: AccessGrants.alwaysAllowedApplications

    visible: root.applications.length > 0
    implicitHeight: visible ? row.implicitHeight + 22 : 0
    radius: Theme.radiusBase
    color: Theme.alpha(Theme.emerald, 0.06)
    border.width: 1
    border.color: Theme.alpha(Theme.emerald, 0.24)

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        Glyph {
            name: "logos"
            size: 18
            thickness: 1.6
            tone: Theme.sky
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: qsTr("Simorg Desktop")
                color: Theme.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            // The specifier somebody would search for, or paste into a question.
            SelectableText {
                Layout.fillWidth: true
                text: root.applications.join(", ")
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.monoFamily
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Every agent needs it, so it is always allowed, whatever is chosen here.")
                color: Theme.textFaint
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            implicitWidth: allowedRow.implicitWidth + 16
            implicitHeight: 22
            radius: 11
            color: "transparent"
            border.width: 1
            border.color: Theme.alpha(Theme.emerald, 0.4)

            RowLayout {
                id: allowedRow
                anchors.centerIn: parent
                spacing: 5

                Glyph { name: "lock"; size: 11; thickness: 1.7; tone: Theme.emerald }

                Text {
                    text: qsTr("Always allowed")
                    color: Theme.emerald
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
