// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QString>

namespace simorg::client {

/** `dev` or `prod`: every path, port and file of the service is per environment. */
bool isEnvironmentName(const QString &name);

/**
 * The run directory of the user's own service:
 * `SIMORG_RUN_DIR` when set, otherwise `~/Library/Application Support/Simorg/run`
 * on macOS, `$XDG_RUNTIME_DIR/simorg` or else `~/.local/state/simorg/run` on
 * Linux, and `%LOCALAPPDATA%\Simorg\run` on Windows.
 */
QString runDirectory();

/**
 * The configuration directory of the user's own service:
 * `SIMORG_CONFIG_DIR` when set, otherwise `~/Library/Application Support/Simorg`
 * on macOS, `$XDG_CONFIG_HOME/simorg` or else `~/.config/simorg` on Linux, and
 * `%APPDATA%\Simorg` on Windows.
 *
 * What the service leaves there for a front end to read while it is down — the
 * inventory and the journal — and where this app's own crash marker goes.
 */
QString configDirectory();

/** `<run dir>/simorgm-<environment>.json`. */
QString discoveryFilePath(const QString &environment);

/** `<run dir>/simorgm-<environment>.stopped`. */
QString stoppedMarkerPath(const QString &environment);

/**
 * A client asked the service to stop, and it did: no client
 * starts it again on its own, only when the person asks one for something that
 * needs it. The service removes the marker when it starts.
 */
struct StoppedMarker
{
    bool present = false;
    /** The client that asked, as it named itself; empty when it named nothing. */
    QString requestedBy;
    QString stoppedAt;

    /** Reads it; a file of another user's, or one others can write, is not the service's and reads as absent. */
    static StoppedMarker read(const QString &environment);
};

/** `<run dir>/simorgm-<environment>.updating`. */
QString updatingMarkerPath(const QString &environment);

/**
 * The service is replacing itself with a newer version. No client
 * starts it meanwhile: the binary it would start is the old one, which on Windows
 * the update is replacing at that moment, and the update brings the new one up by
 * itself. Present while it names a live process or is less than five minutes old;
 * an older one is what an update that never finished left, and reads as absent.
 */
struct UpdatingMarker
{
    bool present = false;
    QString from;
    QString to;

    /** Reads it; a file of another user's, or one others can write, is not the service's and reads as absent. */
    static UpdatingMarker read(const QString &environment);
};

/** `<run dir>/simorgm-peers-<environment>.json`. */
QString peerDiscoveryFilePath(const QString &environment);

/**
 * The peer pipe a running service listens on for applications, read from its
 * peer discovery file with the same checks as {@link Discovery::read}: empty, with
 * `problem` saying why, when there is no file, or none this client can trust.
 */
QString readPeerPipe(const QString &environment, QString *problem = nullptr);

/** What a running service published about itself, read and checked. */
struct Discovery
{
    enum class Status {
        /** A file naming a live process: a service, or one that is still starting to answer. */
        Found,
        /** No file: no service. */
        Absent,
        /** A file naming a process that is gone: a service that did not stop cleanly. */
        Stale,
        /** A file this client cannot trust or understand; `problem` says why. */
        Invalid,
    };

    Status status = Status::Absent;
    QString problem;

    /** The service's own version, and the API version it speaks (`major.minor`). */
    QString version;
    QString apiVersion;
    QString environment;
    qint64 pid = 0;
    /** The socket path or pipe name. */
    QString pipe;
    /** The loopback HTTP listener, 0 when it is off or failed to bind. */
    quint16 httpPort = 0;
    /** The local token, for the loopback listeners only. */
    QByteArray token;

    /**
     * Reads `<run dir>/simorgm-<environment>.json`.
     *
     * Refused as Invalid: a file larger than 64 KiB; on macOS and Linux a file
     * owned by another user or writable by anybody else; anything that is not a
     * schema-1 `simorgm` file for this environment with a process id, a pipe and
     * a 64-character token.
     */
    static Discovery read(const QString &environment);
};

} // namespace simorg::client
