// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Shapes

/**
 * Line icons, drawn rather than shipped.
 *
 * The web app hand-draws its icons on a 24×24 grid (see the GLYPHS map in
 * HowItWorks.tsx); these are the same shapes as SVG path data, rendered by Qt
 * Quick Shapes. Keeping them as geometry means no icon font, no image assets,
 * and a stroke weight that stays honest at every size and scale factor.
 */
Item {
    id: root

    /** A key of {@link paths}. Unknown names draw nothing. */
    property string name: ""
    property real size: 20
    property color tone: Theme.textBody
    property real thickness: 1.6

    implicitWidth: size
    implicitHeight: size

    /** Every glyph is one path string on a 24×24 grid, stroked, never filled. */
    readonly property var paths: ({
        "mail": "M3.2 6.6 H20.8 V17.4 H3.2 Z M3.2 7.2 L12 13.4 L20.8 7.2",
        "lock": "M7.6 10.4 V8.1 C7.6 5.7 9.6 3.7 12 3.7 C14.4 3.7 16.4 5.7 16.4 8.1 V10.4 \
                 M5.6 10.4 H18.4 V20 H5.6 Z M12 13.6 V16.8",
        "eye": "M2.6 12 C5.2 7.6 8.4 5.6 12 5.6 C15.6 5.6 18.8 7.6 21.4 12 \
                C18.8 16.4 15.6 18.4 12 18.4 C8.4 18.4 5.2 16.4 2.6 12 Z \
                M12 9.2 C13.5 9.2 14.8 10.5 14.8 12 C14.8 13.5 13.5 14.8 12 14.8 \
                C10.5 14.8 9.2 13.5 9.2 12 C9.2 10.5 10.5 9.2 12 9.2 Z",
        "eye-off": "M2.6 12 C5.2 7.6 8.4 5.6 12 5.6 C15.6 5.6 18.8 7.6 21.4 12 \
                    C18.8 16.4 15.6 18.4 12 18.4 C8.4 18.4 5.2 16.4 2.6 12 Z \
                    M12 9.2 C13.5 9.2 14.8 10.5 14.8 12 C14.8 13.5 13.5 14.8 12 14.8 \
                    C10.5 14.8 9.2 13.5 9.2 12 C9.2 10.5 10.5 9.2 12 9.2 Z \
                    M4.2 4.2 L19.8 19.8",
        "alert": "M12 3.8 L21.4 19.6 H2.6 Z M12 9.6 V14.4 M12 16.4 V17.4",
        /*
          A bell, for something waiting rather than something wrong.

          Deliberately not "alert". A triangle says a fault; this is an agent
          asking its owner a question, and the answer is a decision rather than
          a repair. Using the triangle for both would spend the triangle.
        */
        "bell": "M12 4.4 C9.2 4.4 6.9 6.7 6.9 9.5 V13.2 L5.3 16.6 H18.7 L17.1 13.2 V9.5 \
                 C17.1 6.7 14.8 4.4 12 4.4 Z M12 2.4 V4.4 \
                 M10.1 18.6 C10.4 19.5 11.1 20.2 12 20.2 C12.9 20.2 13.6 19.5 13.9 18.6",
        "check": "M5 12.6 L10 17.4 L19 6.8",
        // Its own path rather than a rotated "check": a rotated IconButton turns
        // its tooltip upside down with it, which is how the first attempt at a
        // close button ended up drawn as a corner.
        "close": "M6.2 6.2 L17.8 17.8 M17.8 6.2 L6.2 17.8",
        "arrow-right": "M4.6 12 H19 M13.4 6.4 L19 12 L13.4 17.6",
        // Its mirror rather than the same path rotated: a rotated IconButton
        // turns its tooltip upside down with it.
        "arrow-left": "M19.4 12 H5 M10.6 6.4 L5 12 L10.6 17.6",
        // A disclosure: a card that opens in place, turned half round when open.
        "chevron-down": "M6.2 9.2 L12 15 L17.8 9.2",
        "chevron-up": "M6.2 14.8 L12 9 L17.8 14.8",
        "grid": "M4 4 H10.4 V10.4 H4 Z M13.6 4 H20 V10.4 H13.6 Z \
                 M4 13.6 H10.4 V20 H4 Z M13.6 13.6 H20 V20 H13.6 Z",
        "robot": "M4.4 8.2 H19.6 V19.6 H4.4 Z M12 4.8 V8.2 \
                  M12 2.6 C12.8 2.6 13.4 3.2 13.4 4 C13.4 4.8 12.8 5.4 12 5.4 \
                  C11.2 5.4 10.6 4.8 10.6 4 C10.6 3.2 11.2 2.6 12 2.6 Z \
                  M9.3 12.2 C9.9 12.2 10.4 12.7 10.4 13.3 C10.4 13.9 9.9 14.4 9.3 14.4 \
                  C8.7 14.4 8.2 13.9 8.2 13.3 C8.2 12.7 8.7 12.2 9.3 12.2 Z \
                  M14.7 12.2 C15.3 12.2 15.8 12.7 15.8 13.3 C15.8 13.9 15.3 14.4 14.7 14.4 \
                  C14.1 14.4 13.6 13.9 13.6 13.3 C13.6 12.7 14.1 12.2 14.7 12.2 Z \
                  M9.7 16.8 H14.3",
        "cube": "M12 2.6 L20.4 7.4 L20.4 16.6 L12 21.4 L3.6 16.6 L3.6 7.4 Z \
                 M12 12 L20.4 7.4 M12 12 L3.6 7.4 M12 12 V21.4",
        "server": "M4 5.2 H20 V10 H4 Z M4 14 H20 V18.8 H4 Z M7.2 7.6 H9 M7.2 16.4 H9",
        "building": "M3.8 20.4 V5 H12.6 V20.4 M12.6 20.4 V10 H20.2 V20.4 \
                     M6.5 8.4 H9.7 M6.5 12 H9.7 M6.5 15.6 H9.7 M15.2 13.4 H17.6 M15.2 16.8 H17.6",
        // ---- The market ------------------------------------------------------
        // Who stands behind an agent, for BrandDiagram: a person, the team they
        // work in, the company they work for, and the shop a vendor keeps. A
        // circle is drawn as two half-arcs so each mark stays one path.
        "people": "M6.2 8.4 a3.2 3.2 0 1 0 6.4 0 a3.2 3.2 0 1 0 -6.4 0 \
                   M3.4 19.8 c0-3.5 2.7-5.6 6-5.6 s6 2.1 6 5.6 \
                   M14.9 9.6 a2.3 2.3 0 1 0 4.6 0 a2.3 2.3 0 1 0 -4.6 0 \
                   M16.5 14.6 c2.9-.1 4.8 1.9 4.8 5.2",
        "team": "M9.1 7.4 a2.9 2.9 0 1 0 5.8 0 a2.9 2.9 0 1 0 -5.8 0 \
                 M2.6 9.8 a2.2 2.2 0 1 0 4.4 0 a2.2 2.2 0 1 0 -4.4 0 \
                 M17 9.8 a2.2 2.2 0 1 0 4.4 0 a2.2 2.2 0 1 0 -4.4 0 \
                 M6.6 19.4 c0-3 2.4-5.2 5.4-5.2 s5.4 2.2 5.4 5.2 \
                 M1.6 17.8 c0-2.3 1.4-4 3.6-4.2 M22.4 17.8 c0-2.3-1.4-4-3.6-4.2",
        "store": "M3.6 9.4 L5.4 4.6 H18.6 L20.4 9.4 \
                  M3.6 9.4 c0 1.6 1.25 2.9 2.8 2.9 s2.8-1.3 2.8-2.9 c0 1.6 1.25 2.9 2.8 2.9 \
                  s2.8-1.3 2.8-2.9 c0 1.6 1.25 2.9 2.8 2.9 s2.8-1.3 2.8-2.9 \
                  M5.4 12.6 V19.8 H18.6 V12.6 M9.9 19.8 v-4.4 h4.2 v4.4",
        // A bolt, for the work a principal puts into its agent. The web
        // diagrams call this one `spark`; `spark` here is already the star
        // above, and a star says "new" where this has to say "powered".
        "bolt": "M13.6 2.6 L6 13.4 h4.8 l-1.2 8 7.6-10.8 h-4.8 z",
        "settings": "M4 8 H19.4 M4.6 16 H20 \
                     M9 5.6 C10.3 5.6 11.4 6.7 11.4 8 C11.4 9.3 10.3 10.4 9 10.4 \
                     C7.7 10.4 6.6 9.3 6.6 8 C6.6 6.7 7.7 5.6 9 5.6 Z \
                     M15 13.6 C16.3 13.6 17.4 14.7 17.4 16 C17.4 17.3 16.3 18.4 15 18.4 \
                     C13.7 18.4 12.6 17.3 12.6 16 C12.6 14.7 13.7 13.6 15 13.6 Z",
        "logout": "M15 8.4 V5.6 H4.6 V18.4 H15 V15.6 M9.6 12 H20.4 M17 8.6 L20.4 12 L17 15.4",
        // The power mark, for Quit Simorg: a ring open at the top, in four curves, with the stroke through the gap.
        "power": "M12 3.4 V11.6 M7.4 7.3 C5.1 9.2 4.2 12.4 5.2 15.3 C6.3 18.1 9 20 12 20 \
                  C15 20 17.7 18.1 18.8 15.3 C19.8 12.4 18.9 9.2 16.6 7.3",
        "external": "M14 4.6 H19.4 V10 M19.4 4.6 L11.4 12.6 M17.4 13.6 V19.4 H4.6 V6.6 H10.4",
        "user": "M12 4.2 C14 4.2 15.6 5.8 15.6 7.8 C15.6 9.8 14 11.4 12 11.4 \
                 C10 11.4 8.4 9.8 8.4 7.8 C8.4 5.8 10 4.2 12 4.2 Z \
                 M4.6 20 C4.6 16.2 7.9 13.6 12 13.6 C16.1 13.6 19.4 16.2 19.4 20",
        "spark": "M12 3.4 L13.9 9.4 L20 11.3 L13.9 13.2 L12 19.2 L10.1 13.2 L4 11.3 L10.1 9.4 Z",

        // ---- Docker section ------------------------------------------------
        // A stack of containers rather than a whale: the shape reads at 16px,
        // it is ours to draw, and it says "isolated boxes" — which is the thing
        // the section is actually about.
        "container": "M3.4 13.4 H8.2 V17.6 H3.4 Z M9.4 13.4 H14.2 V17.6 H9.4 Z \
                      M15.4 13.4 H20.2 V17.6 H15.4 Z M6.4 8.8 H11.2 V12.2 H6.4 Z \
                      M12.4 8.8 H17.2 V12.2 H12.4 Z M9.4 4.2 H14.2 V7.6 H9.4 Z \
                      M2.4 20 H21.6",
        "shield": "M12 3.2 L19.4 6.1 V11.5 C19.4 15.9 16.4 19.4 12 20.8 \
                   C7.6 19.4 4.6 15.9 4.6 11.5 V6.1 Z M9 12 L11.2 14.2 L15.2 10.2",
        "gauge": "M4.2 17.4 C3 15.8 2.4 13.9 2.4 12 C2.4 6.7 6.7 2.4 12 2.4 \
                  C17.3 2.4 21.6 6.7 21.6 12 C21.6 13.9 21 15.8 19.8 17.4 \
                  M12 12 L16 8.6 M12 12 C12.8 12 13.4 12.6 13.4 13.4 \
                  C13.4 14.2 12.8 14.8 12 14.8 C11.2 14.8 10.6 14.2 10.6 13.4 \
                  C10.6 12.6 11.2 12 12 12 Z",
        "layers": "M12 3 L21 7.6 L12 12.2 L3 7.6 Z M3 12 L12 16.6 L21 12 \
                   M3 16.4 L12 21 L21 16.4",
        "cpu": "M7.6 7.6 H16.4 V16.4 H7.6 Z M5 5 H19 V19 H5 Z \
                M9.4 2.6 V5 M14.6 2.6 V5 M9.4 19 V21.4 M14.6 19 V21.4 \
                M2.6 9.4 H5 M2.6 14.6 H5 M19 9.4 H21.4 M19 14.6 H21.4",
        // A graphics card seen from the side: its bracket, its fan and the edge that plugs in.
        "gpu": "M3 4.6 V19.4 M3 6.4 H21 V16.2 H3 M10 11.3 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 \
                M6.6 16.2 V18.6 H15.4 V16.2",
        "memory": "M3.4 7.4 H20.6 V16.6 H3.4 Z M7 10.4 V13.6 M10.4 10.4 V13.6 \
                   M13.6 10.4 V13.6 M17 10.4 V13.6 M6.4 4.6 V7.4 M17.6 4.6 V7.4 \
                   M6.4 16.6 V19.4 M17.6 16.6 V19.4",
        "disk": "M12 3.4 C16.9 3.4 20.8 4.9 20.8 6.8 C20.8 8.7 16.9 10.2 12 10.2 \
                 C7.1 10.2 3.2 8.7 3.2 6.8 C3.2 4.9 7.1 3.4 12 3.4 Z \
                 M3.2 6.8 V17.2 C3.2 19.1 7.1 20.6 12 20.6 C16.9 20.6 20.8 19.1 20.8 17.2 V6.8 \
                 M3.2 12 C3.2 13.9 7.1 15.4 12 15.4 C16.9 15.4 20.8 13.9 20.8 12",
        "sliders": "M5 4.6 V19.4 M12 4.6 V19.4 M19 4.6 V19.4 \
                    M5 9.2 C6 9.2 6.8 10 6.8 11 C6.8 12 6 12.8 5 12.8 \
                    C4 12.8 3.2 12 3.2 11 C3.2 10 4 9.2 5 9.2 Z \
                    M12 13.2 C13 13.2 13.8 14 13.8 15 C13.8 16 13 16.8 12 16.8 \
                    C11 16.8 10.2 16 10.2 15 C10.2 14 11 13.2 12 13.2 Z \
                    M19 6.2 C20 6.2 20.8 7 20.8 8 C20.8 9 20 9.8 19 9.8 \
                    C18 9.8 17.2 9 17.2 8 C17.2 7 18 6.2 19 6.2 Z",
        "play": "M8 5.4 L18 12 L8 18.6 Z",
        "stop": "M7 7 H17 V17 H7 Z",
        "pause": "M9 5.6 V18.4 M15 5.6 V18.4",
        "restart": "M20.2 12 C20.2 16.5 16.5 20.2 12 20.2 C7.5 20.2 3.8 16.5 3.8 12 \
                    C3.8 7.5 7.5 3.8 12 3.8 C15 3.8 17.6 5.4 19 7.8 \
                    M19.6 3.6 V8.2 H15",
        "trash": "M4.6 6.6 H19.4 M9.4 6.6 V4.4 H14.6 V6.6 \
                  M6.6 6.6 L7.4 19.6 H16.6 L17.4 6.6 M10.2 10 V16.4 M13.8 10 V16.4",
        "info": "M12 2.8 C17.1 2.8 21.2 6.9 21.2 12 C21.2 17.1 17.1 21.2 12 21.2 \
                 C6.9 21.2 2.8 17.1 2.8 12 C2.8 6.9 6.9 2.8 12 2.8 Z \
                 M12 10.8 V16.6 M12 7.6 V8.6",
        "refresh": "M20.4 5.6 V10.2 H15.8 M3.6 18.4 V13.8 H8.2 \
                    M4.7 10 C5.6 6.9 8.5 4.6 12 4.6 C14.7 4.6 17 5.9 18.4 8 \
                    M19.3 14 C18.4 17.1 15.5 19.4 12 19.4 C9.3 19.4 7 18.1 5.6 16",
        "terminal": "M3.6 4.8 H20.4 V19.2 H3.6 Z M7 9.4 L10 12 L7 14.6 M12.6 15 H17",
        "check-circle": "M12 2.8 C17.1 2.8 21.2 6.9 21.2 12 C21.2 17.1 17.1 21.2 12 21.2 \
                         C6.9 21.2 2.8 17.1 2.8 12 C2.8 6.9 6.9 2.8 12 2.8 Z \
                         M7.8 12.2 L10.8 15.2 L16.2 9.4",
        /*
          A cross in a circle, for a log line at ERROR.

          Deliberately not "alert". The triangle is a warning — something that
          needs a person eventually — and an error is a thing that has already
          failed and will not come right on its own. Drawing both as a triangle
          would spend the triangle, exactly as using it for the bell would have.
          The same circle as "check-circle" and "info", so the three levels that
          share the level column are the same shape with different contents.
        */
        "close-circle": "M12 2.8 C17.1 2.8 21.2 6.9 21.2 12 C21.2 17.1 17.1 21.2 12 21.2 \
                         C6.9 21.2 2.8 17.1 2.8 12 C2.8 6.9 6.9 2.8 12 2.8 Z \
                         M9 9 L15 15 M15 9 L9 15",
        /*
          A beetle, for a log line at DEBUG.

          The one glyph here whose meaning is a convention rather than a
          picture: nothing about a bug says "detail somebody debugging wants",
          and every developer on earth reads it that way anyway.
        */
        "bug": "M8 10.6 C8 8.4 9.8 6.6 12 6.6 C14.2 6.6 16 8.4 16 10.6 V14.4 \
                C16 16.6 14.2 18.4 12 18.4 C9.8 18.4 8 16.6 8 14.4 Z \
                M9.6 7.5 L8.2 5 M14.4 7.5 L15.8 5 \
                M8 11.8 H4.6 M16 11.8 H19.4 \
                M8.3 15.7 L5.4 17.5 M15.7 15.7 L18.6 17.5 \
                M8.3 9.3 L5.4 7.5 M15.7 9.3 L18.6 7.5",
        "download": "M12 3.6 V15.2 M7.4 10.8 L12 15.4 L16.6 10.8 M4.6 19.4 H19.4",
        "clock": "M12 2.8 C17.1 2.8 21.2 6.9 21.2 12 C21.2 17.1 17.1 21.2 12 21.2 \
                  C6.9 21.2 2.8 17.1 2.8 12 C2.8 6.9 6.9 2.8 12 2.8 Z M12 6.8 V12 L15.6 14.2",
        "home": "M3.4 10.6 L12 3.6 L20.6 10.6 M5.8 9 V20 H18.2 V9 \
                 M9.8 20 V14 H14.2 V20",
        "copy": "M8.6 8.6 H19.4 V19.4 H8.6 Z M15.4 8.6 V5.6 H4.6 V16.4 H8.6",
        // Renaming something where its name is read. See EditableName.qml.
        "pencil": "M4.6 19.4 L5.4 15.6 L15.6 5.4 C16.4 4.6 17.6 4.6 18.4 5.4 \
                   C19.2 6.2 19.2 7.4 18.4 8.2 L8.2 18.4 Z M13.8 7.2 L16.6 10",

        // ---- This Machine section ------------------------------------------
        // The seven things a virtual machine can be granted, plus the two shapes
        // the section itself needs. Drawn to read at 15px in a sidebar, which is
        // the smallest any of them is ever shown at.
        "folder": "M3.6 18.8 V5.2 H9.8 L11.8 8 H20.4 V18.8 Z M3.6 10.2 H20.4",
        "network": "M12 3.4 C16.7 3.4 20.6 7.3 20.6 12 C20.6 16.7 16.7 20.6 12 20.6 \
                    C7.3 20.6 3.4 16.7 3.4 12 C3.4 7.3 7.3 3.4 12 3.4 Z \
                    M3.6 9.4 H20.4 M3.6 14.6 H20.4 \
                    M12 3.4 C14.2 5.8 15.3 8.8 15.3 12 C15.3 15.2 14.2 18.2 12 20.6 \
                    C9.8 18.2 8.7 15.2 8.7 12 C8.7 8.8 9.8 5.8 12 3.4 Z",
        /*
          A globe, for an agent's public face.

          One equator and one meridian, where "network" has two latitude lines
          and a meridian. They are near neighbours on purpose and have to stay
          distinguishable at fifteen pixels, because the rail draws this one and
          the access rules draw the other — "the page anybody can open" and "may
          this agent reach the network" are not a thing to confuse.
        */
        "globe": "M12 3.4 C16.7 3.4 20.6 7.3 20.6 12 C20.6 16.7 16.7 20.6 12 20.6 \
                  C7.3 20.6 3.4 16.7 3.4 12 C3.4 7.3 7.3 3.4 12 3.4 Z \
                  M3.6 12 H20.4 \
                  M12 3.4 C14.2 5.8 15.3 8.8 15.3 12 C15.3 15.2 14.2 18.2 12 20.6 \
                  C9.8 18.2 8.7 15.2 8.7 12 C8.7 8.8 9.8 5.8 12 3.4 Z",
        // A machine inside a machine: the outer frame is the host, the inner
        // one the slot carved out of it.
        "vm": "M3.4 5 H20.6 V19 H3.4 Z M6.6 8.6 H14.2 V15.4 H6.6 Z \
               M16.6 10.6 H18.6 M16.6 13.4 H18.6",

        // ---- Artifact kinds -------------------------------------------------
        //
        // One mark per kind of artifact, matching the web app's table of them. An
        // artifact is drawn from its *kind*, on every surface in the product,
        // rather than from a picture somebody uploaded. These are the same shapes
        // the web app renders through MUI, redrawn as geometry because Qt cannot
        // import an icon font it does not have.
        //
        // `terminal` is the APPLICATION mark and is already defined above, beside the
        // other console shapes.

        /*
          The two rooms an agent draws for itself, and neither is an artifact
          kind. They sit here because they are drawn by one: whatever a
          Workbench or a Brain shows arrives as a component, and these marks
          are the rail's name for the room rather than for its contents.

          `widgets` below is the COMPONENT mark and is used for the Workbench
          too, which is not a collision — a Workbench *is* a surface made of
          components, and the two readings agree.
        */

        /**
         * BRAIN — a head in profile with a fold across it.
         *
         * Drawn rather than borrowed. `spark` was the obvious candidate and is
         * already the mark for a turn arriving, and a glyph meaning two things
         * in one application is a glyph meaning neither. Two strokes, so it
         * still reads at 16px where anything more becomes a smudge.
         */
        "brain": "M9.6 3.6 C6.2 3.6 4 6 4 9 C4 10.4 4.5 11.6 5.3 12.5 \
                  C4.7 13.2 4.4 14.1 4.4 15.1 C4.4 17.8 6.6 20 9.4 20 \
                  C10.9 20 12 19.4 12 19.4 V4.9 C12 4.9 11.1 3.6 9.6 3.6 Z \
                  M14.4 3.6 C17.8 3.6 20 6 20 9 C20 10.4 19.5 11.6 18.7 12.5 \
                  C19.3 13.2 19.6 14.1 19.6 15.1 C19.6 17.8 17.4 20 14.6 20 \
                  C13.1 20 12 19.4 12 19.4 \
                  M12 4.9 C12 4.9 12.9 3.6 14.4 3.6 \
                  M8.4 9 H12 M12 14.2 H15.6",

        /** COMPONENT — interlocking widgets: a part you build something from. */
        "widgets": "M4 4.6 H10.4 V11 H4 Z M13.6 4.6 H20 V11 H13.6 Z \
                    M4 13 H10.4 V19.4 H4 Z M13.6 13 H20 V19.4 H13.6 Z",

        /** IOT — radiating sensor lines: the artifact that reaches hardware. */
        "sensors": "M12 10.6 C12.8 10.6 13.4 11.2 13.4 12 C13.4 12.8 12.8 13.4 12 13.4 \
                    C11.2 13.4 10.6 12.8 10.6 12 C10.6 11.2 11.2 10.6 12 10.6 Z \
                    M8.6 8.6 C6.7 10.5 6.7 13.5 8.6 15.4 \
                    M15.4 8.6 C17.3 10.5 17.3 13.5 15.4 15.4 \
                    M5.8 5.8 C2.4 9.2 2.4 14.8 5.8 18.2 \
                    M18.2 5.8 C21.6 9.2 21.6 14.8 18.2 18.2",

        /** PLUGIN — a jigsaw piece: it slots into an agent already running. */
        "extension": "M9.4 4 C9.4 3 10.2 2.4 11.2 2.4 H12.8 C13.8 2.4 14.6 3 14.6 4 \
                      V5.6 H18.4 V9.4 H20 C21 9.4 21.6 10.2 21.6 11.2 V12.8 \
                      C21.6 13.8 21 14.6 20 14.6 H18.4 V19.4 H4.6 V14.6 H6.2 \
                      C7.2 14.6 7.8 13.8 7.8 12.8 V11.2 C7.8 10.2 7.2 9.4 6.2 9.4 \
                      H4.6 V5.6 H9.4 Z",

        /*
          GADGET — a cable with a plug at each end: the artifact whose whole job
          is joining two things together.

          It was a sealed box while the kind was called `PACKAGE`, and the box
          drew the same mistake the name did — a container is what every kind
          arrives in, so it said nothing about any of them. A gadget is a Simorg
          program that connects artifacts, machines and agents, and this is that
          sentence as a shape. Matches `CableRounded` in the web app's
          `ARTIFACT_TYPE_ICON`.
        */
        "gadget": "M16.6 2.6 V4.6 M19 2.6 V4.6 \
                   M14.8 4.6 H20.8 V9 H14.8 Z \
                   M17.8 9 C17.8 13.4 6.2 10.6 6.2 15 \
                   M3.2 15 H9.2 V19.4 H3.2 Z \
                   M5 19.4 V21.4 M7.4 19.4 V21.4",

        /*
          AGENT — a head with an antenna: the one artifact an agent does not
          publish but *is*. An `APPLICATION` draws `terminal`, defined above.
        */
        "agent": "M12 2.8 V5.4 M10.6 2.8 H13.4 \
                  M6.6 5.4 H17.4 C18.6 5.4 19.4 6.2 19.4 7.4 V15.6 \
                  C19.4 16.8 18.6 17.6 17.4 17.6 H6.6 \
                  C5.4 17.6 4.6 16.8 4.6 15.6 V7.4 \
                  C4.6 6.2 5.4 5.4 6.6 5.4 Z \
                  M2.4 9.8 V13.2 M21.6 9.8 V13.2 \
                  M9 9.8 V12.2 M15 9.8 V12.2 \
                  M9.4 14.8 H14.6 \
                  M8.2 17.6 V21.2 M15.8 17.6 V21.2"
    })

    /*
      Names the platform's access catalogue uses for a permission's icon that are
      drawn with a glyph of another name. The catalogue names `logos` for
      Applications — the panel draws it as a grid of apps — and without this the
      desktop drew nothing at all beside the one permission about applications.
    */
    readonly property var aliases: ({ "logos": "widgets" })
    readonly property string pathData: paths[name] !== undefined ? paths[name]
                                       : (aliases[name] !== undefined ? paths[aliases[name]] : "")

    Shape {
        anchors.fill: parent
        antialiasing: true
        visible: root.pathData.length > 0

        // Authored on a 24-unit grid; scaled to whatever the caller asked for.
        transform: Scale {
            xScale: root.size / 24
            yScale: root.size / 24
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.tone
            strokeWidth: root.thickness * 24 / root.size
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.pathData }
        }
    }
}
