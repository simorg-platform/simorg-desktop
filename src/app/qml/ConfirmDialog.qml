// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * "Are you sure?", for the handful of things here that cannot be undone.
 *
 * Deliberately not a native message box: those cannot be styled, they steal
 * focus from the whole application, and on macOS they arrive with a generic
 * application icon that tells the reader nothing about what they are being
 * asked. This is an overlay inside the window that asked the question.
 *
 * The destructive action is *not* the default and does not have focus. Somebody
 * who hits Return out of habit should get "no".
 */
Item {
    id: root

    property string title: ""
    property string body: ""
    property string confirmText: qsTr("Continue")
    property string cancelText: qsTr("Cancel")
    /** Draws the confirming button in rose. */
    property bool destructive: true

    signal accepted()
    /** Any way of saying no: the cancel button, Escape, or a click outside the panel. */
    signal rejected()
    /**
     * The cancel button itself, and only that, emitted before {@link rejected}.
     *
     * For a dialog whose second button is a choice of its own rather than "no":
     * pressing Escape on "Keep Simorg running?" is somebody changing their mind,
     * not somebody choosing Quit Simorg.
     */
    signal cancelPressed()

    visible: opacity > 0
    opacity: 0
    z: 200

    function open() { root.opacity = 1; }
    function close() { root.opacity = 0; }

    Behavior on opacity {
        NumberAnimation { duration: Theme.duration(Theme.durFast) }
    }

    // Swallows clicks and keys so nothing behind the dialog can be operated
    // while it is up.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.base, 0.72)

        TapHandler {
            onTapped: {
                root.close();
                root.rejected();
            }
        }
    }

    Keys.onEscapePressed: {
        root.close();
        root.rejected();
    }

    focus: root.opacity > 0

    GlassPanel {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 460)
        implicitHeight: content.implicitHeight + 44

        scale: root.opacity > 0 ? 1 : 0.96
        Behavior on scale {
            NumberAnimation {
                duration: Theme.duration(Theme.durBase)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.easeOut
            }
        }

        // The panel itself must not close the dialog when clicked.
        TapHandler { onTapped: {} }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            spacing: Theme.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: 13

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 34
                    height: 34
                    radius: 5
                    color: Theme.alpha(root.destructive ? Theme.rose : Theme.sky, 0.13)
                    border.width: 1
                    border.color: Theme.alpha(root.destructive ? Theme.rose : Theme.sky, 0.3)

                    Glyph {
                        anchors.centerIn: parent
                        name: root.destructive ? "alert" : "info"
                        size: 17
                        thickness: 1.7
                        tone: root.destructive ? Theme.rose : Theme.sky
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.body
                color: Theme.textBody
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.5
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: Theme.spaceSm

                Item { Layout.fillWidth: true }

                GhostButton {
                    text: root.cancelText
                    implicitHeight: 38
                    focus: true
                    onClicked: {
                        root.close();
                        root.cancelPressed();
                        root.rejected();
                    }
                }

                // Rose rather than the brand gradient: a destructive action
                // should not be wearing the colour of the app's happy path.
                Item {
                    implicitWidth: Math.max(110, confirmLabel.implicitWidth + 36)
                    implicitHeight: 38

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: confirmHover.hovered
                               ? Theme.alpha(root.destructive ? Theme.rose : Theme.blue, 0.24)
                               : Theme.alpha(root.destructive ? Theme.rose : Theme.blue, 0.14)
                        border.width: 1
                        border.color: Theme.alpha(root.destructive ? Theme.rose : Theme.blue, 0.55)

                        Behavior on color {
                            ColorAnimation { duration: Theme.duration(Theme.durFast) }
                        }
                    }

                    Text {
                        id: confirmLabel
                        anchors.centerIn: parent
                        text: root.confirmText
                        color: root.destructive ? Theme.rose : Theme.blue
                        font.pixelSize: Theme.fontBody
                        font.weight: Font.DemiBold
                    }

                    HoverHandler {
                        id: confirmHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            root.close();
                            root.accepted();
                        }
                    }
                }
            }
        }
    }
}
