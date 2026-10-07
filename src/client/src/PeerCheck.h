// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>
#include <QtGlobal>

namespace simorg::client::detail {

/**
 * Whether the server end of a connected local socket runs as this process's user.
 *
 * `descriptor` is QLocalSocket::socketDescriptor(): a file descriptor on Unix,
 * where the peer's user id is read from the kernel, and the pipe's handle on
 * Windows, where the server process's token is compared with this one's. Returns
 * an empty string when it does, and a sentence saying why not otherwise.
 */
QString sameUserProblem(qintptr descriptor);

/** Whether a process with this id is running (a process run by another user counts). */
bool processIsAlive(qint64 pid);

} // namespace simorg::client::detail
