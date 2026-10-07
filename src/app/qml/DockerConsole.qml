// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The monitoring centre — what Docker is doing on this machine.
 *
 * Four lenses on one subject, so a segmented control rather than more tabs:
 * Overview answers "is anything wrong", Containers answers "what is running",
 * Images answers "what is this costing me", and Resources is the only one of
 * the four that changes anything.
 *
 * The header stays put across all four, because "which Docker am I looking at"
 * is a question that should never require switching views to answer — on a
 * machine with a remote context set, it is the whole answer.
 */
Item {
    id: root

    property int view: 0
    property string toastText: ""
    property string toastTone: "success"

    readonly property var views: [
        { key: "overview", label: qsTr("Overview"), glyph: "gauge" },
        { key: "containers", label: qsTr("Containers"), glyph: "container",
          badge: Docker.containersRunning },
        { key: "images", label: qsTr("Images"), glyph: "layers", badge: Docker.imageCount },
        { key: "settings", label: qsTr("Settings"), glyph: "settings" }
    ]

    /** Settings, which is the Resources page. See DockerSection.showResources. */
    function showResources() {
        root.view = 3;
    }

    Connections {
        target: Docker

        function onActionSucceeded(action, message) {
            root.toastTone = "success";
            root.toastText = message;
            toastTimer.restart();
        }

        function onActionFailed(action, message) {
            root.toastTone = "error";
            root.toastText = message;
            // Failures stay up longer: they usually need reading twice, and
            // sometimes acting on.
            toastTimer.restart();
        }
    }

    Timer {
        id: toastTimer
        interval: root.toastTone === "error" ? 9000 : 4000
        onTriggered: root.toastText = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ----------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 20
                spacing: 14

                StateDot {
                    state: "running"
                    size: 8
                }

                ColumnLayout {
                    spacing: 1

                    RowLayout {
                        spacing: 8

                        Text {
                            text: Docker.platformName.length > 0
                                  ? Docker.platformName
                                  : qsTr("Docker Engine %1").arg(Docker.engineVersion)
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            font.letterSpacing: -0.2
                        }

                        Rectangle {
                            implicitWidth: apiLabel.implicitWidth + 14
                            implicitHeight: 18
                            radius: 4
                            color: Theme.alpha(Theme.emerald, 0.11)
                            border.width: 1
                            border.color: Theme.alpha(Theme.emerald, 0.3)

                            Text {
                                id: apiLabel
                                anchors.centerIn: parent
                                text: qsTr("API %1").arg(Docker.apiVersion)
                                color: Theme.alpha(Theme.emerald, 0.95)
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }
                    }

                    ElidedText {
                        text: Docker.endpoint
                        color: Theme.textFaint
                        font.pixelSize: 11
                        font.family: Theme.monoFamily
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 420
                    }
                }

                Item { Layout.fillWidth: true }

                SegmentedControl {
                    items: root.views
                    currentIndex: root.view
                    onSelected: function (index) { root.view = index; }
                }

                IconButton {
                    glyph: "refresh"
                    tooltip: qsTr("Check again now")
                    busy: Docker.probing
                    onClicked: Docker.refresh()
                }
            }
        }

        // ---- Restart owed ----------------------------------------------
        // Kept above the views rather than inside Resources: somebody who
        // changed a limit and moved on has to be able to see that it has not
        // taken effect yet.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Docker.restartPending ? 62 : 0
            visible: height > 0
            clip: true

            Behavior on Layout.preferredHeight {
                enabled: Theme.motion
                NumberAnimation {
                    duration: Theme.durBase
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }

            InfoCallout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 28
                anchors.rightMargin: 20
                anchors.topMargin: 10
                glyph: "alert"
                tone: Theme.amber
                title: qsTr("New limits are saved but not applied")
                body: qsTr("Docker picks them up when it restarts.")

                GhostButton {
                    text: qsTr("Restart Docker")
                    implicitHeight: 34
                    onClicked: Docker.restartEngine()
                }
            }
        }

        // ---- Views -------------------------------------------------------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.view

            DockerOverview {
                onOpenView: function (index) { root.view = index; }
            }

            DockerContainers {}

            DockerImages {}

            // The engine's only setting is its size; the engine itself is the person's to update.
            DockerResourcesView {}
        }
    }

    // ---- Toast ---------------------------------------------------------
    Item {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 22
        width: Math.min(root.width - 60, 520)
        height: banner.implicitHeight
        opacity: root.toastText.length > 0 ? 1 : 0
        visible: opacity > 0
        z: 50

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }

        transform: Translate {
            y: root.toastText.length > 0 ? 0 : 10
            Behavior on y {
                NumberAnimation {
                    duration: Theme.duration(Theme.durBase)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }
        }

        AlertBanner {
            id: banner
            width: parent.width
            text: root.toastText
            tone: root.toastTone
        }
    }
}
