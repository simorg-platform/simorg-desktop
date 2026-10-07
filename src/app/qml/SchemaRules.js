// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
.pragma library

/**
 * The schema language, as the interface reads it.
 *
 * A shared library rather than methods on a component, because the same three
 * questions are asked in three places — the top of a form, inside a rule list's
 * row, and again when a value is collected for saving — and three copies of
 * "is this field being asked here" is three copies that drift.
 *
 * `.pragma library` so there is one instance of it rather than one per
 * importing component. Nothing here touches a QML object; these are the
 * platform's machine catalogue rules, and the platform re-applies every one of
 * them on the way in. What is here decides what somebody is *shown*.
 */

/**
 * Anything list-shaped, as a real JavaScript array.
 *
 * A list that has been through C++ — read back out of the stored settings, say
 * — arrives as a sequence wrapper rather than an `Array`. It indexes, it has a
 * length, and `JSON.stringify` renders it perfectly, but `Array.isArray` says
 * no; a guard written that way silently treated a stored folder list as empty
 * and drew the "nothing here yet" panel over the top of real settings.
 *
 * Copying rather than returning it as it is, because the copy is also what
 * makes `slice`, `splice` and `push` available to every caller that edits one.
 */
function toArray(value) {
    if (value === undefined || value === null)
        return [];
    if (Array.isArray(value))
        return value;
    // A string has a length too, and is not a list of anything here.
    if (typeof value === "object" && typeof value.length === "number") {
        const copy = [];
        for (let i = 0; i < value.length; ++i)
            copy.push(value[i]);
        return copy;
    }
    return [];
}

/**
 * Whether a field is asked at this scope.
 *
 * A field with no scope belongs to every one of them, which is nearly all of
 * them: "these programs may run" and "these commands are allowed" are answerable
 * once for a whole computer as readily as once for one agent.
 */
function inScope(field, scope) {
    const declared = String(field.scope || "");
    return declared.length === 0 || declared === scope;
}

/**
 * Whether a field's condition is met by the record it sits in.
 *
 * A sibling holding nothing counts as holding its own default — which is what
 * lets a record written before the condition existed keep meaning what it
 * meant, and what makes an out-of-scope sibling still decide the fields that
 * depend on it. `siblings` is therefore the **whole** field list, never the
 * narrowed one.
 */
function applies(field, values, siblings) {
    const on = String(field.showWhenField || "");
    if (on.length === 0)
        return true;

    let held = values ? values[on] : undefined;
    if (held === undefined || held === null || held === "") {
        for (let i = 0; i < siblings.length; ++i) {
            if (siblings[i].key === on) {
                held = siblings[i].defaultValue;
                break;
            }
        }
    }

    return String(held === undefined || held === null ? "" : held)
            === String(field.showWhenEquals);
}

/** The fields to draw: in scope, and with their condition met. */
function visibleFields(fields, values, scope) {
    const all = fields || [];
    const shown = [];
    for (let i = 0; i < all.length; ++i) {
        if (inScope(all[i], scope) && applies(all[i], values, all))
            shown.push(all[i]);
    }
    return shown;
}

/** A fresh record, from the schema's own defaults. Lists start empty. */
function defaults(fields, scope) {
    const all = fields || [];
    const record = {};
    for (let i = 0; i < all.length; ++i) {
        const field = all[i];
        if (!inScope(field, scope))
            continue;
        if (field.defaultValue !== undefined && field.defaultValue !== null) {
            record[field.key] = field.defaultValue;
        } else if (field.type === "STRING_LIST" || field.type === "RULE_LIST") {
            // Empty rather than absent, so a form can push into it without
            // every caller special-casing the first row.
            record[field.key] = [];
        }
    }
    return record;
}

/**
 * A copy with one key replaced.
 *
 * Records are replaced rather than edited in place: a QML binding on a `var`
 * holding an object does not re-evaluate when a property inside it changes, so
 * a form that mutated its own record would save correctly and display staleley.
 */
function withValue(values, key, value) {
    const next = {};
    for (const existing in values)
        next[existing] = values[existing];
    next[key] = value;
    return next;
}

/** The same, removing a key. Used where "not set" and "set to empty" differ. */
function without(values, key) {
    const next = {};
    for (const existing in values) {
        if (existing !== key)
            next[existing] = values[existing];
    }
    return next;
}

/**
 * Drops every value whose field is not being asked.
 *
 * A path typed and then hidden by a condition is an answer to a question that
 * is no longer on the screen, and it must not be saved: it would sit in the
 * record looking like a real folder. Recurses one level into a rule list, which
 * is as deep as the language goes.
 */
function trim(values, fields, scope) {
    const all = fields || [];
    const clean = {};

    for (let i = 0; i < all.length; ++i) {
        const field = all[i];
        if (!inScope(field, scope) || !applies(field, values, all))
            continue;

        const value = values ? values[field.key] : undefined;
        if (value === undefined)
            continue;

        if (field.type === "RULE_LIST") {
            const given = toArray(value);
            const rows = [];
            for (let r = 0; r < given.length; ++r)
                rows.push(trim(given[r], field.fields || [], scope));
            clean[field.key] = rows;
            continue;
        }

        clean[field.key] = value;
    }

    return clean;
}

/**
 * Whether a record says anything at all.
 *
 * An empty list counts as nothing, which is what makes "I removed the last
 * folder" clear the setting instead of storing an empty one. The distinction
 * matters downstream: "configured with nothing" and "not configured" are
 * different states and only one of them should occupy a row.
 */
function isEmpty(values) {
    for (const key in values) {
        const value = values[key];
        if (value === undefined || value === null || value === "")
            continue;
        if (typeof value === "object" && typeof value.length === "number"
                && value.length === 0)
            continue;
        return false;
    }
    return true;
}

/** Deep enough for comparing two records of scalars and one level of rows. */
function same(a, b) {
    return JSON.stringify(a || {}) === JSON.stringify(b || {});
}
