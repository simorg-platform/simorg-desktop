// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Simorg's applications, found on the platform and installed from here.
 *
 * A search box and a grid of what the platform's directory answers — the same
 * search the catalogue page makes, narrowed to applications, as the person
 * signed in here. Each card says what the application is, who publishes it,
 * and whether it is published for **this** computer: an application is one
 * program per operating system, and one with nothing for this one cannot be
 * installed here however much somebody wants it, so its button says so rather
 * than failing after the press.
 *
 * What is already installed says so and offers nothing; what is installing
 * shows how far it has got, on the card that was pressed.
 */
Item {
    id: root

    /** True while this view is on screen; the first search is made then, not at launch. */
    property bool active: root.visible

    onActiveChanged: root.firstSearch()
    Component.onCompleted: root.firstSearch()

    function firstSearch() {
        if (root.active && !ApplicationDirectory.searched && !ApplicationDirectory.searching)
            ApplicationDirectory.search();
    }

    /** The application a button was last pressed for, which is where a refusal is said. */
    property string actedOn: ""

    /** How many cards fit, at a comfortable width of about 320. */
    readonly property int columns: Math.max(1, Math.floor((width - 48 + Theme.spaceMd) / (320 + Theme.spaceMd)))

    /** This computer, in words, from the driver code the service named. */
    readonly property string here: {
        switch (Applications.driverCode) {
        case "BINARY_MAC_APPLE_SILICON": return qsTr("this Mac (Apple silicon)");
        case "BINARY_MAC_X64": return qsTr("this Mac (Intel)");
        case "BINARY_LINUX_ARM": return qsTr("this Linux computer (arm64)");
        case "BINARY_LINUX_X64": return qsTr("this Linux computer (x86-64)");
        case "BINARY_WINDOWS_ARM": return qsTr("this Windows computer (arm64)");
        case "BINARY_WINDOWS_X64": return qsTr("this Windows computer (x86-64)");
        default: return qsTr("this computer");
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 24
                spacing: Theme.spaceMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceMd

                    SimorgTextField {
                        id: box
                        Layout.fillWidth: true
                        Layout.maximumWidth: 560
                        label: qsTr("Search Simorg's applications")
                        glyph: "store"
                        text: ApplicationDirectory.query
                        onTextChanged: ApplicationDirectory.query = box.text
                        onAccepted: ApplicationDirectory.search()
                    }

                    BusyRing {
                        visible: ApplicationDirectory.searching
                        running: ApplicationDirectory.searching
                        size: 18
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: ApplicationDirectory.searched && ApplicationDirectory.error.length === 0
                        text: ApplicationDirectory.total === 1 ? qsTr("1 application")
                                                               : qsTr("%1 applications").arg(ApplicationDirectory.total)
                        color: Theme.textFaint
                        font.pixelSize: 12
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Marked by whether each is published for %1. Installing one puts it on this computer for your account; opening it is up to you.").arg(root.here)
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                InfoCallout {
                    Layout.fillWidth: true
                    visible: ApplicationDirectory.error.length > 0
                    glyph: "alert"
                    tone: Theme.amber
                    title: qsTr("Simorg's directory could not be searched")
                    body: ApplicationDirectory.error
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.columns
                    columnSpacing: Theme.spaceMd
                    rowSpacing: Theme.spaceMd

                    Repeater {
                        model: ApplicationDirectory

                        delegate: GlassPanel {
                            id: card

                            required property string specifier
                            required property string name
                            required property string tagline
                            required property string owner
                            required property string version
                            required property bool verified
                            required property int available
                            required property string platforms

                            /*
                              What this computer already has of it — installed,
                              installing, failed — read from the installed list
                              whenever it moves.
                            */
                            property var mine: ({})
                            function reread() { card.mine = Applications.bySpecifier(card.specifier); }
                            Component.onCompleted: card.reread()
                            Connections {
                                target: Applications
                                function onChanged() { card.reread(); }
                            }

                            readonly property bool installedHere: card.mine.installed === true
                            readonly property string installPhase: card.mine.installState || ""
                            readonly property bool installingHere: card.installPhase.length > 0 && card.installPhase !== "failed"

                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.maximumWidth: 480
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: cardBody.implicitHeight + 32

                            ColumnLayout {
                                id: cardBody
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        implicitWidth: 40
                                        implicitHeight: 40
                                        radius: Theme.radiusLarge
                                        color: Theme.alpha(Theme.sky, 0.1)
                                        border.width: 1
                                        border.color: Theme.alpha(Theme.sky, 0.3)

                                        Glyph {
                                            anchors.centerIn: parent
                                            name: "cube"
                                            size: 18
                                            thickness: 1.6
                                            tone: Theme.sky
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            ElidedText {
                                                Layout.fillWidth: true
                                                Layout.maximumWidth: Math.ceil(implicitWidth)
                                                text: card.name
                                                color: Theme.textPrimary
                                                font.pixelSize: Theme.fontSmall
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Glyph {
                                                visible: card.verified
                                                name: "check-circle"
                                                size: 12
                                                thickness: 1.7
                                                tone: Theme.sky
                                            }

                                            Item { Layout.fillWidth: true }
                                        }

                                        ElidedText {
                                            Layout.fillWidth: true
                                            text: card.owner.length > 0 ? qsTr("by %1").arg(card.owner) : card.specifier
                                            color: Theme.textFaint
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                ElidedText {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    text: card.tagline.length > 0 ? card.tagline : qsTr("No tagline yet.")
                                    color: card.tagline.length > 0 ? Theme.textMuted : Theme.alpha(Theme.textMuted, 0.55)
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignTop
                                }

                                SelectableText {
                                    Layout.fillWidth: true
                                    text: card.version.length > 0 ? card.specifier + ":" + card.version : card.specifier
                                    color: Theme.textFaint
                                    font.pixelSize: 10
                                    font.family: Theme.monoFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Theme.borderSubtle
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Glyph {
                                        name: card.available === 1 ? "check" : card.available === 0 ? "close" : "info"
                                        size: 12
                                        thickness: 1.7
                                        tone: card.available === 1 ? Theme.emerald
                                            : card.available === 0 ? Theme.textFaint : Theme.textMuted
                                    }

                                    ElidedText {
                                        Layout.fillWidth: true
                                        text: card.available === 1 ? qsTr("Published for %1").arg(root.here)
                                            : card.available === 0
                                              ? (card.platforms.length > 0 ? qsTr("Only for %1").arg(card.platforms)
                                                                          : qsTr("Not published for %1").arg(root.here))
                                            : qsTr("Its platforms are not listed")
                                        color: card.available === 1 ? Theme.textBody : Theme.textFaint
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }

                                    BusyRing {
                                        visible: card.installingHere
                                        running: card.installingHere
                                        size: 16
                                    }

                                    PrimaryButton {
                                        visible: !card.installedHere
                                        enabled: card.available !== 0 && !card.installingHere
                                        text: card.installingHere ? qsTr("Installing…")
                                            : card.installPhase === "failed" ? qsTr("Try again")
                                            : qsTr("Install")
                                        implicitHeight: 30
                                        onClicked: {
                                            root.actedOn = card.specifier;
                                            Applications.install(card.specifier);
                                        }
                                    }

                                    // As tall as the button it stands in for, so every card is one height.
                                    Text {
                                        visible: card.installedHere
                                        Layout.preferredHeight: 30
                                        verticalAlignment: Text.AlignVCenter
                                        text: qsTr("Installed")
                                        color: Theme.emerald
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // Why it did not install, on the card that was pressed.
                                SelectableText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: card.installPhase === "failed" ? (card.mine.installProblem || "")
                                        : root.actedOn === card.specifier ? Applications.lastError : ""
                                    color: Theme.rose
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                ComingSoon {
                    Layout.fillWidth: true
                    visible: ApplicationDirectory.searched && !ApplicationDirectory.searching
                             && ApplicationDirectory.count === 0 && ApplicationDirectory.error.length === 0
                    glyph: "store"
                    tone: Theme.sky
                    title: ApplicationDirectory.query.trim().length > 0
                           ? qsTr("No application matches “%1”").arg(ApplicationDirectory.query.trim())
                           : qsTr("No applications are published yet")
                    body: qsTr("Applications are published on Simorg like any other artifact, one program per operating system. When one is published that you can see, it appears here.")
                    points: []
                }
            }
        }
    }
}
