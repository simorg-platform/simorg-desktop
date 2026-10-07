// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * One resource of a virtual machine's envelope, as two sliders.
 *
 * A resource is not a number here, it is a **pair**: what the agent is
 * guaranteed, and how far it may climb. Both are set on one control because
 * they are one decision — a guarantee above its own ceiling is not a state
 * anybody meant to ask for, and this keeps the ceiling honest by pushing it up
 * with the floor rather than letting somebody build a slot the platform will
 * refuse.
 *
 * ## Why the sliders are indexed rather than continuous
 *
 * The platform offers sizes, not a range: `0.125, 0.25, 0.5, 1, 2, 3, 4, …`
 * cores. Drawn on a linear track those choices bunch into the first thirtieth
 * of the travel and nobody can pick a quarter core; drawn one step per stop,
 * every size gets the same room. So the slider runs over *positions* in the
 * list, and the value is the entry it lands on.
 *
 * ## The extra stop on the ceiling
 *
 * The far right of the ceiling slider is **Maximum allowed** — the slot takes
 * as much as the machine has spare, which is what the platform means by a null
 * ceiling. It is the last position rather than a checkbox beside the track,
 * because that is where it belongs on the scale: it is the largest thing you
 * can ask for, and asking for it is one drag rather than a drag and a tick.
 *
 * ## A ceiling alone
 *
 * The graphics card's memory has no guarantee, because nothing can reserve a
 * card's memory for anybody: {@link hasGuarantee} false draws the ceiling
 * without the floor, and says what the ceiling is in that resource's words.
 */
Item {
    id: root

    property string label: ""
    property string glyph: ""
    property color tone: Theme.cyan

    /** The sizes on offer, in the resource's own base unit. */
    property var steps: []

    /** The guarantee, in the same unit. */
    property real minimumValue: 0
    /** The ceiling. Meaningless while {@link capped} is false. */
    property real maximumValue: 0
    /** False means "as much as the machine allows". */
    property bool capped: true

    /** False for a resource with a ceiling and no floor: only the ceiling is drawn. */
    property bool hasGuarantee: true
    /** What the ceiling slider says under its label. */
    property string ceilingHint: qsTr("The most it may take while this computer is quiet.")
    /** What no ceiling is, in this resource's words, for the header. */
    property string uncappedText: qsTr("the machine's limit")

    /** How a value of this resource is written. `Docker.formatCores`, usually. */
    property var format: function (value) { return String(value); }

    /** Somebody moved the guarantee. */
    signal minimumChosen(real value)
    /** Somebody moved the ceiling; `capped` false is the last stop. */
    signal maximumChosen(real value, bool capped)

    implicitHeight: column.implicitHeight

    readonly property int stepCount: root.steps ? root.steps.length : 0
    /** The position of the last stop on the ceiling track: "Maximum allowed". */
    readonly property int uncappedIndex: root.stepCount

    /**
     * The position a value sits at, or the nearest one below it.
     *
     * Nearest rather than exact, because a slot sized in a browser — or by an
     * older list of sizes — is a perfectly legitimate number that is not on
     * this list, and a slider that snapped it to the first stop would silently
     * shrink an agent the moment somebody looked at its page.
     */
    function indexOf(value) {
        let best = 0;
        let bestGap = Infinity;
        for (let i = 0; i < root.stepCount; i++) {
            const gap = Math.abs(root.steps[i] - value);
            if (gap < bestGap) {
                best = i;
                bestGap = gap;
            }
        }
        return best;
    }

    function valueAt(index) {
        const clamped = Math.max(0, Math.min(root.stepCount - 1, Math.round(index)));
        return root.steps[clamped];
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spaceSm

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            Glyph {
                visible: root.glyph.length > 0
                name: root.glyph
                size: 15
                thickness: 1.7
                tone: Theme.alpha(root.tone, 0.9)
            }

            Text {
                Layout.fillWidth: true
                text: root.label
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            Text {
                text: !root.hasGuarantee
                      ? (root.capped ? qsTr("up to %1").arg(root.format(root.maximumValue))
                                     : root.uncappedText)
                      : root.capped
                      ? qsTr("%1 to %2").arg(root.format(root.minimumValue))
                                        .arg(root.format(root.maximumValue))
                      : qsTr("%1 to %2").arg(root.format(root.minimumValue)).arg(root.uncappedText)
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: 12
            }
        }

        ResourceSlider {
            Layout.fillWidth: true
            visible: root.hasGuarantee
            label: qsTr("Guaranteed")
            hint: qsTr("Held for this agent even while the machine is busy.")
            tone: root.tone
            enabled: root.enabled
            minimum: 0
            maximum: Math.max(0, root.stepCount - 1)
            step: 1
            value: root.indexOf(root.minimumValue)
            format: function (index) { return root.format(root.valueAt(index)); }
            onMoved: function (index) {
                const chosen = root.valueAt(index);
                root.minimumChosen(chosen);
                /*
                  A guarantee above its own ceiling is a slot the platform
                  refuses, so the ceiling is carried up rather than left behind
                  to fail on save. Only ever upwards, and never past the top of
                  the list: an uncapped ceiling is already above everything.
                */
                if (root.capped && chosen > root.maximumValue)
                    root.maximumChosen(chosen, true);
            }
        }

        ResourceSlider {
            Layout.fillWidth: true
            label: qsTr("Ceiling")
            hint: root.ceilingHint
            tone: root.tone
            enabled: root.enabled
            minimum: 0
            maximum: root.uncappedIndex
            step: 1
            value: root.capped ? root.indexOf(root.maximumValue) : root.uncappedIndex
            format: function (index) {
                return index >= root.uncappedIndex
                       ? qsTr("Maximum allowed")
                       : root.format(root.valueAt(index));
            }
            onMoved: function (index) {
                if (index >= root.uncappedIndex) {
                    root.maximumChosen(root.maximumValue, false);
                    return;
                }
                const chosen = root.valueAt(index);
                root.maximumChosen(chosen, true);
                // And the floor comes down with it, for the same reason the
                // ceiling goes up: the pair has to stay a pair.
                if (root.hasGuarantee && chosen < root.minimumValue)
                    root.minimumChosen(chosen);
            }
        }
    }
}
