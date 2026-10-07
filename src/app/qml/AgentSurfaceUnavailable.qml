// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * What stands in for a surface in a build with no browser engine.
 *
 * Compiled in under the name {@link AgentSurfaceWebView} when Qt WebEngine is
 * not available — see `src/app/CMakeLists.txt` — so everything above it is
 * unchanged: the same pane, the same rail entry, the same two functions called
 * on it. Only the thing that would have drawn a page is different.
 *
 * ## Why a build like that exists
 *
 * Because Chromium is a large thing to make mandatory. `QtWebEngineCore` is
 * a binary of a few hundred megabytes inside a framework of about a gigabyte,
 * and it pins a Chromium version with its own security cadence — this
 * application inherits a browser's patch schedule the day it links one. That is
 * a price worth paying for the surfaces and it is not a price every packager
 * will want to pay for every platform, so it is a switch rather than an
 * assumption.
 *
 * What must not happen is the rail entry quietly disappearing. Somebody whose
 * build cannot draw a Workbench should be told that, on the page they clicked
 * to, rather than left to wonder why the application on their laptop has one
 * fewer room than the one in the screenshots.
 */
Item {
    id: root

    property string surface: ""
    property int agentId: 0

    /**
     * Nothing will ever report in from here, so the pane must not wait for it.
     *
     * The pane covers its view until the page says it drew, and this is not a
     * page: waiting on it would hide the sentence below behind a spinner that
     * never stops.
     */
    readonly property bool drawsNothing: true

    /** The two calls the pane makes. Both are nothing to do here. */
    function applyThemeChoice(choice) {}
    function reloadSurface() {}

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 420)
        spacing: 14

        Glyph {
            Layout.alignment: Qt.AlignHCenter
            name: root.surface === "BRAIN" ? "brain" : "widgets"
            size: 26
            tone: Theme.textFaint
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.textBody
            font.pixelSize: 13
            text: qsTr("This build cannot draw an agent's own pages.")
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: 11
            text: qsTr("It was compiled without a browser engine. The same pages are on the web console.")
        }
    }
}
