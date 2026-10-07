// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * Where Simorg puts things on this computer, how much it comes to, and how to
 * get it back.
 *
 * The folder cannot be moved, and that is stated rather than hidden behind a
 * control that would half-work: a container holds the folder it was given for
 * as long as it runs, so moving it while agents are working is not something
 * this app can do safely. What it *can* do is empty it, and that is the only
 * button here.
 */
Item {
    id: root

    /*
      Measured when this view is opened, and not before.

      It is a walk of somebody's disk. Doing it at startup would slow every
      launch for a screen most people never open, and doing it on a timer would
      keep a laptop's disk awake for a number nobody is reading.
    */
    onVisibleChanged: if (visible) root.measure()
    Component.onCompleted: if (visible) root.measure()

    /** The folders' sizes, and what the indexes say is in the cache. */
    function measure() {
        Storage.refresh();
        Artifacts.refresh();
    }

    /** What the last sweep did, kept so the page can say so afterwards. */
    property string sweepMessage: ""

    Connections {
        target: Storage

        function onCleared(freedBytes, keptAgents) {
            if (Storage.clearError.length > 0) {
                root.sweepMessage = "";
                return;
            }

            const freed = qsTr("The cache was emptied, and %1 came back.")
                              .arg(Docker.formatBytes(freedBytes));
            root.sweepMessage = keptAgents === 0
                ? freed
                : keptAgents === 1
                  ? qsTr("%1 One agent is working, so its folder was left alone.").arg(freed)
                  : qsTr("%1 %2 agents are working, so their folders were left alone.")
                        .arg(freed).arg(keptAgents);
        }
    }

    /** How many agents a sweep would spare right now. Drives the warning below. */
    readonly property int busyCount: Hub.agents.runningCount

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

                /*
                  ---- Where Simorg keeps things ---------------------------

                  A list of places, shown and not editable: the path, what it
                  is for, how much it holds, and a way to open it. This is the
                  one page in the app that answers "where did it put my
                  things".

                  There is one entry today: a container fetches its own
                  sources, and /work lives inside the image. The list is a list
                  because access management brings granted folders to it.
                */
                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: storage.implicitHeight + 40

                        ColumnLayout {
                            id: storage
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "disk"; size: 16; thickness: 1.7; tone: Theme.amber }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Where Simorg keeps things")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    visible: Storage.measured
                                    text: Storage.complete
                                          ? Docker.formatBytes(Storage.totalBytes)
                                          : qsTr("over %1").arg(Docker.formatBytes(Storage.totalBytes))
                                    color: Theme.textBody
                                    font.pixelSize: 12
                                    font.family: Theme.monoFamily
                                }

                                BusyRing {
                                    visible: Storage.measuring
                                    size: 14
                                }

                                IconButton {
                                    glyph: "refresh"
                                    size: 26
                                    tooltip: qsTr("Measure again")
                                    enabled: !Storage.measuring && !Storage.clearing
                                    onClicked: Storage.refresh()
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            Repeater {
                                model: [
                                    {
                                        label: qsTr("ARTIFACT CACHE"),
                                        path: Storage.cacheRoot,
                                        bytes: Storage.cacheBytes,
                                        blurb: qsTr("Anything an agent or a Simorg program downloads is kept here so it is not downloaded again. Each agent has its own folder inside it and cannot see the others. Deleting it costs time, never work.")
                                    }
                                ]

                                delegate: ColumnLayout {
                                    id: place
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: place.modelData.label
                                            color: Theme.textFaint
                                            font.pixelSize: Theme.fontEyebrow
                                            font.weight: Font.ExtraBold
                                            font.letterSpacing: 1.2
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            visible: Storage.measured
                                            text: Docker.formatBytes(place.modelData.bytes)
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.monoFamily
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ElidedText {
                                            Layout.fillWidth: true
                                            text: place.modelData.path
                                            color: Theme.textBody
                                            font.pixelSize: 12
                                            font.family: Theme.monoFamily
                                            elide: Text.ElideMiddle
                                        }

                                        IconButton {
                                            glyph: "copy"
                                            size: 24
                                            tooltip: qsTr("Copy")
                                            onClicked: App.copyToClipboard(place.modelData.path)
                                        }

                                        IconButton {
                                            glyph: "external"
                                            size: 24
                                            tooltip: qsTr("Open")
                                            onClicked: App.revealPath(place.modelData.path)
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 2
                                        text: place.modelData.blurb
                                        color: Theme.textFaint
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.45
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                text: qsTr("This cannot be changed yet. A container holds its folder for as long as it runs, so moving it while agents are working is not something Simorg can do safely.")
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: Storage.measured && !Storage.complete
                                text: qsTr("This figure is a floor. The folder was large enough that Simorg stopped counting rather than keep this page waiting.")
                                color: Theme.textFaint
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }
                        }
                    }
                }

                /*
                  ---- Emptying the cache ----------------------------------

                  There is a button for this one because everything in it
                  downloads again, which is the whole definition of what belongs
                  in a cache. Folders access management brings here will need
                  no button, for the opposite reason.
                */
                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: sweep.implicitHeight + 40

                        ColumnLayout {
                            id: sweep
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "trash"; size: 16; thickness: 1.7; tone: Theme.cyan }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Emptying the cache")
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
                                text: qsTr("Everything in the artifact cache can be downloaded again, so emptying it costs time and bandwidth and nothing else.")
                                color: Theme.textBody
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                lineHeight: 1.45
                            }

                            InfoCallout {
                                Layout.fillWidth: true
                                glyph: "info"
                                tone: Theme.sky
                                title: qsTr("Agents that are working keep their folders")
                                body: root.busyCount === 0
                                      ? qsTr("An agent's cache is mounted into its container for as long as that container runs, so the folder of any agent that is working is left where it is. Nothing is running on this computer right now, so the whole cache would go.")
                                      : root.busyCount === 1
                                        ? qsTr("An agent's cache is mounted into its container for as long as that container runs, so the folder of any agent that is working is left where it is. One agent is working here now, and its folder will be kept.")
                                        : qsTr("An agent's cache is mounted into its container for as long as that container runs, so the folder of any agent that is working is left where it is. %1 agents are working here now, and their folders will be kept.").arg(root.busyCount)
                            }

                            InfoCallout {
                                Layout.fillWidth: true
                                visible: Storage.clearError.length > 0
                                glyph: "alert"
                                tone: Theme.amber
                                title: qsTr("Some of it could not be removed")
                                body: Storage.clearError
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: Theme.spaceSm

                                GhostButton {
                                    text: Storage.clearing ? qsTr("Emptying…")
                                                           : qsTr("Empty the cache")
                                    implicitHeight: 34
                                    enabled: !Storage.clearing && !Storage.measuring
                                    onClicked: clearConfirm.open()
                                }

                                BusyRing {
                                    visible: Storage.clearing
                                    size: 15
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.sweepMessage.length > 0 && !Storage.clearing
                                    text: root.sweepMessage
                                    color: Theme.emerald
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                Item { Layout.fillWidth: root.sweepMessage.length === 0 }
                            }
                        }
                    }
                }

                /*
                  ---- What is in the cache ---------------------------------

                  Everything a runtime fetched and kept, read from the index
                  each one writes into its folder, with its size and which
                  agent fetched it. It was a view of the Artifacts tab, which
                  is the Applications tab now; the cache is a question about
                  this disk, and it is answered beside the folder it is in.
                */
                Reveal {
                    step: 2
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: cached.implicitHeight + 40

                        ColumnLayout {
                            id: cached
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20
                            spacing: Theme.spaceMd

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Glyph { name: "layers"; size: 16; thickness: 1.7; tone: Theme.cyan }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("What is in the cache")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    visible: Artifacts.scanned
                                    text: Artifacts.count === 1 ? qsTr("1 artifact")
                                                                : qsTr("%1 artifacts").arg(Artifacts.count)
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                }

                                BusyRing {
                                    visible: Artifacts.scanning
                                    running: Artifacts.scanning
                                    size: 14
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }

                            // Each agent's folder is its own; the sentence the list is read under.
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Each agent is given only its own folder when its container starts, so one agent cannot see what another fetched, even one that goes looking.")
                                color: Theme.textMuted
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }

                            ArtifactList {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 320
                                onlyApplications: false
                                emptyTitle: qsTr("Nothing has been cached here yet")
                                emptyBody: qsTr("When an agent or a Simorg program downloads something, it is kept in the cache folder so it is not downloaded again. Whatever is there is listed here, with its size and which agent fetched it.")
                            }
                        }
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: clearConfirm
        // Named so the interface test can accept it without hunting for a
        // button: what is worth testing here is the line in `onAccepted`, and
        // clicking at coordinates would be testing the dialog instead.
        objectName: "clearCacheConfirm"
        anchors.fill: parent
        title: qsTr("Empty the artifact cache?")
        body: root.busyCount === 0
              ? qsTr("Everything in it downloads again the next time something needs it. No agent is working on this computer right now, so all of it will go.")
              : qsTr("Everything in it downloads again the next time something needs it. The folders of the agents that are working right now are left alone, because their containers have them open.")
        confirmText: qsTr("Empty it")
        /*
          The busy list is read at the moment of the press, not when the page
          was drawn. A container that came up while somebody was reading this
          dialog is one whose folder must survive the sweep.
        */
        onAccepted: {
            root.sweepMessage = "";
            Storage.clearCache(Hub.agents.busyAgentIds());
        }
    }
}
