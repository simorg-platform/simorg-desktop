// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The terms and the privacy notice, in the application rather than in a browser.
 *
 * ## Why a window of its own
 *
 * It is opened from two places that have nothing else in common: the tick box
 * on the sign-in window, before there is a session, and the Legal panel in
 * Settings, long after there is one. A modal inside either of those would have
 * to exist twice, and the sign-in copy would be a modal over a modal the first
 * time somebody hit an error. A window is also what every desktop application
 * uses for this, so it behaves the way a reader expects: it can be resized,
 * moved beside the sign-in window, and closed without disturbing anything.
 *
 * It is deliberately **not** modal. Somebody reading clause 7 should be able to
 * go and look at what the application is actually doing.
 *
 * ## Reading, and agreeing
 *
 * The window only ever *shows* the agreement. Accepting it is a tick box on the
 * sign-in window, and the record is written when the person actually signs in.
 * The "I agree" button here is a shortcut to that tick box, not a second way of
 * agreeing, which is why it disappears the moment the current edition has been
 * accepted.
 */
ApplicationWindow {
    id: win

    title: qsTr("Simorg Terms and Privacy")
    width: 920
    height: 780
    minimumWidth: 560
    minimumHeight: 520
    color: Theme.base

    /** Which document is on screen; an index into `Legal.documents`. */
    property int current: 0

    /** Ticks the box on the sign-in window, or records the acceptance directly. */
    signal agreed

    /** Below this the version line moves under the heading instead of beside it. */
    readonly property bool wide: width >= 680

    readonly property var documents: Legal.documents

    /**
     * Shows one document by id, from the top.
     *
     * Named `open` rather than `show` because `Window` already has a `show`,
     * and a QML function that shadows one of those is a trap for whoever calls
     * the base method next.
     *
     * By id rather than by index because the callers are a tick box that names
     * the agreement and a button that says "Privacy notice", and neither of
     * them should know what order the documents are in.
     */
    function open(documentId) {
        const index = Legal.documentIndex(documentId);
        win.current = index >= 0 ? index : 0;
        reader.scrollToTop();
        win.visible = true;
        win.raise();
        win.requestActivate();
    }

    background: Rectangle { color: Theme.base }

    AuroraBackground {
        anchors.fill: parent
    }

    // Escape closes it, the way every read-only window on every platform does.
    Shortcut {
        sequences: [StandardKey.Close, "Esc"]
        onActivated: win.close()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Heading ------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 30
            Layout.rightMargin: 30
            Layout.topMargin: 24
            Layout.bottomMargin: 16
            spacing: Theme.spaceMd

            GridLayout {
                Layout.fillWidth: true
                columns: win.wide ? 2 : 1
                columnSpacing: Theme.spaceMd
                rowSpacing: 6

                GradientText {
                    Layout.fillWidth: true
                    text: qsTr("Terms and privacy")
                    pixelSize: 24
                    horizontalAlignment: Text.AlignLeft
                }

                // The edition, stated plainly. Somebody who is asked to accept
                // something a second time is owed a way to tell the two apart.
                RowLayout {
                    Layout.alignment: win.wide ? Qt.AlignRight | Qt.AlignVCenter : Qt.AlignLeft
                    spacing: 8

                    Rectangle {
                        implicitWidth: editionLabel.implicitWidth + 18
                        implicitHeight: 22
                        radius: 5
                        color: Theme.alpha(Theme.sky, 0.12)
                        border.width: 1
                        border.color: Theme.alpha(Theme.sky, 0.3)

                        Text {
                            id: editionLabel
                            anchors.centerIn: parent
                            text: qsTr("Edition %1").arg(Legal.version)
                            color: Theme.sky
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0.4
                        }
                    }

                    Text {
                        text: qsTr("In effect since %1").arg(Legal.effective)
                        color: Theme.textFaint
                        font.pixelSize: 11
                    }
                }
            }

            SegmentedControl {
                Layout.alignment: Qt.AlignLeft
                items: win.documents.map(function (document) {
                    return { key: document.id, label: document.title, glyph: document.glyph };
                })
                currentIndex: win.current
                onSelected: function (index) {
                    win.current = index;
                    reader.scrollToTop();
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderSubtle
        }

        // ---- The document -------------------------------------------------
        LegalDocumentView {
            id: reader
            Layout.fillWidth: true
            Layout.fillHeight: true
            document: win.current >= 0 && win.current < win.documents.length
                      ? win.documents[win.current] : ({})
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderSubtle
        }

        // ---- Footer -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 30
            Layout.rightMargin: 30
            Layout.topMargin: 14
            Layout.bottomMargin: 18
            spacing: Theme.spaceMd

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                LinkLabel {
                    text: qsTr("Read it on simorg.tech")
                    onActivated: App.openExternal(win.current === Legal.documentIndex("privacy")
                                                  ? Legal.onlinePrivacy : Legal.onlineTerms)
                }

                Text {
                    Layout.fillWidth: true
                    text: Legal.accepted
                          ? qsTr("Accepted on this computer on %1.").arg(
                                Qt.formatDateTime(Legal.acceptedAt, "d MMMM yyyy"))
                          : qsTr("Questions about any of this go to %1.").arg(Legal.contactEmail)
                    color: Theme.textFaint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            GhostButton {
                text: qsTr("Close")
                implicitHeight: 38
                onClicked: win.close()
            }

            PrimaryButton {
                visible: !Legal.accepted
                implicitHeight: 38
                text: qsTr("I agree")
                onClicked: {
                    win.agreed();
                    win.close();
                }
            }
        }
    }

    /*
      The one tooltip this window can show, in its overlay so it is above
      everything and clipped by nothing. Declared here rather than beside each
      elided label: there is one pointer, so there is one bubble. See `Tip.qml`.
    */
    TipLayer {}
}
