// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QLoggingCategory>

/**
 * The front ends' logging category, `simorg.app`. Silent by default except
 * warnings; turn it on with `QT_LOGGING_RULES="simorg.*.debug=true"` or
 * `simorg --verbose`.
 */
Q_DECLARE_LOGGING_CATEGORY(lcApp)
