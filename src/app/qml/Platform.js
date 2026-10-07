// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
.pragma library

/**
 * What kind of thing this is, as a mark rather than a picture.
 *
 * Two tables, both mirrors of the web app's, both here for the same reason: the
 * platform identifies an artifact and a machine by their *kind* rather than by
 * an uploaded image, which almost nobody would set and which tells a reader
 * nothing.
 *
 * A `.pragma library` rather than functions on a component: the same question is
 * asked from the artifact list, the machine card and anywhere else a row shows
 * one of these, and three copies of a lookup table is three copies that drift.
 *
 * The web halves live in Simorg's web app. Change one, change the other — the
 * *shapes* differ because Qt cannot import MUI, but which mark means
 * "plugin" and which name means "Ubuntu" must not.
 */

/**
 * The `Glyph` name for an artifact kind.
 *
 * Falls back to the application mark for a kind this build does not recognise, the
 * same as the web app does: a blank square where an icon belongs reads as a bug,
 * and every artifact is at least something you can run.
 */
function glyphForArtifactKind(kind) {
    switch (String(kind === undefined || kind === null ? "" : kind).toUpperCase()) {
    case "COMPONENT": return "widgets";
    case "IOT": return "sensors";
    case "PLUGIN": return "extension";
    /* `PACKAGE` is what `GADGET` was called; an older runtime still sends it. */
    case "GADGET":
    case "PACKAGE": return "gadget";
    case "AGENT": return "agent";
    default: return "terminal";
    }
}

/**
 * Which operating-system mark to draw, from whatever a device called itself.
 *
 * Substring matching rather than equality, because the reported name ranges from
 * a clean `macOS` to `Ubuntu 24.04.1 LTS` to a bare `Linux`, and refusing to
 * recognise the long ones would put a blank square beside a perfectly ordinary
 * machine.
 *
 * Order matters where names nest: `ios` is tested first because an iPhone
 * reports a string containing neither "mac" nor "darwin", and `debian` last
 * because Ubuntu and Raspberry Pi OS are both Debian derivatives that sometimes
 * say so — the more specific answer is the more useful one.
 */
function osKey(osName) {
    var name = String(osName === undefined || osName === null ? "" : osName).toLowerCase();
    if (name.length === 0) return "generic";

    if (/\b(ios|ipados|iphone|ipad)\b/.test(name)) return "ios";
    if (name.indexOf("mac") >= 0 || name.indexOf("darwin") >= 0 || name.indexOf("osx") >= 0) return "macos";
    if (name.indexOf("android") >= 0) return "android";
    if (name.indexOf("windows") >= 0 || name.indexOf("win32") >= 0) return "windows";
    if (name.indexOf("raspberr") >= 0 || name.indexOf("raspbian") >= 0) return "raspberry";
    if (name.indexOf("ubuntu") >= 0 || name.indexOf("pop!") >= 0 || name.indexOf("mint") >= 0) return "ubuntu";
    if (name.indexOf("fedora") >= 0 || name.indexOf("red hat") >= 0 || name.indexOf("rhel") >= 0) return "fedora";
    if (name.indexOf("arch") >= 0 || name.indexOf("manjaro") >= 0) return "arch";
    if (name.indexOf("alpine") >= 0) return "alpine";
    if (name.indexOf("suse") >= 0) return "suse";
    if (name.indexOf("debian") >= 0) return "debian";
    if (name.indexOf("linux") >= 0 || name.indexOf("centos") >= 0 || name.indexOf("rocky") >= 0
        || name.indexOf("alma") >= 0 || name.indexOf("gentoo") >= 0 || name.indexOf("nix") >= 0) {
        return "linux";
    }
    return "generic";
}

