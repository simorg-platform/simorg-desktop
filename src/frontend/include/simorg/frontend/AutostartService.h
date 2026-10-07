// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

namespace simorg {

/** What should be started when the computer is. */
enum class AutostartTarget {
    /**
     * The tray application, started with no window shown.
     *
     * The thing a person wants running on their own laptop: it appears in the
     * menu bar, holds the Hub session, and opens its window when asked.
     */
    DesktopApp,
    /**
     * The headless daemon an older release started at login, for a machine with
     * nobody sitting at it: the Simorg machine service is that now, so an entry
     * of this kind is only ever taken away (removeCommandsAndLoginItems).
     */
    Daemon,
};

/** The program and arguments an autostart entry should run. */
struct AutostartCommand
{
    QString program;
    QStringList arguments;

    bool isValid() const { return !program.isEmpty(); }
    /** `"C:\…\simorg-desktop.exe" --background`, quoted for a Windows registry value. */
    QString toWindowsCommandLine() const;
};

/**
 * Starting Simorg when the computer starts.
 *
 * One class, three mechanisms, because there is no portable one — and each
 * platform has a *correct* answer that is not a matter of taste:
 *
 * | | Desktop app | Daemon |
 * |---|---|---|
 * | **macOS** | `~/Library/LaunchAgents/<label>.plist` | the same, different label |
 * | **Linux** | an XDG entry in `~/.config/autostart` | a systemd **user** unit |
 * | **Windows** | `HKCU\\…\\CurrentVersion\\Run` | the same, different value name |
 *
 * The Linux split is the one that matters. An XDG autostart entry only fires
 * when somebody logs into a desktop session, which is exactly right for a tray
 * app and useless for a server nobody logs into graphically. A systemd user
 * unit with lingering enabled starts at boot and stays up, which is exactly
 * wrong for a tray app that would then have no display to draw on.
 *
 * ## Per-user, never system-wide
 *
 * Every mechanism here writes inside the user's own home directory or their own
 * registry hive. Nothing needs administrator rights, nothing is written to
 * `/etc` or `HKLM`, and nothing affects anybody else who uses the computer. A
 * background agent that holds one person's session has no business being
 * installed for everybody, and asking for a password to tick a checkbox would
 * be a bad trade.
 *
 * ## What is testable
 *
 * The file contents and the paths are pure functions and are unit tested. What
 * cannot be tested on a build machine is whether the operating system honours
 * them, so every write is verified by reading the entry back.
 */
class AutostartService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supported READ isSupported CONSTANT)
    Q_PROPERTY(bool enabled READ isEnabled NOTIFY changed)
    Q_PROPERTY(QString location READ location CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    /**
     * @param target which of the two programs this instance manages.
     * @param command what to run. Defaults to {@link defaultCommand}, which
     *   resolves the right binary beside the running one.
     */
    explicit AutostartService(AutostartTarget target, AutostartCommand command = {},
                              QObject *parent = nullptr);

    /**
     * Whether this build can manage an autostart entry at all.
     *
     * False on a platform with no mechanism this code knows, and false when the
     * program it would point at cannot be found — an entry naming a binary that
     * is not there is worse than no entry, because it fails silently at every
     * boot from then on.
     */
    bool isSupported() const;

    /** Whether the entry exists **and** points at the current binary. */
    bool isEnabled() const;

    /**
     * Whether an entry of this target's name exists at all, wherever it points.
     *
     * Not {@link isEnabled}: an entry an older copy left, naming a program that
     * has moved or gone, is not this one being enabled, but it is still Simorg's
     * and still runs at every login — which is what removing Simorg has to find.
     */
    bool hasEntry() const;

    /**
     * Creates or removes the entry, and reports whether it worked.
     *
     * Verified by reading back rather than trusted: a write that a sandbox or a
     * policy quietly discarded must not be reported to somebody as a checkbox
     * that is now ticked. Removing needs nothing to be installed: it takes away
     * the entry of this name, wherever that pointed.
     */
    Q_INVOKABLE bool setEnabled(bool enabled);

    /**
     * Where the entry lives, in words a person could act on.
     *
     * Shown in the interface, because "it did not work" is unanswerable without
     * it and because somebody removing Simorg deserves to know what it left
     * behind.
     */
    QString location() const;

    /** Why the last {@link setEnabled} failed, or empty. */
    QString lastError() const { return m_lastError; }

    /** The command this instance would install. */
    AutostartCommand command() const { return m_command; }

    // ---- Pure helpers, exercised directly by tests ----------------------

    /**
     * What to run for a target, resolved next to the running executable:
     * {@link commandFor} with this process's directory and, on Linux, the
     * AppImage it was started from (`APPIMAGE`).
     */
    static AutostartCommand defaultCommand(AutostartTarget target);

    /**
     * What to run for a target when the running program is in
     * `programDirectory` and was started from the AppImage `appImage` — empty
     * when it was not, and ignored off Linux.
     *
     * On Linux the AppImage wins whenever there is one. Started from it, the
     * program runs from a mount its runtime makes (`/tmp/.mount_…`) under a new
     * name every time and takes away when it ends, so an entry naming anything
     * inside it would start nothing at the next login, and would not even be
     * recognised by the next run as this one. The AppImage stays where it was,
     * and its AppRun starts the app (scripts/package-driver.sh). Without one, the bundle's
     * launcher above `bin/` comes before the program itself: it is what offers
     * the loader `lib/fallback/` on a machine that has no sound library of its
     * own (scripts/bundle-linux.sh).
     */
    static AutostartCommand commandFor(AutostartTarget target, const QString &programDirectory,
                                       const QString &appImage);

    /** Reverse-DNS label / unit / registry-value name for a target. */
    static QString entryName(AutostartTarget target);

    /** A launchd property list that runs `command` at login and keeps it up. */
    static QString launchAgentPlist(const QString &label, const AutostartCommand &command);

    /** An XDG autostart desktop entry. Its `Exec=` quoted as the Desktop Entry Specification asks. */
    static QString xdgAutostartEntry(const AutostartCommand &command);

    /** A systemd **user** unit that restarts the daemon if it dies. Its `ExecStart=` quoted as systemd asks. */
    static QString systemdUserUnit(const AutostartCommand &command);

Q_SIGNALS:
    /** The entry was created or removed, or an attempt failed. */
    void changed();

private:
    bool writeEntryFile(const QString &path, const QString &contents);
    bool removeEntryFile(const QString &path);
    /** The file this target's entry lives in, on the platforms that use one. */
    QString entryFilePath() const;
    void setLastError(const QString &message);

    AutostartTarget m_target;
    AutostartCommand m_command;
    QString m_lastError;
};

} // namespace simorg
