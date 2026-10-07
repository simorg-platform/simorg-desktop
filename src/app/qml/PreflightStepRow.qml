// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One line of the environment check.
 *
 * Four states and one shape: the mark on the left says where this step is, the
 * title never changes, and the line under it is what was found on *this*
 * computer. That last part is the whole value of the screen. "Docker Engine"
 * with a red cross tells somebody nothing they can act on; "Docker Engine is
 * installed but not running" tells them what to do next.
 *
 * A failure is drawn in amber rather than red. None of these is a fault: every
 * one of them is a thing somebody can fix in the next minute, and spending the
 * colour that means "something has gone wrong" on "you are not online yet"
 * leaves nothing to say it with when something actually has.
 */
Item {
    id: root

    /*
      One row per check, given its values rather than a whole step at a time:
      the rows are a list model keyed by the check (`PreflightStepsModel`), so a
      download telling its progress four times a second changes the numbers on
      the row that is already there instead of building it again.
    */
    required property string key
    required property int check
    /** `state` is every QML item's own; the check's is this. */
    required property int stepState
    required property string title
    required property string detail
    /** 0 to 1, and -1 where there is nothing to measure. */
    required property real progress
    required property string remedy

    readonly property int state_: root.stepState
    readonly property bool busy: root.state_ === PreflightState.Checking
                                 || root.state_ === PreflightState.Working
    readonly property color tone: {
        if (root.state_ === PreflightState.Passed) return Theme.emerald;
        if (root.state_ === PreflightState.Failed) return Theme.amber;
        if (root.busy) return Theme.sky;
        return Theme.textFaint;
    }

    implicitHeight: layout.implicitHeight

    Accessible.role: Accessible.StaticText
    Accessible.name: root.detail.length > 0 ? root.title + ": " + root.detail : root.title

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 14

        // ---- The mark ------------------------------------------------
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            width: 34
            height: 34

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusBase
                color: Theme.alpha(root.tone, 0.1)
                border.width: 1
                border.color: Theme.alpha(root.tone, 0.26)

                Behavior on color {
                    ColorAnimation { duration: Theme.duration(Theme.durBase) }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Theme.duration(Theme.durBase) }
                }
            }

            BusyRing {
                anchors.centerIn: parent
                visible: root.busy
                running: root.busy
                size: 18
                tone: root.tone
            }

            Glyph {
                anchors.centerIn: parent
                visible: !root.busy
                name: root.state_ === PreflightState.Passed ? "check"
                    : root.state_ === PreflightState.Failed ? "alert"
                    : "clock"
                size: 16
                thickness: 1.8
                tone: root.tone
            }
        }

        // ---- What it is, and what was found --------------------------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.detail
                color: root.state_ === PreflightState.Failed ? Theme.textBody : Theme.textMuted
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
                lineHeight: 1.45
            }

            // A bar for the whole of the work, measured or not (WorkBar.qml says why).
            WorkBar {
                Layout.fillWidth: true
                Layout.topMargin: 4
                working: root.state_ === PreflightState.Working
                progress: root.progress
            }
        }
    }
}
