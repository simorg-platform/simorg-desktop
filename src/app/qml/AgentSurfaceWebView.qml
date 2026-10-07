// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtWebChannel
import QtWebEngine
import Simorg

/**
 * The browser view an agent's surface is actually drawn in.
 *
 * Its own file, and loaded through a `Loader` rather than placed inline,
 * for two reasons that pull the same way:
 *
 * - **The import is the dependency.** `import QtWebEngine` in a file that is
 *   always loaded would make Chromium a hard requirement of the interface. Here
 *   it is reached only when a surface is opened, and a build without Qt
 *   WebEngine substitutes {@link AgentSurfaceUnavailable} under this same name —
 *   see `src/app/CMakeLists.txt`.
 * - **A view is expensive.** Chromium costs a process and a few hundred
 *   megabytes of address space per view. One exists while a surface is on
 *   screen and is destroyed when it stops being.
 *
 * ## What it loads is not the engine
 *
 * It loads a page **this application serves**, over a scheme this build
 * registers, and the engine is the iframe inside it. That is not a layer for
 * its own sake: the engine speaks its half of the protocol by posting to
 * `window.parent`, and a top-level engine's parent is itself — it would answer
 * its own handshake and nothing would ever reach us. See `SurfaceRouter`.
 *
 * ## How that page reaches the application
 *
 * Over a `WebChannel`, which is the bridge Qt gives a page and a native
 * application for exactly this. One object is registered on it — the pane's
 * `AgentSurfaceSession`, as `surface` — and it is the whole of what the page can
 * call: read the world, send an event, report that the engine connected.
 * Everything else the application knows stays on this side of it.
 */
WebEngineView {
    id: view

    /** `WORKBENCH` or `BRAIN`. Decides which page the scheme serves. */
    property string surface: ""
    property int agentId: 0

    /**
     * The `AgentSurfaceSession` this page talks to.
     *
     * The page is not loaded until there is one, and that order is the point: a
     * channel hands a page the objects registered at the moment it connects, so
     * an object registered after the page has loaded is one the page never
     * learns about.
     */
    property var session: null

    /*
      Transparent, so the pane's own background shows until the page paints its
      ground. The page paints one immediately — a `color-scheme` decided when it
      was served — so this is only ever the first frame, and white there would
      be a flash in a dark window.
    */
    backgroundColor: "transparent"

    webChannel: WebChannel {
        id: channel
    }

    Component.onCompleted: {
        /*
          `qwebchannel.js`, into the host page's main world and nowhere else.

          Not into the engine's frame: that renders modules somebody else
          published, and the channel is the application. Injected rather than
          served from the surface scheme, because it is the script Qt ships for
          this and a copy of it would drift from the Qt it has to talk to.
        */
        const script = WebEngine.script();
        script.name = "qwebchannel";
        script.sourceUrl = "qrc:///qtwebchannel/qwebchannel.js";
        script.injectionPoint = WebEngineScript.DocumentCreation;
        script.worldId = WebEngineScript.MainWorld;
        script.runsOnSubFrames = false;
        view.userScripts.insert(script);
        view.loadWhenReady();
    }

    onSessionChanged: view.loadWhenReady()

    /** Registers the session and loads the page, once, when both are possible. */
    function loadWhenReady() {
        if (!view.session || view.url.toString().length > 0)
            return;
        channel.registerObject("surface", view.session);
        view.url = AgentSurfaces.hostUrl(view.surface, view.agentId);
    }

    /**
     * Repaint the surface in the other mood, without reloading it.
     *
     * The document's own `color-scheme` was decided when it was served and
     * cannot be changed after the fact, so this tells the page, which tells the
     * engine and updates its own root at the same time. A reload would work and
     * would throw away whatever the person was doing inside.
     */
    function applyThemeChoice(choice) {
        view.runJavaScript(
            "window.__simorgSurface && window.__simorgSurface.setThemeChoice("
            + JSON.stringify(choice) + ")");
    }

    /** Throw the page away and load it again. The session stays registered. */
    function reloadSurface() {
        view.reload();
    }

    /*
      A page that never loads never reports, and the pane covering it waits for
      a report: its fallback only starts once the engine has said hello. So a
      failure to load this application's own page, or a renderer that dies
      under it, is told to the session the way the page would tell it, and the
      pane shows it with its retry instead of a spinner with no end.
    */
    onLoadingChanged: function (loadingInfo) {
        const failed = loadingInfo.status === WebEngineView.LoadFailedStatus
                       || loadingInfo.status === WebEngineLoadingInfo.LoadFailedStatus;
        if (failed && view.session)
            view.session.report("error", qsTr("The page for this view could not be loaded: %1")
                                         .arg(loadingInfo.errorString));
    }
    onRenderProcessTerminated: function (terminationStatus, exitCode) {
        if (terminationStatus !== WebEngineView.NormalTerminationStatus && view.session)
            view.session.report("error", qsTr("The browser process drawing this view stopped (exit %1).")
                                         .arg(exitCode));
    }

    settings.localContentCanAccessFileUrls: false
    settings.localContentCanAccessRemoteUrls: false
    /*
      Off, both of them. What renders inside is published by somebody else, and
      neither a file picker nor a screen capture prompt is something an agent's
      interface should be able to raise on the computer hosting it.
    */
    settings.screenCaptureEnabled: false
    settings.allowWindowActivationFromJavaScript: false

    /*
      Nothing opens a second window.

      A request is granted by handing it a view with `openIn`, so **not** doing
      that is how one is refused — there is no `deny()` and no flag to set. The
      handler exists rather than being left off because an unhandled
      `newWindowRequested` is a request nobody answered, and this is a decision:
      there is one place a surface is drawn and this is it. A renderer asking
      for a second window is either confused or trying something.
    */
    onNewWindowRequested: function (request) {
        void request;
    }

    /*
      Every permission an agent's interface can ask the browser for is refused
      here rather than passed to the person at the keyboard. A camera prompt
      raised by a component nobody has heard of, in a window that is not a
      browser, is a prompt somebody accepts without knowing what they agreed to
      — and what an agent may reach on this computer is decided on its own
      Access management screen, not by a dialog.

      `permissionRequested` arrived in Qt 6.8, which is why the build requires
      at least that before it will draw a surface at all: on 6.4 this handler
      would be a binding to a signal that does not exist, and the whole
      component would fail to load. See `src/app/CMakeLists.txt`.
    */
    onPermissionRequested: function (permission) {
        permission.deny();
    }
}
