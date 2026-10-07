// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * What is running, and the controls for it.
 *
 * A table rather than cards: the reason to open this view is to compare rows —
 * which of these is using the processor, which one stopped — and cards make
 * comparison impossible by putting every value in a different place.
 *
 * Logs open in a panel below the list rather than in a window of their own, so
 * the container they belong to stays visible while they are read.
 */
Item {
    id: root

    property string selectedId: ""

    /*
      One dialog for the whole list, not one per row.

      A ListView delegate is 54 pixels tall and is recycled as the model
      reconciles, so a confirmation living inside a row would be clipped to
      nothing and could be destroyed out from under the person reading it. The
      row asks; this owns the asking.
    */
    property string pendingId: ""
    property string pendingName: ""
    property bool pendingRunning: false

    /*
      The column geometry, declared once.

      The headings and the rows are separate items in separate files, and a
      layout hint that appears in only one of them puts every column after it
      out by however much it was worth — which is a table whose numbers sit
      under the wrong titles. Sharing the numbers makes that impossible, and
      pinning minimum to maximum stops a long container name stealing width
      from the readings.
    */
    readonly property int dotColumn: 20
    readonly property int statusColumn: 170
    readonly property int cpuColumn: 74
    readonly property int memoryColumn: 90
    readonly property int actionColumn: 140
    readonly property bool compact: root.width <= 980

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Column headings -------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            visible: Docker.containers.count > 0

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 24
                spacing: 14

                Item { Layout.preferredWidth: root.dotColumn }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("NAME")
                    color: Theme.textFaint
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.preferredWidth: root.statusColumn
                    Layout.minimumWidth: root.statusColumn
                    Layout.maximumWidth: root.statusColumn
                    visible: !root.compact
                    text: qsTr("STATUS")
                    color: Theme.textFaint
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.preferredWidth: root.cpuColumn
                    Layout.minimumWidth: root.cpuColumn
                    Layout.maximumWidth: root.cpuColumn
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("CPU")
                    color: Theme.textFaint
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.preferredWidth: root.memoryColumn
                    Layout.minimumWidth: root.memoryColumn
                    Layout.maximumWidth: root.memoryColumn
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("MEMORY")
                    color: Theme.textFaint
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Item { Layout.preferredWidth: root.actionColumn }
            }
        }

        // ---- The list ---------------------------------------------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Docker.containers
            // Rows are recycled as the model reconciles; without this a row can
            // keep a stale delegate's expanded state.
            reuseItems: true

            ScrollBar.vertical: ScrollBar {}

            delegate: DockerContainerRow {
                id: row
                width: list.width
                compact: root.compact
                dotColumn: root.dotColumn
                statusColumn: root.statusColumn
                cpuColumn: root.cpuColumn
                memoryColumn: root.memoryColumn
                actionColumn: root.actionColumn
                selected: root.selectedId === containerId

                onShowLogs: {
                    root.selectedId = row.containerId;
                    Docker.openLogs(row.containerId, row.name);
                }

                onRequestStop: rowConfirm.askStop(row.containerId, row.name)
                onRequestRemove: rowConfirm.askRemove(row.containerId, row.name, row.running)
            }

            // ---- Empty -----------------------------------------------
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 420)
                visible: Docker.containers.count === 0
                spacing: Theme.spaceMd

                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    name: "container"
                    size: 40
                    thickness: 1.4
                    tone: Theme.alpha(Theme.textMuted, 0.4)
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Nothing is running yet")
                    color: Theme.textBody
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Containers appear here the moment anything starts one — an agent, a build, or you from a terminal.")
                    color: Theme.textFaint
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }
        }

        // ---- Logs --------------------------------------------------------
        DockerLogPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: Docker.logContainerId.length > 0
                                    ? Math.max(220, root.height * 0.44)
                                    : 0
            visible: Layout.preferredHeight > 0
            clip: true

            onClosed: {
                root.selectedId = "";
                Docker.closeLogs();
            }

            Behavior on Layout.preferredHeight {
                enabled: Theme.motion
                NumberAnimation {
                    duration: Theme.durBase
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }
        }
    }

    ConfirmDialog {
        id: rowConfirm
        anchors.fill: parent

        property string action: ""

        function askStop(id, name) {
            rowConfirm.action = "stop";
            root.pendingId = id;
            root.pendingName = name;
            rowConfirm.title = qsTr("Stop %1?").arg(name);
            rowConfirm.body = qsTr("Docker asks it to shut down cleanly and gives it ten seconds before stopping it outright, so anything half-finished will not complete. Starting it again afterwards keeps its data.");
            rowConfirm.confirmText = qsTr("Stop");
            rowConfirm.destructive = false;
            rowConfirm.open();
        }

        function askRemove(id, name, running) {
            rowConfirm.action = "remove";
            root.pendingId = id;
            root.pendingName = name;
            root.pendingRunning = running;
            rowConfirm.title = qsTr("Remove %1?").arg(name);
            rowConfirm.body = running
                ? qsTr("This container is running. Removing it stops it first, and it is then gone for good along with anything written inside it that is not on a volume.")
                : qsTr("The container is removed for good, along with anything written inside it that is not on a volume. The image it was built from stays.");
            rowConfirm.confirmText = qsTr("Remove");
            rowConfirm.destructive = true;
            rowConfirm.open();
        }

        onAccepted: {
            if (rowConfirm.action === "stop")
                Docker.stopContainer(root.pendingId);
            else if (rowConfirm.action === "remove")
                Docker.removeContainer(root.pendingId, root.pendingRunning);
        }
    }
}
