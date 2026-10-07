// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/Profile.h"

#include <QRegularExpression>
#include <QStringList>

namespace simorg::app {

bool Profile::prefersDarkTheme() const
{
    return themePreference.compare(QStringLiteral("LIGHT"), Qt::CaseInsensitive) != 0;
}

QString Profile::initials() const
{
    const QString source = displayName.trimmed();
    if (source.isEmpty())
        return QStringLiteral("?");
    static const QRegularExpression space(QStringLiteral("\\s+"));
    const QStringList words = source.split(space, Qt::SkipEmptyParts);
    if (words.size() >= 2)
        return (words.first().left(1) + words.at(1).left(1)).toUpper();
    return source.left(2).toUpper();
}

Profile Profile::fromService(const QJsonObject &profile)
{
    Profile result;
    if (profile.isEmpty())
        return result;
    const auto text = [&profile](const char *key) { return profile.value(QLatin1String(key)).toString(); };
    result.id = profile.value(QStringLiteral("id")).toInt();
    result.email = text("email");
    result.username = text("username");
    result.title = text("title");
    result.tagline = text("tagline");
    result.avatarUrl = text("avatar_url");
    result.actingTitle = profile.value(QStringLiteral("acting")).toObject().value(QStringLiteral("title")).toString();
    result.themePreference = text("theme_preference");
    result.displayName = text("display_name");
    result.handle = text("handle");
    return result;
}

bool Profile::operator==(const Profile &other) const
{
    return id == other.id && email == other.email && username == other.username && title == other.title
           && tagline == other.tagline && avatarUrl == other.avatarUrl && actingTitle == other.actingTitle
           && themePreference == other.themePreference && displayName == other.displayName && handle == other.handle;
}

} // namespace simorg::app
