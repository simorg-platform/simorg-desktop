// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

#include <optional>

namespace simorg::app::crash {

/**
 * The app's crash marker: a few bytes a crashing process leaves so the next
 * launch can report the crash.
 *
 * The same shape as the service's own crash marker, because the reason is the
 * same: a process whose event loop
 * has gone cannot send anything, and a network write from a signal handler is
 * undefined. So the handler writes `<signal number> <version>` into a file and
 * dies the way it was going to — the operating system still records the crash
 * and still writes its own report — and the next launch reads those bytes,
 * deletes them and reports one error through the service.
 *
 * `<config dir>/simorg-desktop-<env>.crash`, owner-only, one line.
 */

/** Where the marker for this environment is. */
QString markerPath(const QString &environment);

/**
 * Installs the handler for `SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGFPE` and `SIGILL`
 * — on Windows, an unhandled-exception filter. Call once, on the main thread,
 * before other threads start: the path and the version are copied into fixed
 * buffers first, so the handler itself allocates and formats nothing. False when
 * the path does not fit its buffer or the handler could not be installed.
 */
bool install(const QString &markerPath, const QString &version);

/** What a marker said. */
struct Marker
{
    /** A signal number on POSIX, `0x…` on Windows. */
    QString signal;
    /** The version that crashed, or empty when the marker named none. */
    QString version;
};

/**
 * The marker a previous launch left, **deleted before this returns**. A marker
 * that is empty, unreadable or larger than a marker is, is deleted too and gives
 * nothing: one that survived would be reported at every launch, and a crash that
 * appears to happen every morning is more misleading than one missed once.
 */
std::optional<Marker> take(const QString &markerPath);

/** `SIGSEGV` for `11`, and so on for the five; the text itself for anything else. */
QString signalName(const QString &signal);

} // namespace simorg::app::crash
