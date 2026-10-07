// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

// Small readings of the service's shapes that more than one model makes.

#include <QJsonObject>
#include <QJsonValue>
#include <QLocale>
#include <QString>

namespace simorg::app::support {

/** A member that is a string, or empty for null, absent or anything else. */
inline QString text(const QJsonObject &object, const char *key)
{
    return object.value(QLatin1String(key)).toString();
}

/** A member that is a whole number, or `fallback` for null or absent. */
inline qint64 number(const QJsonObject &object, const char *key, qint64 fallback = 0)
{
    const QJsonValue value = object.value(QLatin1String(key));
    return value.isDouble() ? qint64(value.toDouble()) : fallback;
}

/** The sentence of an RFC 9457 problem the service put in a state: its detail, or else its title. Empty for null. */
inline QString problemMessage(const QJsonValue &problem)
{
    const QJsonObject object = problem.toObject();
    const QString detail = text(object, "detail");
    return detail.isEmpty() ? text(object, "title") : detail;
}

/** A size for a person, in the units a file manager uses. */
inline QString formatBytes(qint64 bytes)
{
    if (bytes <= 0)
        return QStringLiteral("0 B");
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeSIFormat);
}

} // namespace simorg::app::support
