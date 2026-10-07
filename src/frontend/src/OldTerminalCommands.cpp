// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/OldTerminalCommands.h"

#include "simorg/frontend/AutostartService.h"
#include "simorg/frontend/Logging.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#endif

namespace simorg {
namespace oldterminalcommands {
namespace {

/** The markers an older release wrapped its profile block in. */
constexpr auto kBlockStart = "# >>> simorg >>>";
constexpr auto kBlockEnd = "# <<< simorg <<<";

/** Whether `directory` holds anything answering to `simorg` or `sim`: Simorg CLI's, or anything else's. */
bool holdsACommand(const QString &directory)
{
    const QDir folder(directory);
    for (const QString &name : names()) {
        for (const QString &file : {name, name + QStringLiteral(".cmd"), name + QStringLiteral(".exe")}) {
            const QFileInfo info(folder.absoluteFilePath(file));
            if (info.exists() || info.isSymLink())
                return true;
        }
    }
    return false;
}

#ifdef Q_OS_WIN
/** The person's own `Path`, as REG_EXPAND_SZ so the entries that use a variable keep expanding. */
QString readUserPath()
{
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_READ, &key) != ERROR_SUCCESS)
        return {};
    DWORD type = 0;
    DWORD bytes = 0;
    QString value;
    if (RegQueryValueExW(key, L"Path", nullptr, &type, nullptr, &bytes) == ERROR_SUCCESS && bytes > 0) {
        QList<wchar_t> buffer(static_cast<int>(bytes / sizeof(wchar_t)) + 1, L'\0');
        if (RegQueryValueExW(key, L"Path", nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()), &bytes) ==
            ERROR_SUCCESS)
            value = QString::fromWCharArray(buffer.constData());
    }
    RegCloseKey(key);
    return value;
}

bool writeUserPath(const QString &value)
{
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS)
        return false;
    const std::wstring data = value.toStdWString();
    const LONG result = RegSetValueExW(key, L"Path", 0, REG_EXPAND_SZ, reinterpret_cast<const BYTE *>(data.c_str()),
                                       static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    if (result != ERROR_SUCCESS)
        return false;
    // What Explorer starts from now on reads the new PATH.
    DWORD_PTR ignored = 0;
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, reinterpret_cast<LPARAM>(L"Environment"),
                        SMTO_ABORTIFHUNG, 5000, &ignored);
    return true;
}

/** Takes `directory` off the person's PATH. */
void takeOffPath(const QString &directory)
{
    const QString current = readUserPath();
    QStringList entries = current.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    const qsizetype before = entries.size();
    entries.removeIf([&directory](const QString &entry) {
        return QDir::cleanPath(entry).compare(QDir::cleanPath(directory), Qt::CaseInsensitive) == 0;
    });
    if (entries.size() != before && !writeUserPath(entries.join(QLatin1Char(';'))))
        qCWarning(lcApp) << "could not take" << directory << "off PATH";
}
#else
/** Takes the block an older release wrote for `directory` out of `profile`. */
void takeOffPath(const QString &profile, const QString &directory)
{
    QFile file(profile);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QString existing = QString::fromUtf8(file.readAll());
    file.close();
    const QString updated = withoutBlockFor(existing, directory);
    if (updated == existing)
        return;
    QSaveFile out(profile);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text) || out.write(updated.toUtf8()) < 0 || !out.commit())
        qCWarning(lcApp) << "could not take" << directory << "off PATH in" << profile;
}
#endif

} // namespace

QStringList names()
{
    return {QStringLiteral("simorg"), QStringLiteral("sim")};
}

QStringList candidateDirectories(const QString &home)
{
#ifdef Q_OS_WIN
    Q_UNUSED(home);
    return {QDir(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation))
                .absoluteFilePath(QStringLiteral("bin"))};
#else
    const QDir homeDir(home);
    return {homeDir.absoluteFilePath(QStringLiteral(".local/bin")), homeDir.absoluteFilePath(QStringLiteral("bin")),
            QStringLiteral("/usr/local/bin")};
#endif
}

QString profileFileFor(const QString &shell, const QString &home)
{
    const QDir homeDir(home);
    const QString name = QFileInfo(shell).fileName();
    if (name.contains(QLatin1String("zsh")))
        return homeDir.absoluteFilePath(QStringLiteral(".zshrc"));
    if (name.contains(QLatin1String("fish")))
        return homeDir.absoluteFilePath(QStringLiteral(".config/fish/conf.d/simorg.fish"));
    if (name.contains(QLatin1String("bash")))
        return homeDir.absoluteFilePath(QStringLiteral(".bashrc"));
    return homeDir.absoluteFilePath(QStringLiteral(".profile"));
}

QString withoutBlockFor(const QString &text, const QString &directory)
{
    // Non-greedy and anchored on both markers: a block missing its end is left exactly as it is.
    static const QRegularExpression block(
        QStringLiteral("^[ \\t]*%1.*?%2[ \\t]*\\r?\\n?")
            .arg(QRegularExpression::escape(QLatin1String(kBlockStart)),
                 QRegularExpression::escape(QLatin1String(kBlockEnd))),
        QRegularExpression::DotMatchesEverythingOption | QRegularExpression::MultilineOption);
    QString result = text;
    qsizetype from = 0;
    for (;;) {
        const QRegularExpressionMatch match = block.match(result, from);
        if (!match.hasMatch())
            return result;
        if (match.captured(0).contains(directory)) {
            result.remove(match.capturedStart(0), match.capturedLength(0));
            from = match.capturedStart(0);
        } else {
            from = match.capturedEnd(0);
        }
    }
}

bool madeByOlderDesktop(const QString &target, const QString &appImage)
{
    const QString cleaned = QDir::cleanPath(target);
    if (cleaned.endsWith(QLatin1String(".app/Contents/Helpers/simorg")))
        return true;
    if (appImage.isEmpty())
        return false;
    const QString image = QFileInfo(appImage).canonicalFilePath();
    return cleaned == QDir::cleanPath(appImage) || (!image.isEmpty() && cleaned == image);
}

bool shimMadeByOlderDesktop(const QString &text, const QString &installFolder)
{
    // Joined rather than resolved, so a Windows folder reads the same on any system that tests it.
    const QString program = QDir::toNativeSeparators(QDir::cleanPath(installFolder + QStringLiteral("/simorg.exe")));
    return text.contains(program, Qt::CaseInsensitive);
}

QStringList removeFrom(const QString &home, const QString &shell, const QString &appImage,
                       const QString &installFolder)
{
    QStringList removed;
    QStringList folders;
    for (const QString &directory : candidateDirectories(home)) {
        for (const QString &name : names()) {
#ifdef Q_OS_WIN
            Q_UNUSED(appImage);
            const QString path = QDir(directory).absoluteFilePath(name + QStringLiteral(".cmd"));
            QFile shim(path);
            if (!shim.open(QIODevice::ReadOnly | QIODevice::Text))
                continue;
            const bool ours = shimMadeByOlderDesktop(QString::fromUtf8(shim.readAll()), installFolder);
            shim.close();
            if (!ours)
                continue;
#else
            Q_UNUSED(installFolder);
            const QString path = QDir(directory).absoluteFilePath(name);
            const QFileInfo link(path);
            if (!link.isSymLink() || !madeByOlderDesktop(link.symLinkTarget(), appImage))
                continue;
#endif
            if (QFile::remove(path)) {
                removed << path;
                if (!folders.contains(directory))
                    folders << directory;
            } else {
                qCWarning(lcApp) << "could not remove an older release's" << path;
            }
        }
    }
    // The PATH an older release added for a folder goes with its last command, and never while Simorg CLI's are there.
    for (const QString &directory : std::as_const(folders)) {
        if (holdsACommand(directory))
            continue;
#ifdef Q_OS_WIN
        Q_UNUSED(shell);
        takeOffPath(QDir::toNativeSeparators(directory));
        QDir().rmdir(directory);
#else
        takeOffPath(profileFileFor(shell, home), directory);
#endif
    }
    if (!removed.isEmpty())
        qCInfo(lcApp) << "took an older release's terminal commands away:" << removed.join(QStringLiteral(", "));
    return removed;
}

QStringList removeFromThisComputer()
{
    return removeFrom(QDir::homePath(), QProcessEnvironment::systemEnvironment().value(QStringLiteral("SHELL")),
                      qEnvironmentVariable("APPIMAGE"), QCoreApplication::applicationDirPath());
}

} // namespace oldterminalcommands

QString removeCommandsAndLoginItems()
{
    QStringList problems;
    oldterminalcommands::removeFromThisComputer();
    // Every login item of Simorg's name, not only one naming this copy: an older
    // copy's names a program that has moved or gone, and runs at every login all
    // the same — an AppImage's always did, since each run had a mount of its own.
    for (const AutostartTarget target : {AutostartTarget::DesktopApp, AutostartTarget::Daemon}) {
        AutostartService autostart(target);
        if (autostart.hasEntry() && !autostart.setEnabled(false))
            problems << autostart.lastError();
    }
    return problems.join(QLatin1Char(' '));
}

} // namespace simorg
