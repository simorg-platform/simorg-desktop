// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The signed-in shell.
 *
 * Laid out as a desktop application rather than as a web console in a window:
 * one toolbar across the top carrying the section tabs, and everything below it
 * given to the section. The sections are peers — Home, Docker, and the ones to
 * come — so they sit side by side in a tab strip, where a sidebar would have
 * implied a hierarchy that does not exist and spent a fifth of the window width
 * saying so.
 *
 * Sections are all instantiated and kept alive: a section that rebuilt itself
 * on every visit would lose its scroll position and its open log, and the one
 * section that costs anything to keep alive stops polling when it is hidden.
 */
ApplicationWindow {
    id: win

    title: qsTr("Simorg")
    width: 1280
    height: 840
    minimumWidth: 940
    minimumHeight: 620
    color: Theme.base

    property int section: 0

    /**
     * Set when somebody chooses to look around rather than wait for a first
     * connection that is not coming quickly.
     *
     * Cleared when there is nothing left to dismiss, so the next sign-in on this
     * window gets the setup screen it is owed rather than inheriting a decision
     * somebody made about a different session.
     */
    property bool setupDismissed: false

    /** Whether the setup screen is over the window right now. */
    readonly property bool setupCovering: Hub.enrolling && !win.setupDismissed

    /*
      Forgotten the moment there is nothing to dismiss.

      Bound to the state rather than to the overlay's own visibility: dismissing
      it makes the overlay invisible while enrolment is still going on, and a
      reset written that way would clear the flag it had just set.
    */
    Connections {
        target: Hub
        function onStateChanged() {
            if (!Hub.enrolling)
                win.setupDismissed = false;
        }
    }

    /*
      The four sections, in the order somebody grows into them: where you are,
      what is working for you, the engine underneath it, and the app's own
      configuration last — which is where a settings entry belongs in every
      application anybody has used.

      There is no tab for the machine itself. Capacity is under Agents: a
      virtual machine exists because an agent needed one, and a capacity reading
      is only interesting as "how much have the agents been promised". The
      access rules are in Settings, being the one thing about the machine that
      names no agent, and the hardware's own specification is a glance on Home.

      `soon: true` opens a real screen that is still being filled in; it is
      marked so nobody mistakes a placeholder for a fault.
    */
    readonly property var sections: [
        /*
          Overview carries a badge, and it is the only one that does.

          What it counts is questions an agent has asked the owner of this
          computer — the one thing in this app that is *addressed to the person*
          rather than reported to them, and the one thing that leaves an agent
          unable to run until it is answered. It is a binding on a notifying
          property, so it appears and clears itself as decisions are made.
        */
        {
            key: "overview",
            label: qsTr("Overview"),
            glyph: "home",
            ready: true,
            badge: AccessGrants.pendingCount
        },
        { key: "agents", label: qsTr("Agents"), glyph: "robot", ready: true },
        /*
          The applications on this computer: installed, running, which agents
          may use them, and the platform's to install. It was **Artifacts**,
          about the disk; the disk is under Settings now, beside its folders.
        */
        { key: "applications", label: qsTr("Applications"), glyph: "cube", ready: true },
        { key: "docker", label: qsTr("Docker"), glyph: "container", ready: true },
        { key: "settings", label: qsTr("Settings"), glyph: "settings", ready: true }
    ]

    /** Where Docker sits in {@link sections}; read by everything that links to it. */
    readonly property int dockerSection: 3

    /** Where Agents sits, so a notification can land on one agent's own page. */
    readonly property int agentsSection: 1

    /** Where Applications sits, for anything that wants somebody to install one. */
    readonly property int applicationsSection: 2

    /**
     * Where Settings sits. Anything asking for the machine's access rules lands
     * here, and so does anything asking where Simorg keeps things on the disk.
     */
    readonly property int settingsSection: 4

    /**
     * Puts the window on the screen where this computer's rules are written.
     *
     * Called from the tray, when somebody clicks the notification saying an
     * agent is asking for something and there is no agent to name. A window that
     * opened on whatever tab was last in use would be a click that did nothing.
     *
     * Under Settings rather than Agents: the rules are about this computer and
     * apply to agents that have not arrived yet. See {@link SettingsSection}.
     */
    function showAccessManagement() {
        win.section = win.settingsSection;
        settingsSection.showAccess();
    }

    /** One agent's own access screen. Where a permission notification lands. */
    function showAgentAccess(agentId) {
        win.section = win.agentsSection;
        agentsSection.showAgentAccess(agentId);
    }

    /**
     * One agent's virtual machine, for the Home tile that counts the slices.
     *
     * By agent rather than by list: what a computer has been carved into is
     * shown per agent now, on the agent's own page, which is also the only
     * place it can be changed.
     */
    function showVirtualMachine(agentId) {
        win.section = win.agentsSection;
        agentsSection.showVirtualMachine(agentId);
    }

    /**
     * One agent on its Settings, for the bar that says a newer release of it is
     * ready: the update is applied there.
     */
    function showAgentSettings(agentId) {
        win.section = win.agentsSection;
        agentsSection.showAgentSettings(agentId);
    }

    /*
      Closing the window is not quitting.

      Simorg has to stay running for this computer to be a machine anybody can
      be given work on, so the window closing hides it and the tray icon is how
      it comes back. That is the whole behaviour on macOS and Windows, and on
      any Linux desktop with a status-notifier host.

      Where there is **no tray**, hiding silently would leave a process nobody
      can see or reach — so that case asks instead. Both answers are honest ones
      and neither is hidden behind a default.
    */
    onClosing: function (close) {
        if (App.trayAvailable) {
            close.accepted = false;
            App.hideToTray();
            return;
        }
        close.accepted = false;
        noTrayClose.open();
    }

    background: Rectangle { color: Theme.base }

    /*
      The Home tile and the toolbar pill report Docker from every section, so
      something has to keep asking while the Docker section is closed. This is
      the slow watch — a probe every half minute — and it stops with the window,
      so a tray-resident app with no window open costs nothing.
    */
    onVisibleChanged: Docker.setSummaryActive(visible)
    Component.onCompleted: {
        if (visible)
            Docker.setSummaryActive(true);
        if (Updates.reviewPending)
            win.reviewUpdates();
    }

    /**
     * Settings → Updates: from the updates bar, and when Simorg Desktop has just
     * been opened by its own update, where the person pressed it.
     */
    function reviewUpdates() {
        win.section = win.settingsSection;
        settingsSection.showUpdates();
        Updates.reviewed();
    }

    Connections {
        target: Updates
        function onReviewPendingChanged() {
            if (Updates.reviewPending)
                win.reviewUpdates();
        }
    }

    // Quieter than the sign-in screen: this window fills up with content, and
    // the backdrop has to stay behind it.
    AuroraBackground {
        anchors.fill: parent
        intensity: 0.45
    }

    /*
      ⌘1…⌘5 / Ctrl+1…Ctrl+5. A tab strip that cannot be driven from the keyboard
      is one half its users will resent.

      Written out rather than generated with a Repeater: a Repeater instantiates
      Items, and a Shortcut is not one — it produces a delegate warning and no
      shortcuts at all.
    */
    Shortcut { sequence: "Ctrl+1"; onActivated: win.section = 0 }
    Shortcut {
        sequence: "Ctrl+2"
        onActivated: if (win.sections[1].ready) win.section = 1
    }
    Shortcut {
        sequence: "Ctrl+3"
        onActivated: if (win.sections[2].ready) win.section = 2
    }
    Shortcut {
        sequence: "Ctrl+4"
        onActivated: if (win.sections[3].ready) win.section = 3
    }
    Shortcut {
        sequence: "Ctrl+5"
        onActivated: if (win.sections[4].ready) win.section = 4
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Toolbar ---------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            z: 5

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.base, 0.6)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 14
                spacing: 18

                /*
                  ---- Wordmark ----------------------------------------------

                  A link to the Simorg website, which is what a product's mark
                  is everywhere else — people try it, and a mark that does
                  nothing reads as a dead control.

                  Where it goes follows the estate this build points at, so a
                  developer running against localhost lands on the site they are
                  editing rather than on production. That is `landingUrl` in
                  config/config.<env>.json, and the destination is shown on
                  hover so nobody has to click to find out.
                */
                Item {
                    id: wordmark

                    Layout.preferredWidth: wordmarkRow.implicitWidth
                    Layout.preferredHeight: 39

                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Simorg")
                    Accessible.description: qsTr("Open the Simorg website")

                    RowLayout {
                        id: wordmarkRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        opacity: wordmarkHover.hovered ? 1 : 0.9

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.duration(Theme.durFast) }
                        }

                        /*
                          Layout.preferredWidth, not width: a layout sizes its
                          children from their implicit sizes, and an Image takes
                          its implicit size from sourceSize — so plain width and
                          height are ignored and the mark renders at 96px, over
                          the section header below it.

                          Half again the size it was drawn at. The bird is the
                          one piece of branding in this window and it was set at
                          the size of a row icon, which made the product's mark
                          the smallest thing on its own toolbar.
                        */
                        Image {
                            source: "qrc:/simorg/branding/simorg-logo.svg"
                            sourceSize: Qt.size(96, 96)
                            Layout.preferredWidth: 39
                            Layout.preferredHeight: 39
                            smooth: true
                            mipmap: true
                        }

                        Text {
                            text: "SIMORG"
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 2.2
                        }
                    }

                    HoverHandler {
                        id: wordmarkHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler { onTapped: App.openWebsite() }

                    // Hand-rolled rather than Controls' ToolTip, to match the
                    // one IconButton draws: same shape, same delay, no popup.
                    Rectangle {
                        visible: opacity > 0
                        opacity: wordmarkHover.hovered ? 1 : 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 8
                        implicitWidth: wordmarkTip.implicitWidth + 18
                        implicitHeight: 26
                        radius: Theme.radiusSmall
                        color: Theme.baseHigh
                        border.width: 1
                        border.color: Theme.borderStrong
                        z: 100

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.duration(Theme.durFast) }
                        }

                        RowLayout {
                            id: wordmarkTip
                            anchors.centerIn: parent
                            spacing: 7

                            Glyph {
                                name: "external"
                                size: 12
                                thickness: 1.7
                                tone: Theme.textFaint
                            }

                            Text {
                                text: App.websiteUrl.replace(/^https?:\/\//, "")
                                color: Theme.textBody
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 22
                    color: Theme.borderSubtle
                }

                SectionTabs {
                    id: tabs
                    Layout.preferredHeight: 40
                    items: win.sections
                    currentIndex: win.section
                    onSelected: function (index) {
                        win.section = index;
                        /*
                          Which parts of this application people actually open.

                          The key rather than the label: a label is translated
                          and reworded, and a count that changed meaning when
                          somebody edited a string would be a count nobody
                          could compare across two months. Recorded here rather
                          than in each section, because this is the one place a
                          section is chosen.
                        */
                        WatchDog.track("section_opened", { section: win.sections[index].key });
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: App.devMode
                    implicitWidth: envLabel.implicitWidth + 18
                    implicitHeight: 22
                    radius: 5
                    color: Theme.alpha(Theme.amber, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(Theme.amber, 0.42)

                    Text {
                        id: envLabel
                        anchors.centerIn: parent
                        text: qsTr("DEV")
                        color: Theme.amber
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                }

                // ---- Account chip --------------------------------------
                Rectangle {
                    id: accountChip
                    implicitWidth: accountRow.implicitWidth + 20
                    implicitHeight: 38
                    radius: 8
                    color: accountHover.hovered || accountMenu.visible
                           ? Theme.alpha(Theme.sky, 0.09)
                           : "transparent"
                    border.width: 1
                    border.color: accountHover.hovered || accountMenu.visible
                                  ? Theme.alpha(Theme.blue, 0.4)
                                  : Theme.borderSubtle

                    Behavior on color {
                        ColorAnimation { duration: Theme.duration(Theme.durFast) }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: Theme.duration(Theme.durFast) }
                    }

                    RowLayout {
                        id: accountRow
                        anchors.centerIn: parent
                        spacing: 9

                        Avatar {
                            initials: Auth.user.initials
                            source: App.accountAvatar
                            size: 27
                            glow: accountHover.hovered ? 1 : 0
                        }

                        ElidedText {
                            text: Auth.user.displayName
                            color: Theme.textBody
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.maximumWidth: 150
                        }
                    }

                    HoverHandler {
                        id: accountHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: accountMenu.visible ? accountMenu.close() : accountMenu.open()
                    }

                    Menu {
                        id: accountMenu
                        y: accountChip.height + 6
                        x: accountChip.width - width
                        width: 264

                        background: GlassPanel {
                            implicitWidth: 264
                            radius: Theme.radiusBase
                        }

                        /*
                          The account this menu acts on, so a shared machine
                          never leaves anyone guessing whose session is live.

                          With the face beside the name, at the size the rest of
                          the product shows a person at: the chip that opens this
                          menu is small enough to be a mark, and this is where
                          somebody actually looks to check who they are signed in
                          as. Same picture, same cache, one property.
                        */
                        MenuItem {
                            enabled: false
                            implicitHeight: 62

                            contentItem: RowLayout {
                                spacing: 11

                                Avatar {
                                    Layout.alignment: Qt.AlignVCenter
                                    initials: Auth.user.initials
                                    source: App.accountAvatar
                                    size: 38
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    ElidedText {
                                        text: Auth.user.displayName
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSmall
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // The handle, not the email address: it is the
                                    // name this account answers to everywhere on the
                                    // platform, and it is public. Muted rather than
                                    // faint because a second line still has to be
                                    // readable — faint over dark glass is not.
                                    ElidedText {
                                        text: Auth.user.handle
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            background: Item {}
                        }

                        MenuSeparator {
                            contentItem: Rectangle {
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }
                        }

                        /*
                          Straight to this person's own page on the web —
                          `/catalogue/<username>`, the one profile address the platform
                          has.

                          Whether that browser is signed in is not knowable from
                          here, so this opens the destination and lets the web
                          app decide: anything needing a session sends them to
                          `/login?redirect=<path>` and returns them afterwards.
                        */
                        MenuItem {
                            id: profileItem
                            text: qsTr("Profile")
                            implicitHeight: 40
                            onTriggered: App.openProfile(Auth.user.username)

                            contentItem: RowLayout {
                                spacing: 10
                                Glyph {
                                    name: "user"
                                    size: 16
                                    thickness: 1.6
                                    tone: profileItem.hovered ? Theme.sky : Theme.textBody
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: profileItem.text
                                    color: profileItem.hovered ? Theme.textPrimary : Theme.textBody
                                    font.pixelSize: Theme.fontSmall
                                }
                                Glyph {
                                    name: "external"
                                    size: 13
                                    thickness: 1.6
                                    tone: profileItem.hovered ? Theme.sky : Theme.textFaint
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: profileItem.hovered ? Theme.alpha(Theme.sky, 0.09) : "transparent"
                            }
                        }

                        MenuItem {
                            id: openWebItem
                            text: qsTr("Open Simorg in browser")
                            implicitHeight: 40
                            onTriggered: App.openWebApp()

                            contentItem: RowLayout {
                                spacing: 10
                                Glyph {
                                    name: "external"
                                    size: 16
                                    thickness: 1.6
                                    tone: openWebItem.hovered ? Theme.sky : Theme.textBody
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: openWebItem.text
                                    color: openWebItem.hovered ? Theme.textPrimary : Theme.textBody
                                    font.pixelSize: Theme.fontSmall
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: openWebItem.hovered ? Theme.alpha(Theme.sky, 0.09) : "transparent"
                            }
                        }

                        MenuItem {
                            id: signOutItem
                            text: qsTr("Sign out")
                            implicitHeight: 40
                            // Asks first when agents are running on this computer; see `leaveConfirm`.
                            onTriggered: App.signOut()

                            contentItem: RowLayout {
                                spacing: 10
                                Glyph {
                                    name: "logout"
                                    size: 16
                                    thickness: 1.6
                                    tone: signOutItem.hovered ? Theme.rose : Theme.textBody
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: signOutItem.text
                                    color: signOutItem.hovered ? Theme.rose : Theme.textBody
                                    font.pixelSize: Theme.fontSmall
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: signOutItem.hovered ? Theme.alpha(Theme.rose, 0.1) : "transparent"
                            }
                        }

                        /*
                          Quit Simorg, where somebody looks for a way to leave.

                          The tray menu has it, and so does Settings, far down a
                          page nobody opens to quit; a desktop without a tray (a
                          Raspberry Pi) left only the second. Through the same
                          bridge call as every other Quit, so it asks first when
                          agents are running here.
                        */
                        MenuItem {
                            id: quitItem
                            objectName: "quitItem"
                            text: qsTr("Quit Simorg")
                            implicitHeight: 40
                            onTriggered: App.quit()

                            contentItem: RowLayout {
                                spacing: 10
                                Glyph {
                                    name: "power"
                                    size: 16
                                    thickness: 1.6
                                    tone: quitItem.hovered ? Theme.rose : Theme.textBody
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: quitItem.text
                                    color: quitItem.hovered ? Theme.rose : Theme.textBody
                                    font.pixelSize: Theme.fontSmall
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: quitItem.hovered ? Theme.alpha(Theme.rose, 0.1) : "transparent"
                            }
                        }
                    }
                }
            }
        }

        /*
          ---- Connection ------------------------------------------------

          Between the toolbar and the sections, taking no height at all when
          there is nothing wrong. It pushes the window down rather than floating
          over it: a bar that covered the first row of a section would hide the
          thing somebody was reading at the moment they most want to keep
          reading it.
        */
        ConnectionBanner {
            Layout.fillWidth: true
            covered: win.setupCovering
        }

        /*
          ---- Updates -----------------------------------------------------

          Whenever something of Simorg on this computer has a newer version,
          until it is installed.
          Its one button opens Settings → Updates, where each is updated on a
          press; nothing updates by itself.
        */
        UpdatesBar {
            Layout.fillWidth: true
            visible: !win.setupCovering && (shown || closing)
            onReview: win.reviewUpdates()
        }

        /*
          ---- Agents with a newer release --------------------------------

          The same kind of bar for the agents on this computer: one of them was
          installed from a published agent whose publisher released a newer
          version. Its one button opens that agent on its Settings, where the
          update is applied; nothing updates by itself. Quiet while that agent's
          own page is open, which has a bar of its own.
        */
        AgentUpdatesBar {
            Layout.fillWidth: true
            visible: !win.setupCovering && (shown || closing)
            openAgentId: win.section === win.agentsSection ? agentsSection.openAgentId : 0
            onReview: function (agentId) { win.showAgentSettings(agentId); }
        }

        /*
          ---- Signing out -----------------------------------------------

          The one operation in this window that takes real time. Signing out is
          not a local gesture: the service closes the agents' rooms, stops their
          containers and sweeps this computer's cache and journal, so the next
          person to sign in here gets a machine with nothing of the last one on
          it. That is seconds of work, and for those seconds a dashboard that
          sat there unchanged would make the menu item look as if it had done
          nothing.

          Collapsed to nothing when it is not happening, the same shape as the
          restart the Docker section owes.
        */
        Item {
            id: leaving

            /**
             * True only while the closing animation has to run.
             *
             * This row's height is layout: the sections below start where it
             * ends. An animated height is advanced by the render loop, so a
             * window in the tray or still on its way up at launch can leave it
             * stopped part-way — a band of nothing under the tab bar that never
             * closes. Leaving the layout is therefore a timer's job, and timers
             * are the event loop's. See `ConnectionBanner`, where that was
             * found happening on a real machine.
             */
            property bool closing: false
            readonly property bool leavingNow: Auth.state === AuthState.SigningOut

            Layout.fillWidth: true
            Layout.preferredHeight: leaving.leavingNow ? 74 : 0
            visible: leaving.leavingNow || leaving.closing
            clip: true

            Behavior on Layout.preferredHeight {
                enabled: Theme.motion
                NumberAnimation {
                    duration: Theme.durBase
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeOut
                }
            }

            onLeavingNowChanged: {
                if (leaving.leavingNow) {
                    leaving.closing = false;
                    shut.stop();
                } else {
                    leaving.closing = true;
                    shut.restart();
                }
            }

            Timer {
                id: shut
                interval: Theme.durBase + 250
                onTriggered: leaving.closing = false
            }

            InfoCallout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 10
                glyph: "shield"
                tone: Theme.sky
                title: qsTr("Signing out")
                body: qsTr("Simorg is stopping your agents and clearing this computer, so nothing of your account is left on it.")

                BusyRing {
                    size: 18
                    tone: Theme.sky
                }
            }
        }

        // ---- Sections --------------------------------------------------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: win.section

            HomeSection {
                onOpenSection: function (index) { win.section = index; }
                onOpenDocker: win.section = win.dockerSection
                onOpenVirtualMachine: function (agentId) { win.showVirtualMachine(agentId); }
                onOpenAgentAccess: (agentId) => win.showAgentAccess(agentId)
            }

            AgentsSection {
                id: agentsSection
                onOpenDocker: win.section = win.dockerSection
                onOpenMachineRules: win.showAccessManagement()
                onOpenDockerResources: {
                    win.section = win.dockerSection;
                    dockerSection.showResources();
                }
            }

            ApplicationsSection {}

            DockerSection { id: dockerSection }

            SettingsSection { id: settingsSection }
        }
    }

    /*
      The welcome after a first setup, over Overview.

      Owed by `MachineSetup` from the moment the wizard that followed this
      computer's registration finishes, until it is closed — see
      `MachineSetupModel::isWelcomeOwed`. Shown only while this window is on
      screen, so it rises into view when somebody is there to see it rather than
      behind a window in the tray, and never over the first-connection screen,
      which has to finish first.
    */
    MachineWelcome {
        anchors.fill: parent
        shown: MachineSetup.welcomeOwed && win.visible && !win.setupCovering
        // It is about where you are now, so it opens over the page that says so.
        onShownChanged: if (shown) win.section = 0
        onOpenLogos: App.openLogosMachines(Auth.user.username)
        onClosed: MachineSetup.acknowledgeWelcome()
    }

    // An application waiting for this computer's owner to allow it.
    PeerConsentSheet {
        anchors.fill: parent
    }

    ConfirmDialog {
        id: noTrayClose
        anchors.fill: parent
        destructive: false
        title: qsTr("Keep Simorg running?")
        body: qsTr("This desktop has no menu bar icon for Simorg. It can keep running in the background, and starting Simorg again brings this window back. Or it can stop now, which takes this computer off the platform until you start it again.")
        confirmText: qsTr("Keep running")
        cancelText: qsTr("Quit Simorg")
        onAccepted: App.hideToTray()
        // The button only: Escape or a click outside is somebody changing their mind, and leaves the window open.
        onCancelPressed: App.quit()
    }

    /*
      Quitting or signing out while agents are running here.

      Either one stops every agent on this computer, so it is asked about first,
      whichever menu it was chosen from: the tray, the menu bar, ⌘Q, the account
      menu above, or Settings. `DesktopApplication` decides that there is
      something to ask and puts it on `App.leaveQuestion`; Main.qml brings this
      window forward for it. Settings' own Quit Simorg has always asked, so it
      asks here too with nothing running, in the plainer words it always used.
    */
    ConfirmDialog {
        id: leaveConfirm
        anchors.fill: parent
        /**
         * What was asked, kept while the dialog fades out: the bridge clears the
         * question the moment it is answered, and a title that emptied itself
         * half way through the fade would be a flicker of the wrong words.
         */
        property string asked: ""
        property bool stopsAgents: false
        /** The window was in the tray when the question brought it forward, and goes back there on a no. */
        property bool hideAfterNo: false

        title: asked === "signOut" ? qsTr("Sign out?")
             : asked === "uninstall" ? qsTr("Uninstall Simorg?")
             : qsTr("Quit Simorg?")
        body: {
            if (asked === "signOut")
                return qsTr("Signing out stops all the agents running on this computer, so that nothing of your account is left on it. Are you sure you want to continue?");
            if (asked === "uninstall")
                return qsTr("Uninstalling Simorg stops all the agents running on this computer, because it signs you out first. Are you sure you want to continue?");
            if (stopsAgents)
                return qsTr("Quitting Simorg stops all the agents running on this computer, because they run here only while Simorg does. Are you sure you want to continue?");
            return qsTr("Your machine leaves the platform until Simorg is started again.");
        }
        confirmText: asked === "signOut" ? qsTr("Sign out") : asked === "uninstall" ? qsTr("Uninstall") : qsTr("Quit")
        onAccepted: App.answerLeave(true)
        onRejected: {
            App.answerLeave(false);
            if (hideAfterNo)
                win.hide();
        }

        Connections {
            target: App

            function onLeaveQuestionChanged() {
                if (App.leaveQuestion === "") {
                    leaveConfirm.close();
                    return;
                }
                leaveConfirm.asked = App.leaveQuestion;
                leaveConfirm.stopsAgents = App.leaveStopsAgents;
                leaveConfirm.open();
            }
        }
    }

    /**
     * Brings the window forward for the leave question; Main.qml calls it. `wasHidden`
     * is whether the window was in the tray, so a no puts it back there.
     */
    function askToLeave(wasHidden) {
        leaveConfirm.hideAfterNo = wasHidden;
    }

    /*
      Shown only until this computer's first handshake, and dismissible from the
      moment that first attempt fails.

      A reconnect is deliberately excluded, and so is every failure after the
      first success: a laptop waking up and re-establishing its socket is
      plumbing, and an overlay that appeared every time would be the app
      interrupting to narrate itself over a window full of perfectly good
      information. That case belongs to the bar above. See
      {@link HubModel::isEnrolling}.
    */
    MachineRegistration {
        anchors.fill: parent
        visible: win.setupCovering
        opacity: visible ? 1 : 0
        onDismissed: win.setupDismissed = true

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration(Theme.durBase) }
        }
    }

    /*
      The one tooltip this window can show, in its overlay so it is above
      everything and clipped by nothing. Declared here rather than beside each
      elided label: there is one pointer, so there is one bubble. See `Tip.qml`.
    */
    TipLayer {}
}
