// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Uninstall Simorg: why, and whether the data goes too.
 *
 * ## One form, and nothing pressed for the person
 *
 * The reasons are optional and any number may be ticked: people often have more
 * than one, and a form that made them choose the main one would lose the second.
 * There are ten of them, with Other last and the comment box under it. They leave the computer anonymously,
 * through the machine service, with no account, machine or address on them.
 *
 * "Also delete Simorg's data and the agent image" is ticked to begin with: after
 * the sign-out every uninstall runs, what is left is logs and an image of several
 * gigabytes that only Simorg uses. The size beside it is the cache and that image
 * as they are measured now, and is left off when neither is known.
 *
 * ## What pressing Uninstall does
 *
 * Asks, when agents are running here, because signing out stops them — the same
 * question Quit and Sign out ask (`App.uninstall`). From then on the uninstall
 * window says every step as it happens, and this page is behind it.
 */
Item {
    id: root

    /** Each code the person ticked, as `{code: true}`. */
    property var chosen: ({})
    property bool removeData: true

    /** Measured when the page is opened, so the size beside the box is today's. */
    onVisibleChanged: if (visible) Storage.refresh()
    Component.onCompleted: if (visible) Storage.refresh()

    readonly property real dataBytes: (Storage.measured ? Storage.cacheBytes : 0)
                                      + Docker.images.bytesOf("simorg/agent-runtime")

    function tickedCodes() {
        const codes = [];
        for (const reason of Uninstall.reasons) {
            if (root.chosen[reason.code] === true)
                codes.push(reason.code);
        }
        return codes;
    }

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

                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: form.implicitHeight + 48
                    accent: Theme.danger

                    ColumnLayout {
                        id: form
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 24
                        spacing: Theme.spaceMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Glyph {
                                name: "trash"
                                size: 16
                                thickness: 1.7
                                tone: Theme.danger
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Uninstall Simorg")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("This removes Simorg from this computer. Your account and your agents on "
                                       + "simorg.tech stay, and you can install Simorg again at any time.")
                            color: Theme.textMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            lineHeight: 1.25
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            text: qsTr("Why are you uninstalling? (optional, pick any)")
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: Uninstall.reasons

                                delegate: SimorgCheckBox {
                                    required property var modelData

                                    objectName: "reason_" + modelData.code
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    checked: root.chosen[modelData.code] === true
                                    onToggled: function (isChecked) {
                                        const next = Object.assign({}, root.chosen);
                                        next[modelData.code] = isChecked;
                                        root.chosen = next;
                                    }
                                }
                            }
                        }

                        SimorgTextArea {
                            id: comment
                            objectName: "uninstallComment"
                            Layout.fillWidth: true
                            label: qsTr("Tell us more (optional)")
                            rows: 4
                            // The platform keeps at most this much, so the box stops there rather than losing the end.
                            onTextChanged: {
                                if (text.length > Uninstall.commentLimit)
                                    text = text.substring(0, Uninstall.commentLimit);
                            }
                        }

                        SimorgCheckBox {
                            objectName: "removeData"
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: root.dataBytes > 0
                                  ? qsTr("Also delete Simorg's data and the agent image (%1)").arg(Docker.formatBytes(root.dataBytes))
                                  : qsTr("Also delete Simorg's data and the agent image")
                            checked: root.removeData
                            onToggled: function (isChecked) { root.removeData = isChecked; }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 6

                            Item {
                                Layout.fillWidth: true
                            }

                            PrimaryButton {
                                objectName: "uninstallButton"
                                text: qsTr("Uninstall")
                                enabled: !Uninstall.started
                                onClicked: App.uninstall(root.tickedCodes(), comment.text, root.removeData)
                            }
                        }
                    }
                }
            }
        }
    }
}
