// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
pragma Singleton

import QtQuick

/**
 * The Simorg design language, in whichever mode the signed-in account asked for.
 *
 * Same palette, same gradients, same motion curves as the web console — cyan on
 * the demand side, violet on the provider side, amber for the flywheel — so the
 * desktop app reads as the same product as the Simorg web console.
 *
 * ## Where the colours come from
 *
 * Not from here. Every colour below is a one-line alias onto `ThemeTokens`,
 * which is generated from Simorg's design tokens — the same table the three
 * web apps compile into CSS custom properties. Adding a colour here
 * rather than there forks the design language, and the fork would only be
 * visible on one of the four surfaces.
 *
 * ## Switching
 *
 * `dark` is set once from the session (see Main.qml) and re-set whenever the
 * account changes. Because every screen binds through these aliases rather than
 * naming a colour, flipping that one boolean repaints the whole application —
 * no reload, no re-instantiation, nothing to remember to update.
 *
 * Nothing here is computed per-frame: every value is a constant, or a binding
 * on a single boolean, that another binding can depend on cheaply.
 */
QtObject {
    id: theme

    // ---- Mode ----------------------------------------------------------
    /**
     * Which palette is live.
     *
     * Defaults to dark, which is both the theme the app shipped with and what
     * an account with no stored preference gets. Qt exposes no system-level
     * light/dark signal to Qt Quick on any of the three platforms, so there is
     * nothing to fall back to but the account.
     */
    property bool dark: true

    readonly property QtObject palette: dark ? ThemeTokens.darkPalette : ThemeTokens.lightPalette

    // ---- Accents -------------------------------------------------------
    readonly property color cyan: palette.accentCyan
    readonly property color sky: palette.accentSky
    readonly property color blue: palette.accentBlue
    readonly property color indigo: palette.accentIndigo
    readonly property color violet: palette.accentViolet
    readonly property color amber: palette.accentAmber
    readonly property color emerald: palette.accentEmerald
    readonly property color rose: palette.accentRose

    // ---- Surfaces ------------------------------------------------------
    /** Deepest background; the colour the window paints before anything else. */
    readonly property color base: palette.layerVoid
    /** The web's `layer-950`: the ground an identity's picture and initials sit on. */
    readonly property color layer950: palette.layer950
    readonly property color baseMid: palette.layerVoidMid
    readonly property color baseHigh: palette.layerVoidHigh
    readonly property color surface: palette.surfaceCardFrom
    readonly property color surfaceDeep: palette.surfaceCardTo
    readonly property color inset: palette.surfaceInset

    readonly property color borderSubtle: palette.borderSubtle
    readonly property color borderStrong: palette.borderStrong
    readonly property color borderFocus: palette.borderFocus

    // ---- Text ----------------------------------------------------------
    readonly property color textPrimary: palette.textPrimary
    readonly property color textBody: palette.textBody
    readonly property color textMuted: palette.textMuted
    readonly property color textFaint: palette.textFaint
    /** On a filled brand surface — a gradient button, a solid accent chip. */
    readonly property color textOnAccent: palette.textOnAccent

    /** Informational text, in light and dark alike. */
    readonly property color info: palette.info
    readonly property color infoSurface: palette.infoSurface
    readonly property color danger: palette.danger
    readonly property color dangerSurface: palette.dangerSurface

    // ---- Logs ----------------------------------------------------------
    /**
     * One colour per level the engine writes into an agent's log line, every
     * one of them held to 4.5:1 in both modes, washes included.
     */
    readonly property color logDebug: palette.logDebug
    readonly property color logInfo: palette.logInfo
    readonly property color logWarning: palette.logWarning
    readonly property color logWarningSurface: palette.logWarningSurface
    readonly property color logWarningBorder: palette.logWarningBorder
    readonly property color logError: palette.logError
    readonly property color logErrorSurface: palette.logErrorSurface
    readonly property color logErrorBorder: palette.logErrorBorder
    readonly property color logFatal: palette.logFatal
    readonly property color logOnFatal: palette.logOnFatal
    readonly property color logUser: palette.logUser
    readonly property color logUserDebug: palette.logUserDebug

    // ---- Gradients -----------------------------------------------------
    /** Edge of the platform hexagon: cyan → blue → violet. */
    readonly property var brandGradientStops: [palette.brandStopFrom,
                                               palette.brandStopMid,
                                               palette.brandStopTo]
    /**
     * Wordmark and headings: sky → periwinkle → light violet on dark, and the
     * same sweep in saturated mid-tones on light.
     *
     * Declared as `color` properties first so the array holds real colours.
     * String literals in a `var` array stay strings, and anything that reads
     * `.r`/`.g`/`.b` off them — GradientText does — gets undefined back.
     */
    readonly property color headingFrom: palette.headingStopFrom
    readonly property color headingMid: palette.headingStopMid
    readonly property color headingTo: palette.headingStopTo
    readonly property var headingGradientStops: [headingFrom, headingMid, headingTo]
    readonly property color ctaFrom: palette.ctaStopFrom
    readonly property color ctaTo: palette.ctaStopTo
    readonly property color ctaFromHover: palette.ctaStopFromHover
    readonly property color ctaToHover: palette.ctaStopToHover

    // ---- Metrics -------------------------------------------------------
    /**
     * Corners, kept deliberately tight.
     *
     * A large radius reads as friendly and consumer; a small one reads as
     * precise. This application asks somebody to hand an agent their files,
     * their network and their terminal, and the surface making that request
     * should look like an instrument rather than a toy. So the scale is short
     * and shallow: enough to soften a corner, never enough to round it.
     *
     * `radiusPill` is the exception and is for things that are genuinely
     * circular — a status dot, an avatar — where the shape is the meaning
     * rather than a decoration. **It is not for buttons.**
     */
    readonly property int radiusSmall: 3
    readonly property int radiusBase: 5
    readonly property int radiusLarge: 8
    readonly property int radiusPill: 999

    readonly property int spaceXs: 6
    readonly property int spaceSm: 10
    readonly property int spaceMd: 16
    readonly property int spaceLg: 24
    readonly property int spaceXl: 36

    // ---- Typography ----------------------------------------------------
    /**
     * The platform's own UI face — San Francisco, Segoe UI, or whatever the
     * Linux desktop is set to — read from the application's default font. A
     * bundled face would look foreign on at least two of the three platforms.
     *
     * Never the empty string. An empty family does not mean "the default" to
     * Qt: it asks the font database for a family with no name, and on Windows
     * that resolves to MS Sans Serif, a bitmap face from Windows 3.1 with no
     * bold and no antialiasing, so every heading, link and text field set in it
     * would come out thin and jagged. On macOS the same request happens to land
     * on the system face, which is why it is easy to miss.
     */
    readonly property string fontFamily: Qt.application.font.family
    // Menlo rather than SF Mono: SF Mono is not registered under that family
    // name on a stock macOS, and asking for a missing family costs Qt a full
    // font-alias scan on first use.
    readonly property string monoFamily: Qt.platform.os === "windows" ? "Consolas"
                                       : Qt.platform.os === "osx" ? "Menlo" : "monospace"

    readonly property int fontDisplay: 30
    readonly property int fontTitle: 21
    readonly property int fontBody: 14
    readonly property int fontSmall: 13
    readonly property int fontEyebrow: 11

    // ---- Motion --------------------------------------------------------
    /** Set by SIMORG_REDUCED_MOTION; every animation in the app honours it. */
    property bool motion: true

    readonly property int durFast: 140
    readonly property int durBase: 240
    readonly property int durSlow: 420
    readonly property int durReveal: 520

    /** cubic-bezier(0.22, 1, 0.36, 1) — the "settle" curve used across the web console. */
    readonly property var easeOut: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
    /** cubic-bezier(0.4, 0, 0.2, 1) — symmetric, for colour and opacity. */
    readonly property var easeInOut: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]

    /** Duration that collapses to zero when motion is off. */
    function duration(ms) {
        return theme.motion ? ms : 0;
    }

    // ---- Helpers -------------------------------------------------------
    /** Same colour at a different opacity. */
    function alpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    /** Mixes two colours; `t` runs 0 → `from`, 1 → `to`. */
    function mix(from, to, t) {
        return Qt.rgba(from.r + (to.r - from.r) * t,
                       from.g + (to.g - from.g) * t,
                       from.b + (to.b - from.b) * t,
                       from.a + (to.a - from.a) * t);
    }
}
