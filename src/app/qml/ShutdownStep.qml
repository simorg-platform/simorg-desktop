// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One line of the quitting checklist.
 *
 * ## Why a checklist and not a single bar
 *
 * Because quitting is two genuinely different operations that can fail
 * separately, and only one of them risks anybody's work. Asking the agents to
 * finish is a conversation with the platform; stopping containers is Docker on
 * this computer. Somebody who presses *Force Quit!* skips the first — the one
 * whose whole purpose is that nothing in progress is lost — and they can only
 * weigh that if they can see which step is running.
 *
 * ## The three states, and why "done" is not one colour
 *
 * A step is waiting, running, or finished, and it is drawn as a marker with a
 * label under it.
 *
 *   - **Waiting** is dim and numbered. It has not started; there is nothing to
 *     report about it, and a spinner on a step that has not begun would claim
 *     work that is not happening.
 *   - **Running** is a filled cyan dot. Deliberately *not* a second spinner:
 *     the window's own header already carries one, and two identical rings an
 *     inch apart read as two things happening rather than as one thing at a
 *     known point. The header spins because something is in flight; this marks
 *     where.
 *   - **Finished** is a tick — green normally, amber with a warning mark when
 *     {@link warned} is set.
 *
 * That last split matters more than it looks. Step one "completes" whether every
 * agent finished or somebody stopped waiting for them, and a green tick over the
 * second case would be the window telling somebody their work is safe when it is
 * not. The step is done either way; only one of them went the way it was meant
 * to.
 *
 * ## It keeps its detail after it finishes
 *
 * A completed step still shows its count — "3 of 3 finished" — rather than
 * clearing to a bare tick. That count *is* the reassurance somebody was waiting
 * for, and removing it at the moment it becomes true takes away the answer just
 * as it arrives.
 */
RowLayout {
    id: root

    /** 1 or 2. Shown in the marker until the step has something better to say. */
    property int index: 1
    property string title: ""
    /** The count under the title, or an empty string for no second line. */
    property string detail: ""
    /** This step is happening now. */
    property bool running: false
    /** This step is behind us, however it went. */
    property bool done: false
    /** It finished, and not the way it was meant to. See the class note. */
    property bool warned: false
    /**
     * Whole seconds left of this step's budget, or zero for a step with none.
     *
     * Only step one has one. Stopping containers is bounded by Docker rather
     * than by a platform setting, and a clock on it would promise a precision
     * this app does not have.
     */
    property int secondsLeft: 0
    /** The whole budget, so the clock's ring has a scale to drain against. */
    property int totalSeconds: 0

    spacing: 10

    /**
     * The marker: a number, a spinner, or a tick.
     *
     * A fixed square rather than one sized to its content, so the two steps'
     * titles line up with each other — a list whose text shifted sideways as
     * each step changed state would draw the eye to the movement rather than to
     * what changed.
     */
    Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 1
        implicitWidth: 18
        implicitHeight: 18

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: !root.running && !root.done
            color: "transparent"
            border.width: 1
            border.color: Theme.textFaint

            Text {
                anchors.centerIn: parent
                text: root.index
                color: Theme.textFaint
                font.pixelSize: 10
            }
        }

        Rectangle {
            anchors.centerIn: parent
            visible: root.running
            width: 9
            height: 9
            radius: width / 2
            color: Theme.cyan

            /*
              A slow pulse rather than a spin. Enough movement to say "here, and
              still going" without competing with the header's spinner for the
              same glance.
            */
            SequentialAnimation on opacity {
                running: root.running
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 780; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.35; to: 1.0; duration: 780; easing.type: Easing.InOutQuad }
            }
        }

        Glyph {
            anchors.centerIn: parent
            visible: root.done
            name: root.warned ? "alert" : "check-circle"
            size: 16
            thickness: 1.8
            tone: root.warned ? Theme.amber : Theme.emerald
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSm

            ElidedText {
                Layout.fillWidth: true
                text: root.title
                /*
                  The running step is the bright one, and the finished step stays
                  legible rather than fading out.

                  A completed step that dimmed to the same grey as one that has
                  not started would make the list unreadable at a glance — which
                  is the one thing a person does with it.
                */
                color: root.running ? Theme.textPrimary
                                    : (root.done ? Theme.textMuted : Theme.textFaint)
                font.pixelSize: 12
                font.weight: root.running ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            /*
              On the title's line, right-aligned, and only while this step is the
              one running.

              Beside the thing it is counting rather than under it: a clock on its
              own row would read as a fact about the whole window, and the budget
              belongs to this step alone.
            */
            CountdownPill {
                visible: root.running && root.secondsLeft > 0
                secondsLeft: root.secondsLeft
                totalSeconds: root.totalSeconds
            }
        }

        ElidedText {
            Layout.fillWidth: true
            visible: root.detail.length > 0
            text: root.detail
            color: root.warned ? Theme.amber : Theme.textFaint
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
