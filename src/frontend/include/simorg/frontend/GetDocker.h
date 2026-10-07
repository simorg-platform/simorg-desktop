// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

namespace simorg {

/**
 * Where somebody without Docker gets one: Docker's own page, and on Linux its
 * guide to installing Docker Engine. Simorg installs no Docker itself,
 * so both front ends say Docker
 * is missing and point here.
 */
inline QString getDockerUrl()
{
#if defined(Q_OS_LINUX)
    return QStringLiteral("https://docs.docker.com/engine/install/");
#else
    return QStringLiteral("https://docs.docker.com/get-started/get-docker/");
#endif
}

} // namespace simorg
