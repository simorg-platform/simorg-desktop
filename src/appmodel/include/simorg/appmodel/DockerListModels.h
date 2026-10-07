// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QTimeZone>

#include <cstdint>

namespace simorg::app {

/** How the Docker screens write sizes, shares and ages, as `docker` itself writes them. */
namespace dockerformat {

/** SI units, as `docker system df` means them: 1.23 GB is 1.23 × 10⁹ bytes. `—` for a negative. */
QString bytes(qint64 bytes);
QString percent(double value);
/** "just now", "3 minutes ago"; `—` for no time. */
QString age(qint64 unixSeconds);
QString gibibytes(qint64 mib, int decimals = 1);
QString megabytes(double mib);
/** Whole cores without decimals, a fraction with at most two: "2", "0.5". */
QString cores(double cores);

} // namespace dockerformat

/**
 * A list whose rows are service objects told apart by an id, changed row by row.
 *
 * A new list is applied as removals, moves, inserts and changes rather than a
 * reset, so a view keeps its scroll position and selection while the service
 * sends the same containers every few seconds.
 */
class KeyedRowsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    /** Every role of one row by its role name, for a delegate that is not a view's. */
    Q_INVOKABLE QVariantMap at(int row) const;

    /** Makes the rows `rows`, in that order. */
    void reconcile(const QList<QJsonObject> &rows);

Q_SIGNALS:
    void countChanged();

protected:
    KeyedRowsModel(const char *key, QObject *parent);
    const QJsonObject &row(int index) const { return m_rows.at(index); }

private:
    QString keyOf(const QJsonObject &row) const;

    QString m_key;
    QList<QJsonObject> m_rows;
};

/** The engine's containers for `Docker.containers`: running first, then by name. */
class ContainerListModel : public KeyedRowsModel
{
    Q_OBJECT

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        ShortIdRole,
        NameRole,
        ImageRole,
        CommandRole,
        StateRole,
        StatusRole,
        HealthRole,
        PortsRole,
        PortsTextRole,
        CreatedRole,
        AgeRole,
        RunningRole,
        PausedRole,
        CpuPercentRole,
        CpuTextRole,
        MemoryUsageRole,
        MemoryLimitRole,
        MemoryTextRole,
        MemoryPercentRole,
        NetworkTextRole,
    };

    explicit ContainerListModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** Sorts the service's `DockerContainer` list the way the screen shows it, and applies it. */
    void apply(const QList<QJsonObject> &containers);
};

/** The engine's images for `Docker.images`: the largest first. */
class ImageListModel : public KeyedRowsModel
{
    Q_OBJECT

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        ShortIdRole,
        RepositoryRole,
        TagRole,
        RepoTagRole,
        SizeRole,
        SizeTextRole,
        SharedSizeRole,
        ContainersRole,
        CreatedRole,
        AgeRole,
        DanglingRole,
        InUseRole,
    };

    explicit ImageListModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void apply(const QList<QJsonObject> &images);

    /**
     * What every tag of `repository` takes on disk, together: the agent runtime's size
     * beside Uninstall's "Also delete Simorg's data and the agent image", so the box
     * says what ticking it frees.
     */
    Q_INVOKABLE qint64 bytesOf(const QString &repository) const;
};

/**
 * The lines of one container's output for `Docker.logs` and `Docker.agentLogs`,
 * oldest first.
 *
 * Holds at most `capacity` lines (0 for no limit), which is the person's log
 * setting; lowering it drops the oldest at once, in one removal. A line is
 * output, an error (stderr), or information: what an application on this
 * computer wrote into an agent's log, such as Simorg Desktop's `userLog`.
 * A line given a time is put where that
 * time puts it, so lines from two sources read in the order they happened.
 *
 * A line is drawn by its **level** — `[DEBUG]`, `[INFO]`, `[WARNING]`,
 * `[ERROR]`, `[FATAL]`, `[USER]`, `[USER_DEBUG]`, as the engine writes them at
 * the head of every line — and by what it is only when it names none. The
 * engine writes everything to stderr, so the stream alone painted a healthy
 * agent's whole log the red of a crash. See {@link toneAt}.
 */
class DockerLogModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int capacity READ capacity WRITE setCapacity NOTIFY capacityChanged)

public:
    enum Role {
        TextRole = Qt::UserRole + 1,
        ToneRole,
    };

    /** What a line is, which decides how it is drawn when it names no level. */
    enum class Kind : std::uint8_t { output, error, info };

    /** The level a line names at its head, or `none`. */
    enum class Level : std::uint8_t { none, debug, info, warning, error, fatal, user, userDebug };

    /**
     * The level among the bracketed groups `text` opens with, and nowhere after
     * them: `[2026-10-04 22:54:36.441][ERROR][ENGINE][INVALID_PLUGIN] …` is an
     * error, and `[…][INFO][hub][X] got [ERROR] back` is information that
     * mentions one. The Logos reads a line by the same rule, so one line is the
     * same colour in both windows.
     */
    static Level levelOf(QStringView text);

    /**
     * `text` with the time it opens with moved from GMT into `zone`, in the same
     * shape: `[2026-10-04 22:54:36.441]…` is `[2026-10-05 02:24:36.441]…` in
     * Tehran. The engine stamps every line in GMT; a line that opens with no
     * time is returned as it is.
     */
    static QString withTimesIn(const QString &text, const QTimeZone &zone);

    static constexpr int defaultCapacity = 10000;

    explicit DockerLogModel(QObject *parent = nullptr);

    int capacity() const { return m_capacity; }
    void setCapacity(int capacity);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void append(const QString &text, bool isError);
    /** `text` where `at` puts it among the lines with a time: after every line at or before it. */
    void insert(const QString &text, Kind kind, const QDateTime &at);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void appendBlankLine();
    /** Every line; with `localTimes`, each line's time in this computer's own zone. */
    Q_INVOKABLE QString toPlainText(bool localTimes = false) const;
    Q_INVOKABLE QString lineAt(int row) const;
    /** {@link lineAt}, with the line's time in this computer's own zone. See {@link withTimesIn}. */
    Q_INVOKABLE QString localLineAt(int row) const;
    /**
     * How a row is drawn: its level's name — `DEBUG`, `INFO`, `WARNING`,
     * `ERROR`, `FATAL`, `USER`, `USER_DEBUG` — or, for a line that names none,
     * `ERROR` for stderr (what reaches it outside the engine's format is a
     * crash, almost always), `USER` for an application's `userLog`, and an
     * empty string for plain output.
     */
    Q_INVOKABLE QString toneAt(int row) const;

Q_SIGNALS:
    void countChanged();
    void capacityChanged();

private:
    bool trimToCapacity();

    struct Line
    {
        QString text;
        Kind kind = Kind::output;
        /** Invalid for a line given no time, which stays where it was appended. */
        QDateTime at;
        /** Read once, when the line arrives, rather than by every row that draws it. */
        Level level = Level::none;
    };
    static QString toneOf(const Line &line);
    void insertAt(qsizetype row, Line line);

    QList<Line> m_lines;
    int m_capacity = defaultCapacity;
};

} // namespace simorg::app
