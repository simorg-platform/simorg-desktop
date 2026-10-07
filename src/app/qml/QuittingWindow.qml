// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What Simorg is doing while it quits.
 *
 * ## Why a window at all
 *
 * Quitting takes as long as the agents take to finish and their containers take
 * to stop — a second or two each, and this machine may be running four. That
 * wait is real and cannot be removed.
 *
 * What can be removed is the **silence**: no window, no icon change, nothing in
 * the menu bar, for however long it takes. There is no way to tell a clean shutdown from a hang by
 * looking at nothing, and the reasonable response to a hang — force quit — is
 * the one action that leaves every container running.
 *
 * ## Why it is a list of two and not one line
 *
 * Because two genuinely different things happen, they can fail separately, and
 * only one of them risks anybody's work.
 *
 * ```
 *   1. Stopping your agents      over Simorg, so each finishes what it was
 *                                doing and flushes what it was holding
 *   2. Stopping containers       Docker, locally
 * ```
 *
 * Collapsing them into one bar would hide the distinction that matters. If
 * somebody presses *Force Quit!*, what they skip is the first step — the one
 * whose whole purpose is that nothing in progress is lost — and a person about
 * to press it deserves to see which of the two they are cutting short.
 *
 * The completed step keeps its tick and its count rather than disappearing,
 * because "the agents are done" is the reassurance somebody wanted, and taking
 * it off the screen the moment it becomes true is taking away the answer.
 *
 * ## What it says, and what it does not
 *
 * It reports. It does not ask: somebody who chose Quit has already decided, and
 * a confirmation here would be a dialog that exists to be dismissed.
 *
 * There is no **Cancel**, because "cancel" would mean starting things again — a
 * different operation with its own failures. What there is instead is **Quit
 * anyway**, which stops *waiting* rather than stopping the shutdown, and it
 * appears only after the wait has gone on long enough to be worth escaping. It
 * says plainly what it leaves behind, and during step one it says so in the
 * strongest terms the window uses anywhere, because that is the press that can
 * actually cost somebody something.
 *
 * ## Frameless, on top, and not closable
 *
 * No title bar: there is nothing to do to this window except read it. Closing
 * it would either do nothing or abandon the shutdown, and neither is a button
 * worth drawing — which is why the close affordance is absent rather than
 * disabled.
 */
ApplicationWindow {
    id: win

    /*
      Bound to the run rather than shown by whoever starts one.

      A run can start from this app, from a terminal, or from the operating
      system ending the session,
      and a window that had to be opened by each of them is a window that one of
      them would never open.

      `App.quitting` is the other half of it, and it comes first: choosing Quit
      asks the service over a socket, and until that request is answered there is
      no run to bind to. On a service that is busy or gone those seconds used to
      show the dashboard, unchanged, with nothing anywhere saying the application
      was leaving.
    */
    visible: (Shutdown.active || App.quitting) && !win.dismissed

    /**
     * A run that is over and was not this app's own way out.
     *
     * The app that asked to quit goes with the run — the window and the process
     * end together, which is the whole ceremony. Anybody else is left holding a
     * window with a tick in it and nothing more to say, so it says its piece for
     * a few seconds and puts itself away rather than sitting there until the
     * next launch.
     */
    property bool dismissed: false

    /**
     * Brings it to the front, and keeps it there.
     *
     * Quit is usually chosen from the tray, and a tray menu does not make the
     * application active — so without this the window that explains the wait can
     * open behind whatever the person is actually looking at, which is the same
     * as not opening at all. It is raised again on every frame of the run and
     * asks for the keyboard when the step changes: enough to stay in front,
     * without snatching focus once a second for a clock that is ticking down.
     */
    function surface(takeFocus) {
        win.raise();
        if (takeFocus)
            win.requestActivate();
    }

    onVisibleChanged: if (visible) win.surface(true)
    onPhaseChanged: if (win.visible) win.surface(true)

    Connections {
        target: Shutdown

        function onChanged() {
            if (!Shutdown.complete) {
                win.dismissed = false;
                linger.stop();
            } else if (!Shutdown.askedHere && !App.quitting) {
                linger.restart();
            }
            if (win.visible)
                win.surface(false);
        }
    }

    Timer {
        id: linger
        interval: 5000
        onTriggered: win.dismissed = true
    }

    width: 440
    // Sized to the content rather than to a round number: two steps, a bar and
    // a footer, and the space left over read as a window waiting for something
    // else to appear in it.
    height: 288
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    // Centred on whichever screen the pointer is on, which on a laptop with an
    // external display is the one the person is looking at.
    x: Screen.virtualX + (Screen.width - width) / 2
    y: Screen.virtualY + (Screen.height - height) / 2

    /** Mirrors `ShutdownCoordinator::Phase`; read straight off the int. */
    readonly property int phaseAgents: 1
    readonly property int phaseContainers: 2

    /** The step the run is on, watched so the window can come forward when it moves. */
    readonly property int phase: Shutdown.phase

    readonly property bool onAgents: Shutdown.phase === win.phaseAgents
    /** True once step one is behind us, whether it went well or not. */
    readonly property bool agentsDone: Shutdown.agentsSettled
    /** Somebody cut the graceful part short, or the platform ran out of time. */
    readonly property bool agentsCutShort: Shutdown.agentsInterrupted > 0

    /**
     * How long the agents were given, in words rather than digits.
     *
     * "2 minutes", not "120 seconds". The clock beside step one is the precise
     * reading; this is the sentence that explains what the clock is *for*, and a
     * sentence with a raw second count in it makes somebody do arithmetic to
     * work out whether they can wait.
     *
     * Rounded, deliberately. An operator can configure ninety seconds, and "about
     * 2 minutes" is the honest thing to tell a person who is deciding whether to
     * stand there — the exact figure is on the clock a line above.
     */
    readonly property string budgetPhrase: {
        const seconds = Shutdown.graceSeconds
        if (seconds <= 0)
            return ""
        if (seconds < 60)
            return qsTr("%1 seconds").arg(seconds)
        const minutes = Math.round(seconds / 60)
        return minutes === 1 ? qsTr("a minute") : qsTr("%1 minutes").arg(minutes)
    }

    /**
     * Whether waiting has gone on long enough to offer a way out of it.
     *
     * The service's answer, not a clock of this window's: Force is offered 20
     * seconds after the stop was asked for, to every app
     * at the same moment. Hidden until then on purpose: the agents get a real
     * chance to finish, and taking the escape during step one is what loses work.
     */
    readonly property bool waitedLongEnough: Shutdown.forceAvailable

    /** Another app on this computer asked for this stop, which is worth saying: nobody here pressed Quit. */
    readonly property bool askedElsewhere: Shutdown.requestedBy.length > 0 && !Shutdown.askedHere

    /*
      What to say before the service has said anything.

      The run's own words whenever there is a run. Between pressing Quit and the
      first frame arriving there is none, and this window is on screen for that
      whole gap — so it says what it does know, which is that Simorg was asked to
      stop, rather than showing an empty panel with a spinner in it.
    */
    readonly property string headline: Shutdown.headline.length > 0 ? Shutdown.headline
                                                                    : qsTr("Quitting Simorg")
    readonly property string detail: Shutdown.detail.length > 0
                                     ? Shutdown.detail
                                     : qsTr("Asking Simorg to stop your agents and the containers they run in.")
    /** Nothing has been counted yet, so the bar sweeps rather than sitting at nothing. */
    readonly property bool indeterminate: !Shutdown.active || Shutdown.indeterminate

    GlassPanel {
        anchors.fill: parent
        anchors.margins: 8
        opaque: true

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 24
            spacing: Theme.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                /*
                  A spinner while there is waiting left, a tick when there is
                  not. The swap is the clearest signal in the window that the
                  thing being waited for has actually happened.
                */
                BusyRing {
                    // Pinned to the title line rather than centred on the
                    // block: the detail wraps to three lines on the endings
                    // worth reading, and a marker that drifted down beside them
                    // would stop pointing at the thing it marks.
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    visible: !Shutdown.complete
                    size: 20
                    tone: Theme.cyan
                }

                Glyph {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    visible: Shutdown.complete
                    // An alert rather than a tick when something was cut short.
                    // A green tick over an interrupted shutdown would be the
                    // window telling somebody their work is safe when it is not.
                    name: win.agentsCutShort ? "alert" : "check-circle"
                    size: 20
                    thickness: 1.8
                    tone: win.agentsCutShort ? Theme.amber : Theme.emerald
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    ElidedText {
                        Layout.fillWidth: true
                        text: win.headline
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: win.detail
                        color: Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: win.askedElsewhere
                        text: qsTr("Asked for by %1.").arg(Shutdown.requestedBy)
                        color: Theme.textFaint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    /*
                      What is actually happening, for somebody who has never seen
                      this window before.

                      The line above says *how far through*; this says *why there
                      is a wait at all*, and it is the difference between a person
                      who waits and one who force-quits. Three facts, in the order
                      somebody needs them: the agents have been told, they have a
                      known amount of time, and they stop early when they can.

                      Only during step one. Stopping containers needs no
                      explanation — it is the part everybody already expects from
                      quitting an application.
                    */
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: win.onAgents && win.budgetPhrase !== ""
                        text: qsTr("Your agents know this computer is closing and have %1 to save "
                                   + "their work. Most finish sooner; the rest are stopped when the "
                                   + "time runs out.").arg(win.budgetPhrase)
                        color: Theme.textFaint
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        lineHeight: 1.25
                    }
                }
            }

            /*
              ---- The two steps ---------------------------------------------

              Both are always drawn, from the first frame. A list that grew as it
              went would keep changing height under somebody's eyes and would
              never let them see how much was left — which is most of what a
              person wants from a progress display they cannot influence.
            */
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6

                ShutdownStep {
                    Layout.fillWidth: true
                    index: 1
                    title: qsTr("Letting your agents finish")
                    running: win.onAgents
                    done: win.agentsDone
                    /*
                      How long they have left, from the platform.

                      Two minutes of a spinner reads as a hang, and the
                      reasonable response to a hang is the force quit that leaves
                      every container running. A number going down is what makes
                      this a wait somebody sits through rather than escapes.
                    */
                    secondsLeft: Shutdown.secondsLeft
                    totalSeconds: Shutdown.graceSeconds
                    // Amber, not green: the step completed, and not the way it
                    // was meant to.
                    warned: win.agentsCutShort
                    detail: {
                        /*
                          Spelled out rather than left to `qsTr`'s `%n` plural
                          form, which only resolves once a translation exists —
                          untranslated it prints "1 agent(s)" verbatim, and
                          English is the language that ships without a
                          catalogue.
                        */
                        if (win.agentsCutShort)
                            return Shutdown.agentsInterrupted === 1
                                ? qsTr("1 agent did not finish")
                                : qsTr("%1 agents did not finish").arg(Shutdown.agentsInterrupted)
                        if (Shutdown.agentsTotal > 0)
                            return qsTr("%1 of %2 finished")
                                       .arg(Shutdown.agentsFinished)
                                       .arg(Shutdown.agentsTotal)
                        // The honest word for a machine that was running
                        // nothing, and for one that could not reach Simorg to
                        // ask. Neither is a fault and neither is a wait.
                        return win.agentsDone ? qsTr("Nothing to wait for") : qsTr("Asking Simorg…")
                    }
                }

                ShutdownStep {
                    Layout.fillWidth: true
                    index: 2
                    title: qsTr("Stopping containers")
                    running: Shutdown.phase === win.phaseContainers && !Shutdown.complete
                    done: Shutdown.complete
                    detail: Shutdown.total > 0
                            ? qsTr("%1 of %2 stopped").arg(Shutdown.stopped).arg(Shutdown.total)
                            : (Shutdown.phase === win.phaseContainers
                               ? qsTr("Checking what is running…")
                               : "")
                }
            }

            /*
              ---- How far through, over both steps ---------------------------

              One bar rather than one per step, because a person watching this is
              waiting for a single thing — the app to go — and a gauge that reset
              half way would read as the whole business starting again.

              Indeterminate until a count has come back, because until then
              nobody knows the scale, and a bar that started at zero and jumped
              to two thirds would be inventing one.
            */
            Rectangle {
                id: track
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.inset
                clip: true

                /*
                  Two bars rather than one that switches.

                  The determinate one is positioned by its width; the
                  indeterminate one is positioned by an animation. A single
                  rectangle doing both had an `x` binding and an
                  `Animation on x` competing for the same property, where
                  whichever was installed last silently won.
                */
                Rectangle {
                    id: fill
                    visible: !win.indeterminate
                    height: parent.height
                    radius: parent.radius
                    color: Shutdown.complete
                           ? (win.agentsCutShort ? Theme.amber : Theme.emerald)
                           : Theme.cyan
                    width: parent.width * Math.max(0, Math.min(1, Shutdown.progress))

                    Behavior on width {
                        NumberAnimation { duration: Theme.duration(Theme.durBase) }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Theme.duration(Theme.durBase) }
                    }
                }

                // A sweep while the count is unknown, so the bar reads as
                // working rather than as stuck at a third of the way along.
                Rectangle {
                    id: sweep
                    visible: win.indeterminate
                    height: parent.height
                    width: parent.width * 0.32
                    radius: parent.radius
                    color: Theme.cyan

                    SequentialAnimation on x {
                        running: sweep.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: -sweep.width
                            to: track.width
                            duration: 1100
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }

            /*
              The way out, and what taking it costs.

              Hidden on the row rather than on each child, so an offer that is
              not being made takes no height at all — a reserved gap under the
              bar reads as something missing from the window.
            */
            RowLayout {
                Layout.fillWidth: true
                visible: win.waitedLongEnough && !Shutdown.complete
                spacing: Theme.spaceSm

                /*
                  Permission and cost in one line, in that order.

                  "You may do this" before "here is what it costs", because
                  somebody reading this has already decided they want to leave and
                  the useful thing is to tell them it is allowed — then let them
                  weigh it. A line that only warned would read as the app talking
                  them out of a choice it is offering them anyway.

                  During step one the cost is somebody's work in progress, which
                  is the only thing in this window worth a warning colour.
                */
                Text {
                    Layout.fillWidth: true
                    text: win.onAgents
                          ? qsTr("Force quit if you would rather not wait. "
                                 + "Anything your agents have not saved is lost.")
                          : qsTr("Force quit if you would rather not wait. "
                                 + "Containers still running are stopped next time.")
                    color: win.onAgents ? Theme.amber : Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                LinkLabel {
                    Layout.alignment: Qt.AlignBottom
                    text: qsTr("Force Quit!")
                    onActivated: Shutdown.quitNow()
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
