// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick

/**
 * The standard content surface — dark glass over the aurora background.
 *
 * Mirrors `surfaceCardSx` from the web console: a diagonal translucent fill, a
 * hairline border, and a single highlight along the top edge that reads as
 * light catching a raised surface.
 */
Rectangle {
    id: root

    /** Lifts and brightens on hover; set by cards that can be clicked. */
    property bool interactive: false
    property bool hovered: false
    property color accent: Theme.blue
    /**
     * Lays the surface over solid ground instead of over whatever is behind it.
     *
     * The fill is translucent by design: these are cards on an aurora
     * background, and the background showing through is the effect. A **modal**
     * is the one place that is wrong — the page it covers goes on showing
     * through the panel that is supposed to be in front of it, and the result
     * reads as muddy rather than as raised.
     */
    property bool opaque: false

    radius: Theme.radiusLarge
    color: "transparent"
    border.width: 1
    border.color: interactive && hovered ? Theme.alpha(accent, 0.45) : Theme.borderSubtle

    Behavior on border.color {
        ColorAnimation { duration: Theme.duration(Theme.durBase) }
    }

    // Solid ground, when there is to be any. First, so the translucent fill
    // below composites over it rather than over the page.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        visible: root.opaque
        color: Theme.base
    }

    // The fill sits behind the border so the hairline stays crisp at any radius.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.surface }
            GradientStop { position: 1.0; color: Theme.surfaceDeep }
        }
    }

    // Specular highlight along the top edge.
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - parent.radius
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.alpha(Theme.textPrimary, 0) }
            GradientStop { position: 0.5; color: Theme.alpha(Theme.textPrimary, 0.09) }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.textPrimary, 0) }
        }
    }
}
