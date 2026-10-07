// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg
import "Platform.js" as Platform

/**
 * The cached artifacts on this computer, or just the ones that installed a
 * program.
 *
 * One component for both because they are the same rows with a filter over
 * them, and the difference that matters is in the empty state: "nothing has
 * been downloaded" and "nothing has been installed" are different facts about a
 * computer and deserve different sentences.
 *
 * ## The role column
 *
 * What the agent that fetched an artifact may do with it, as its runtime
 * recorded at the time. It is shown as **not recorded** rather than guessed at
 * when the index carries none: a role invented on a laptop would be a claim
 * about somebody's permissions that nothing checked, and the whole value of the
 * column is that it is not that.
 */
Item {
    id: root

    /** True for the Applications view, which is the same rows with a filter. */
    property bool onlyApplications: false

    /*
      Filled in by whoever uses this, and never blank if they forget.

      An empty state with no words in it is the one failure mode this component
      has, because it is what somebody sees on a computer where everything is
      working exactly as intended.
    */
    property string emptyTitle: qsTr("Nothing has been cached here yet")
    property string emptyBody: qsTr("When an agent or a Simorg program downloads something, it is kept so it is not downloaded again. Whatever is there will be listed here.")

    /*
      The applications view is what agents put here for themselves: what the
      person installed through Simorg has the Applications tab's own list, and
      counting it twice would say two different things about one program.
    */
    readonly property int shownCount: root.onlyApplications ? Artifacts.agentApplicationCount
                                                            : Artifacts.count

    // ---- Empty --------------------------------------------------------
    //
    // Only once a scan has finished. "Nothing here" and "we have not looked
    // yet" are different facts, and showing the first while the second is true
    // is how a screen tells somebody their cache is empty when it is not.
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: Theme.spaceMd
        visible: Artifacts.scanned && root.shownCount === 0

        Glyph {
            Layout.alignment: Qt.AlignHCenter
            name: root.onlyApplications ? "cube" : "layers"
            size: 32
            thickness: 1.4
            tone: Theme.textFaint
        }

        Text {
            Layout.fillWidth: true
            text: root.emptyTitle
            color: Theme.textPrimary
            font.pixelSize: 15
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: root.emptyBody
            color: Theme.textMuted
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.5
        }

        GhostButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            text: qsTr("Open the cache folder")
            implicitHeight: 34
            onClicked: App.revealPath(Storage.cacheRoot)
        }
    }

    // ---- Rows ---------------------------------------------------------
    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        clip: true
        visible: root.shownCount > 0
        spacing: 8

        model: Artifacts

        header: Item {
            width: list.width
            height: 34

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                spacing: Theme.spaceMd

                Text {
                    Layout.preferredWidth: 260
                    text: qsTr("ARTIFACT")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("CACHED BY")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.preferredWidth: 150
                    text: qsTr("ACCESS ROLE")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.preferredWidth: 90
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("SIZE")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontEyebrow
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }
            }
        }

        delegate: Item {
            id: row

            required property string specifier
            required property string title
            required property string kind
            // Matches the model role. It was `version` until releases and tags
            // became one thing; a required property naming a role the model no
            // longer has fails the whole delegate at runtime, silently as far
            // as the compiler is concerned.
            required property string tag
            required property string agentHandle
            required property string sizeText
            required property string accessRole
            required property string installedPath
            required property bool installed
            required property int agentId
            required property string cache

            // The filter is here rather than in a proxy model: one extra model
            // for a boolean would be a class to keep in step with this one, and
            // the list is short enough that a hidden row costs nothing.
            readonly property bool shown: !root.onlyApplications || (row.installed && row.cache === "agent")

            width: list.width
            height: row.shown ? card.implicitHeight : 0
            visible: row.shown

            GlassPanel {
                id: card
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 28
                anchors.rightMargin: 28
                implicitHeight: 62

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: Theme.spaceMd

                    /*
                      What kind of artifact this is, drawn.

                      The same mark the web catalog and the panel show for the
                      same kind — see `Platform.glyphForArtifactKind`, which
                      mirrors the web panel's table. A row that
                      says only a name and a tag makes somebody read every
                      line to find the one plugin in a list of applications.
                    */
                    Glyph {
                        name: Platform.glyphForArtifactKind(row.kind)
                        size: 18
                        thickness: 1.5
                        tone: Theme.textMuted
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 260
                        spacing: 1

                        ElidedText {
                            Layout.fillWidth: true
                            text: row.title
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        ElidedText {
                            Layout.fillWidth: true
                            text: row.specifier
                            color: Theme.textFaint
                            font.pixelSize: 11
                            font.family: Theme.monoFamily
                            elide: Text.ElideMiddle
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        ElidedText {
                            Layout.fillWidth: true
                            text: row.cache === "installed" ? qsTr("Installed by you")
                                : row.agentId > 0 ? qsTr("Agent %1").arg(row.agentId)
                                : qsTr("sim exec")
                            color: Theme.textBody
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        ElidedText {
                            Layout.fillWidth: true
                            visible: row.installed
                            text: row.installedPath
                            color: Theme.textFaint
                            font.pixelSize: 11
                            font.family: Theme.monoFamily
                            elide: Text.ElideMiddle
                        }
                    }

                    // Never invented. An empty role means the runtime did not
                    // record one, and saying so is the whole value of showing it.
                    ElidedText {
                        Layout.preferredWidth: 150
                        text: row.accessRole.length > 0 ? row.accessRole : qsTr("not recorded")
                        color: row.accessRole.length > 0 ? Theme.textBody : Theme.textFaint
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.preferredWidth: 90
                        horizontalAlignment: Text.AlignRight
                        text: row.sizeText
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.monoFamily
                    }
                }
            }
        }
    }
}
