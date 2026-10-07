#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
"""Simorg Desktop's application icons, drawn from the Simorg mark.

    scripts/make-icons.sh            what to run: this, in a pinned container
    python3 make_icons.py --check    only say whether the committed files are current

The mark (resources/branding/simorg-logo.svg), extruded towards the bottom and
lit from above: on macOS and Linux raised on a white plate with continuous
("squircle") corners, the way macOS draws its own apps; on Windows standing on
its own, the way Windows 11 draws its. Everything below is written from that one
file, so changing the mark and running this again is the whole of a rebrand:

    packaging/macos/Simorg.icns                      the Finder and Dock icon
    packaging/windows/simorg.ico                     the programs' icon resource (and so
                                                     their windows), the Start menu and
                                                     Apps & Features
    packaging/windows/installer-dialog.bmp           the installer's first and last page
    packaging/windows/installer-banner.bmp           the installer's other pages
    packaging/macos/dmg-background.png, @2x.png      behind the .dmg's window, saying to
                                                     drag Simorg onto Applications
    resources/branding/app-icon/simorg-<N>.png       the Linux window icon and hicolor
                                                     icons at each size
    resources/branding/app-icon/simorg-app-icon.svg  the Linux scalable icon

Each platform gets its own geometry rather than one picture scaled:

  macOS    Apple's app icon grid: an 824-unit plate on a 1024 canvas, 100 units
           clear all round for the system's shadow and the Dock's magnification.
  Linux    The plate fills the canvas: freedesktop desktops neither mask nor pad
           icons, and draw them at 16 to 48 pixels far more often than at 256,
           where a macOS margin would only make the mark smaller.
  Windows  Microsoft's Windows 11 app icon guidance: no backplate — the mark is
           the icon, front-facing, lit from the top, filling the canvas — with a
           soft two-layer shadow from 48 pixels up and none below, where it
           would only blur the edge.

And each size its own drawing: at 16 to 32 pixels the mark takes more of the
plate (on Windows, more of the canvas, and its strokes are thickened by half a
pixel so the wings stay lines), the extrusion stays at least half a pixel deep so
the edge still reads, and the soft shadows, which would only blur a small icon,
are left out.

Only the Python standard library and `rsvg-convert` (librsvg 2.50 or later, for
the SVG filters), with the Inter typeface installed for the one line of words
on the .dmg's picture. PNG decoding and the ICO, ICNS and BMP containers are
written here, so the output does not depend on which imaging library a machine
has.
"""

import argparse
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

LOGO = os.path.join(ROOT, "resources", "branding", "simorg-logo.svg")
APP_ICON_DIR = os.path.join(ROOT, "resources", "branding", "app-icon")
ICNS = os.path.join(ROOT, "packaging", "macos", "Simorg.icns")
ICO = os.path.join(ROOT, "packaging", "windows", "simorg.ico")
DIALOG_BMP = os.path.join(ROOT, "packaging", "windows", "installer-dialog.bmp")
BANNER_BMP = os.path.join(ROOT, "packaging", "windows", "installer-banner.bmp")
DMG_BACKGROUND = os.path.join(ROOT, "packaging", "macos", "dmg-background.png")
DMG_BACKGROUND_2X = os.path.join(ROOT, "packaging", "macos", "dmg-background@2x.png")

# The .dmg window's geometry, in points, which every Simorg application's disk
# image shares: the layout places the icons there, and the picture is drawn to
# the same numbers. The window is measured title bar included.
DMG_WINDOW = (680, 380)
DMG_APP_AT = (170, 150)
DMG_APPLICATIONS_AT = (510, 150)

CANVAS = 1024.0

# The sizes each container carries.
#
# Windows asks for 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80 and 96 at the
# scale factors between 100 % and 400 %, and 256 for Explorer's large views; a
# size that is missing is scaled from the next one up and comes out soft.
ICO_SIZES = [16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 128, 256]
# Below this, a 32-bit DIB rather than PNG: what every Windows reader accepts.
ICO_PNG_FROM = 64
# The freedesktop hicolor theme's usual sizes; also the window icon's.
LINUX_SIZES = [16, 22, 24, 32, 48, 64, 128, 256, 512]
# (type, pixels): what iconutil writes for a full .iconset, 16 pt to 512 pt @2x.
ICNS_ENTRIES = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128),
    ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
]

BRAND_BLUE = "#007fff"


# ---------------------------------------------------------------- the mark ----

def read_mark():
    """The mark's drawing, its fills taken off so each layer can paint it its own way."""
    with open(LOGO, encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    view_box = re.search(r'viewBox="([^"]+)"', text)
    if not view_box:
        sys.exit(f"make_icons: {LOGO} has no viewBox")
    _, _, width, height = (float(v) for v in view_box.group(1).split())
    inner = re.search(r"<svg[^>]*>(.*)</svg>", text, flags=re.S).group(1)
    inner = re.sub(r'\s+fill="[^"]*"', "", inner).strip()
    return inner, width, height


def mark_bounds(inner, width, height, rsvg):
    """The mark's inked box in its own units, measured from a render: the file's
    viewBox has a margin of its own, and the plate is laid out around the ink."""
    size = 2048
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           f'width="{size}" height="{size}" viewBox="0 0 {width} {height}">'
           f'<g fill="#000">{inner}</g></svg>')
    w, h, pixels = decode_png(rasterise(rsvg, svg, size, size))
    left, top, right, bottom = w, h, -1, -1
    for y in range(h):
        row = pixels[y * w * 4:(y + 1) * w * 4]
        alphas = row[3::4]
        if not any(alphas):
            continue
        top = min(top, y)
        bottom = y
        first = next(i for i, a in enumerate(alphas) if a)
        last = w - 1 - next(i for i, a in enumerate(reversed(alphas)) if a)
        left = min(left, first)
        right = max(right, last)
    scale = width / w
    return (left * scale, top * scale, (right + 1) * scale, (bottom + 1) * scale)


# ---------------------------------------------------------------- geometry ----

def smooth_rect(x, y, w, h, radius, smoothing=0.6):
    """A rounded rectangle with continuous corners, as Apple draws its icon plate.

    Figma's corner smoothing (the construction in "Desperately seeking
    squircles"): each corner is a Bezier ramp, a circular arc of 90*(1 -
    smoothing) degrees, and a ramp back, so the curvature grows from the
    straight edge instead of jumping to 1/radius where a plain arc begins. At
    radius 22.5 % and smoothing 0.6 it matches the macOS 11+ app icon shape.
    """
    r = radius
    p = (1 + smoothing) * r
    p = min(p, w / 2, h / 2)
    arc_measure = 90 * (1 - smoothing)
    arc = math.sin(math.radians(arc_measure / 2)) * r * math.sqrt(2)
    alpha = (90 - arc_measure) / 2
    p3_p4 = r * math.tan(math.radians(alpha / 2))
    beta = 45 * smoothing
    c = p3_p4 * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - arc - c - d) / 3
    a = 2 * b

    def f(v):
        return f"{v:.3f}".rstrip("0").rstrip(".")

    return " ".join([
        f"M {f(x + w - p)} {f(y)}",
        f"c {f(a)} 0 {f(a + b)} 0 {f(a + b + c)} {f(d)}",
        f"a {f(r)} {f(r)} 0 0 1 {f(arc)} {f(arc)}",
        f"c {f(d)} {f(c)} {f(d)} {f(b + c)} {f(d)} {f(a + b + c)}",
        f"L {f(x + w)} {f(y + h - p)}",
        f"c 0 {f(a)} 0 {f(a + b)} {f(-d)} {f(a + b + c)}",
        f"a {f(r)} {f(r)} 0 0 1 {f(-arc)} {f(arc)}",
        f"c {f(-c)} {f(d)} {f(-(b + c))} {f(d)} {f(-(a + b + c))} {f(d)}",
        f"L {f(x + p)} {f(y + h)}",
        f"c {f(-a)} 0 {f(-(a + b))} 0 {f(-(a + b + c))} {f(-d)}",
        f"a {f(r)} {f(r)} 0 0 1 {f(-arc)} {f(-arc)}",
        f"c {f(-d)} {f(-c)} {f(-d)} {f(-(b + c))} {f(-d)} {f(-(a + b + c))}",
        f"L {f(x)} {f(y + p)}",
        f"c 0 {f(-a)} 0 {f(-(a + b))} {f(d)} {f(-(a + b + c))}",
        f"a {f(r)} {f(r)} 0 0 1 {f(arc)} {f(-arc)}",
        f"c {f(c)} {f(-d)} {f(b + c)} {f(-d)} {f(a + b + c)} {f(-d)}",
        "Z",
    ])


def mix(a, b, t):
    """Two #rrggbb colours, `t` of the way from the first to the second."""
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


# -------------------------------------------------------------------- icon ----

def icon_svg(mark, pixels, flavour):
    """One icon as SVG on the 1024 canvas, drawn for `pixels` pixels.

    flavour is "macos" (Apple's grid), "plate" (Linux) or "windows" (no plate)."""
    if flavour == "windows":
        return windows_svg(mark, pixels)
    inner, mark_w, mark_h, bounds = mark
    unit = CANVAS / pixels                      # canvas units in one output pixel
    small = pixels <= 32
    tiny = pixels <= 24

    if flavour == "macos":
        # Apple's app icon template: the plate is 824 of 1024, 100 all round.
        px, py, pw = 100.0, 100.0, 824.0
        radius = 185.4
    else:
        # A little room at the sides and more below, for the shadow; at least
        # half a pixel so the edge is not cut off at 16 pixels.
        side = max(34.0, 0.5 * unit)
        top = max(26.0, 0.5 * unit)
        bottom = max(46.0, 1.0 * unit)
        px, py = side, top
        pw = CANVAS - 2 * side
        pw = min(pw, CANVAS - top - bottom)
        px = (CANVAS - pw) / 2
        radius = 0.215 * pw
    ph = pw

    # How much of the plate the mark takes. Larger when small, where every pixel
    # of the mark is one fewer of the plate's white.
    share = 0.66 if pixels >= 64 else 0.69 if pixels >= 48 else 0.72 if pixels >= 32 else 0.78
    left, top_, right, bottom_ = bounds
    ink_w, ink_h = right - left, bottom_ - top_
    size = pw * share
    scale = size / max(ink_w, ink_h)
    depth = max(0.028 * size, 0.55 * unit)      # the extrusion, never under half a pixel
    cx = px + pw / 2
    cy = py + ph / 2 - depth / 2                # face and extrusion centred together
    tx = cx - scale * (left + ink_w / 2)
    ty = cy - scale * (top_ + ink_h / 2)
    face_top = cy - scale * ink_h / 2
    face_bottom = cy + scale * ink_h / 2

    plate = smooth_rect(px, py, pw, ph, radius)
    border = max(3.0, 0.8 * unit)
    border_opacity = 0.24 if small else 0.14
    inset = smooth_rect(px + border / 2, py + border / 2, pw - border, ph - border,
                        max(radius - border / 2, 0))

    steps = max(2, min(48, math.ceil(depth / 0.5)))
    extrusion = []
    for i in range(steps, 0, -1):
        offset = depth * i / steps
        colour = mix("#0b5cc9", "#05306b", i / steps)
        extrusion.append(f'<use xlink:href="#mark" transform="translate(0 {offset:.3f})" fill="{colour}"/>')

    # Shadows are measured in canvas units and scaled with the plate. At 32
    # pixels and below they would only soften the edge, so they are left out.
    if flavour == "macos":
        plate_shadow = [(14, 12, 0.30), (2.5, 2.5, 0.22)]
    else:
        plate_shadow = [(10, 9, 0.28), (1.6, 1.8, 0.24)]

    defs = [
        f'<g id="mark" transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f})">{inner}</g>',
        '<linearGradient id="plateFill" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#ffffff"/><stop offset="0.55" stop-color="#f4f7fb"/>'
        '<stop offset="1" stop-color="#e4e9f1"/></linearGradient>',
        f'<linearGradient id="face" gradientUnits="userSpaceOnUse" x1="0" y1="{face_top:.2f}" x2="0" y2="{face_bottom:.2f}">'
        '<stop offset="0" stop-color="#5ab5ff"/><stop offset="0.42" stop-color="#1b8cff"/>'
        '<stop offset="1" stop-color="#0068e0"/></linearGradient>',
    ]
    body = []

    if not small:
        merge = []
        prims = []
        for n, (blur, dy, opacity) in enumerate(plate_shadow):
            prims.append(f'<feGaussianBlur in="SourceAlpha" stdDeviation="{blur}" result="b{n}"/>'
                         f'<feOffset in="b{n}" dy="{dy}" result="o{n}"/>'
                         f'<feFlood flood-color="#0a1a33" flood-opacity="{opacity}"/>'
                         f'<feComposite in2="o{n}" operator="in" result="s{n}"/>')
            merge.append(f'<feMergeNode in="s{n}"/>')
        defs.append('<filter id="plateShadow" x="-10%" y="-10%" width="120%" height="125%">'
                    + "".join(prims) + "<feMerge>" + "".join(merge) + "</feMerge></filter>")
        body.append(f'<path d="{plate}" fill="#000" filter="url(#plateShadow)"/>')

    body.append(f'<path d="{plate}" fill="url(#plateFill)"/>')
    body.append(f'<path d="{inset}" fill="none" stroke="#1a2c4d" stroke-opacity="{border_opacity}" '
                f'stroke-width="{border:.2f}"/>')
    if pixels >= 64:
        # A catch of light along the top edge of the plate, inside it.
        defs.append(f'<clipPath id="plateClip"><path d="{plate}"/></clipPath>')
        body.append(f'<path d="{smooth_rect(px, py + 3.5, pw, ph, radius)}" fill="none" stroke="#ffffff" '
                    f'stroke-opacity="0.9" stroke-width="5" clip-path="url(#plateClip)"/>')

    if not tiny:
        # The raised mark's own shadow on the plate: wide and soft, and a tight
        # one where it meets the plate.
        defs.append('<filter id="markShadow" x="-20%" y="-20%" width="140%" height="150%">'
                    '<feGaussianBlur in="SourceAlpha" stdDeviation="10" result="b1"/>'
                    '<feOffset in="b1" dy="16" result="o1"/>'
                    '<feFlood flood-color="#08244f" flood-opacity="0.30"/><feComposite in2="o1" operator="in" result="s1"/>'
                    '<feGaussianBlur in="SourceAlpha" stdDeviation="2.5" result="b2"/>'
                    '<feOffset in="b2" dy="4" result="o2"/>'
                    '<feFlood flood-color="#08244f" flood-opacity="0.28"/><feComposite in2="o2" operator="in" result="s2"/>'
                    '<feMerge><feMergeNode in="s1"/><feMergeNode in="s2"/></feMerge></filter>')
        body.append('<g filter="url(#markShadow)" fill="#000">'
                    f'<use xlink:href="#mark" transform="translate(0 {depth:.3f})"/><use xlink:href="#mark"/></g>')

    body.append("<g>" + "".join(extrusion) + "</g>")

    if pixels >= 48:
        # Light from above: a bright rim along every upward-facing edge of the face.
        defs.append('<filter id="rim" x="-5%" y="-5%" width="110%" height="110%">'
                    f'<feOffset in="SourceAlpha" dy="{max(3.0, 0.7 * unit):.2f}" result="down"/>'
                    '<feComposite in="SourceAlpha" in2="down" operator="out" result="edge"/>'
                    '<feGaussianBlur in="edge" stdDeviation="0.8" result="soft"/>'
                    '<feFlood flood-color="#ffffff" flood-opacity="0.6"/>'
                    '<feComposite in2="soft" operator="in" result="light"/>'
                    '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="light"/></feMerge></filter>')
        body.append('<g filter="url(#rim)"><use xlink:href="#mark" fill="url(#face)"/></g>')
    else:
        body.append('<use xlink:href="#mark" fill="url(#face)"/>')

    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{pixels}" height="{pixels}" viewBox="0 0 1024 1024">'
            "<defs>" + "".join(defs) + "</defs>" + "".join(body) + "</svg>")


def windows_svg(mark, pixels):
    """The Windows icon: the mark on its own, as Windows 11 draws app icons.

    Microsoft's guidance for Windows 11 app icons is a single front-facing
    shape with no backplate, lit from the top, using the whole canvas, with a
    soft shadow only where it has room to be soft. So the mark takes most of
    the canvas (86 % from 64 pixels up, all but half a pixel at 16), keeps its
    extrusion and highlight as the depth Fluent icons have, and is thickened at
    16 to 32 pixels, where its wings would otherwise be lines thinner than a
    pixel. The brand blue has the contrast Windows asks for against both the
    light and the dark taskbar, so it needs no outline."""
    inner, mark_w, mark_h, bounds = mark
    unit = CANVAS / pixels
    left, top_, right, bottom_ = bounds
    ink_w, ink_h = right - left, bottom_ - top_

    share = 0.86 if pixels >= 64 else 0.90 if pixels >= 48 else 0.94 if pixels >= 32 else 0.97
    size = CANVAS * share
    scale = size / max(ink_w, ink_h)
    depth = max(0.018 * size, 0.5 * unit)
    # Thickened where a stroke would be thinner than a pixel.
    boost = 0.45 * unit if pixels <= 32 else 0.0
    shadowed = pixels >= 48
    # Centred with its extrusion, and lifted a little for the shadow below it.
    lift = 0.012 * CANVAS if shadowed else 0.0
    cx = CANVAS / 2
    cy = CANVAS / 2 - depth / 2 - lift
    tx = cx - scale * (left + ink_w / 2)
    ty = cy - scale * (top_ + ink_h / 2)
    face_top = cy - scale * ink_h / 2
    face_bottom = cy + scale * ink_h / 2

    stroke = (f' stroke-width="{boost / scale:.4f}" stroke-linejoin="round"' if boost else "")
    defs = [
        f'<g id="mark" transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f})"{stroke}>{inner}</g>',
        f'<linearGradient id="face" gradientUnits="userSpaceOnUse" x1="0" y1="{face_top:.2f}" x2="0" y2="{face_bottom:.2f}">'
        '<stop offset="0" stop-color="#5ab5ff"/><stop offset="0.42" stop-color="#1b8cff"/>'
        '<stop offset="1" stop-color="#0068e0"/></linearGradient>',
    ]
    body = []

    if shadowed:
        # Fluent's two shadows: a soft key light's below, and a tight ambient one.
        defs.append('<filter id="fluentShadow" x="-15%" y="-15%" width="130%" height="140%">'
                    '<feGaussianBlur in="SourceAlpha" stdDeviation="14" result="b1"/>'
                    '<feOffset in="b1" dy="14" result="o1"/>'
                    '<feFlood flood-color="#061a3a" flood-opacity="0.26"/><feComposite in2="o1" operator="in" result="s1"/>'
                    '<feGaussianBlur in="SourceAlpha" stdDeviation="4" result="b2"/>'
                    '<feOffset in="b2" dy="3" result="o2"/>'
                    '<feFlood flood-color="#061a3a" flood-opacity="0.18"/><feComposite in2="o2" operator="in" result="s2"/>'
                    '<feMerge><feMergeNode in="s1"/><feMergeNode in="s2"/></feMerge></filter>')
        body.append('<g filter="url(#fluentShadow)" fill="#000">'
                    f'<use xlink:href="#mark" transform="translate(0 {depth:.3f})"/><use xlink:href="#mark"/></g>')

    steps = max(2, min(48, math.ceil(depth / 0.5)))
    extrusion = []
    for i in range(steps, 0, -1):
        colour = mix("#0b5cc9", "#05306b", i / steps)
        paint = f'fill="{colour}"' + (f' stroke="{colour}"' if boost else "")
        extrusion.append(f'<use xlink:href="#mark" transform="translate(0 {depth * i / steps:.3f})" {paint}/>')
    body.append("<g>" + "".join(extrusion) + "</g>")

    face_paint = 'fill="url(#face)"' + (' stroke="url(#face)"' if boost else "")
    if pixels >= 48:
        defs.append('<filter id="rim" x="-5%" y="-5%" width="110%" height="110%">'
                    f'<feOffset in="SourceAlpha" dy="{max(3.0, 0.7 * unit):.2f}" result="down"/>'
                    '<feComposite in="SourceAlpha" in2="down" operator="out" result="edge"/>'
                    '<feGaussianBlur in="edge" stdDeviation="0.8" result="soft"/>'
                    '<feFlood flood-color="#ffffff" flood-opacity="0.55"/>'
                    '<feComposite in2="soft" operator="in" result="light"/>'
                    '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="light"/></feMerge></filter>')
        body.append(f'<g filter="url(#rim)"><use xlink:href="#mark" {face_paint}/></g>')
    else:
        body.append(f'<use xlink:href="#mark" {face_paint}/>')

    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{pixels}" height="{pixels}" viewBox="0 0 1024 1024">'
            "<defs>" + "".join(defs) + "</defs>" + "".join(body) + "</svg>")


def scalable_svg(mark):
    """The Linux scalable icon: the 256-pixel drawing, with a note on where it came from."""
    svg = icon_svg(mark, 256, "plate")
    note = ("<!-- Simorg Desktop's application icon. Generated by scripts/icons/make_icons.py from "
            "resources/branding/simorg-logo.svg; edit those and run scripts/make-icons.sh. "
            "Copyright (C) 2026 Simorg, licensed GPL-3.0-or-later with this application. -->")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + note + "\n" + svg + "\n"


# ------------------------------------------------------ installer pictures ----

def dialog_svg(mark):
    """WixUIDialogBmp: 493 x 312, behind the installer's first and last page.

    The dialog draws its title and text from 135 dialog units in, about 180
    pixels, on whatever is here; so the art stays in the left 164 pixels. The
    rest is the system's button face, #f0f0f0, rather than white: the last
    page's "Open Simorg now" box is a Win32 check box, which Windows Installer
    paints on that colour whatever is behind it, and on white it was a grey
    block. Matched, the page, the box and the band of buttons below are one.

    The panel is light, a white that turns the palest brand blue towards the
    bottom, because the Windows icon has no plate of its own: on the dark blue
    panel the macOS-style icon stood on, the blue mark all but vanished."""
    icon = icon_svg(mark, 256, "windows")
    icon = icon.replace('width="256" height="256"', 'x="18" y="84" width="128" height="128"', 1)
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            'width="493" height="312" viewBox="0 0 493 312">'
            '<defs><linearGradient id="panel" x1="0" y1="0" x2="0.3" y2="1">'
            '<stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#d9e8fc"/></linearGradient>'
            '<radialGradient id="glow" cx="0.5" cy="0.47" r="0.5">'
            '<stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/>'
            '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>'
            '<rect width="493" height="312" fill="#f0f0f0"/>'
            '<rect width="164" height="312" fill="url(#panel)"/>'
            '<rect width="164" height="312" fill="url(#glow)"/>'
            # Where the panel meets the page.
            '<rect x="163" width="1" height="312" fill="#c8d6ea"/>'
            + icon + "</svg>")


def banner_svg(mark):
    """WixUIBannerBmp: 493 x 58, across the top of the installer's other pages,
    under their title and description, which are drawn from the left."""
    icon = icon_svg(mark, 64, "windows")
    icon = icon.replace('width="64" height="64"', 'x="435" y="5" width="48" height="48"', 1)
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            'width="493" height="58" viewBox="0 0 493 58">'
            '<defs><linearGradient id="fade" x1="0" y1="0" x2="1" y2="0">'
            '<stop offset="0.55" stop-color="#ffffff"/><stop offset="1" stop-color="#e3efff"/></linearGradient></defs>'
            '<rect width="493" height="58" fill="url(#fade)"/>'
            + icon + "</svg>")


def dmg_background_svg():
    """Behind the .dmg's window: DMG_WINDOW points, drawn at 1x and 2x.

    Finder puts Simorg's icon and the Applications shortcut on it (their places
    are DMG_APP_AT and DMG_APPLICATIONS_AT) and labels them; the picture says
    what to do with them. "Drag and drop" between the two, the way Docker's disk
    image says it, and an arrow under the words from Simorg to Applications, so
    it reads without the words too. Words and arrow go from the ink of the mark's
    extrusion to the brand blue, in the direction of the drag.

    The same pale field as the Windows installer's panel, lighter still: Finder
    draws the labels in black on a light picture in Dark Mode as well, and they
    need the contrast. Nothing that matters is in the bottom 90 points, which the
    title bar and, for people who show them, Finder's path and status bars
    cover."""
    width, height = DMG_WINDOW
    (ax, ay), (bx, by) = DMG_APP_AT, DMG_APPLICATIONS_AT
    # The arrow leaves from beside Simorg's label, dips under the words and
    # comes up at the folder's lower corner; its head follows the curve's end.
    start = (ax + 62, ay + 76)
    end = (bx - 66, by + 76)
    c1 = (start[0] + 50, start[1] + 62)
    c2 = (end[0] - 50, end[1] + 62)
    heading = math.atan2(c2[1] - end[1], c2[0] - end[0])
    head, spread = 17.0, math.radians(34)
    wings = [(end[0] + head * math.cos(heading + s * spread), end[1] + head * math.sin(heading + s * spread))
             for s in (-1, 1)]

    def f(v):
        return f"{v:.2f}".rstrip("0").rstrip(".")

    curve = (f"M {f(start[0])} {f(start[1])} C {f(c1[0])} {f(c1[1])}, {f(c2[0])} {f(c2[1])}, "
             f"{f(end[0])} {f(end[1])}")
    arrow_head = (f"M {f(wings[0][0])} {f(wings[0][1])} L {f(end[0])} {f(end[1])} "
                  f"L {f(wings[1][0])} {f(wings[1][1])}")
    middle = (ax + bx) / 2
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            f'width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            '<defs><linearGradient id="field" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e3edfc"/></linearGradient>'
            f'<linearGradient id="arrowInk" gradientUnits="userSpaceOnUse" x1="{f(start[0])}" y1="0" x2="{f(end[0])}" y2="0">'
            f'<stop offset="0" stop-color="#0b2a5b"/><stop offset="1" stop-color="{BRAND_BLUE}"/></linearGradient>'
            f'<linearGradient id="wordInk" gradientUnits="userSpaceOnUse" x1="{f(middle - 90)}" y1="0" x2="{f(middle + 90)}" y2="0">'
            f'<stop offset="0" stop-color="#0b2a5b"/><stop offset="1" stop-color="{BRAND_BLUE}"/></linearGradient></defs>'
            f'<rect width="{width}" height="{height}" fill="url(#field)"/>'
            f'<text x="{f(middle)}" y="{f(ay + 9)}" text-anchor="middle" font-family="Inter" font-weight="600" '
            'font-size="25" letter-spacing="-0.3" fill="url(#wordInk)">Drag and drop</text>'
            '<g fill="none" stroke="url(#arrowInk)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="{curve}"/><path d="{arrow_head}"/></g>'
            "</svg>")


# ------------------------------------------------------------- rasterising ----

def rasterise(rsvg, svg, width, height):
    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "in.svg")
        target = os.path.join(work, "out.png")
        with open(source, "w", encoding="utf-8") as f:
            f.write(svg)
        subprocess.run([rsvg, "-w", str(width), "-h", str(height), "-f", "png", "-o", target, source],
                       check=True)
        with open(target, "rb") as f:
            return f.read()


def decode_png(data):
    """8-bit RGBA or RGB, non-interlaced: what rsvg-convert writes (RGB when
    nothing is transparent). Returns (width, height, RGBA bytes)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat = 8, bytearray()
    width = height = channels = None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour not in (2, 6) or interlace != 0:
                raise ValueError("expected 8-bit RGB or RGBA without interlacing")
            channels = 4 if colour == 6 else 3
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    n = channels
    stride = width * n
    out = bytearray(height * stride)
    previous = bytearray(stride)
    i = 0
    for y in range(height):
        kind = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if kind == 1:
            for x in range(n, stride):
                line[x] = (line[x] + line[x - n]) & 0xFF
        elif kind == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 0xFF
        elif kind == 3:
            for x in range(stride):
                left = line[x - n] if x >= n else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 0xFF
        elif kind == 4:
            for x in range(stride):
                a = line[x - n] if x >= n else 0
                b = previous[x]
                c = previous[x - n] if x >= n else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                predictor = a if pa <= pb and pa <= pc else b if pb <= pc else c
                line[x] = (line[x] + predictor) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        previous = line
    if n == 4:
        return width, height, bytes(out)
    rgba = bytearray(width * height * 4)
    rgba[0::4] = out[0::3]
    rgba[1::4] = out[1::3]
    rgba[2::4] = out[2::3]
    rgba[3::4] = b"\xff" * (width * height)
    return width, height, bytes(rgba)


# -------------------------------------------------------------- containers ----

def ico(entries):
    """entries: [(pixels, png bytes)]. A DIB below ICO_PNG_FROM, PNG from it."""
    images = []
    for pixels, png in entries:
        if pixels >= ICO_PNG_FROM:
            images.append((pixels, png))
            continue
        w, h, rgba = decode_png(png)
        header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, 0, 0, 0, 0, 0)
        xor = bytearray()
        mask = bytearray()
        mask_stride = ((w + 31) // 32) * 4
        for y in range(h - 1, -1, -1):                       # bottom-up
            row = rgba[y * w * 4:(y + 1) * w * 4]
            bits = bytearray(mask_stride)
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                xor += bytes((b, g, r, a))
                if a == 0:
                    bits[x // 8] |= 0x80 >> (x % 8)
            mask += bits
        images.append((pixels, header + bytes(xor) + bytes(mask)))
    directory = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    blobs = b""
    for pixels, blob in images:
        dim = 0 if pixels >= 256 else pixels
        directory += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
        blobs += blob
    return directory + blobs


def icns(entries):
    """entries: [(type, png bytes)], with a table of contents first, as iconutil writes."""
    toc = b"".join(kind.encode("ascii") + struct.pack(">I", 8 + len(png)) for kind, png in entries)
    chunks = [b"TOC " + struct.pack(">I", 8 + len(toc)) + toc]
    chunks += [kind.encode("ascii") + struct.pack(">I", 8 + len(png)) + png for kind, png in entries]
    body = b"".join(chunks)
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def bmp24(png):
    """A 24-bit BMP of an opaque PNG: what Windows Installer's dialogs show."""
    w, h, rgba = decode_png(png)
    stride = (w * 3 + 3) & ~3
    pixels = bytearray()
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            r, g, b, a = rgba[(y * w + x) * 4:(y * w + x) * 4 + 4]
            # Onto white, in case anything was left transparent.
            r = (r * a + 255 * (255 - a)) // 255
            g = (g * a + 255 * (255 - a)) // 255
            b = (b * a + 255 * (255 - a)) // 255
            row += bytes((b, g, r))
        row += bytes(stride - len(row))
        pixels += row
    info = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    header = b"BM" + struct.pack("<IHHI", 14 + 40 + len(pixels), 0, 0, 14 + 40)
    return header + info + bytes(pixels)


# -------------------------------------------------------------------- main ----

def build(rsvg):
    """Every output, as {path: bytes}."""
    inner, width, height = read_mark()
    bounds = mark_bounds(inner, width, height, rsvg)
    mark = (inner, width, height, bounds)

    cache = {}

    def png(pixels, flavour):
        key = (pixels, flavour)
        if key not in cache:
            cache[key] = rasterise(rsvg, icon_svg(mark, pixels, flavour), pixels, pixels)
        return cache[key]

    out = {}
    out[ICNS] = icns([(kind, png(pixels, "macos")) for kind, pixels in ICNS_ENTRIES])
    out[ICO] = ico([(pixels, png(pixels, "windows")) for pixels in ICO_SIZES])
    for pixels in LINUX_SIZES:
        out[os.path.join(APP_ICON_DIR, f"simorg-{pixels}.png")] = png(pixels, "plate")
    out[os.path.join(APP_ICON_DIR, "simorg-app-icon.svg")] = scalable_svg(mark).encode("utf-8")
    out[DIALOG_BMP] = bmp24(rasterise(rsvg, dialog_svg(mark), 493, 312))
    out[BANNER_BMP] = bmp24(rasterise(rsvg, banner_svg(mark), 493, 58))
    width, height = DMG_WINDOW
    out[DMG_BACKGROUND] = rasterise(rsvg, dmg_background_svg(), width, height)
    out[DMG_BACKGROUND_2X] = rasterise(rsvg, dmg_background_svg(), 2 * width, 2 * height)
    return out, mark


def main():
    parser = argparse.ArgumentParser(description="Write Simorg Desktop's application icons from the Simorg mark.")
    parser.add_argument("--check", action="store_true",
                        help="write nothing; fail when a committed file differs from what would be written")
    parser.add_argument("--preview", metavar="DIR",
                        help="also write every size of both flavours as PNG into DIR, for looking at")
    parser.add_argument("--rsvg", default="rsvg-convert", help="the rsvg-convert to use")
    args = parser.parse_args()

    try:
        version = subprocess.run([args.rsvg, "--version"], check=True, capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        sys.exit("make_icons: rsvg-convert is needed (librsvg 2.50 or later); scripts/make-icons.sh brings one")
    print(f"  {version}")

    outputs, mark = build(args.rsvg)

    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        for flavour in ("macos", "plate", "windows"):
            for pixels in sorted(set(ICO_SIZES + LINUX_SIZES + [1024])):
                data = rasterise(args.rsvg, icon_svg(mark, pixels, flavour), pixels, pixels)
                with open(os.path.join(args.preview, f"{flavour}-{pixels}.png"), "wb") as f:
                    f.write(data)
        for name, svg, w, h in (("installer-dialog", dialog_svg(mark), 493, 312),
                                ("installer-banner", banner_svg(mark), 493, 58),
                                ("dmg-background", dmg_background_svg(), 2 * DMG_WINDOW[0], 2 * DMG_WINDOW[1])):
            with open(os.path.join(args.preview, name + ".png"), "wb") as f:
                f.write(rasterise(args.rsvg, svg, w, h))

    stale = []
    for path, data in sorted(outputs.items()):
        relative = os.path.relpath(path, ROOT).replace(os.sep, "/")
        current = None
        if os.path.exists(path):
            with open(path, "rb") as f:
                current = f.read()
        if current == data:
            print(f"  = {relative}")
            continue
        if args.check:
            stale.append(relative)
            print(f"  ! {relative} is not what the mark makes")
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        print(f"  + {relative}  ({len(data):,} bytes)")

    if stale:
        sys.exit("make_icons: run scripts/make-icons.sh and commit what it writes")


if __name__ == "__main__":
    main()
