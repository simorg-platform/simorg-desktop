// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// Private to the core library.
#pragma once

#include <QByteArray>

namespace simorg::app {

/**
 * The script Simorg Desktop hands its own update to on macOS and Linux, baked in
 * at build time from `config/update/desktop-handover.sh`, the way the surface
 * document is (EmbeddedSurface.h) and for the same reason: a Qt resource inside
 * a static library initialises only if every consumer links it just so, and an
 * update that found its script empty would close the app and never open it again.
 */
QByteArray embeddedHandoverShell();

/** Its Windows twin, from `config/update/desktop-handover.ps1`, embedded the same way. */
QByteArray embeddedHandoverPowerShell();

} // namespace simorg::app
