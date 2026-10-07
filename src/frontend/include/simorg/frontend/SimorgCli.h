// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>

class QProcess;

namespace simorg {

/**
 * Simorg CLI on this computer, as Settings → Overview names it: its version, or
 * that it is not installed.
 *
 * Simorg CLI is an application of its own (`@simorg/betsalel/simorg-cli`), so
 * this app carries none of it and only looks. It looks where Simorg CLI's
 * installers put it, then on PATH, and asks each program it finds what it is
 * with `version --json`; the first that answers with a version is the one
 * shown. The installers' places come first because a Mac app started from the
 * Finder has no `~/.local/bin` on its PATH.
 *
 * The machine service learns of a copy only once it registered itself,
 * on `sim setup` or `sim update`,
 * so a copy installed a minute ago is found here and not there yet.
 *
 * The command an older Simorg Desktop carried answers to the same names and
 * prints the same document, so it is told apart twice: a link to it is never
 * run, since on Linux it is the AppImage and would open the app, and a document
 * carrying `qt` is not Simorg CLI's, because Simorg CLI is built without Qt.
 */
class SimorgCli : public QObject
{
    Q_OBJECT

public:
    /**
     * @param environment this build's, `dev` or `prod`, handed to the program as `SIMORG_ENV`.
     * @param answerLimitMs how long a program has to answer before it is stopped and the next one asked:
     *   long enough for `version` to ask the machine service for its own, which it waits up to five seconds for.
     */
    explicit SimorgCli(QString environment, QObject *parent = nullptr, int answerLimitMs = 10'000);

    /** Whether a look has finished: until the first one has, nothing is known either way. */
    bool isChecked() const { return m_checked; }
    /** Its version, or empty when it is not installed, or not checked yet. */
    QString version() const { return m_version; }
    /** The program that answered, or empty. */
    QString program() const { return m_program; }

    /** Looks again, at {@link candidatesOnThisComputer}; does nothing while a look is running. */
    void check();
    /** Looks at `programs`, in order. */
    void check(const QStringList &programs);

    /**
     * Where Simorg CLI may be, in order and each program once: on macOS and
     * Linux the paths the terminal installer recorded in
     * `<dataHome>/simorg/applications/simorg-cli.installed`, then `sim` and
     * `simorg` in `~/.local/bin`, `~/bin` and every folder of `path`; on Windows `sim.exe` and `simorg.exe` in
     * `<localAppData>\Programs\Simorg CLI`, where its installer puts them, then
     * on `path`. Only programs that exist and can be run are listed, and never a
     * link an older Simorg Desktop made (`appImage` is this app's AppImage).
     */
    static QStringList candidates(const QString &home, const QString &dataHome, const QString &localAppData,
                                  const QStringList &path, const QString &appImage);

    /** {@link candidates} for the person running this app, `/usr/local/bin` first on its path. */
    static QStringList candidatesOnThisComputer();

    /**
     * The version a `version --json` printed: its `simorg`, from the document
     * or the last line that is one. Empty for anything else, the command an
     * older Simorg Desktop carried included, whose document names its `qt`.
     */
    static QString reportedVersion(const QByteArray &printed);

Q_SIGNALS:
    /** A look finished. */
    void changed();

private:
    void tryNext();
    void finish(const QString &program, const QString &version);

    const QString m_environment;
    const int m_answerLimitMs;
    QStringList m_queue;
    QPointer<QProcess> m_process;
    bool m_checked = false;
    QString m_version;
    QString m_program;
};

} // namespace simorg
