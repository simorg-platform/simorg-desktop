// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "CrashMarker.h"

#include "simorg/client/Discovery.h"

#include <QFile>
#include <QFileInfo>

#include <algorithm>
#include <array>
#include <cstddef>

#if defined(Q_OS_WIN)
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <csignal>
#include <memory>
#endif

namespace simorg::app::crash {
namespace {

/** The most a marker holds: a signal or exception code, a space, a version and a line feed. */
constexpr qint64 maxMarkerBytes = 128;
constexpr std::size_t versionBytes = 64;

// Written once by install(), before any handler can run, and only read afterwards.
std::array<char, versionBytes> g_version{};
std::size_t g_versionLength = 0;

/** A version as a marker may carry it: printable ASCII without spaces, cut to fit. */
void keepVersion(const QByteArray &version)
{
    std::size_t length = 0;
    for (const char character : version) {
        if (length == g_version.size())
            break;
        const bool printable = character > ' ' && character < '\x7f';
        g_version.at(length++) = printable ? character : '_';
    }
    g_versionLength = length;
}

#if !defined(Q_OS_WIN)

constexpr std::array<int, 5> crashSignals{SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL};
constexpr std::size_t alternateStackBytes = std::size_t{64} * 1024;

std::array<char, 4096> g_path{};

/** write() until everything went or it failed; async-signal-safe. */
void writeAll(int descriptor, const char *data, std::size_t size) noexcept
{
    while (size > 0) {
        const ssize_t written = ::write(descriptor, data, size);
        if (written < 0) {
            if (errno == EINTR)
                continue;
            return;
        }
        data += written;
        size -= static_cast<std::size_t>(written);
    }
}

/** Only async-signal-safe calls: open, write, close, sigaction, raise. Nothing allocates or formats. */
void onCrash(int signalNumber) noexcept
{
    const int saved = errno;
    const int descriptor = ::open(g_path.data(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (descriptor >= 0) {
        std::array<char, 12> digits{};
        std::size_t length = 0;
        auto value = static_cast<unsigned>(signalNumber);
        do {
            digits.at(digits.size() - 1 - length) = static_cast<char>('0' + (value % 10U));
            ++length;
            value /= 10U;
        } while (value != 0U && length < digits.size());
        writeAll(descriptor, digits.data() + (digits.size() - length), length);
        writeAll(descriptor, " ", 1);
        writeAll(descriptor, g_version.data(), g_versionLength);
        writeAll(descriptor, "\n", 1);
        (void)::close(descriptor);
    }
    // It dies the way it was going to, so the system still records the crash and writes its own report.
    struct sigaction defaultAction{};
    defaultAction.sa_handler = SIG_DFL;
    (void)sigemptyset(&defaultAction.sa_mask);
    (void)::sigaction(signalNumber, &defaultAction, nullptr);
    errno = saved;
    (void)::raise(signalNumber);
}

#else

std::array<wchar_t, 32768> g_path{};

void writeAll(HANDLE file, const char *data, DWORD size) noexcept
{
    while (size > 0) {
        DWORD written = 0;
        if (WriteFile(file, data, size, &written, nullptr) == 0 || written == 0)
            return;
        data += written;
        size -= written;
    }
}

LONG WINAPI onUnhandledException(EXCEPTION_POINTERS *pointers) noexcept
{
    const HANDLE file = CreateFileW(g_path.data(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        const DWORD code =
            pointers != nullptr && pointers->ExceptionRecord != nullptr ? pointers->ExceptionRecord->ExceptionCode : 0;
        std::array<char, 10> text{'0', 'x'};
        constexpr char hex[] = "0123456789ABCDEF";
        for (std::size_t index = 0; index < 8; ++index)
            text.at(9 - index) = hex[(code >> (4U * index)) & 0xFU];
        writeAll(file, text.data(), static_cast<DWORD>(text.size()));
        writeAll(file, " ", 1);
        writeAll(file, g_version.data(), static_cast<DWORD>(g_versionLength));
        writeAll(file, "\n", 1);
        (void)CloseHandle(file);
    }
    // The search continues, so Windows still writes its own crash report.
    return EXCEPTION_CONTINUE_SEARCH;
}

#endif

} // namespace

QString markerPath(const QString &environment)
{
    return client::configDirectory() + QStringLiteral("/simorg-desktop-") + environment + QStringLiteral(".crash");
}

#if !defined(Q_OS_WIN)

bool install(const QString &path, const QString &version)
{
    const QByteArray native = QFile::encodeName(path);
    if (native.isEmpty() || static_cast<std::size_t>(native.size()) >= g_path.size() || native.contains('\0'))
        return false;
    std::copy(native.cbegin(), native.cend(), g_path.begin());
    g_path.at(static_cast<std::size_t>(native.size())) = '\0';
    keepVersion(version.toUtf8());

    // Held for the life of the process: the handler may run on it at any moment, including
    // after a stack overflow, which is why it has a stack of its own.
    static const std::unique_ptr<std::array<char, alternateStackBytes>> alternateStack =
        std::make_unique<std::array<char, alternateStackBytes>>();
    stack_t stack{};
    stack.ss_sp = alternateStack->data();
    stack.ss_size = alternateStackBytes;
    stack.ss_flags = 0;
    if (::sigaltstack(&stack, nullptr) != 0)
        return false;

    struct sigaction action{};
    action.sa_handler = onCrash;
    action.sa_flags = SA_ONSTACK;
    (void)sigemptyset(&action.sa_mask);
    for (const int signalNumber : crashSignals) {
        if (::sigaction(signalNumber, &action, nullptr) != 0)
            return false;
    }
    return true;
}

QString signalName(const QString &signal)
{
    bool isNumber = false;
    const int number = signal.toInt(&isNumber);
    if (!isNumber)
        return signal;
    switch (number) {
    case SIGSEGV:
        return QStringLiteral("SIGSEGV");
    case SIGABRT:
        return QStringLiteral("SIGABRT");
    case SIGBUS:
        return QStringLiteral("SIGBUS");
    case SIGFPE:
        return QStringLiteral("SIGFPE");
    case SIGILL:
        return QStringLiteral("SIGILL");
    default:
        return signal;
    }
}

#else

bool install(const QString &path, const QString &version)
{
    const std::wstring native = path.toStdWString();
    if (native.empty() || native.size() >= g_path.size() || native.find(L'\0') != std::wstring::npos)
        return false;
    std::copy(native.cbegin(), native.cend(), g_path.begin());
    g_path.at(native.size()) = L'\0';
    keepVersion(version.toUtf8());
    (void)SetUnhandledExceptionFilter(onUnhandledException);
    return true;
}

QString signalName(const QString &signal)
{
    return signal;
}

#endif

std::optional<Marker> take(const QString &path)
{
    QFile file(path);
    if (!file.exists())
        return std::nullopt;
    QByteArray contents;
    if (file.size() <= maxMarkerBytes && file.open(QIODevice::ReadOnly))
        contents = file.readAll().trimmed();
    file.close();
    // Deleted whatever it held: a marker that survived would be reported at every launch.
    QFile::remove(path);

    const QList<QByteArray> parts = contents.split(' ');
    if (parts.isEmpty() || parts.first().isEmpty())
        return std::nullopt;
    Marker marker;
    marker.signal = QString::fromLatin1(parts.first());
    if (parts.size() > 1)
        marker.version = QString::fromLatin1(parts.at(1));
    return marker;
}

} // namespace simorg::app::crash
