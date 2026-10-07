// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * How much of a log this application keeps.
 *
 * ## Why this view exists
 *
 * The cap was five thousand lines and it was compiled in. Nothing said so: a
 * window left open on a busy container read "5000 lines" for ever, and the
 * first hour of output had been dropped without a word. Whether five thousand
 * is the right number depends entirely on what somebody is doing — generous for
 * watching an agent come up, useless for finding the one stack trace in a
 * night's output — which makes it a question rather than a constant.
 *
 * ## The one setting on this page that is not about this computer
 *
 * Everything else under Settings is a fact about the machine: where the cache
 * is, whether the app starts with the session, what an agent may reach here.
 * This is a statement about how much scrollback *this person* wants, so it is
 * stored on their account and follows them to their other computers. The panel
 * says which, because a page whose settings are written in two different places
 * has to say which is which.
 */
Item {
    id: root

    /*
      The field's own text, not the setting.

      A number being typed passes through states that are not numbers — an empty
      box, a single digit — and binding the setting to it would apply "1" on the
      way to "100000" and drop a log window to its floor while somebody was
      still typing. So the field holds text, the setting is written when the
      typing stops, and the two are re-synchronised whenever the setting moves
      underneath.
    */
    property string draft: String(LogSettings.maxLines)

    /*
      Set rather than bound, in both directions.

      `text: root.draft` would be a binding the first keystroke destroys — QML
      drops a binding the moment something assigns to the property behind it —
      and the field would then stop following the setting for the rest of the
      session, which is exactly when it has to follow it: after a save, after
      the account's answer arrives, after a value out of range is refused.
    */
    function syncDraft() {
        root.draft = String(LogSettings.maxLines);
        lines.text = root.draft;
    }

    /** What is in the box, as a number. Zero when it is not one. */
    readonly property int typed: {
        const value = parseInt(root.draft, 10);
        return isNaN(value) ? 0 : value;
    }

    readonly property bool outOfRange: root.typed < LogSettings.minimumLines
                                       || root.typed > LogSettings.maximumLines

    function commit() {
        if (root.outOfRange) {
            // Put the field back rather than clamping silently. Somebody who
            // typed 50 asked for something this cannot do, and a box that
            // quietly became 200 would not have told them.
            root.syncDraft();
            return;
        }
        LogSettings.apply(root.typed, LogSettings.unlimited);
    }

    onVisibleChanged: if (visible) root.syncDraft()

    Connections {
        target: LogSettings
        function onChanged() {
            // Not while somebody is typing into it: the account's answer
            // arriving mid-edit must not replace what they are in the middle of.
            if (!lines.editing)
                root.syncDraft();
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
                Layout.maximumWidth: 860
                Layout.fillWidth: true
                Layout.leftMargin: 34
                Layout.rightMargin: 34
                Layout.topMargin: 26
                Layout.bottomMargin: 34
                spacing: Theme.spaceLg

                // ---- How many lines --------------------------------------
                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: retention.implicitHeight + 40

                        ColumnLayout {
                            id: retention
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph {
                                    name: "terminal"
                                    size: 16
                                    thickness: 1.7
                                    tone: Theme.cyan
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Log window")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }

                                BusyRing {
                                    visible: LogSettings.busy
                                    running: LogSettings.busy
                                    size: 15
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("A log window holds its lines in this computer's memory. When it reaches the number below, the oldest line is dropped as each new one arrives, so the window stays the same size however long it is left open.")
                                color: Theme.textBody
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                SimorgTextField {
                                    id: lines
                                    Layout.preferredWidth: 200
                                    enabled: !LogSettings.unlimited
                                    label: qsTr("Lines kept")
                                    glyph: "layers"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    maximumLength: 8
                                    errorText: root.outOfRange && root.draft.length > 0
                                               ? qsTr("Between %1 and %2")
                                                 .arg(LogSettings.minimumLines)
                                                 .arg(LogSettings.maximumLines)
                                               : ""
                                    onTextChanged: root.draft = text
                                    Component.onCompleted: root.syncDraft()
                                    onAccepted: root.commit()
                                    // Clicking away is the other way somebody
                                    // finishes with a field, and it has to mean
                                    // the same thing as pressing Return.
                                    onEditingChanged: if (!editing) root.commit()
                                }

                                Item { Layout.fillWidth: true }
                            }

                            SimorgCheckBox {
                                Layout.fillWidth: true
                                checked: LogSettings.unlimited
                                text: qsTr("Keep every line, however many there are")
                                onToggled: function (checked) {
                                    /*
                                      The number goes with it, unchanged.

                                      Unticking this has to give somebody back
                                      the figure they typed rather than the
                                      default — a box that forgets what you set
                                      the moment you tick something beside it is
                                      one you stop trusting.
                                    */
                                    LogSettings.apply(LogSettings.maxLines, checked);
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: LogSettings.unlimited
                                text: qsTr("Nothing is dropped. A container that prints steadily for a day will hold a day of output in memory, and this computer is where that memory comes from.")
                                color: Theme.amber
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Stored on your account, so it follows you to your other computers. Everything else under Settings is a fact about this machine.")
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: LogSettings.lastError.length > 0
                                text: LogSettings.lastError
                                color: Theme.rose
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }
                        }
                    }
                }

                // ---- And what it does not cover --------------------------
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: scope.implicitHeight + 40

                        ColumnLayout {
                            id: scope
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph {
                                    name: "info"
                                    size: 16
                                    thickness: 1.7
                                    tone: Theme.sky
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("What this applies to")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Every window in this application that shows lines of output: an agent's container log, the engine's log under Docker, and the activity log. They share one setting because they are one component.")
                                color: Theme.textBody
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Not the activity log under Agents, which is a record of what the platform and this computer did rather than output from a program. It is written to a file, kept separately, and is not held in memory.")
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Nothing here changes what a container itself keeps. Docker holds its own copy, and this is only how much of it is read into this window.")
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
