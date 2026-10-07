// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/AutostartService.h"

#include "simorg/frontend/BuildInfo.h"
#include "simorg/frontend/Logging.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>

#ifdef Q_OS_WIN
#include <QSettings>
#endif

namespace simorg {
namespace {

#ifdef Q_OS_WIN
/** `HKCU\…\Run` — the per-user startup list on Windows. */
constexpr auto kWindowsRunKey =
    "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";
#endif

/**
 * XML-escapes a value going into a launchd plist.
 *
 * A home directory can contain an ampersand. It is rare and it is legal, and a
 * plist that ends up malformed because of one fails at login with nothing on
 * screen to say why.
 */
QString xmlEscaped(const QString &value)
{
    QString escaped = value;
    escaped.replace(QLatin1Char('&'), QLatin1String("&amp;"));
    escaped.replace(QLatin1Char('<'), QLatin1String("&lt;"));
    escaped.replace(QLatin1Char('>'), QLatin1String("&gt;"));
    return escaped;
}

/** The directory an autostart entry belongs in, created if it is missing. */
QString ensureDirectory(const QString &path)
{
    QDir().mkpath(path);
    return path;
}

/**
 * The desktop application, or empty when this build has none beside it.
 *
 * Looked for next to the running executable rather than on `PATH`: an entry
 * has to name an absolute path, because a login session's `PATH` is not the
 * shell's. The app is this program, a sibling file, or on macOS a bundle a few
 * directories up.
 */
QString desktopExecutable(const QString &programDirectory)
{
    // Already the desktop app: nothing to search for.
    if (QCoreApplication::applicationName() == QLatin1String(SIMORG_ORGANIZATION)
        && QCoreApplication::applicationFilePath().contains(QLatin1String("Simorg.app"))) {
        return QCoreApplication::applicationFilePath();
    }

    const QDir directory(programDirectory);

#ifdef Q_OS_WIN
    const QStringList candidates{QStringLiteral("simorg-desktop.exe")};
#elif defined(Q_OS_MACOS)
    const QStringList candidates{QStringLiteral("Simorg.app/Contents/MacOS/Simorg"),
                                 QStringLiteral("../Applications/Simorg.app/Contents/MacOS/Simorg"),
                                 QStringLiteral("simorg-desktop")};
#else
    // The bundle's launcher above bin/ before the program in it: see commandFor.
    const QStringList candidates{QStringLiteral("../simorg-desktop"), QStringLiteral("simorg-desktop")};
#endif

    // A file: a directory is "executable" too, and `../simorg-desktop` beside a
    // build tree could be one.
    for (const QString &candidate : candidates) {
        const QFileInfo info(directory.absoluteFilePath(candidate));
        if (info.isFile() && info.isExecutable())
            return info.canonicalFilePath();
    }
    return {};
}

/**
 * An XDG `Exec=` value (Desktop Entry Specification, "The Exec key").
 *
 * A space in a folder name is the ordinary case — an AppImage kept in
 * `~/My Apps` — and unquoted it splits the program in two. So an argument
 * holding any character the specification reserves is double-quoted, with `"`,
 * `` ` ``, `$` and `\` escaped inside; a `%`, which would start a field code, is
 * doubled wherever it is; and the whole then gets the escaping every
 * desktop-entry string gets, which a reader undoes before it reads the quotes,
 * so a backslash inside quotes is written as four.
 *
 * Checked against GLib, which GNOME starts autostart entries with: spaces,
 * quotes, `$`, backslashes and shell punctuation all come through. A `%` in the
 * program's path does not, however it is written — GLib looks for the program
 * before it reads `%%` as `%` — so there the specification's form is written,
 * which a launcher that follows it reads (checked on Debian 12 with GLib 2.74).
 */
QString xdgExecLine(const AutostartCommand &command)
{
    static const QString reserved = QStringLiteral(" \t\n\r\"'\\><~|&;$*?#()`");
    QStringList words;
    for (const QString &word : QStringList{command.program} + command.arguments) {
        QString value = word;
        value.replace(QLatin1Char('%'), QLatin1String("%%"));
        if (std::any_of(value.cbegin(), value.cend(), [](QChar c) { return reserved.contains(c); })) {
            QString inner;
            for (const QChar c : value) {
                if (c == u'"' || c == u'`' || c == u'$' || c == u'\\')
                    inner += QLatin1Char('\\');
                inner += c;
            }
            value = QLatin1Char('"') + inner + QLatin1Char('"');
        }
        value.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
        value.replace(QLatin1Char('\n'), QLatin1String("\\n"));
        value.replace(QLatin1Char('\t'), QLatin1String("\\t"));
        value.replace(QLatin1Char('\r'), QLatin1String("\\r"));
        words << value;
    }
    return words.join(QLatin1Char(' '));
}

/**
 * A systemd `ExecStart=` value (systemd.service(5), "Command lines"). It is
 * split on whitespace, so a word holding any is double-quoted, with `"` and `\`
 * escaped inside; `%` starts a specifier anywhere, so it is doubled; and `$`
 * starts a variable in the arguments but not in the program's own path, which
 * systemd reads as written — a doubled one there is looked for as `$$`
 * (checked with `systemd-analyze verify`).
 */
QString systemdExecLine(const AutostartCommand &command)
{
    QStringList words;
    for (const QString &word : QStringList{command.program} + command.arguments) {
        QString value = word;
        value.replace(QLatin1Char('%'), QLatin1String("%%"));
        if (!words.isEmpty())
            value.replace(QLatin1Char('$'), QLatin1String("$$"));
        if (std::any_of(value.cbegin(), value.cend(), [](QChar c) {
                return c.isSpace() || c == u'"' || c == u'\'' || c == u'\\';
            })) {
            value.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
            value.replace(QLatin1Char('"'), QLatin1String("\\\""));
            value.replace(QLatin1Char('\n'), QLatin1String("\\n"));
            value.replace(QLatin1Char('\r'), QLatin1String("\\r"));
            value = QLatin1Char('"') + value + QLatin1Char('"');
        }
        words << value;
    }
    return words.join(QLatin1Char(' '));
}

} // namespace

QString AutostartCommand::toWindowsCommandLine() const
{
    // Quoted whether or not it contains a space: `C:\Program Files\…` is the
    // ordinary case, and a value that is only sometimes quoted is a value
    // somebody will eventually copy without the quotes.
    QString line = QLatin1Char('"') + QDir::toNativeSeparators(program) + QLatin1Char('"');
    for (const QString &argument : arguments)
        line += QLatin1Char(' ') + argument;
    return line;
}

AutostartService::AutostartService(AutostartTarget target, AutostartCommand command,
                                   QObject *parent)
    : QObject(parent)
    , m_target(target)
    , m_command(command.isValid() ? command : defaultCommand(target))
{
}

AutostartCommand AutostartService::defaultCommand(AutostartTarget target)
{
    return commandFor(target, QCoreApplication::applicationDirPath(),
                      qEnvironmentVariable("APPIMAGE"));
}

AutostartCommand AutostartService::commandFor(AutostartTarget target, const QString &programDirectory,
                                              const QString &appImage)
{
    // `--background`: started by the system, it belongs in the menu bar and
    // not in front of somebody who has just logged in.
    const QStringList desktopArguments{QStringLiteral("--background")};

#if !defined(Q_OS_WIN) && !defined(Q_OS_MACOS)
    const QFileInfo image(appImage);
    if (target == AutostartTarget::DesktopApp && !appImage.isEmpty() && image.isFile() && image.isExecutable())
        return {image.canonicalFilePath(), desktopArguments};
#else
    Q_UNUSED(appImage)
#endif

    switch (target) {
    case AutostartTarget::DesktopApp: {
        const QString program = desktopExecutable(programDirectory);
        if (program.isEmpty())
            return {};
        return {program, desktopArguments};
    }
    case AutostartTarget::Daemon:
        // Nothing starts it: the program it ran was the `simorg` command of a release before Simorg CLI, and Simorg
        // CLI never runs at login. With no program its entry is never made, and an older one is still taken away.
        return {};
    }
    return {};
}

QString AutostartService::entryName(AutostartTarget target)
{
    return target == AutostartTarget::DesktopApp ? QStringLiteral("tech.simorg.desktop")
                                                 : QStringLiteral("tech.simorg.daemon");
}

QString AutostartService::launchAgentPlist(const QString &label, const AutostartCommand &command)
{
    QString arguments;
    QTextStream stream(&arguments);
    stream << "\t\t<string>" << xmlEscaped(command.program) << "</string>\n";
    for (const QString &argument : command.arguments)
        stream << "\t\t<string>" << xmlEscaped(argument) << "</string>\n";

    /*
      `RunAtLoad` and `KeepAlive` together, and `KeepAlive` deliberately not as a
      bare true: `SuccessfulExit=false` restarts the agent when it dies and
      leaves it alone when it exits cleanly, which is what "Quit Simorg" does.
      A bare `KeepAlive` would relaunch the app a second after somebody quit it.
    */
    return QStringLiteral(
               "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
               "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
               "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
               "<plist version=\"1.0\">\n"
               "<dict>\n"
               "\t<key>Label</key>\n"
               "\t<string>%1</string>\n"
               "\t<key>ProgramArguments</key>\n"
               "\t<array>\n%2"
               "\t</array>\n"
               "\t<key>RunAtLoad</key>\n"
               "\t<true/>\n"
               "\t<key>KeepAlive</key>\n"
               "\t<dict>\n"
               "\t\t<key>SuccessfulExit</key>\n"
               "\t\t<false/>\n"
               "\t</dict>\n"
               "\t<key>ProcessType</key>\n"
               "\t<string>Background</string>\n"
               "</dict>\n"
               "</plist>\n")
        .arg(xmlEscaped(label), arguments);
}

QString AutostartService::xdgAutostartEntry(const AutostartCommand &command)
{
    /*
      `X-GNOME-Autostart-enabled` is written explicitly because GNOME's own
      tweak tools write `false` into this file rather than deleting it — so an
      entry that only ever appears when enabled would come back disabled after
      somebody had turned it off and on again elsewhere.
    */
    return QStringLiteral("[Desktop Entry]\n"
                          "Type=Application\n"
                          "Name=Simorg\n"
                          "Comment=Keep Simorg running in the background\n"
                          "Exec=%1\n"
                          "Icon=tech.simorg.desktop\n"
                          "Terminal=false\n"
                          "NoDisplay=true\n"
                          "X-GNOME-Autostart-enabled=true\n"
                          "StartupNotify=false\n")
        .arg(xdgExecLine(command));
}

QString AutostartService::systemdUserUnit(const AutostartCommand &command)
{
    /*
      A user unit, and `default.target` rather than `multi-user.target`: this
      belongs to one person's session. With `loginctl enable-linger` it also
      survives them logging out, which is what a headless server wants.

      `Restart=on-failure` rather than `always`, for the reason launchd gets
      `SuccessfulExit=false`: a clean exit is somebody stopping it on purpose.
    */
    return QStringLiteral("[Unit]\n"
                          "Description=Simorg background agent\n"
                          "Documentation=https://simorg.tech\n"
                          "After=network-online.target\n"
                          "Wants=network-online.target\n"
                          "\n"
                          "[Service]\n"
                          "Type=simple\n"
                          "ExecStart=%1\n"
                          "Restart=on-failure\n"
                          "RestartSec=5\n"
                          "\n"
                          "[Install]\n"
                          "WantedBy=default.target\n")
        .arg(systemdExecLine(command));
}

QString AutostartService::entryFilePath() const
{
    const QString home = QDir::homePath();

#ifdef Q_OS_MACOS
    return home + QStringLiteral("/Library/LaunchAgents/") + entryName(m_target)
        + QStringLiteral(".plist");
#elif defined(Q_OS_WIN)
    return {}; // The registry, not a file.
#else
    const QString configHome = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    if (m_target == AutostartTarget::Daemon) {
        return configHome + QStringLiteral("/systemd/user/") + entryName(m_target)
            + QStringLiteral(".service");
    }
    return configHome + QStringLiteral("/autostart/") + entryName(m_target)
        + QStringLiteral(".desktop");
#endif
}

QString AutostartService::location() const
{
#ifdef Q_OS_WIN
    return QStringLiteral("%1\\%2").arg(QLatin1String(kWindowsRunKey), entryName(m_target));
#else
    return QDir::toNativeSeparators(entryFilePath());
#endif
}

bool AutostartService::isSupported() const
{
    // A pointer at a binary that is not there fails silently at every boot from
    // then on, which is worse than a checkbox that is honestly unavailable.
    return m_command.isValid() && QFileInfo::exists(m_command.program);
}

bool AutostartService::isEnabled() const
{
    if (!isSupported())
        return false;

#ifdef Q_OS_WIN
    QSettings run(QLatin1String(kWindowsRunKey), QSettings::NativeFormat);
    const QString value = run.value(entryName(m_target)).toString();
    // Compared against what *this* build would write: an entry left by an older
    // install, pointing somewhere else, is not this one being enabled.
    return !value.isEmpty() && value == m_command.toWindowsCommandLine();
#else
    QFile file(entryFilePath());
    if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    const QString contents = QString::fromUtf8(file.readAll());

    /*
      The path has to appear, and on Linux the entry must not be one somebody
      disabled in a desktop tweak tool. Reading rather than merely stat-ing is
      what makes "enabled" mean "would actually start this binary".

      On Linux it is the whole line this build would write that has to be
      there, not the path alone: quoting changes how a path is spelled, and
      the line is what says which program with which arguments.
    */
#ifdef Q_OS_MACOS
    return contents.contains(m_command.program);
#else
    const QString line = m_target == AutostartTarget::Daemon
                             ? QStringLiteral("ExecStart=") + systemdExecLine(m_command)
                             : QStringLiteral("Exec=") + xdgExecLine(m_command);
    if (!contents.split(QLatin1Char('\n')).contains(line))
        return false;
    return !contents.contains(QLatin1String("X-GNOME-Autostart-enabled=false"));
#endif
#endif
}

bool AutostartService::hasEntry() const
{
#ifdef Q_OS_WIN
    QSettings run(QLatin1String(kWindowsRunKey), QSettings::NativeFormat);
    return run.contains(entryName(m_target));
#else
    return QFileInfo::exists(entryFilePath());
#endif
}

bool AutostartService::setEnabled(bool enabled)
{
    setLastError(QString());

    // Only creating needs the program; an entry of this name is removed
    // whatever it pointed at.
    if (enabled && !isSupported()) {
        setLastError(m_command.isValid()
                         ? tr("%1 is not installed on this computer.").arg(m_command.program)
                         : tr("Simorg could not find the program to start."));
        Q_EMIT changed();
        return false;
    }

#ifdef Q_OS_WIN
    QSettings run(QLatin1String(kWindowsRunKey), QSettings::NativeFormat);
    if (enabled)
        run.setValue(entryName(m_target), m_command.toWindowsCommandLine());
    else
        run.remove(entryName(m_target));
    run.sync();

    if (run.status() != QSettings::NoError) {
        setLastError(tr("Windows would not update the startup list."));
        Q_EMIT changed();
        return false;
    }
#else
    const QString path = entryFilePath();
    const bool written = enabled
#ifdef Q_OS_MACOS
        ? writeEntryFile(path, launchAgentPlist(entryName(m_target), m_command))
#else
        ? writeEntryFile(path, m_target == AutostartTarget::Daemon
                                   ? systemdUserUnit(m_command)
                                   : xdgAutostartEntry(m_command))
#endif
        : removeEntryFile(path);

    if (!written) {
        Q_EMIT changed();
        return false;
    }

#ifdef Q_OS_LINUX
    /*
      systemd has to be told the unit file exists.

      Failures here are reported but not fatal: the unit is on disk and will be
      picked up at the next login even if `systemctl` is missing entirely, which
      it is inside a container and on the handful of distributions that do not
      use systemd.
    */
    if (m_target == AutostartTarget::Daemon) {
        QProcess::execute(QStringLiteral("systemctl"),
                          {QStringLiteral("--user"), QStringLiteral("daemon-reload")});
        const int code = QProcess::execute(
            QStringLiteral("systemctl"),
            {QStringLiteral("--user"), enabled ? QStringLiteral("enable")
                                               : QStringLiteral("disable"),
             entryName(m_target) + QStringLiteral(".service")});
        if (code != 0) {
            qCWarning(lcApp) << "systemctl --user" << (enabled ? "enable" : "disable")
                             << "returned" << code;
        }
    }
#endif
#endif

    /*
      Read back rather than trusted.

      A sandbox, a managed device policy or a read-only home can accept a write
      and discard it. Telling somebody the box is ticked when the entry is not
      there is the one outcome worth going out of the way to prevent. A removal
      is read back as the entry being gone, not merely as no longer this
      build's: one pointing elsewhere is not enabled, and still runs at login.
    */
    if ((enabled ? isEnabled() : hasEntry()) != enabled) {
        setLastError(enabled ? tr("The startup entry could not be created.")
                             : tr("The startup entry could not be removed."));
        Q_EMIT changed();
        return false;
    }

    qCInfo(lcApp) << "autostart" << entryName(m_target) << (enabled ? "enabled" : "disabled")
                  << "at" << location();
    Q_EMIT changed();
    return true;
}

bool AutostartService::writeEntryFile(const QString &path, const QString &contents)
{
    ensureDirectory(QFileInfo(path).absolutePath());

    // QSaveFile: a half-written plist is a login that fails with nothing to
    // read, and this cannot leave one behind.
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setLastError(tr("Could not write %1.").arg(QDir::toNativeSeparators(path)));
        return false;
    }
    file.write(contents.toUtf8());
    if (!file.commit()) {
        setLastError(tr("Could not write %1.").arg(QDir::toNativeSeparators(path)));
        return false;
    }
    return true;
}

bool AutostartService::removeEntryFile(const QString &path)
{
    // Already gone is the outcome asked for, not a failure.
    if (!QFile::exists(path))
        return true;
    if (QFile::remove(path))
        return true;
    setLastError(tr("Could not remove %1.").arg(QDir::toNativeSeparators(path)));
    return false;
}

void AutostartService::setLastError(const QString &message)
{
    m_lastError = message;
    if (!message.isEmpty())
        qCWarning(lcApp) << "autostart:" << message;
}

} // namespace simorg
