// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

namespace simorg::client::detail {

struct StartOutcome
{
    enum class Kind {
        /** Asked to start; readiness is the caller's to wait for. */
        Asked,
        /** Nothing is installed that could be started. */
        NotInstalled,
        /** Something is installed and could not be started; `detail` says what answered. */
        Failed,
    };

    Kind kind = Kind::Failed;
    QString detail;
};

/**
 * Starts the user's service for an environment, without waiting for it.
 *
 * `SIMORGM_BINARY`, when set, is started directly on every system as
 * `<binary> run --env <environment>`. Otherwise: on macOS the LaunchAgent is
 * kick-started, or bootstrapped from `~/Library/LaunchAgents` or
 * `/Library/LaunchAgents` when launchd does not have it loaded; on Linux
 * `systemctl --user start --no-block` starts the unit; on Windows
 * `%ProgramFiles%\Simorg\simorgm.exe` is started with no console window, in a
 * process group of its own, inheriting no handles and outside the caller's job
 * where the job allows it.
 */
StartOutcome startService(const QString &environment);

/**
 * Asks the system's service manager to stop the user's service for an
 * environment, without waiting: for Quit Simorg when the service never answered,
 * so there was nobody to ask over the API.
 *
 * On macOS the LaunchAgent is booted out with `launchctl bootout`, and on Linux
 * the unit is stopped with `systemctl --user stop --no-block`. Either way the
 * service is sent `SIGTERM` and runs its bounded shutdown, as it does when the
 * computer shuts down, and a service too hung to answer the signal is killed
 * once the manager's own timeout runs out. It stays installed: the next launch
 * starts it afresh. Windows has no service manager for it — the app itself started the
 * process — and a process that never answered is not killed by force, so there
 * it does nothing; neither does a service started from `SIMORGM_BINARY`, which
 * is somebody's own build. True when the manager was asked and accepted.
 */
bool stopService(const QString &environment);

} // namespace simorg::client::detail
