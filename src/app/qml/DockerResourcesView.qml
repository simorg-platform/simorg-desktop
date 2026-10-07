// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * How much of this computer Docker may take.
 *
 * The only view in the section that changes anything, and it is built to make
 * that obvious: nothing is written while a slider moves, the Save button
 * appears only when there is something to save, and the fact that a restart is
 * what applies the change is stated before it is made rather than after.
 *
 * On a Linux host there is no virtual machine to size and no global limit to
 * set. Rather than greying out four controls and leaving people to guess, the
 * view says so and explains what does apply there.
 */
Item {
    id: root

    // Working copy. Editing the live values directly would write on every drag
    // frame and restart Docker's settings file a hundred times a second.
    property int cpus: 0
    property real memoryMib: 0
    property real diskMib: 0
    property bool loaded: false

    readonly property bool dirty: root.loaded
                                  && (root.cpus !== Docker.limits.cpus
                                      || root.memoryMib !== Docker.limits.memoryMib
                                      || root.diskMib !== Docker.limits.diskMib)

    /** Saving is in flight: the service has the numbers and has not answered yet. */
    readonly property bool saving: Docker.busyAction === "set_limits"
    /** The managed runtime is being restarted, which is what applies a saved size. */
    readonly property bool restarting: Docker.busyAction === "restart_engine"

    /**
     * Why the disk cannot be moved, when it cannot; empty while it can.
     *
     * A virtual disk grows and never shrinks, so its floor is the size the
     * machine already has — and on a computer with no free space left the floor
     * and the ceiling meet. The control then has nothing to offer, and saying
     * which of the two reasons it is beats a slider that ignores the pointer.
     */
    readonly property string diskStuck: {
        if (Docker.limits.maximumDiskMib > Docker.limits.minimumDiskMib)
            return "";
        if (Docker.limits.maximumDiskMib <= 0)
            return qsTr("Simorg cannot read how much room is left on this disk, so it cannot offer a larger size.");
        return qsTr("Docker's machine already has %1, and a virtual disk cannot be made smaller — there is no free space left on this computer to make it bigger.")
                   .arg(Docker.formatGibibytes(Docker.limits.minimumDiskMib, 0));
    }

    function reload() {
        root.cpus = Docker.limits.cpus;
        root.memoryMib = Docker.limits.memoryMib;
        root.diskMib = Docker.limits.diskMib;
        root.loaded = true;
    }

    Component.onCompleted: {
        reload();
        Docker.refreshGpu();
    }
    // The service keeps its answer for five minutes; asking each time the page shows costs nothing more.
    onVisibleChanged: if (visible) Docker.refreshGpu()

    Connections {
        target: Docker
        function onLimitsChanged() {
            // Somebody else's change — the CLI, or an edit to the file — is
            // taken; a half-made edit here is not clobbered by a poll.
            if (!root.dirty)
                root.reload();
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: 0

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 760
                Layout.fillWidth: true
                Layout.margins: 28
                spacing: Theme.spaceLg

                /*
                  ---- What Docker has right now -------------------------

                  First, and above the sliders, because it is the only number
                  on this screen that describes the engine actually running
                  containers. The sliders below describe a *configuration
                  file*, and on any machine where the two come apart — a Mac
                  with Colima installed and a context pointing at Docker
                  Desktop is the common one — a panel that showed only the file
                  was a panel showing a number with no relationship to the
                  containers on the next tab.
                */
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Docker.ready
                    spacing: Theme.spaceSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: qsTr("WHAT DOCKER HAS RIGHT NOW")
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontEyebrow
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1.3
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Docker.runtimeTitle
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceMd

                        StatTile {
                            Layout.fillWidth: true
                            label: qsTr("PROCESSOR CORES")
                            value: Docker.engineCpus > 0 ? String(Docker.engineCpus)
                                                         : qsTr("not reported")
                            caption: qsTr("Shared by every container here")
                            glyph: "cpu"
                            tone: Theme.cyan
                        }

                        StatTile {
                            Layout.fillWidth: true
                            label: qsTr("MEMORY")
                            value: Docker.memoryTotal > 0 ? Docker.formatBytes(Docker.memoryTotal)
                                                          : qsTr("not reported")
                            caption: qsTr("The ceiling all of them share")
                            glyph: "memory"
                            tone: Theme.violet
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Reported by the engine that is actually serving containers on this computer, which is not always the one the settings below describe.")
                        color: Theme.textFaint
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }

                    /*
                      What an agent allowed the graphics card computes on here,
                      beside the processors and the memory because it is the
                      third thing Docker has to give — and the one that most
                      often is not there for a reason somebody can fix.
                    */
                    GpuOfferPanel {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        // Only once the service has answered: one older than the graphics card never will.
                        visible: known
                        offer: Docker.gpu
                    }
                }

                // ---- Not applicable here -------------------------------
                InfoCallout {
                    Layout.fillWidth: true
                    visible: !Docker.limits.managed
                    glyph: "info"
                    tone: Theme.sky
                    title: qsTr("There is no pool to divide up on this machine")
                    body: Docker.limits.reason
                }

                Text {
                    Layout.fillWidth: true
                    visible: !Docker.limits.managed
                    text: qsTr("Where there is no virtual machine, containers are limited one at a time when they are started, rather than by a ceiling over all of them. Simorg sets those per-container limits itself when it runs work for an agent.")
                    color: Theme.textBody
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }

                // ---- The controls ---------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Docker.limits.managed
                    spacing: Theme.spaceLg

                    /*
                      Sliders that silently sized a different engine than the one
                      on screen would be worse than no sliders, so when the two
                      come apart it is said before anything is moved.
                    */
                    InfoCallout {
                        Layout.fillWidth: true
                        visible: Docker.limits.appliesToOtherEngine === true
                        glyph: "alert"
                        tone: Theme.amber
                        title: qsTr("These sliders size %1, not %2")
                                   .arg(Docker.limits.managedRuntimeTitle)
                                   .arg(Docker.limits.activeRuntimeTitle)
                        // Both engines named. "A different engine" was true and
                        // useless: the numbers below looked invented until you
                        // knew which machine on your disk they described.
                        body: qsTr("Your containers are being served by %1, and the numbers above are its. The sliders below are the size of %2, which is also on this computer and which Simorg can resize. Changing them will not affect what you see under Containers until %2 is the engine in use.")
                                  .arg(Docker.limits.activeRuntimeTitle)
                                  .arg(Docker.limits.managedRuntimeTitle)
                    }

                    // The runtime says what it is; a sentence hardcoded for one
                    // platform read very oddly on the others.
                    InfoCallout {
                        Layout.fillWidth: true
                        visible: Docker.limits.explainer.length > 0
                        glyph: "gauge"
                        tone: Theme.sky
                        title: qsTr("Docker runs in a machine of its own")
                        body: Docker.limits.explainer
                    }

                    // Says what the sliders are before anybody moves one. The
                    // readout above and the controls below describe different
                    // things whenever two engines are installed, and an
                    // unlabelled second set of numbers is what made these read
                    // as arbitrary.
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: Docker.limits.managedRuntimeTitle.length > 0
                              ? qsTr("THE SIZE OF %1").arg(Docker.limits.managedRuntimeTitle.toUpperCase())
                              : qsTr("THE SIZE DOCKER IS GIVEN")
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontEyebrow
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.3
                    }

                    GlassPanel {
                        Layout.fillWidth: true
                        implicitHeight: sliders.implicitHeight + 44

                        ColumnLayout {
                            id: sliders
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 22
                            spacing: Theme.spaceLg

                            ResourceSlider {
                                Layout.fillWidth: true
                                label: qsTr("Processor cores")
                                glyph: "cpu"
                                tone: Theme.cyan
                                hint: qsTr("This computer has %1. Leaving some free keeps everything else responsive while Docker works.")
                                          .arg(Docker.limits.hostCpus)
                                minimum: Docker.limits.minimumCpus
                                maximum: Math.max(Docker.limits.minimumCpus, Docker.limits.hostCpus)
                                step: 1
                                value: root.cpus
                                format: (v) => Math.round(v) === 1 ? qsTr("1 core")
                                                                   : qsTr("%1 cores").arg(Math.round(v))
                                onMoved: function (value) { root.cpus = Math.round(value); }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            ResourceSlider {
                                Layout.fillWidth: true
                                label: qsTr("Memory")
                                glyph: "memory"
                                tone: Theme.violet
                                hint: qsTr("Of the %1 in this computer. Docker will not start with less than %2.")
                                          .arg(Docker.formatGibibytes(Docker.limits.hostMemoryMib, 0))
                                          .arg(Docker.formatGibibytes(Docker.limits.minimumMemoryMib, 0))
                                minimum: Docker.limits.minimumMemoryMib
                                maximum: Math.max(Docker.limits.minimumMemoryMib,
                                                  Docker.limits.maximumMemoryMib)
                                step: 512
                                value: root.memoryMib
                                format: (v) => Docker.formatGibibytes(v)
                                onMoved: function (value) { root.memoryMib = value; }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            ResourceSlider {
                                Layout.fillWidth: true
                                label: qsTr("Disk limit")
                                glyph: "disk"
                                tone: Theme.amber
                                hint: root.diskStuck.length > 0
                                      ? root.diskStuck
                                      : qsTr("The most Docker's storage may grow to. It only takes what it actually uses, and right now that is %1.")
                                            .arg(Docker.formatBytes(Docker.diskTotal))
                                minimum: Docker.limits.minimumDiskMib
                                // Headroom above what is already committed —
                                // the disk is sparse, so gibibytes already
                                // promised are not in the free-space figure.
                                maximum: Math.max(Docker.limits.minimumDiskMib,
                                                  Docker.limits.maximumDiskMib)
                                step: 4096
                                value: root.diskMib
                                format: (v) => Docker.formatGibibytes(v, 0)
                                onMoved: function (value) { root.diskMib = value; }
                            }
                        }
                    }

                    /*
                      ---- Save ------------------------------------------

                      What is happening is said on this row rather than only in
                      the toast at the bottom of the window or the banner at the
                      top of the section: this is where the press was, and it is
                      where somebody is looking for the answer to it.
                    */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceSm

                        PrimaryButton {
                            text: root.saving ? qsTr("Saving…") : qsTr("Save limits")
                            visible: root.dirty
                            enabled: !root.saving
                            onClicked: Docker.applyLimits(root.cpus, root.memoryMib, root.diskMib)
                        }

                        GhostButton {
                            text: qsTr("Discard changes")
                            visible: root.dirty && !root.saving
                            onClicked: root.reload()
                        }

                        /*
                          The restart, offered where the size was saved.

                          It is what makes a saved number the machine's, and
                          leaving it to the banner across the top of the section
                          meant scrolling away from the thing just pressed to
                          finish the job it started. The section's banner stays:
                          it is for somebody who saved and walked off.
                        */
                        PrimaryButton {
                            text: root.restarting ? qsTr("Restarting Docker…") : qsTr("Restart Docker now")
                            visible: !root.dirty && Docker.restartPending
                            enabled: !root.restarting
                            onClicked: Docker.restartEngine()
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.dirty
                            text: {
                                if (root.restarting)
                                    return qsTr("Everything running is stopping and starting again with the new size.");
                                if (Docker.restartPending)
                                    return qsTr("Saved, and waiting on a restart to take effect.");
                                return qsTr("Saved. Move a slider to change anything.");
                            }
                            color: Docker.restartPending ? Theme.textMuted : Theme.textFaint
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillWidth: root.dirty }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.dirty
                        text: qsTr("Saving writes these to the runtime's own configuration. They take effect when it restarts, which Simorg can do for you afterwards. Everything running will stop and start again.")
                        color: Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.45
                    }

                    // ---- Where these live -------------------------------
                    GlassPanel {
                        Layout.fillWidth: true
                        implicitHeight: origin.implicitHeight + 34

                        ColumnLayout {
                            id: origin
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 17
                            spacing: 5

                            Text {
                                text: qsTr("WHERE THESE ARE STORED")
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontEyebrow
                                font.weight: Font.ExtraBold
                                font.letterSpacing: 1.3
                            }

                            ElidedText {
                                Layout.fillWidth: true
                                text: Docker.limits.settingsPath
                                color: Theme.textBody
                                font.pixelSize: 12
                                font.family: Theme.monoFamily
                                elide: Text.ElideMiddle
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 3
                                text: Docker.limits.storageNote
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }
                        }
                    }
                }
            }
        }
    }
}
