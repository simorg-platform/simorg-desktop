// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The first window, and on most mornings a window nobody sees.
 *
 * ## What it is for
 *
 * Simorg runs agents inside containers, which means it needs three things from
 * the computer it is installed on: a connection, a Docker Engine, and the image
 * an agent runs in. None of those has anything to do with having an account,
 * and all three are knowable in the first second. This asks, before the sign-in
 * window, and says what it found.
 *
 * The other order would have somebody sign in, land on a dashboard, open
 * **Docker** because it was there, and only then discover that the one thing
 * this application exists to do could not happen on their machine. So finding
 * out is here, and the Docker tab shows what Docker is doing rather than how
 * to get it.
 *
 * ## Two screens, one window
 *
 * The checklist is the window. The other is the explanation of what Docker is,
 * shown here because this is where somebody meets it. Installing Docker is the
 * person's to do, so neither screen installs anything: both say it is missing
 * and link Docker's own page.
 *
 * ## It can always be put away
 *
 * "Continue anyway" is offered whenever something needs attention, and it is
 * deliberate. This application is not only a container host: agents can be
 * read, logs looked at, settings changed. A check that could not be dismissed
 * would be a computer somebody cannot use because of something they mean to fix
 * this evening.
 */
ApplicationWindow {
    id: win

    title: qsTr("Simorg")
    width: 840
    height: 700
    minimumWidth: 560
    /*
      Tall enough for the three steps, the heading above them and the buttons
      below. Measured at the widest wording each step can carry, because a
      minimum smaller than the content is not a minimum.
    */
    minimumHeight: 620
    color: Theme.base

    /**
     * The one thing worth offering, decided by the check rather than here.
     *
     * Not worked out here from `Docker.status`: two places deciding the same
     * thing is two places that can disagree — a line of text saying Docker is
     * not installed above a button offering to start it. `PreflightModel::remedy`
     * is the only answer, and the sentence beside the button comes from the
     * same step.
     */
    readonly property string remedy: Preflight.remedy

    /** 0 the checklist, 1 what Docker is. */
    property int page: 0

    /** With no Docker here, the graphics panel names the Docker that would lend the card, and how to install it. */
    readonly property bool graphicsAdvice: win.remedy === "manual" && Preflight.graphics.state === "configurable"
                                           && ((Preflight.graphics.commands || []).length > 0
                                               || typeof Preflight.graphics.guide === "string")

    onVisibleChanged: if (visible) win.page = 0

    // Closing is not quitting, exactly as it is not on the sign-in window: the
    // app carries on behind the tray icon. With no tray to fall back to,
    // closing has to mean what it says, and it is Quit Simorg, as there.
    onClosing: function (close) {
        close.accepted = false;
        if (!App.trayAvailable) {
            App.quit();
            return;
        }
        /*
          Put away, not merely hidden.

          Closing this window is somebody saying they have read it, so the
          check stops holding the screen — otherwise the next thing that
          surfaces a window would bring this one straight back, and a window
          that reopens when you close it is a window people force-quit.
        */
        Preflight.dismiss();
        App.hideToTray();
    }

    background: Rectangle { color: Theme.base }

    AuroraBackground {
        anchors.fill: parent
    }

    // A build pointed at localhost should never be mistaken for the real thing.
    Rectangle {
        visible: App.devMode
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width: devLabel.implicitWidth + 20
        height: 24
        radius: 5
        color: Theme.alpha(Theme.amber, 0.12)
        border.width: 1
        border.color: Theme.alpha(Theme.amber, 0.45)
        z: 10

        Text {
            id: devLabel
            anchors.centerIn: parent
            text: qsTr("DEV · %1").arg(App.apiEndpoint.replace(/^https?:\/\//, ""))
            color: Theme.amber
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: win.page

        // ---- 0. The checklist ------------------------------------------
        Item {
            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: win.width
                    spacing: 0

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 620
                        Layout.fillWidth: true
                        Layout.margins: 36
                        spacing: Theme.spaceLg

                        // ---- Heading -------------------------------
                        Reveal {
                            step: 0
                            Layout.fillWidth: true

                            ColumnLayout {
                                width: parent.width
                                spacing: Theme.spaceSm

                                PulseHex {
                                    Layout.alignment: Qt.AlignHCenter
                                    size: 96
                                }

                                GradientText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    text: Preflight.ready
                                          ? qsTr("This computer is ready")
                                          : Preflight.needsAttention
                                            ? qsTr("One thing to sort out first")
                                            : qsTr("Getting this computer ready")
                                    pixelSize: 26
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    Layout.fillWidth: true
                                    /*
                                      The last line claims work only while there
                                      is work. A check can settle with a step
                                      still waiting — which image this computer
                                      needs is named at sign-in
 — and "Simorg is
                                      checking" under three motionless rows is
                                      the sentence that teaches somebody this
                                      window is decoration.
                                    */
                                    text: Preflight.ready
                                          ? qsTr("Everything an agent needs is in place here.")
                                          : Preflight.needsAttention
                                            ? qsTr("Agents run inside containers on your own machine. This one is missing something they need.")
                                            : Preflight.running
                                              ? qsTr("Agents run inside containers on your own machine. Simorg is checking that this one has what that takes.")
                                              : qsTr("Agents run inside containers on your own machine. Simorg has checked everything it can from here.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.5
                                }
                            }
                        }

                        // ---- The three checks ----------------------
                        Reveal {
                            step: 1
                            Layout.fillWidth: true

                            GlassPanel {
                                width: parent.width
                                implicitHeight: checks.implicitHeight + 44
                                accent: Preflight.needsAttention ? Theme.amber : Theme.blue

                                ColumnLayout {
                                    id: checks
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 22
                                    spacing: Theme.spaceMd

                                    Repeater {
                                        // The rows themselves, so a step that
                                        // changes is the same row with new
                                        // values rather than a new row.
                                        model: Preflight.stepList

                                        delegate: PreflightStepRow {
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }

                        /*
                          No Docker here: the person installs one of their
                          choosing, and the next check finds it
.
                        */
                        Reveal {
                            step: 2
                            Layout.fillWidth: true
                            visible: win.remedy === "manual"

                            GetDockerCard {
                                width: parent.width
                                graphicsBelow: win.graphicsAdvice
                            }
                        }

                        /*
                          The graphics card: available, what would make it so
                          with the exact commands, or why this computer cannot
. Beside the checks and never
                          one of them — an agent runs without a card — and here
                          because a computer being set up is when choosing a
                          Docker that lends one costs nothing.
                        */
                        Reveal {
                            step: 2
                            Layout.fillWidth: true
                            visible: graphicsPanel.known

                            GpuOfferPanel {
                                id: graphicsPanel
                                width: parent.width
                                offer: Preflight.graphics
                            }
                        }

                        // ---- What is being downloaded, and from where ----
                        Reveal {
                            step: 2
                            Layout.fillWidth: true
                            /*
                              Bound to the step rather than to the fetcher.

                              They say the same thing on a real machine, and
                              only the step says it in a rendered scenario —
                              which is the difference between this panel being
                              checked by the interface test and being seen for
                              the first time by somebody on a slow connection.
                            */
                            visible: win.remedy === "cancel"

                            InfoCallout {
                                width: parent.width
                                glyph: "download"
                                tone: Theme.sky
                                title: Preflight.fetchDetail.length > 0
                                       ? qsTr("Downloading, %1").arg(Preflight.fetchDetail)
                                       : qsTr("Downloading")
                                // Named only when the service says where from: "from , and kept" is what
                                // a registry nobody has named reads as.
                                body: Preflight.registry.length > 0
                                      ? qsTr("This is the sealed box your agents run inside. It is fetched once, from %1, and kept by Docker afterwards. You can carry on using Simorg while it finishes.").arg(Preflight.registry)
                                      : qsTr("This is the sealed box your agents run inside. It is fetched once and kept by Docker afterwards. You can carry on using Simorg while it finishes.")
                            }
                        }

                        /*
                          The image is not published for this computer: most
                          often a release built for one architecture only, an
                          arm64 image on an Intel or AMD computer's Docker.
                          Downloading again would be refused the same way,
                          and there is nothing on this computer to change, so
                          this says so rather than offering the download.
                        */
                        Reveal {
                            step: 2
                            Layout.fillWidth: true
                            visible: Preflight.imageUnavailable

                            InfoCallout {
                                objectName: "imageUnavailableCallout"
                                width: parent.width
                                glyph: "cube"
                                tone: Theme.amber
                                title: Preflight.problemTitle.length > 0
                                       ? Preflight.problemTitle
                                       : qsTr("The agent image is not published for this computer yet")
                                body: qsTr("Downloading it again would be refused the same way, and nothing on this computer needs to change. Agents start here as soon as Simorg publishes the image for it; Check again looks for it.")
                            }
                        }

                        // ---- What to do about it -------------------
                        Reveal {
                            step: 3
                            Layout.fillWidth: true

                            ColumnLayout {
                                width: parent.width
                                spacing: Theme.spaceSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spaceSm

                                    /*
                                      One primary action, and which one depends
                                      on what is actually wrong.

                                      A row of four buttons, three of them
                                      pointless on any given machine, is how a
                                      screen stops being read. Getting Docker is
                                      not in this row: it is the person's to
                                      install, and the card above says how.
                                    */
                                    PrimaryButton {
                                        visible: win.remedy === "start"
                                        text: qsTr("Start Docker")
                                        onClicked: Docker.startEngine()
                                    }

                                    PrimaryButton {
                                        objectName: "downloadButton"
                                        visible: win.remedy === "fetch" && !Preflight.imageUnavailable
                                        text: qsTr("Download it now")
                                        onClicked: Preflight.fetchMissingImages()
                                    }

                                    // The one thing that can help when the image is not published here.
                                    PrimaryButton {
                                        objectName: "checkAgainPrimary"
                                        visible: Preflight.imageUnavailable
                                        text: qsTr("Check again")
                                        onClicked: Preflight.run()
                                    }

                                    /*
                                      Offered for a check that has finished with
                                      nothing to decide, which is not only a
                                      check where everything passed.

                                      A computer that has not heard which image
                                      it needs cannot check for one
: that step waits
                                      for an answer that arrives on its own
                                      rather than failing, so there is no
                                      "Continue anyway" and, when this read
                                      `Preflight.ready`, there was no button at
                                      all — a first-run window holding the
                                      screen with no way past it.
                                    */
                                    PrimaryButton {
                                        visible: Preflight.ready
                                                 || (!Preflight.needsAttention && !Preflight.running)
                                        text: qsTr("Continue")
                                        onClicked: Preflight.dismiss()
                                    }

                                    // Offered while Docker is missing: somebody
                                    // asked to install software they have never
                                    // heard of deserves to know what it is for.
                                    GhostButton {
                                        visible: win.remedy === "manual"
                                        text: qsTr("What is Docker?")
                                        onClicked: win.page = 1
                                    }

                                    GhostButton {
                                        visible: win.remedy === "cancel"
                                        text: qsTr("Cancel the download")
                                        onClicked: Preflight.cancelFetch()
                                    }

                                    GhostButton {
                                        visible: Preflight.needsAttention && win.remedy !== "cancel"
                                                 && !Preflight.imageUnavailable
                                        text: qsTr("Check again")
                                        onClicked: Preflight.run()
                                    }

                                    Item { Layout.fillWidth: true }

                                    GhostButton {
                                        visible: Preflight.needsAttention
                                        text: qsTr("Continue anyway")
                                        onClicked: Preflight.dismiss()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: Preflight.needsAttention
                                    text: qsTr("You can sign in and look around without this. Agents placed on this computer will not start until it is sorted.")
                                    color: Theme.textFaint
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.45
                                }

                            }
                        }

                        /*
                          The version line, at the end of the column rather than
                          anchored to the bottom of the window.

                          Anchored, it was drawn straight through the buttons
                          whenever the content was taller than the window —
                          which on the state with the most to say is every time.
                          GPLv3 does not require a notice in the interface;
                          §5(d) only obliges a modified version to keep showing
                          one where the original already does.
                        */
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            text: qsTr("Simorg %1 · GPL-3.0").arg(App.version)
                            color: Theme.alpha(Theme.textMuted, 0.5)
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        // ---- 1. What Docker is, and how to get it ----------------------
        Item {
            DockerIntro {
                anchors.fill: parent
            }

            GhostButton {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 20
                text: qsTr("Back")
                onClicked: win.page = 0
            }
        }
    }


    /*
      The one tooltip this window can show, in its overlay so it is above
      everything and clipped by nothing. Declared here rather than beside each
      elided label: there is one pointer, so there is one bubble. See `Tip.qml`.
    */
    TipLayer {}
}
