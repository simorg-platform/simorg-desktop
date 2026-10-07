// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Setting this computer up, the first time somebody signs in on it.
 *
 * ## Where it sits
 *
 * Third of four windows, and the order is the order of what has to be true:
 * the environment check, the sign-in window, **this**, and then the dashboard.
 * It appears only on a machine that owes it — see {@link MachineSetupModel} —
 * so on every morning after the first nobody sees it.
 *
 * ## Why it is a window and not a card on the dashboard
 *
 * Because until the naming step is done, the platform does not list this
 * machine at all. A dashboard shown first would be a dashboard for a computer
 * that, as far as the rest of the account is concerned, is not there: absent
 * from the machine list, unassignable to any agent, with nothing on the screen
 * explaining why. One question at a time, in the order the answers are needed,
 * is the honest arrangement.
 *
 * ## Closing it is allowed
 *
 * Every window in this application can be closed and this one is no exception:
 * the app carries on behind its tray icon, and the wizard comes back the next
 * time a window opens, on the step it stopped at — the platform remembers where
 * that was, so a laptop that was shut mid-wizard picks up rather than restarts.
 * What somebody loses by closing it is the machine being listed, which the
 * welcome screen says out loud rather than trapping them here to prevent.
 */
ApplicationWindow {
    id: win

    title: qsTr("Simorg")
    width: 860
    /*
      Tall enough for the naming step, which is the longest: three fields, a
      seven-line readme box, the gap above and below, and the bar under them.
      Measured rather than guessed — see the interface test, which asserts the
      three steps against this window.

      The old 780 was 90px short of that, and the shortfall landed on the
      welcome screen as a callout cut off by the footer.
    */
    height: 880
    minimumWidth: 620
    /*
      And a floor well under it, because a window that will not fit on a small
      display is worse than one that scrolls: below this the step scrolls, with
      the same gap under it that it has above.
    */
    minimumHeight: 640
    color: Theme.base

    /**
     * Which screen is on show. 0 welcome, 1 name, 2 Docker.
     *
     * Kept here rather than read straight off `MachineSetup.step`, for one
     * reason: **Back**. The platform records the furthest step this machine has
     * reached and is right to — somebody who walks back to fix a typo has not
     * un-named their machine — so where the wizard *reopens* is the platform's
     * answer, and where it is *right now* is this window's.
     */
    property int page: 0

    /**
     * The gap above the step and the gap below it, which are the same gap.
     *
     * Said once because it is used twice: a step that begins 32px under the
     * progress markers and then ends flush against the footer reads as content
     * that has been cut off rather than content that has finished.
     */
    readonly property int pageGap: 32

    /**
     * The step on screen, which is the one the scrolling area is sized from.
     *
     * A StackLayout keeps all three pages alive and its own implicit height is
     * the tallest of them, so a scroll area measured from the layout would give
     * the welcome screen a page of nothing underneath it to scroll through.
     * What the area has to be as tall as is what is being shown.
     */
    readonly property Item currentStep: win.page === 1
                                        ? identityStep
                                        : win.page === 2 ? runtimeStep : welcomeStep

    /** The platform's answer, whenever it moves. */
    function syncFromPlatform() {
        if (MachineSetup.step === SetupState.Identity)
            win.page = 1;
        else if (MachineSetup.step === SetupState.Runtime)
            win.page = 2;
        else if (MachineSetup.step === SetupState.Welcome)
            win.page = 0;
    }

    Connections {
        target: MachineSetup
        function onStateChanged() { win.syncFromPlatform(); }
    }

    Component.onCompleted: win.syncFromPlatform()
    // A window reopened from the tray picks up where the platform says, rather
    // than wherever it happened to be when it was last closed.
    onVisibleChanged: if (visible) win.syncFromPlatform()

    /*
      Closing is not quitting, exactly as on every other window: the app carries
      on behind the tray icon and this comes back with it. Where there is no
      tray, closing has to mean what it says, and it is Quit Simorg, which asks
      first if agents are running: the window going on its own would leave the
      app running with nothing on screen and nothing to reach it by.
    */
    onClosing: function (close) {
        close.accepted = false;
        if (App.trayAvailable)
            App.hideToTray();
        else
            App.quit();
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Where you are, of three -------------------------------------
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            spacing: Theme.spaceSm

            Repeater {
                model: [qsTr("Welcome"), qsTr("Name"), qsTr("Docker")]

                delegate: RowLayout {
                    id: marker
                    required property string modelData
                    required property int index
                    spacing: Theme.spaceSm

                    /*
                      Passed, current, or still to come. Three states rather
                      than two, because "done" and "not yet" look identical when
                      only the current one is marked, and somebody on the second
                      screen wants to know there is a third.
                    */
                    readonly property bool passed: win.page > marker.index
                    readonly property bool active: win.page === marker.index

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: marker.passed
                               ? Theme.alpha(Theme.emerald, 0.18)
                               : marker.active
                                 ? Theme.alpha(Theme.blue, 0.22)
                                 : Theme.alpha(Theme.base, 0.5)
                        border.width: 1
                        border.color: marker.passed
                                      ? Theme.alpha(Theme.emerald, 0.5)
                                      : marker.active
                                        ? Theme.alpha(Theme.blue, 0.7)
                                        : Theme.borderSubtle

                        Glyph {
                            anchors.centerIn: parent
                            visible: marker.passed
                            name: "check"
                            size: 14
                            thickness: 2
                            tone: Theme.emerald
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !marker.passed
                            text: String(marker.index + 1)
                            color: marker.active ? Theme.textPrimary : Theme.textFaint
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        text: marker.modelData
                        color: marker.active
                               ? Theme.textPrimary
                               : marker.passed ? Theme.textMuted : Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        font.weight: marker.active ? Font.DemiBold : Font.Normal
                    }

                    // The rule between two markers. Never after the last one,
                    // which would be a line pointing at nothing.
                    Rectangle {
                        visible: marker.index < 2
                        Layout.leftMargin: 2
                        Layout.rightMargin: 2
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 1
                        color: Theme.borderSubtle
                    }
                }
            }
        }

        // ---- The step itself ---------------------------------------------
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            Item {
                width: win.width
                /*
                  As tall as the step, plus the same gap above it and below it.

                  Every term here has to be present. The steps are Items holding
                  an anchored column, so each one is asked for the height of that
                  column — without it the page measures zero, the area is not
                  scrollable at all, and the bottom of a long step is simply cut
                  off by the footer with no way to reach it.
                */
                implicitHeight: win.pageGap + pages.height + win.pageGap

                StackLayout {
                    id: pages
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: win.pageGap
                    width: Math.min(win.width - 72, 620)
                    height: win.currentStep ? win.currentStep.implicitHeight : 0
                    currentIndex: win.page

                    SetupWelcomeStep { id: welcomeStep }
                    SetupIdentityStep { id: identityStep }
                    SetupRuntimeStep { id: runtimeStep }
                }
            }
        }

        // ---- What to do about it -----------------------------------------
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: footer.implicitHeight + 36
            color: Theme.alpha(Theme.base, 0.55)

            // A hairline above the bar, so the buttons read as a footer rather
            // than as the last thing in the scrolling content.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                id: footer
                anchors.centerIn: parent
                width: Math.min(win.width - 72, 620)
                spacing: Theme.spaceSm

                Text {
                    Layout.fillWidth: true
                    /*
                      The consequence, said on every screen until it stops being
                      true. Somebody who reads nothing else on this window should
                      still know why it is worth finishing.
                    */
                    text: MachineSetup.listed
                          ? qsTr("This computer is on your account as %1.")
                                .arg(MachineSetup.title)
                          : qsTr("This computer is not on your account until you name it.")
                    color: MachineSetup.listed ? Theme.textFaint : Theme.amber
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }

                GhostButton {
                    visible: win.page === 1
                    text: qsTr("Back")
                    enabled: !MachineSetup.busy
                    onClicked: win.page = 0
                }

                PrimaryButton {
                    text: {
                        if (win.page === 0)
                            return qsTr("Get started");
                        if (win.page === 1)
                            return qsTr("Save and continue");
                        return runtimeStep.ready
                               ? qsTr("Finish setup")
                               : qsTr("Finish anyway");
                    }
                    enabled: !MachineSetup.busy && (win.page !== 1 || identityStep.valid)
                    onClicked: {
                        if (win.page === 0) {
                            MachineSetup.completeWelcome();
                            return;
                        }
                        if (win.page === 1) {
                            identityStep.submit();
                            return;
                        }
                        runtimeStep.submit();
                    }
                }
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
