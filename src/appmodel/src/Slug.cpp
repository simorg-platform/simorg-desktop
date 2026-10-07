// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/Slug.h"

#include <QCoreApplication>
#include <QRegularExpression>

namespace simorg::app::slug {
namespace {

/** `^[a-z0-9]+(-[a-z0-9]+)*$`: lowercase words, single hyphens between them. */
const QRegularExpression &shape()
{
    static const QRegularExpression pattern(QStringLiteral("^[a-z0-9]+(-[a-z0-9]+)*$"));
    return pattern;
}

QString tr(const char *text)
{
    return QCoreApplication::translate("Slug", text);
}

} // namespace

bool isValid(const QString &value)
{
    return !value.isEmpty() && value.length() <= maxLength && shape().match(value).hasMatch();
}

QString problem(const QString &value)
{
    // In the service's order, so the first problem named is the same one.
    if (value.isEmpty())
        return tr("Enter a name.");
    if (value.length() > maxLength)
        return tr("Use at most %1 characters.").arg(maxLength);
    if (value.contains(QRegularExpression(QStringLiteral("[A-Z]"))))
        return tr("Use lowercase letters only.");
    if (value.startsWith(QLatin1Char('-')) || value.endsWith(QLatin1Char('-')))
        return tr("A handle cannot start or end with a hyphen.");
    if (value.contains(QLatin1String("--")))
        return tr("Use a single hyphen between words.");
    if (!shape().match(value).hasMatch())
        return tr("Use lowercase letters, digits and single hyphens only.");
    return {};
}

QString fromText(const QString &text)
{
    if (text.isEmpty())
        return {};

    // Compatibility decomposition splits an accented letter into its base and a mark, and the marks go: "Café" is
    // "cafe".
    const QString decomposed = text.normalized(QString::NormalizationForm_KD);
    QString value;
    value.reserve(decomposed.size());
    for (const QChar &ch : decomposed) {
        if (ch.category() != QChar::Mark_NonSpacing)
            value.append(ch);
    }

    // A lowercase-then-uppercase boundary is a word boundary ("MacBook" is two), and so is the end of an acronym
    // ("SMac" is "S" then "Mac").
    value.replace(QRegularExpression(QStringLiteral("([a-z])([A-Z])")), QStringLiteral("\\1-\\2"));
    value.replace(QRegularExpression(QStringLiteral("([A-Z]+)([A-Z][a-z])")), QStringLiteral("\\1-\\2"));

    value = value.toLower();
    value.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    value.remove(QRegularExpression(QStringLiteral("^-|-$")));
    return value.left(maxLength).remove(QRegularExpression(QStringLiteral("-$")));
}

} // namespace simorg::app::slug
