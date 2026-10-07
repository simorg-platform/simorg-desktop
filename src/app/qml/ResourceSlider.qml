// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * One resource ceiling — processors, memory, disk.
 *
 * Two things make this different from a plain slider, and both matter because
 * the value being set can stop Docker from starting:
 *
 *  - The track is drawn from the *minimum*, not from zero. Docker will not run
 *    below two gigabytes, so a slider that offered 0–34 GB would spend the
 *    first sixth of its travel on values that break the thing being configured.
 *  - Where the machine's own headroom ends is marked on the track, so promising
 *    Docker everything is a visible decision rather than an accident.
 */
Item {
    id: root

    property string label: ""
    property string glyph: ""
    property color tone: Theme.blue

    property real minimum: 0
    property real maximum: 100
    property real value: 0
    /** Snap increment. 0 is continuous. */
    property real step: 0
    /** Formats a value for display. */
    property var format: (v) => String(Math.round(v))
    /** A short line under the label saying what this actually does. */
    property string hint: ""

    /**
     * Nothing to choose: the floor and the ceiling are the same number.
     *
     * It happens for real — a disk that cannot be made smaller on a computer
     * with no free space to make it bigger, a memory ceiling that has come down
     * to the floor — and a slider that silently refuses to move is the worst
     * possible way to say so. The track reads as spent, the handle does not
     * follow the pointer, and the caller puts the reason beside it.
     */
    readonly property bool fixed: root.maximum <= root.minimum

    signal moved(real value)

    implicitHeight: column.implicitHeight

    function clampAndSnap(candidate) {
        let v = Math.max(root.minimum, Math.min(root.maximum, candidate));
        if (root.step > 0)
            v = root.minimum + Math.round((v - root.minimum) / root.step) * root.step;
        return Math.max(root.minimum, Math.min(root.maximum, v));
    }

    readonly property real fraction: root.maximum > root.minimum
                                     ? (root.value - root.minimum) / (root.maximum - root.minimum)
                                     : 0

    opacity: enabled && !root.fixed ? 1 : 0.4

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            Glyph {
                visible: root.glyph.length > 0
                name: root.glyph
                size: 15
                thickness: 1.7
                tone: Theme.alpha(root.tone, 0.9)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: root.label
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.hint.length > 0
                    text: root.hint
                    color: Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // The number is monospaced so it stops jittering sideways while the
            // handle is being dragged.
            Text {
                text: root.format(root.value)
                color: Theme.textPrimary
                font.family: Theme.monoFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            implicitHeight: 26

            readonly property real usable: width - handle.width
            readonly property real handleX: root.fraction * usable

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                height: 6
                radius: 3
                color: Theme.inset
                border.width: 1
                border.color: Theme.borderSubtle
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: track.handleX + handle.width / 2
                height: 6
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.alpha(root.tone, 0.55) }
                    GradientStop { position: 1.0; color: root.tone }
                }
            }

            Rectangle {
                id: handle
                width: 18
                height: 18
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                x: track.handleX
                color: Theme.baseHigh
                border.width: 2
                border.color: root.tone

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: root.tone
                }

                scale: drag.active || hover.hovered ? 1.15 : 1
                Behavior on scale {
                    NumberAnimation { duration: Theme.duration(Theme.durFast) }
                }
            }

            HoverHandler {
                id: hover
                enabled: root.enabled && !root.fixed
                cursorShape: Qt.PointingHandCursor
            }

            DragHandler {
                id: drag
                enabled: root.enabled && !root.fixed
                target: null
                onCentroidChanged: {
                    if (!active)
                        return;
                    const usable = Math.max(1, track.usable);
                    const x = Math.max(0, Math.min(usable, drag.centroid.position.x - handle.width / 2));
                    root.moved(root.clampAndSnap(root.minimum
                                                 + (x / usable) * (root.maximum - root.minimum)));
                }
            }

            TapHandler {
                enabled: root.enabled && !root.fixed
                onTapped: function (point) {
                    const usable = Math.max(1, track.usable);
                    const x = Math.max(0, Math.min(usable, point.position.x - handle.width / 2));
                    root.moved(root.clampAndSnap(root.minimum
                                                 + (x / usable) * (root.maximum - root.minimum)));
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.format(root.minimum)
                color: Theme.textFaint
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            // The same number twice would read as a scale rather than as the
            // one value on offer, so the far end is left off when there is no
            // range to describe.
            Text {
                visible: !root.fixed
                text: root.format(root.maximum)
                color: Theme.textFaint
                font.pixelSize: 11
            }
        }
    }
}
