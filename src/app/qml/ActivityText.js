// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
.pragma library

/**
 * One entry of the activity journal, as the line every front end writes.
 *
 * The journal is shown in three places — the Activity tab, the few recent lines
 * on an agent's own page, and Simorg CLI's `sim logs` in a terminal — and a log that spelled
 * an event differently in two of them would make a bug report say two things
 * about one event. So the layout lives here, once, and is a copy of the one
 * `simorg::ActivityEntry::oneLine` writes on the service's side.
 *
 * A `.pragma library` for the reason `Platform.js` is one: the same question is
 * asked from two components, and two copies of a format string is two copies
 * that drift.
 */

/**
 * `17:30:28  ERROR   paprika  Its container stopped.`
 *
 * The level tag is padded to a fixed six characters so the sentences line up
 * under each other when several lines are pasted together — which is what a log
 * is copied for. The subject is left out where there is none, rather than
 * leaving a gap somebody has to work out the meaning of; on an agent's own page
 * there never is one, because the whole panel is about that agent.
 */
function oneLine(entry) {
    if (!entry)
        return "";
    const agent = entry.agentSlug || "";
    const machine = entry.virtualMachine || "";
    const subject = agent.length > 0 ? agent : machine;
    const date = entry.dateText || "";
    const time = entry.timeText || "";
    const when = date.length > 0 ? date + " " + time : time;
    const tag = ((entry.levelTag || "") + "      ").substring(0, 6);
    const message = entry.message || "";
    return subject.length > 0
           ? when + "  " + tag + "  " + subject + "  " + message
           : when + "  " + tag + "  " + message;
}

/** A run of entries as text, newest last, ready for the clipboard. */
function asText(entries) {
    const lines = [];
    for (let i = 0; i < entries.length; ++i)
        lines.push(oneLine(entries[i]));
    return lines.join("\n");
}
