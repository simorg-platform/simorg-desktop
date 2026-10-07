// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What Simorg is doing before it can show anybody anything.
 *
 * ## The half second it covers
 *
 * The session is the service's, not this app's. For the moment between the
 * process starting and the service answering, nothing here knows whether this
 * computer has somebody signed in on it. Showing the **sign-in window** in that
 * moment, then replacing it with the dashboard when the answer arrived, would
 * flash a login form past for half a second on every launch of a signed-in
 * machine, which reads as a session that was lost and then found again.
 *
 * So this is what a launch shows instead: the mark, one sentence, and the two
 * things actually being waited for. When the answer comes the window gives way
 * to the dashboard, the sign-in window or the setup wizard, and on an ordinary
 * morning it is on screen for less time than it takes to read.
 *
 * ## And the wait that is not half a second
 *
 * The same wait has a long form, and it is the reason this window is written
 * rather than a splash image: the service can be missing, refused, stopped, or a
 * version this build cannot speak to. None of those should end at a sign-in
 * window, where the only thing to do is type a password into a form that would
 * fail. Here the reason is on the screen in the service client's own
 * words, with the retry that skips the backoff — and nothing pretends to be
 * ready.
 *
 * ## And the one wait this window ends itself
 *
 * A computer with Simorg Desktop and no machine service has nothing for the app
 * to talk to, and the service is what does the work. Somebody who has just
 * installed Simorg Desktop is not told Simorg is missing: the window says it is
 * setting up the Simorg machine service, and does. The setup starts by itself,
 * the only question is the operating system's own password prompt, and the checklist
 * grows a first row for it. A button appears only once something stopped it —
 * the prompt closed, or the setup failed, with what it printed, selectable —
 * and once it is done the session reaches the new service on its own. See
 * `ServiceInstallModel`.
 *
 * ## Frameless, and centred
 *
 * The same shape as the quitting window, which is the other end of the same
 * idea: a small panel that reports, with nothing on it to operate except the one
 * thing worth offering. It is not closable, because closing it would leave an
 * app with no window and nothing said.
 *
 * ## And a way out of it
 *
 * **Quit Simorg** sits beside every *Try again* the window offers, because on a
 * desktop with no tray — a Raspberry Pi — a launch stuck on "Reaching the
 * Simorg machine service" would otherwise have no way out at all. It is the
 * same Quit as everywhere else (`App.quit`): with
 * a connection the service is asked to stop, agents and all; without one the
 * system's service manager is asked to stop the service that never answered, so
 * opening Simorg again starts it afresh. With agents running it asks first, here
 * rather than on a dashboard that has no session behind it yet.
 */
ApplicationWindow {
    id: win

    // Named so the interface tests can tell it from the environment check, which
    // carries the same title.
    objectName: "startingWindow"
    title: qsTr("Simorg")
    width: 420
    // Its usual size, and taller only while it sets the service up.
    height: Math.max(268, body.implicitHeight + 16 + 48)
    flags: Qt.Dialog | Qt.FramelessWindowHint
    color: "transparent"

    // Centred on whichever screen the pointer is on, as the quitting window is.
    x: Screen.virtualX + (Screen.width - width) / 2
    y: Screen.virtualY + (Screen.height - height) / 2

    /** The service answered, so the session is the only thing still unknown. */
    readonly property bool linked: Service.connected

    /**
     * Everything this launch was waiting for is in.
     *
     * The session, and — for somebody signed in — whether this computer owes its
     * owner the setup wizard, which is the last thing that decides which window
     * comes after this one. See `DesktopApplication::surfaceWindow`.
     */
    readonly property bool settled: Auth.known && (!Auth.signedIn || !MachineSetup.undecided)

    /** Nothing here fixes itself; the window stops saying "starting" and says what is wrong. */
    readonly property bool stuck: Service.severe

    /** No machine service on this computer: the one stuck state this window can fix. */
    readonly property bool missing: Service.notInstalled

    /**
     * This window is setting the service up: from the moment it starts until the
     * service answers, and after, so the checklist keeps its first row rather
     * than getting shorter under somebody's eyes.
     */
    readonly property bool settingUp: ServiceInstall.available && (win.missing || ServiceInstall.attempted)

    /** No service, and nothing this app can do about it by itself: a development build, or Linux without pkexec. */
    readonly property bool cannotSetUp: win.missing && !ServiceInstall.available

    /**
     * Quit Simorg would stop agents running here, and it is asked about on this
     * window while this is the one on screen (Main.qml leaves it here).
     */
    readonly property bool askingToQuit: win.visible && App.leaveQuestion === "quit"

    /**
     * Whether the wait has gone on long enough to be worth explaining.
     *
     * A sentence about backoff under a spinner that is about to disappear is
     * noise. After four seconds it is not: something is slower than it should
     * be, and the detail from the last attempt is what a person needs.
     */
    property bool waited: false

    Timer {
        id: patience
        interval: 4000
        onTriggered: win.waited = true
    }

    /**
     * The service was set up and has not answered four seconds on: the same
     * patience, from the moment the setup finished, before Quit is offered beside
     * "Added. Connecting to it now." — the ordinary connection takes a moment,
     * and a button that appeared for it would only flash.
     */
    property bool setUpWaited: false

    Timer {
        interval: 4000
        running: ServiceInstall.succeeded && !win.linked
        onRunningChanged: if (!running) win.setUpWaited = false
        onTriggered: win.setUpWaited = true
    }

    onVisibleChanged: {
        win.waited = false;
        if (visible) {
            patience.restart();
        } else {
            patience.stop();
            // The launch moved on while the question was up: it was about a window that has gone, and the next
            // window's own Quit asks again if it is still wanted.
            if (App.leaveQuestion === "quit")
                App.answerLeave(false);
        }
    }

    GlassPanel {
        anchors.fill: parent
        anchors.margins: 8
        opaque: true

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 24
            spacing: Theme.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // Sized from sourceSize inside a layout, as everywhere else the
                // mark appears; plain width and height would draw it at 180px.
                Image {
                    Layout.alignment: Qt.AlignTop
                    source: "qrc:/simorg/branding/simorg-logo.svg"
                    sourceSize: Qt.size(180, 180)
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    smooth: true
                    mipmap: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        objectName: "startingTitle"
                        Layout.fillWidth: true
                        // The service's own phrase while it is the thing being
                        // waited for, and this window's once it is not. Wrapped
                        // rather than cut: "Setting up the Simorg machine
                        // service" does not fit on one line of this window.
                        text: {
                            if (win.linked)
                                return qsTr("Opening Simorg");
                            if (win.settingUp)
                                return qsTr("Setting up the Simorg machine service");
                            return Service.title;
                        }
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (win.settingUp && !win.linked)
                                return qsTr("Simorg Desktop runs your agents through this small program in the background. It is added to this computer once, and starts by itself after that.");
                            if (win.cannotSetUp)
                                return qsTr("Simorg Desktop runs your agents through the Simorg machine service, a small program in the background.");
                            if (win.stuck)
                                return Service.detail;
                            if (win.linked)
                                return qsTr("Finding out who is signed in on this computer.");
                            return win.waited && Service.detail.length > 0
                                   ? Service.detail
                                   : qsTr("Simorg keeps your agents running in the background. This is the app catching up with it.");
                        }
                        color: win.stuck && !win.missing ? Theme.amber : Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.3
                    }
                }
            }

            /*
              ---- The things being waited for ------------------------------

              The same checklist as the quitting window, and for the same
              reason: operations that can fail separately, all drawn from the
              start, so the window never changes height under somebody's eyes.
              Setting the service up adds a first row, there from the moment
              the setup begins.
            */
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6

                ShutdownStep {
                    objectName: "setUpStep"
                    Layout.fillWidth: true
                    visible: win.settingUp
                    index: 1
                    title: qsTr("Adding the Simorg machine service")
                    running: ServiceInstall.running
                    done: ServiceInstall.succeeded || ServiceInstall.declined || ServiceInstall.failed
                    warned: ServiceInstall.declined || ServiceInstall.failed
                    detail: ServiceInstall.step
                }

                ShutdownStep {
                    Layout.fillWidth: true
                    index: win.settingUp ? 2 : 1
                    title: qsTr("Reaching the Simorg machine service")
                    running: win.settingUp ? ServiceInstall.succeeded && !win.linked : !win.linked && !win.stuck
                    done: win.linked || (!win.settingUp && win.stuck)
                    warned: !win.settingUp && win.stuck && !win.linked
                    detail: {
                        if (win.linked)
                            return qsTr("Connected");
                        // Nothing to reach until it is there, and nothing said about it until then.
                        if (win.settingUp)
                            return ServiceInstall.succeeded ? qsTr("Connecting…") : "";
                        if (win.missing)
                            return qsTr("Not set up");
                        return win.stuck ? qsTr("Not answering") : qsTr("Connecting…");
                    }
                }

                ShutdownStep {
                    Layout.fillWidth: true
                    index: win.settingUp ? 3 : 2
                    title: qsTr("Finding your session")
                    running: win.linked && !win.settled
                    done: win.settled
                    detail: {
                        if (!Auth.known)
                            return "";
                        // Signed in, and the platform has not yet said whether this
                        // computer is one it already knows about.
                        if (!win.settled)
                            return qsTr("Checking this computer…");
                        return Auth.signedIn ? qsTr("Signed in as %1").arg(Auth.user.displayName)
                                             : qsTr("Nobody is signed in here");
                    }
                }
            }

            /*
              The way on, and only when there is one.

              Hidden on the row rather than on each child, so an offer that is
              not being made takes no height at all — a reserved gap under the
              list reads as something missing from the window.
            */
            RowLayout {
                Layout.fillWidth: true
                visible: !win.missing && (win.stuck || (win.waited && !win.settled)) && !win.askingToQuit
                spacing: Theme.spaceSm

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (win.stuck)
                            return qsTr("Simorg cannot run agents on this computer until this is sorted out.");
                        // Connected, and still nothing about the session: the one state a
                        // client cannot talk itself out of, and asking again is what does it.
                        if (win.linked)
                            return qsTr("Simorg is answering but has not said who is signed in here yet.");
                        return qsTr("Still trying. This does not usually take long.");
                    }
                    color: Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                // Quieter than Try again, which is the way on; this is the way out. Once: the setup's panel has its own.
                LinkLabel {
                    objectName: "quitLink"
                    Layout.alignment: Qt.AlignBottom
                    visible: !installPanel.visible
                    text: qsTr("Quit Simorg")
                    tone: Theme.textMuted
                    onActivated: App.quit()
                }

                LinkLabel {
                    Layout.alignment: Qt.AlignBottom
                    text: qsTr("Try again")
                    onActivated: Service.retryNow()
                }
            }

            /*
              Quit Simorg would stop agents running here: asked on this window,
              in the words the dashboard uses, because a dashboard brought out
              for it would have no session behind it yet.
            */
            ColumnLayout {
                objectName: "quitQuestion"
                Layout.fillWidth: true
                visible: win.askingToQuit
                spacing: Theme.spaceSm

                Text {
                    Layout.fillWidth: true
                    text: App.leaveStopsAgents
                          ? qsTr("Quitting Simorg stops all the agents running on this computer, because they run here only while Simorg does. Are you sure you want to continue?")
                          : qsTr("Your machine leaves the platform until Simorg is started again.")
                    color: App.leaveStopsAgents ? Theme.amber : Theme.textMuted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    Item { Layout.fillWidth: true }

                    GhostButton {
                        objectName: "cancelQuit"
                        text: qsTr("Cancel")
                        onClicked: App.answerLeave(false)
                    }

                    PrimaryButton {
                        objectName: "confirmQuit"
                        text: qsTr("Quit")
                        onClicked: App.answerLeave(true)
                    }
                }
            }

            /*
              ---- Setting the machine service up ----------------------------

              In place of the row above while the service is being set up: what
              is happening now, or what stopped it. The buttons appear only
              then, to start it again or to quit; what the installer printed
              appears only when it failed. Where this app cannot set it up at
              all, the reason, on Linux without pkexec the command that does it
              from a terminal, and Quit. Never Quit while the setup runs: the
              installer is this app's child, and would go with it.
            */
            ColumnLayout {
                id: installPanel
                objectName: "serviceInstallPanel"
                Layout.fillWidth: true
                visible: (win.settingUp && !win.linked) || win.cannotSetUp
                spacing: Theme.spaceSm

                Text {
                    Layout.fillWidth: true
                    text: win.cannotSetUp ? ServiceInstall.unavailableReason : ServiceInstall.status
                    color: ServiceInstall.declined || ServiceInstall.failed ? Theme.amber : Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }

                // What the installer printed, selectable, for when it did not finish.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(112, installOutput.implicitHeight + 14)
                    visible: ServiceInstall.failed && ServiceInstall.output.length > 0
                    radius: 8
                    color: Theme.inset
                    border.color: Theme.borderSubtle
                    clip: true

                    Flickable {
                        id: outputScroll
                        anchors.fill: parent
                        anchors.margins: 7
                        contentWidth: width
                        contentHeight: installOutput.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        // Follows the newest line while it arrives.
                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                        SelectableText {
                            id: installOutput
                            width: outputScroll.width
                            text: ServiceInstall.output
                            color: Theme.textMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: 10
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                // The same setup, from a terminal, where this app cannot ask for a password.
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.cannotSetUp && ServiceInstall.terminalCommand.length > 0
                    spacing: Theme.spaceXs

                    SelectableText {
                        Layout.fillWidth: true
                        text: ServiceInstall.terminalCommand
                        color: Theme.textFaint
                        font.family: Theme.monoFamily
                        font.pixelSize: 10
                        wrapMode: Text.WrapAnywhere
                    }

                    CopyAction {
                        text: ServiceInstall.terminalCommand
                        tooltip: qsTr("Copy the install command")
                    }
                }

                // Last, after what there is to read.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: ServiceInstall.declined || ServiceInstall.failed || win.cannotSetUp || win.setUpWaited
                    spacing: Theme.spaceSm

                    PrimaryButton {
                        objectName: "setUpAgainButton"
                        visible: ServiceInstall.declined || ServiceInstall.failed
                        text: qsTr("Try again")
                        onClicked: ServiceInstall.install()
                    }

                    GhostButton {
                        objectName: "quitButton"
                        text: qsTr("Quit Simorg")
                        onClicked: App.quit()
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    /* One pointer, one bubble — see Tip.qml. */
    TipLayer {}
}
