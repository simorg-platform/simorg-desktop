// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * A bar for the whole of a piece of work, measured or not: the environment
 * check's steps and the rows of Settings → Updates.
 *
 * Drawn only while there is a fraction to draw, it would flicker twice in one
 * download: appearing when the size arrives and disappearing again when the
 * download ends and the image is being loaded, which reports no measure. So the
 * bar stays for as long as the work runs: it fills when there is a measure and
 * sweeps when there is not, which says *still working* without claiming a
 * position it does not know.
 */
Item {
    id: bar

    /** Whether the work runs; the bar is not drawn otherwise. */
    property bool working: false
    /** The fraction done, or below 0 when nothing can be measured. */
    property real progress: -1

    readonly property bool measured: bar.progress >= 0

    implicitHeight: 5
    visible: bar.working

    Rectangle {
        anchors.fill: parent
        radius: 2.5
        color: Theme.inset
        border.width: 1
        border.color: Theme.borderSubtle
    }

    // What has been done, where that is known.
    Rectangle {
        objectName: "progressFill"
        height: parent.height
        visible: bar.measured
        width: parent.width * Math.max(0, Math.min(1, bar.progress))
        radius: 2.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.ctaFrom }
            GradientStop { position: 1.0; color: Theme.ctaTo }
        }

        Behavior on width {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    /*
      And a stripe crossing it where it is not: an image being resolved, checked
      or loaded, a package being installed. Still, not empty, when motion is off
      — a bar that does not move is honest about a measure nobody has.
    */
    Item {
        anchors.fill: parent
        visible: !bar.measured
        clip: true

        Rectangle {
            id: sweep
            objectName: "progressSweep"
            height: parent.height
            width: parent.width * 0.4
            x: Theme.motion ? -width : 0
            opacity: Theme.motion ? 1 : 0.5
            radius: 2.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.ctaFrom }
                GradientStop { position: 1.0; color: Theme.ctaTo }
            }

            NumberAnimation on x {
                running: Theme.motion && bar.visible && !bar.measured
                loops: Animation.Infinite
                from: -sweep.width
                to: bar.width
                duration: 1100
            }
        }
    }
}
