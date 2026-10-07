// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import Simorg

/**
 * The QML root.
 *
 * Not a window itself: this app has several, and none of them owns another. It
 * holds them all, keeps at most one of the routed ones on screen, and does what
 * the C++ side asks — the tray menu, a second launch, and a sign-in from the
 * terminal all arrive here as signals on the App bridge.
 */
QtObject {
    id: root

    /**
     * The environment check, which comes before either of the others.
     *
     * Not "as well as": whether this computer can run a container is settled
     * before anybody is asked for a password, so this hides both of the windows
     * that would otherwise be up. See PreflightModel for when it is shown at
     * all, which on a machine that has been ready before is never.
     */
    function showPreflight() {
        // Uninstalling: the uninstall window is the one thing on screen until it is over.
        if (Uninstall.started)
            return;
        startingWindow.hide();
        loginWindow.hide();
        setupWindow.hide();
        dashboardWindow.hide();
        preflightWindow.show();
        preflightWindow.raise();
        preflightWindow.requestActivate();
    }

    /**
     * The launch, while nothing yet knows which window this computer owes.
     *
     * Before the service has answered there is no session to route on, and the
     * sign-in window is a guess that is wrong on every signed-in machine. See
     * `DesktopApplication::surfaceWindow`.
     */
    function showStarting() {
        // Uninstalling: the uninstall window is the one thing on screen until it is over.
        if (Uninstall.started)
            return;
        preflightWindow.hide();
        loginWindow.hide();
        setupWindow.hide();
        dashboardWindow.hide();
        startingWindow.show();
        startingWindow.raise();
        startingWindow.requestActivate();
    }

    function showLogin() {
        // Uninstalling: the uninstall window is the one thing on screen until it is over.
        if (Uninstall.started)
            return;
        preflightWindow.hide();
        startingWindow.hide();
        setupWindow.hide();
        dashboardWindow.hide();
        loginWindow.show();
        loginWindow.raise();
        loginWindow.requestActivate();
    }

    /**
     * This computer's own setup, between signing in and the dashboard.
     *
     * Shown only on a machine that owes one, which C++ decides — see
     * DesktopApplication::surfaceWindow. It hides the dashboard for the same
     * reason the sign-in window does: until this machine has a name the
     * platform does not list it, so a dashboard behind it would be describing a
     * computer nobody else can see.
     */
    function showSetup() {
        // Uninstalling: the uninstall window is the one thing on screen until it is over.
        if (Uninstall.started)
            return;
        preflightWindow.hide();
        startingWindow.hide();
        loginWindow.hide();
        dashboardWindow.hide();
        setupWindow.show();
        setupWindow.raise();
        setupWindow.requestActivate();
    }

    function showDashboard() {
        // Uninstalling: the uninstall window is the one thing on screen until it is over.
        if (Uninstall.started)
            return;
        preflightWindow.hide();
        startingWindow.hide();
        loginWindow.hide();
        setupWindow.hide();
        dashboardWindow.show();
        dashboardWindow.raise();
        dashboardWindow.requestActivate();
    }

    function hideAll() {
        preflightWindow.hide();
        startingWindow.hide();
        loginWindow.hide();
        setupWindow.hide();
        dashboardWindow.hide();
        legalWindow.hide();
    }

    /*
      The first window, and usually one nobody sees.

      Held here beside the other two rather than owned by either, for the same
      reason the terms window is: it is opened from outside both of them, and it
      outranks both. C++ decides when — see DesktopApplication::surfaceWindow —
      and this file only knows how to put it on screen.
    */
    readonly property PreflightWindow preflightWindow: PreflightWindow {}
    /*
      The launch's own window, and the other one nobody usually sees.

      Held here beside the rest for the same reason they are: C++ decides when a
      launch has nothing it can show yet, and this file only knows how to put
      that on the screen.
    */
    readonly property StartingWindow startingWindow: StartingWindow {}
    readonly property LoginWindow loginWindow: LoginWindow {}
    /*
      The wizard a freshly enrolled computer owes its owner.

      Held here beside the other windows rather than inside the dashboard,
      because it is not part of it: it comes before there is a dashboard worth
      showing. C++ decides when, and this file only knows how to put it on the
      screen.
    */
    readonly property SetupWindow setupWindow: SetupWindow {}
    /*
      Quitting, with the wait said out loud.

      Held here beside the others and shown by binding to `Shutdown.active`
      rather than opened by whoever started the service's shutdown run: this app,
      a terminal and the operating system can each start one, and a window each
      of them had to remember to open is one that the others would miss.
    */
    readonly property QuittingWindow quittingWindow: QuittingWindow {}
    /*
      Uninstalling, over everything else.

      Shown by binding to `Uninstall.started`, and the other windows put away
      while it is up: halfway through, the service goes on purpose, and every
      other window would start saying what it says when the service is missing.
      It ends with the app, except after a failure that changed nothing, when
      Close puts it away and the dashboard comes back.
    */
    readonly property UninstallWindow uninstallWindow: UninstallWindow {}
    readonly property Connections uninstalling: Connections {
        target: Uninstall

        function onChanged() {
            if (Uninstall.started === root.wasUninstalling)
                return;
            root.wasUninstalling = Uninstall.started;
            if (Uninstall.started)
                root.hideAll();
            else
                root.showDashboard();
        }
    }
    property bool wasUninstalling: false
    readonly property DashboardWindow dashboardWindow: DashboardWindow {}
    /*
      The agreement, in a window of its own.

      Held here beside the other two rather than inside either, because it is
      opened from both: from the tick box on the sign-in window, before there is
      a session, and from Settings long after there is one. Neither of them owns
      it, and neither should have to know that the other one can open it.
    */
    readonly property LegalWindow legalWindow: LegalWindow {
        onAgreed: {
            /*
              "I agree" in that window is a shortcut to the tick box, not a
              second way of agreeing: the record is written when somebody
              actually signs in. Somebody who is already signed in has no tick
              box in front of them, so for them this *is* the moment.
            */
            if (Auth.signedIn)
                Legal.accept();
            else
                root.loginWindow.acceptTerms();
        }
    }

    /*
      Leaving, with nothing left on screen to pretend otherwise.

      Only when the quit was asked for here. A run somebody started from a
      terminal, or from another application on this computer, leaves the windows
      where they are — the quitting window floats over them and says who asked —
      because this app is not going anywhere and taking somebody's dashboard away
      would be answering a question they did not ask.
    */
    readonly property Connections leaving: Connections {
        target: App

        function onQuittingChanged() {
            if (App.quitting)
                root.hideAll();
        }
    }

    readonly property Connections bridge: Connections {
        target: App

        function onShowPreflightRequested() { root.showPreflight(); }
        function onShowStartingRequested() { root.showStarting(); }
        function onShowLoginRequested() { root.showLogin(); }
        function onShowSetupRequested() { root.showSetup(); }
        function onShowDashboardRequested() { root.showDashboard(); }
        /*
          Arrives immediately after the dashboard request, never instead of it.
          The window has to exist before it can be steered, and the bridge emits
          the two in that order for exactly this reason.
        */
        function onShowAccessManagementRequested() { root.dashboardWindow.showAccessManagement(); }
        function onShowAgentAccessRequested(agentId) { root.dashboardWindow.showAgentAccess(agentId); }
        function onHideAllRequested() { root.hideAll(); }
        function onShowLegalRequested(documentId) { root.legalWindow.open(documentId); }
        /*
          Quit or Sign out would stop agents here, and the question is asked in
          the dashboard wherever it was chosen: from the tray or the menu bar
          there may be no window on screen at all. One that was in the tray goes
          back there if the answer is no.

          Except a Quit while the launch window is the one on screen: that
          window asks it itself, because a dashboard brought out for it would
          have no session behind it yet.
        */
        function onLeaveQuestionChanged() {
            if (App.leaveQuestion === "")
                return;
            if (App.leaveQuestion === "quit" && root.startingWindow.visible)
                return;
            // Back to the tray on a no, and only where there is one: without it, a hidden window is a lost app.
            const wasHidden = !root.dashboardWindow.visible && App.trayAvailable;
            root.showDashboard();
            root.dashboardWindow.askToLeave(wasHidden);
        }
    }

    /*
      The theme follows the account, because nothing else here can tell.

      Qt reports no system light/dark preference to Qt Quick on any of the three
      platforms, so this app cannot read the setting the way a browser does.
      What it can do is ask the API: `whoami` carries the theme the person chose
      on the web — or, for a new account, the one their browser was already
      using when they signed up — and that arrives on the session as
      `themePreference`.

      Signed out, the app stays dark. The screens shown before an account is
      known — the launch and the sign-in window — have always been dark, and
      flashing them to light on a hunch would be worse than being briefly wrong
      for someone who prefers light.
    */
    readonly property Connections session: Connections {
        target: Auth

        function onUserChanged() {
            Theme.dark = !Auth.signedIn || Auth.user.prefersDarkTheme;
        }
        function onStateChanged() {
            Theme.dark = !Auth.signedIn || Auth.user.prefersDarkTheme;
        }
    }

    Component.onCompleted: {
        // Honours SIMORG_REDUCED_MOTION; every animation in the app reads
        // Theme.motion, so this one line turns the lot off.
        Theme.motion = !App.reducedMotion;
        // A session restored from disk is already in place by now, so this
        // catches the resumed case that no signal will fire for.
        Theme.dark = !Auth.signedIn || Auth.user.prefersDarkTheme;
    }
}
