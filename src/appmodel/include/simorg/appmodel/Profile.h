// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QJsonObject>
#include <QMetaType>
#include <QString>

namespace simorg::app {

/**
 * The signed-in account, as QML reads it off `Auth.user`.
 *
 * A value rather than an object so it can be copied freely and still be read
 * property by property from QML. Built from the service's `auth.profile`,
 * which already carries the
 * display name and the handle; the property names are the ones the windows have
 * always bound to.
 */
class Profile
{
    Q_GADGET
    Q_PROPERTY(int id MEMBER id CONSTANT)
    Q_PROPERTY(QString email MEMBER email CONSTANT)
    Q_PROPERTY(QString username MEMBER username CONSTANT)
    Q_PROPERTY(QString title MEMBER title CONSTANT)
    Q_PROPERTY(QString tagline MEMBER tagline CONSTANT)
    Q_PROPERTY(QString avatarUrl MEMBER avatarUrl CONSTANT)
    Q_PROPERTY(QString actingTitle MEMBER actingTitle CONSTANT)
    Q_PROPERTY(QString themePreference MEMBER themePreference CONSTANT)
    Q_PROPERTY(bool prefersDarkTheme READ prefersDarkTheme CONSTANT)
    Q_PROPERTY(QString initials READ initials CONSTANT)
    Q_PROPERTY(QString displayName MEMBER displayName CONSTANT)
    Q_PROPERTY(QString handle MEMBER handle CONSTANT)
    Q_PROPERTY(bool valid READ isValid CONSTANT)

public:
    int id = 0;
    QString email;
    QString username;
    QString title;
    QString tagline;
    QString avatarUrl;
    QString actingTitle;
    /** `LIGHT` or `DARK`; empty reads as dark, the only theme this app had before accounts chose. */
    QString themePreference;
    QString displayName;
    /** `@ada`, or empty when the account has no username. */
    QString handle;

    bool isValid() const { return id > 0; }
    bool prefersDarkTheme() const;
    /** Two letters for an avatar: the first two words' initials, or the first two characters. */
    QString initials() const;

    /** From `auth.profile`'s data; an invalid profile from null or an empty object. */
    static Profile fromService(const QJsonObject &profile);

    bool operator==(const Profile &other) const;
    bool operator!=(const Profile &other) const { return !(*this == other); }
};

} // namespace simorg::app

Q_DECLARE_METATYPE(simorg::app::Profile)
