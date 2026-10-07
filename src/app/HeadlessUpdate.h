// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QStringList>

namespace simorg::app {

/**
 * Whether `arguments`, the words after the program, ask for the update with no
 * window: `update desktop`, the words the Simorg machine service runs the
 * program Simorg Desktop registered with, to update it while it is closed.
 */
bool isHeadlessUpdate(const QStringList &arguments);

/**
 * Updates this copy of Simorg Desktop with no window, as the machine service
 * asks while the app is closed: registers the copy, reads the service's row for
 * it, and downloads, checks and hands over the release, reporting each phase
 * to the service. Answers the row as one JSON document on standard
 * output; the exit code is the outcome: 0 done or nothing newer, 1 failed, 5
 * when the service could not be reached.
 *
 * It was the `simorg update desktop` command of the same package until Simorg
 * CLI became an application of its own; the app is that command now.
 */
int runHeadlessUpdate(int &argc, char *argv[]);

} // namespace simorg::app
