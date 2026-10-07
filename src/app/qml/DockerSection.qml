// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * The Docker section, and the one decision it makes.
 *
 * Which of four things somebody sees here depends entirely on the state of
 * their machine, and getting that decision wrong is the difference between a
 * useful panel and an insulting one: telling a developer with Docker running to
 * install it, or telling somebody who has never heard of containers that a
 * daemon socket is unreachable. So the routing is explicit and each destination
 * is a whole screen written for the person who lands on it.
 *
 * ## Getting Docker does not live here
 *
 * The introduction to what Docker is lives in `PreflightWindow`, which runs
 * before anybody signs in: whether this computer can run a container is a fact
 * about the computer, found out before anybody hands over a password. Nothing
 * in Simorg installs Docker; a computer without it gets `DockerMissing`, which
 * links Docker's own page. What is left here is what this tab is for, which is
 * Docker as it is on this machine right now.
 *
 * Polling is bound to this item being visible. Docker's engine is asked for a
 * container list every two and a half seconds while somebody is looking at one,
 * and not at all otherwise.
 */
Item {
    id: root

    // The section is a page in a StackLayout, so `visible` is exactly "the
    // Docker tab is the open tab".
    onVisibleChanged: Docker.setActive(visible)
    Component.onCompleted: if (visible) Docker.setActive(true)

    readonly property int page: {
        if (Docker.status === DockerStatus.Ready) return 0;
        if (Docker.status === DockerStatus.Unreachable) return 3;
        if (Docker.status === DockerStatus.NotInstalled) return 1;
        return 2; // NotRunning, Starting, Unknown
    }

    /**
     * Opens the resource sliders, from anywhere in the app.
     *
     * The This Machine page divides what Docker has, so the only lever that
     * changes its numbers is here — and a link that dropped somebody on the
     * Docker overview to hunt for it would be a link that made them work.
     *
     * Silent when the engine is not running: there is nothing to configure, and
     * the section is already showing the reason.
     */
    function showResources() {
        console_.showResources();
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: root.page

        DockerConsole { id: console_ }

        DockerMissing {}

        DockerStopped {}

        // Unreachable: a DOCKER_HOST this client will not drive. Rare, and the
        // people who hit it are exactly the people who will understand why.
        Item {
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 560)
                spacing: Theme.spaceMd

                InfoCallout {
                    Layout.fillWidth: true
                    glyph: "alert"
                    tone: Theme.amber
                    title: qsTr("Simorg is not driving this Docker endpoint")
                    body: Docker.detail
                }

                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: 74

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4

                        Text {
                            text: qsTr("ENDPOINT")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        ElidedText {
                            Layout.fillWidth: true
                            text: Docker.endpoint
                            color: Theme.textBody
                            font.family: Theme.monoFamily
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Unset DOCKER_HOST, or point it at a local socket, and Simorg will pick it up on the next check.")
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }
        }
    }
}
