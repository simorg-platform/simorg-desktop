// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/DockerListModels.h"

#include "Support.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>

#include <algorithm>
#include <cmath>

namespace simorg::app {

using support::number;
using support::text;

// ---- Formatting ---------------------------------------------------------------------------

namespace dockerformat {

QString bytes(qint64 bytes)
{
    if (bytes < 0)
        return QStringLiteral("—");
    if (bytes < 1000)
        return QCoreApplication::translate("Docker", "%1 B").arg(bytes);
    static const char *const units[] = {"kB", "MB", "GB", "TB", "PB"};
    double value = double(bytes) / 1000.0;
    int unit = 0;
    while (value >= 1000.0 && unit < 4) {
        value /= 1000.0;
        ++unit;
    }
    return QStringLiteral("%1 %2")
        .arg(value, 0, 'f', value < 10.0 ? 2 : (value < 100.0 ? 1 : 0))
        .arg(QLatin1String(units[unit]));
}

QString percent(double value)
{
    if (!std::isfinite(value) || value < 0)
        return QStringLiteral("—");
    return QStringLiteral("%1%").arg(value, 0, 'f', value < 10.0 ? 2 : 1);
}

QString age(qint64 unixSeconds)
{
    if (unixSeconds <= 0)
        return QStringLiteral("—");
    const qint64 seconds = QDateTime::currentSecsSinceEpoch() - unixSeconds;
    // Spelled out: without a loaded translation `%n minute(s)` reaches the screen with its brackets.
    const auto ago = [](qint64 count, const QString &singular, const QString &plural) {
        return count == 1 ? QCoreApplication::translate("Docker", "1 %1 ago").arg(singular)
                          : QCoreApplication::translate("Docker", "%1 %2 ago").arg(count).arg(plural);
    };
    if (seconds < 60)
        return QCoreApplication::translate("Docker", "just now");
    if (seconds < 3600)
        return ago(seconds / 60, QStringLiteral("minute"), QStringLiteral("minutes"));
    if (seconds < 86400)
        return ago(seconds / 3600, QStringLiteral("hour"), QStringLiteral("hours"));
    if (seconds < 86400 * 30)
        return ago(seconds / 86400, QStringLiteral("day"), QStringLiteral("days"));
    if (seconds < 86400 * 365)
        return ago(seconds / (86400 * 30), QStringLiteral("month"), QStringLiteral("months"));
    return ago(seconds / (86400 * 365), QStringLiteral("year"), QStringLiteral("years"));
}

QString gibibytes(qint64 mib, int decimals)
{
    return QStringLiteral("%1 GiB").arg(double(mib) / 1024.0, 0, 'f', decimals);
}

QString megabytes(double mib)
{
    // Not finite is nothing to show: a meter whose total has not arrived divides by zero in QML, and rounding a NaN is
    // undefined behaviour (Qt asserts on it).
    if (!std::isfinite(mib) || mib <= 0)
        return QStringLiteral("0 MB");
    if (mib < 1024)
        return QCoreApplication::translate("Docker", "%1 MB").arg(qRound(mib));
    const double gib = mib / 1024.0;
    if (qFuzzyCompare(gib, double(qRound(gib))))
        return QCoreApplication::translate("Docker", "%1 GB").arg(qRound(gib));
    return QCoreApplication::translate("Docker", "%1 GB").arg(QString::number(gib, 'f', 1));
}

QString cores(double cores)
{
    if (!std::isfinite(cores) || cores <= 0)
        return QStringLiteral("0");
    if (qFuzzyCompare(cores, double(qRound(cores))))
        return QString::number(qRound(cores));
    QString text = QString::number(cores, 'f', 2);
    while (text.endsWith(QLatin1Char('0')))
        text.chop(1);
    if (text.endsWith(QLatin1Char('.')))
        text.chop(1);
    return text;
}

} // namespace dockerformat

namespace {

qint64 unixSeconds(const QJsonObject &object, const char *key)
{
    const QDateTime at = QDateTime::fromString(text(object, key), Qt::ISODateWithMs);
    return at.isValid() ? at.toSecsSinceEpoch() : 0;
}

/** A number that may be null, as a double; -1 for null, which the formatters write as `—`. */
double orUnknown(const QJsonObject &object, const char *key)
{
    const QJsonValue value = object.value(QLatin1String(key));
    return value.isDouble() ? value.toDouble() : -1.0;
}

} // namespace

// ---- KeyedRowsModel -----------------------------------------------------------------------

KeyedRowsModel::KeyedRowsModel(const char *key, QObject *parent)
    : QAbstractListModel(parent)
    , m_key(QLatin1String(key))
{
}

int KeyedRowsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariantMap KeyedRowsModel::at(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_rows.size())
        return map;
    const QHash<int, QByteArray> names = roleNames();
    for (auto it = names.constBegin(); it != names.constEnd(); ++it)
        map.insert(QString::fromUtf8(it.value()), data(index(row), it.key()));
    return map;
}

QString KeyedRowsModel::keyOf(const QJsonObject &row) const
{
    // Containers are told apart by a string id, agents and virtual machines by a number.
    const QJsonValue key = row.value(m_key);
    return key.isDouble() ? QString::number(qint64(key.toDouble())) : key.toString();
}

void KeyedRowsModel::reconcile(const QList<QJsonObject> &rows)
{
    const qsizetype before = m_rows.size();

    // Departures first, from the back, so the rows ahead of each stay where they are.
    QSet<QString> wanted;
    wanted.reserve(rows.size());
    for (const QJsonObject &row : rows)
        wanted.insert(keyOf(row));
    for (qsizetype index = m_rows.size() - 1; index >= 0; --index) {
        if (wanted.contains(keyOf(m_rows.at(index))))
            continue;
        beginRemoveRows({}, int(index), int(index));
        m_rows.removeAt(index);
        endRemoveRows();
    }

    // Then each row into its place: moved when it is further down, inserted when it is new, changed when it moved on.
    for (qsizetype target = 0; target < rows.size(); ++target) {
        const QJsonObject &incoming = rows.at(target);
        const QString key = keyOf(incoming);
        qsizetype found = -1;
        for (qsizetype search = target; search < m_rows.size(); ++search) {
            if (keyOf(m_rows.at(search)) == key) {
                found = search;
                break;
            }
        }
        if (found < 0) {
            beginInsertRows({}, int(target), int(target));
            m_rows.insert(target, incoming);
            endInsertRows();
            continue;
        }
        if (found != target) {
            beginMoveRows({}, int(found), int(found), {}, int(target));
            m_rows.move(found, target);
            endMoveRows();
        }
        if (m_rows.at(target) != incoming) {
            m_rows[target] = incoming;
            Q_EMIT dataChanged(index(int(target)), index(int(target)));
        }
    }

    if (m_rows.size() != before)
        Q_EMIT countChanged();
}

// ---- ContainerListModel -------------------------------------------------------------------

ContainerListModel::ContainerListModel(QObject *parent)
    : KeyedRowsModel("id", parent)
{
}

void ContainerListModel::apply(const QList<QJsonObject> &containers)
{
    QList<QJsonObject> sorted = containers;
    std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &left, const QJsonObject &right) {
        const bool leftRunning = text(left, "state") == QLatin1String("running");
        const bool rightRunning = text(right, "state") == QLatin1String("running");
        if (leftRunning != rightRunning)
            return leftRunning;
        const int byName = text(left, "name").compare(text(right, "name"), Qt::CaseInsensitive);
        return byName != 0 ? byName < 0 : text(left, "id") < text(right, "id");
    });
    reconcile(sorted);
}

QHash<int, QByteArray> ContainerListModel::roleNames() const
{
    return {
        {IdRole, "containerId"},
        {ShortIdRole, "shortId"},
        {NameRole, "name"},
        {ImageRole, "image"},
        {CommandRole, "command"},
        {StateRole, "state"},
        {StatusRole, "status"},
        {HealthRole, "health"},
        {PortsRole, "ports"},
        {PortsTextRole, "portsText"},
        {CreatedRole, "created"},
        {AgeRole, "age"},
        {RunningRole, "running"},
        {PausedRole, "paused"},
        {CpuPercentRole, "cpuPercent"},
        {CpuTextRole, "cpuText"},
        {MemoryUsageRole, "memoryUsage"},
        {MemoryLimitRole, "memoryLimit"},
        {MemoryTextRole, "memoryText"},
        {MemoryPercentRole, "memoryPercent"},
        {NetworkTextRole, "networkText"},
    };
}

QVariant ContainerListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &container = row(index.row());
    const QJsonObject stats = container.value(QStringLiteral("stats")).toObject();
    const bool running = text(container, "state") == QLatin1String("running");

    // `8080→80/tcp`, or `80/tcp` when nothing on this computer is bound to it.
    const auto ports = [&container] {
        QStringList described;
        for (const QJsonValue &value : container.value(QStringLiteral("ports")).toArray()) {
            const QJsonObject port = value.toObject();
            const QString type = text(port, "type").isEmpty() ? QStringLiteral("tcp") : text(port, "type");
            const qint64 publicPort = number(port, "public_port");
            const QString entry =
                publicPort > 0
                    ? QStringLiteral("%1→%2/%3").arg(publicPort).arg(number(port, "private_port")).arg(type)
                    : QStringLiteral("%1/%2").arg(number(port, "private_port")).arg(type);
            if (!described.contains(entry))
                described << entry;
        }
        return described;
    };

    switch (role) {
    case IdRole:
        return text(container, "id");
    case ShortIdRole:
        return text(container, "short_id");
    case NameRole:
        return text(container, "name");
    case ImageRole:
        return text(container, "image");
    case CommandRole:
        return text(container, "command");
    case StateRole:
        return text(container, "state");
    case StatusRole:
        return text(container, "status");
    case HealthRole:
        return text(container, "health");
    case PortsRole:
        return ports();
    case PortsTextRole: {
        // Three fit before the column elides; the rest are counted.
        const QStringList all = ports();
        if (all.size() <= 3)
            return all.join(QStringLiteral("  "));
        return QStringLiteral("%1  +%2").arg(all.mid(0, 3).join(QStringLiteral("  "))).arg(all.size() - 3);
    }
    case CreatedRole:
        return unixSeconds(container, "created_at");
    case AgeRole:
        return dockerformat::age(unixSeconds(container, "created_at"));
    case RunningRole:
        return running;
    case PausedRole:
        return text(container, "state") == QLatin1String("paused");
    case CpuPercentRole:
        return orUnknown(stats, "cpu_percent");
    case CpuTextRole:
        return running && !stats.isEmpty() ? dockerformat::percent(orUnknown(stats, "cpu_percent"))
                                           : QStringLiteral("—");
    case MemoryUsageRole:
        return stats.isEmpty() ? qint64(-1) : number(stats, "memory_usage_bytes");
    case MemoryLimitRole:
        return number(stats, "memory_limit_bytes");
    case MemoryTextRole:
        return stats.isEmpty() ? QStringLiteral("—") : dockerformat::bytes(number(stats, "memory_usage_bytes"));
    case MemoryPercentRole: {
        const qint64 limit = number(stats, "memory_limit_bytes");
        return limit > 0 ? double(number(stats, "memory_usage_bytes")) * 100.0 / double(limit) : 0.0;
    }
    case NetworkTextRole:
        if (stats.isEmpty())
            return QStringLiteral("—");
        return QStringLiteral("↓ %1   ↑ %2")
            .arg(dockerformat::bytes(number(stats, "network_rx_bytes")),
                 dockerformat::bytes(number(stats, "network_tx_bytes")));
    default:
        return {};
    }
}

// ---- ImageListModel -----------------------------------------------------------------------

ImageListModel::ImageListModel(QObject *parent)
    : KeyedRowsModel("id", parent)
{
}

void ImageListModel::apply(const QList<QJsonObject> &images)
{
    QList<QJsonObject> sorted = images;
    std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &left, const QJsonObject &right) {
        const qint64 leftSize = number(left, "size_bytes");
        const qint64 rightSize = number(right, "size_bytes");
        if (leftSize != rightSize)
            return leftSize > rightSize;
        return text(left, "id") < text(right, "id");
    });
    reconcile(sorted);
}

QHash<int, QByteArray> ImageListModel::roleNames() const
{
    return {
        {IdRole, "imageId"},
        {ShortIdRole, "shortId"},
        {RepositoryRole, "repository"},
        {TagRole, "tag"},
        {RepoTagRole, "repoTag"},
        {SizeRole, "size"},
        {SizeTextRole, "sizeText"},
        {SharedSizeRole, "sharedSize"},
        {ContainersRole, "containers"},
        {CreatedRole, "created"},
        {AgeRole, "age"},
        {DanglingRole, "dangling"},
        {InUseRole, "inUse"},
    };
}

qint64 ImageListModel::bytesOf(const QString &repository) const
{
    qint64 bytes = 0;
    for (int index = 0; index < rowCount(); ++index) {
        const QJsonObject &image = row(index);
        if (!image.value(QStringLiteral("dangling")).toBool() && text(image, "repository") == repository)
            bytes += number(image, "size_bytes");
    }
    return bytes;
}

QVariant ImageListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    const QJsonObject &image = row(index.row());
    // An image whose tag moved to a newer build keeps its digest and loses its name, as `docker images` shows.
    const bool dangling = image.value(QStringLiteral("dangling")).toBool();
    const QString repository =
        dangling || text(image, "repository").isEmpty() ? QStringLiteral("<none>") : text(image, "repository");
    const QString tag = dangling || text(image, "tag").isEmpty() ? QStringLiteral("<none>") : text(image, "tag");

    switch (role) {
    case IdRole:
        return text(image, "id");
    case ShortIdRole:
        return text(image, "short_id");
    case RepositoryRole:
        return repository;
    case TagRole:
        return tag;
    case RepoTagRole:
        return repository + QLatin1Char(':') + tag;
    case SizeRole:
        return number(image, "size_bytes");
    case SizeTextRole:
        return dockerformat::bytes(number(image, "size_bytes"));
    case SharedSizeRole:
        return number(image, "shared_size_bytes", -1);
    case ContainersRole:
        return int(number(image, "containers"));
    case CreatedRole:
        return unixSeconds(image, "created_at");
    case AgeRole:
        return dockerformat::age(unixSeconds(image, "created_at"));
    case DanglingRole:
        return dangling;
    case InUseRole:
        return number(image, "containers") > 0;
    default:
        return {};
    }
}

// ---- DockerLogModel -----------------------------------------------------------------------

DockerLogModel::DockerLogModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int DockerLogModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_lines.size());
}

QHash<int, QByteArray> DockerLogModel::roleNames() const
{
    return {{TextRole, "text"}, {ToneRole, "tone"}};
}

QVariant DockerLogModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_lines.size())
        return {};
    const Line &line = m_lines.at(index.row());
    switch (role) {
    case TextRole:
        return line.text;
    case ToneRole:
        return toneOf(line);
    default:
        return {};
    }
}

namespace {

DockerLogModel::Level levelNamed(QStringView name)
{
    using Level = DockerLogModel::Level;
    if (name == u"DEBUG")
        return Level::debug;
    if (name == u"INFO")
        return Level::info;
    if (name == u"WARNING")
        return Level::warning;
    if (name == u"ERROR")
        return Level::error;
    if (name == u"FATAL")
        return Level::fatal;
    if (name == u"USER")
        return Level::user;
    if (name == u"USER_DEBUG")
        return Level::userDebug;
    return Level::none;
}

} // namespace

DockerLogModel::Level DockerLogModel::levelOf(QStringView text)
{
    // A walk along the head rather than a regular expression: this runs once per line on a busy
    // container, and the head is a handful of characters.
    qsizetype at = 0;
    const auto skipSpaces = [&text, &at] {
        while (at < text.size() && text.at(at).isSpace())
            ++at;
    };
    skipSpaces();
    while (at < text.size() && text.at(at) == u'[') {
        const qsizetype close = text.indexOf(u']', at + 1);
        if (close < 0)
            return Level::none;
        const QStringView group = text.sliced(at + 1, close - at - 1);
        // An opening bracket inside is not a group of the head, so the head ends there.
        if (group.contains(u'['))
            return Level::none;
        if (const Level level = levelNamed(group); level != Level::none)
            return level;
        at = close + 1;
        skipSpaces();
    }
    return Level::none;
}

QString DockerLogModel::withTimesIn(const QString &text, const QTimeZone &zone)
{
    // `[2026-10-04 22:54:36.441]` at the head, the way the engine writes it: date, a space or a `T`, the time,
    // and up to three digits of a second.
    static const QRegularExpression stamp(
        QStringLiteral(R"(^(\s*\[)(\d{4}-\d{2}-\d{2})([ T])(\d{2}:\d{2}:\d{2})(?:\.(\d{1,3}))?\])"));
    const QRegularExpressionMatch match = stamp.match(text);
    if (!match.hasMatch())
        return text;
    QDateTime at = QDateTime::fromString(match.captured(2) + u'T' + match.captured(4), Qt::ISODate);
    if (!at.isValid())
        return text;
    const QString fraction = match.captured(5);
    at.setTimeZone(QTimeZone::utc());
    at = at.addMSecs(fraction.leftJustified(3, u'0').toInt()).toTimeZone(zone);

    QString moved = match.captured(1) + at.toString(QStringLiteral("yyyy-MM-dd")) + match.captured(3)
                    + at.toString(QStringLiteral("HH:mm:ss"));
    // As many digits of the second as the line had, so a column of times stays a column.
    if (!fraction.isEmpty())
        moved += u'.' + at.toString(QStringLiteral("zzz")).left(fraction.size());
    return moved + u']' + text.mid(match.capturedEnd());
}

QString DockerLogModel::toneOf(const Line &line)
{
    switch (line.level) {
    case Level::debug:
        return QStringLiteral("DEBUG");
    case Level::info:
        return QStringLiteral("INFO");
    case Level::warning:
        return QStringLiteral("WARNING");
    case Level::error:
        return QStringLiteral("ERROR");
    case Level::fatal:
        return QStringLiteral("FATAL");
    case Level::user:
        return QStringLiteral("USER");
    case Level::userDebug:
        return QStringLiteral("USER_DEBUG");
    case Level::none:
        break;
    }
    switch (line.kind) {
    case Kind::error:
        return QStringLiteral("ERROR");
    case Kind::info:
        // What an agent had an application write into its log is the agent's user speaking.
        return QStringLiteral("USER");
    case Kind::output:
        break;
    }
    return {};
}

void DockerLogModel::setCapacity(int capacity)
{
    if (m_capacity == capacity)
        return;
    m_capacity = capacity;
    Q_EMIT capacityChanged();
    if (trimToCapacity())
        Q_EMIT countChanged();
}

bool DockerLogModel::trimToCapacity()
{
    if (m_capacity <= 0 || m_lines.size() <= m_capacity)
        return false;
    // One removal for the whole excess: lowering a million-line cap to a thousand is an ordinary thing to do.
    const qsizetype excess = m_lines.size() - m_capacity;
    beginRemoveRows({}, 0, int(excess - 1));
    m_lines.remove(0, excess);
    endRemoveRows();
    return true;
}

void DockerLogModel::append(const QString &text, bool isError)
{
    insertAt(m_lines.size(), Line{text, isError ? Kind::error : Kind::output, {}});
}

void DockerLogModel::insert(const QString &text, Kind kind, const QDateTime &at)
{
    // From the end: lines arrive nearly in order, so this is almost always an append.
    qsizetype row = m_lines.size();
    while (at.isValid() && row > 0 && m_lines.at(row - 1).at.isValid() && m_lines.at(row - 1).at > at)
        --row;
    insertAt(row, Line{text, kind, at});
}

void DockerLogModel::insertAt(qsizetype row, Line line)
{
    line.level = levelOf(line.text);
    if (m_capacity > 0 && m_lines.size() >= m_capacity) {
        // A full log keeps its newest lines: one older than all of them has no place.
        if (row == 0)
            return;
        beginRemoveRows({}, 0, 0);
        m_lines.removeFirst();
        endRemoveRows();
        --row;
    }
    beginInsertRows({}, int(row), int(row));
    m_lines.insert(row, std::move(line));
    endInsertRows();
    Q_EMIT countChanged();
}

void DockerLogModel::appendBlankLine()
{
    append(QString(), false);
}

void DockerLogModel::clear()
{
    if (m_lines.isEmpty())
        return;
    beginResetModel();
    m_lines.clear();
    endResetModel();
    Q_EMIT countChanged();
}

QString DockerLogModel::lineAt(int row) const
{
    return row >= 0 && row < m_lines.size() ? m_lines.at(row).text : QString();
}

QString DockerLogModel::localLineAt(int row) const
{
    return row >= 0 && row < m_lines.size() ? withTimesIn(m_lines.at(row).text, QTimeZone::systemTimeZone())
                                            : QString();
}

QString DockerLogModel::toneAt(int row) const
{
    return row >= 0 && row < m_lines.size() ? toneOf(m_lines.at(row)) : QString();
}

QString DockerLogModel::toPlainText(bool localTimes) const
{
    const QTimeZone here = QTimeZone::systemTimeZone();
    QStringList lines;
    lines.reserve(m_lines.size());
    for (const Line &line : m_lines)
        lines << (localTimes ? withTimesIn(line.text, here) : line.text);
    return lines.join(QLatin1Char('\n'));
}

} // namespace simorg::app
