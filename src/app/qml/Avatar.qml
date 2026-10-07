// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes
import Simorg

/**
 * Somebody's account, in the shape it has on the Logos — or their initials in it.
 *
 * ## The seven cells
 *
 * On the Logos a person, a team or an agent stands on seven cells of the
 * honeycomb with their picture spread across them, and the web panel draws that
 * same figure at the top of every public page. This app draws it too, so the
 * face somebody recognises on the sheet is the face beside their name here: the
 * outer edge of the seven cells with every corner rounded, and no seams inside
 * it — those belong to the sheet rather than to whoever is standing on it.
 *
 * The outline comes from {@link FlowerShape}, in the Logos's own units, so an
 * avatar has the same proportions at twenty-seven pixels in the toolbar and at
 * ninety on an agent's page.
 *
 * ## Drawn as the web draws it
 *
 * Piece for piece what the web's identity avatar draws, so an account
 * looks the same here as on the web: the frame, a fine line in the accent over a
 * faint tint of it; the face a margin inside it on a near-black ground; the
 * picture across the face's own square; the initials light and heavy when there
 * is no picture; the face lit as one raised piece of glossy plastic with the sun
 * low in the east, and a soft shadow under the whole piece. The light and the
 * shadow are {@link FlowerLayer}, painted, because what the web makes of blurs
 * and masks Qt Quick can only draw everywhere that way.
 *
 * ## The initials are not an apology
 *
 * They are what an account with no picture has, which is most accounts, and they
 * render with no load and no failure state. A picture is drawn over them when
 * there is one, and the ground stays underneath, so a slow disk shows two
 * letters rather than a hole.
 *
 * ## The shape is already cut
 *
 * `source` is expected to be an image cut to this outline already — transparent
 * outside it — which is what {@link AvatarCache} writes. Qt Quick has no masking
 * this app can use: `clip` is rectangular, `MultiEffect` needs Qt 6.5 and this
 * app builds on 6.4, and every shader route is dead on the software backend the
 * interface tests render with. Cutting the alpha channel on the way in costs
 * nothing and works everywhere — and both cuts come off the same arithmetic, so
 * the picture cannot end up a corner wider than the frame around it.
 */
Item {
    id: root

    property string initials: "?"
    /** A picture already cut to this outline, on this disk. Empty draws the initials. */
    property url source: ""
    /**
     * The platform's address for a picture — an account's or an agent's — which
     * this resolves through the cache on its own.
     *
     * A caller hands over the address it was given and nothing else: whether the
     * file is on the disk yet, whether it has to be fetched, and what to draw in
     * the meantime are this component's business. An agent's row carries one on
     * `avatarUrl`; the signed-in account's arrives ready-resolved on
     * {@link source}, because the bridge is already following it.
     */
    property string remote: ""
    property real size: 34
    /** Lifts the frame's line, for a row or a card that is being pointed at. */
    property real glow: 0.0
    /** The line around it: the web's default for every identity. */
    property color accent: Theme.cyan

    /**
     * The cut PNG for {@link remote}, once there is one.
     *
     * Asked of the cache rather than bound to it: a picture that is not on this
     * disk yet has no property to bind to, and asking is what starts the fetch.
     * `arrived` is the other half — the cache says when an address has a file,
     * and this asks again. Every row of a list of agents does this once, not
     * once per frame; see AvatarCache.
     */
    property url fetched: ""

    function resolve() {
        root.fetched = root.remote.length > 0 ? Avatars.fileFor(root.remote) : "";
    }

    onRemoteChanged: root.resolve()
    Component.onCompleted: root.resolve()

    readonly property Connections cache: Connections {
        target: Avatars

        function onArrived(url) {
            if (url === root.remote)
                root.resolve();
        }
    }

    /** What is actually drawn: what the caller gave, or what the cache went and got. */
    readonly property url picture: root.source.toString().length > 0 ? root.source : root.fetched

    /** True once a picture is actually on screen, which is when the initials give way to it. */
    readonly property bool showingPicture: face.status === Image.Ready

    implicitWidth: size
    implicitHeight: size

    /** The initials' size, as the web sizes them for an avatar this big. */
    readonly property real initialsSize: Flower.initialsSize(root.size)

    /*
      The weight under the piece, in no colour, reaching past the square. Under
      everything, so it never darkens the frame's own tint.
    */
    FlowerLayer {
        kind: FlowerLayer.Shadow
        avatarSize: root.size
        x: -reach
        y: -reach
        width: root.size + reach * 2
        height: root.size + reach * 2
        opacity: figure.opacity
    }

    /*
      The frame and the ground under the picture, in one Shape.

      Two paths rather than one: the frame is the whole figure, and the face is
      the same figure brought in by the Logos's margin — so the line reads as a
      frame around a picture rather than as a border drawn on top of one.
    */
    Shape {
        id: figure
        anchors.fill: parent
        antialiasing: true
        // Enough to draw a picture behind, but never the thing being pointed at.
        opacity: root.enabled ? 1 : 0.6

        // ---- The frame -------------------------------------------------
        ShapePath {
            fillGradient: LinearGradient {
                x1: root.size * 0.25; y1: root.size * 0.05
                x2: root.size * 0.75; y2: root.size * 0.95
                GradientStop { position: 0.0; color: Theme.alpha(root.accent, 0.28) }
                GradientStop { position: 0.7; color: Theme.alpha(Theme.layer950, 0.6) }
            }
            // Brighter while the row it sits on is under the pointer; a halo
            // around the border is exactly what the Logos removed.
            strokeColor: Theme.alpha(root.accent, 0.45 + 0.45 * root.glow)
            strokeWidth: 1
            capStyle: ShapePath.RoundCap
            PathSvg { path: Flower.framePath(root.size) }
        }

        /*
          ---- The ground under the picture and the initials -------------

          Near-black, as on the web. A bright gradient here would make the
          initials loud and — wherever a picture did not cover the face exactly
          — show through as coloured rims.
        */
        ShapePath {
            fillColor: Theme.alpha(Theme.layer950, 0.94)
            strokeWidth: -1
            PathSvg { path: Flower.facePath(root.size) }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.showingPicture
        text: root.initials
        color: Theme.textPrimary
        font.pixelSize: root.initialsSize
        font.weight: Font.Black
        // The web's -0.02em.
        font.letterSpacing: -0.02 * root.initialsSize
    }

    /*
      Over the initials, never instead of them.

      `mipmap` because this is a 256-pixel picture drawn at 27: without it the
      scene graph point-samples the source and the result crawls with aliasing
      on every hover animation. `asynchronous` because it is a file read, and a
      toolbar should not wait on a disk.
    */
    Image {
        id: face
        anchors.fill: parent
        source: root.picture
        visible: opacity > 0
        opacity: status === Image.Ready ? 1 : 0
        asynchronous: true
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    /*
      The light on the face, over the picture or the initials: the swell, the
      shoulder in shade, the gloss and hairline facing the sun, and the crease
      where the face meets the frame — the crease alone under 26 points, as on
      the web. It is what stops a photograph looking pasted flat into the outline.
    */
    FlowerLayer {
        anchors.fill: parent
        kind: FlowerLayer.Lighting
        avatarSize: root.size
    }
}
