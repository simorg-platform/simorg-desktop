// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "PeerCheck.h"

#include <limits>

#ifdef Q_OS_WIN
#include <vector>
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace simorg::client::detail {

#ifdef Q_OS_WIN

namespace {

/** Closes a handle when it goes out of scope. */
struct OwnedHandle
{
    HANDLE handle = nullptr;
    OwnedHandle() = default;
    explicit OwnedHandle(HANDLE h)
        : handle(h)
    {
    }
    OwnedHandle(const OwnedHandle &) = delete;
    OwnedHandle &operator=(const OwnedHandle &) = delete;
    ~OwnedHandle()
    {
        if (handle)
            CloseHandle(handle);
    }
};

/** The TOKEN_USER of a token, in a buffer sized by asking first. */
bool readTokenUser(HANDLE token, std::vector<BYTE> *buffer)
{
    DWORD needed = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &needed);
    if (needed == 0)
        return false;
    buffer->resize(needed);
    return GetTokenInformation(token, TokenUser, buffer->data(), needed, &needed) != FALSE;
}

} // namespace

QString sameUserProblem(qintptr descriptor)
{
    ULONG serverPid = 0;
    if (!GetNamedPipeServerProcessId(HANDLE(descriptor), &serverPid))
        return QStringLiteral("the pipe did not say which process serves it");

    OwnedHandle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, serverPid));
    if (!process.handle)
        return QStringLiteral("the process serving the pipe could not be examined");

    OwnedHandle serverToken;
    OwnedHandle ownToken;
    if (!OpenProcessToken(process.handle, TOKEN_QUERY, &serverToken.handle)
        || !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &ownToken.handle)) {
        return QStringLiteral("the user running the pipe's process could not be read");
    }

    std::vector<BYTE> server;
    std::vector<BYTE> own;
    if (!readTokenUser(serverToken.handle, &server) || !readTokenUser(ownToken.handle, &own))
        return QStringLiteral("the user running the pipe's process could not be read");

    const auto *serverUser = reinterpret_cast<TOKEN_USER *>(server.data());
    const auto *ownUser = reinterpret_cast<TOKEN_USER *>(own.data());
    if (!EqualSid(serverUser->User.Sid, ownUser->User.Sid))
        return QStringLiteral("the pipe is served by another user's process");
    return {};
}

bool processIsAlive(qint64 pid)
{
    if (pid <= 0 || pid > std::numeric_limits<DWORD>::max())
        return false;
    OwnedHandle process(OpenProcess(SYNCHRONIZE, FALSE, DWORD(pid)));
    if (!process.handle)
        return GetLastError() == ERROR_ACCESS_DENIED;
    return WaitForSingleObject(process.handle, 0) == WAIT_TIMEOUT;
}

#else

QString sameUserProblem(qintptr descriptor)
{
    const int fd = int(descriptor);
    uid_t peer = 0;

#if defined(Q_OS_LINUX)
    ucred credentials{};
    socklen_t length = sizeof(credentials);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &credentials, &length) != 0)
        return QStringLiteral("the socket did not say who serves it");
    peer = credentials.uid;
#else
    gid_t group = 0;
    if (getpeereid(fd, &peer, &group) != 0)
        return QStringLiteral("the socket did not say who serves it");
#endif

    if (peer != geteuid())
        return QStringLiteral("the socket is served by another user's process");
    return {};
}

bool processIsAlive(qint64 pid)
{
    if (pid <= 0 || pid > std::numeric_limits<pid_t>::max())
        return false;
    // Signal 0 checks without sending anything; EPERM means it exists as somebody else's.
    return kill(pid_t(pid), 0) == 0 || errno == EPERM;
}

#endif

} // namespace simorg::client::detail
