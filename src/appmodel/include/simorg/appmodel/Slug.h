// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

/**
 * The platform's naming rule for handles, as the naming window checks it while
 * somebody types.
 *
 * A typing aid and not the authority: the Simorg machine service holds the rule
 * and refuses a handle it does not accept when the name is saved. Answered here because a
 * field's message and the suggested handle follow each keystroke, and a request per
 * keystroke would leave the field a step behind the person typing. The messages are
 * the service's, word for word; the suggestion is this port's and agrees with the
 * service's for Latin text.
 */
namespace simorg::app::slug {

/** The longest handle, in characters. */
inline constexpr int maxLength = 30;

/** Whether `value` is a handle. */
bool isValid(const QString &value);

/** Why `value` is not a handle, in a sentence; empty when it is one. */
QString problem(const QString &value);

/** The handle `text` suggests: "Ada's MacBook Pro" is `ada-s-mac-book-pro`. Empty when nothing is left. */
QString fromText(const QString &text);

} // namespace simorg::app::slug
