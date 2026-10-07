// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// Private to the core library.
#pragma once

#include <QByteArray>

namespace simorg::app {

/**
 * The host document a Workbench or a Brain loads, baked in at build time.
 *
 * Generated into EmbeddedSurface.cpp by CMake from `config/surface/host.html`,
 * exactly as the environment configuration and the container templates are, and
 * for the same reason: a Qt resource inside a *static* library only initialises
 * if every consumer links it just so, and a document that silently came back
 * empty would be a surface that never explains why it is blank.
 *
 * Carries two placeholders — `__SURFACE_CONFIG__` and
 * `__SURFACE_COLOR_SCHEME__` — filled in by {@link SurfaceRouter::document}.
 */
QByteArray embeddedSurfaceDocument();

/** Its script, from `config/surface/host.js`, embedded the same way. */
QByteArray embeddedSurfaceScript();

} // namespace simorg::app
