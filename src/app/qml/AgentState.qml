// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

pragma Singleton

import QtQuick
import Simorg

/**
 * What each container state looks like and what it is called.
 *
 * A singleton because several screens draw the same eight states — the card on
 * the Overview, the pill on the agent's own page, and the log pane's header —
 * and some of them had already been written twice by hand. The
 * failure that produces is not a crash: it is one screen calling a state
 * "Stopped" while another calls it "Exited", which nobody catches because both
 * are reasonable words.
 *
 * The names come from {@link simorg::agentContainerStateName}, so this is the
 * one place where the C++ vocabulary is turned into English and colour.
 */
QtObject {
    id: root

    /** One colour per state, so a wall of rows can be scanned. */
    function tone(stateName) {
        switch (stateName) {
        case "running": return Theme.emerald;
        case "starting": return Theme.amber;
        case "stopped": return Theme.textMuted;
        case "image-missing": return Theme.amber;
        // Not amber. A missing image is an errand; an image that is not the one
        // this build was made with is a refusal, and it should not sit in a
        // list looking like something that will sort itself out.
        case "image-untrusted": return Theme.danger;
        case "conflict": return Theme.rose;
        case "failed": return Theme.danger;
        case "unavailable": return Theme.textFaint;
        default: return Theme.textFaint;
        }
    }

    /**
     * The state in words, with the one reading a container's state alone cannot
     * give: an agent placed here that nobody has started is **Not started**, not
     * Stopped — nothing stopped it, and it waits for somebody to press Start.
     * `lifecycle` is the row's `lifecycle` role.
     */
    function labelFor(stateName, lifecycle) {
        if (stateName === "stopped" && lifecycle && lifecycle.notStarted === true)
            return qsTr("Not started");
        return root.label(stateName);
    }

    /** The state in words. Never a colour on its own. */
    function label(stateName) {
        switch (stateName) {
        case "running": return qsTr("Running");
        case "starting": return qsTr("Starting…");
        case "stopped": return qsTr("Stopped");
        case "image-missing": return qsTr("Image missing");
        case "image-untrusted": return qsTr("Image not verified");
        case "conflict": return qsTr("Name taken");
        case "failed": return qsTr("Failed");
        case "unavailable": return qsTr("Docker is off");
        default: return qsTr("Not checked yet");
        }
    }

    /**
     * The nearest {@link StateDot} state.
     *
     * Docker's own vocabulary is narrower than this one — it has no word for
     * "the image is not here" — so the four states Docker cannot describe are
     * mapped onto the closest thing it can, and the sentence beside the dot
     * carries the difference.
     */
    function dot(stateName) {
        switch (stateName) {
        case "running": return "running";
        case "starting": return "restarting";
        case "failed":
        case "image-untrusted":
        case "conflict": return "dead";
        default: return "exited";
        }
    }
}
