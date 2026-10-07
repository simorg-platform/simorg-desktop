// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/Logging.h"

// Warning and above by default — including in Debug builds, where Qt would
// otherwise let qCDebug through and put internal chatter in front of anyone
// running the CLI. `simorg --verbose` and QT_LOGGING_RULES both lift it.
Q_LOGGING_CATEGORY(lcApp, "simorg.app", QtWarningMsg)
