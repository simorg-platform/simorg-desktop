// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// This application's half of the renderer protocol.
//
// An agent's Workbench and Brain are drawn by an **engine**, which is an
// artifact rather than a part of this application: it is fetched at run time
// and runs in an iframe on another origin. Somebody has to own the world it
// renders, answer its requests, run the surface's program in it and carry what
// that program says to the agent — and that somebody is this file. It is the
// *host*, exactly as Simorg's web panel is one: the same contract, a second
// implementation of it, and the two must not drift.
//
// Two rules shape everything below, and both come from the engine's README:
//
//   - **The host is the only writer.** A component asks for a structural change
//     over `__wom_op` and asks for a field value over `__instance_vibration`;
//     neither takes effect until this file answers.
//   - **Structure is revisioned, fields are not.** `__wom` is a snapshot and
//     always wins; `__wom_patch` carries the next revision and is applied only
//     in order.
//
// ## The application is on the other end of a QWebChannel
//
// Everything this page needs from C++ and everything it has to tell it goes
// through one object, registered on the web view's channel as `surface` — an
// `AgentSurfaceSession`. `qwebchannel.js` is injected into this document, and
// this document only, by the view.
//
//   reads    worldResponse, worldSources, program, worldLoaded, componentLogs
//   calls    sendClientEvent(event), report(state, detail), log(level, line)
//   hears    worldChanged(), serverEvent(delivery)
//
// ## What it does not hold
//
// **No credential**, because it is never given one. The world was read and the
// Hub connection opened as the signed-in person on the C++ side of the channel;
// what crosses it is the world, the program and the events. The environment
// handed to the engine carries public addresses and the agent's identity and
// nothing else — see `AgentSurfaceService::pageConfig`.

(function () {
  "use strict";

  /** The envelope every renderer frame travels in. Shared with the engine's transport. */
  var CHANNEL = "simorg";

  /**
   * The envelope `simorg-comm` posts on, from inside the frame.
   *
   * `simorg-comm` is the component that carries a world's traffic: what the
   * surface's program says leaves the frame on this envelope, and what the agent
   * answers goes back in on it. The renderer's own envelope carries the world and
   * nothing a person did.
   */
  var COMM_CHANNEL = "simorg-comm";

  /** How long the engine gets to say hello before this says it did not. */
  var HANDSHAKE_GRACE_MS = 20000;

  /** The driver every node of a published world is resolved under. */
  var NODE_DRIVER = "WEB_ESM";

  /** The default slot: the children a component draws as its own. */
  var CHILDREN_SLOT = "__children";

  var config = readConfig();
  var notice = document.getElementById("surface-notice");
  var noticeText = document.getElementById("surface-notice-text");

  /** The application, once the channel to it is open. */
  var app = null;
  /** What this page said before the channel was open, said again once it is. */
  var unsent = [];

  var frame = null;
  var engineOrigin = "";
  /**
   * Whether the frame holds the engine's document yet.
   *
   * Until it does, the frame is `about:blank` on this page's own origin, and a
   * frame posted to it is refused by the browser with an error in the console —
   * which is what happened to a world that arrived over the channel before the
   * engine had loaded. Set by the frame's `load`, or by the engine's first
   * message, whichever comes first: the engine speaks while it is still loading.
   */
  var attached = false;

  /** True once the engine has asked to be initialized and been answered. */
  var connected = false;
  /** Whether the renderer said its WebAssembly engine is up. */
  var engineReady = false;
  var revision = 0;
  /**
   * The world as this host believes it, in the order the document named it.
   *
   * That order means nothing. A node carries no position: where it sits is a
   * reference in the vibration map of the node holding it, and a node nothing
   * references is a root.
   */
  var nodes = [];
  var byId = {};
  var artifacts = {};
  var hasWorld = false;
  /** The surface's program, as last read. */
  var programSource = null;
  /** The program this engine was last asked to run. */
  var programRunFor = null;
  var programRequestId = null;
  /** Said once; see `drawn`. */
  var reportedDrawn = false;
  var statusRequestId = null;
  var requestCount = 0;
  /** Specifier to the source resolved for it, for `__driver_req`. */
  var sources = {};

  connectToApplication();

  /*
    Nothing resolved. Said plainly and without a frame: there is no engine to
    load, so a blank iframe would be a worse version of this sentence.
  */
  if (!config || !config.engineDocumentUrl) {
    say("This surface has no renderer yet.");
    report("error", "No engine document was resolved.");
    return;
  }

  engineOrigin = originOf(config.engineDocumentUrl);
  if (!engineOrigin) {
    say("The renderer address could not be read.");
    report("error", "The engine document URL has no origin: " + config.engineDocumentUrl);
    return;
  }

  if (config.theme && config.theme.artifactSpecifier && config.theme.source) {
    sources[config.theme.artifactSpecifier] = config.theme.source;
  }

  /*
    The frame is made once the application has read the world, because the
    world says which engine the surface's program runs on: the release the
    agent's own simorg.toml names, served beside the renderer by the WOM service,
    which checked it against its signed record. Made before then, it would boot
    the renderer's own engine only to be made again on the agent's.
  */
  /** The engine the frame was made with: a version, null for the renderer's own, undefined before it is made. */
  var frameEngine;

  /** The engine release's WebAssembly build, beside the renderer document: `/api/v1/engines/<v>/wasm/`. */
  function engineBaseUrl(version) {
    var at = config.engineDocumentUrl.indexOf("/api/v1/d/");
    if (at < 0) return null;
    return config.engineDocumentUrl.slice(0, at) + "/api/v1/engines/" + encodeURIComponent(version) + "/wasm/";
  }

  function mountFrame(engineVersion) {
    frameEngine = engineVersion;
    var engineBase = engineVersion ? engineBaseUrl(engineVersion) : null;
    /*
      Where the engine posts *to* is this page, and what this page accepts frames
      *from* is wherever the engine is served — which is the WOM service and not
      this origin. Getting either wrong is silent in both directions: every
      inbound frame is dropped as foreign and every outbound one is refused by the
      browser, which looks exactly like an engine that never booted.
    */
    frame = document.createElement("iframe");
    frame.id = "surface-frame";
    frame.title = config.surface === "BRAIN" ? "Brain" : "Workbench";
    frame.setAttribute("referrerpolicy", "no-referrer");
    /*
      `allow-same-origin` keeps the engine in *its* own origin rather than
      granting it this page's, which is what makes the frames it posts carry a
      real origin for this file to check. Scripts are the whole point of the
      frame; nothing else is granted, so it can neither navigate this window nor
      open one.
    */
    frame.setAttribute("sandbox", "allow-scripts allow-same-origin allow-forms");
    frame.src =
      config.engineDocumentUrl +
      (config.engineDocumentUrl.indexOf("?") === -1 ? "?" : "&") +
      "transport=post-message&origin=" +
      encodeURIComponent(window.location.origin) +
      // The engine log, inside the frame. Development only; see pageConfig.
      (config.devtools === true ? "&devtools=1" : "") +
      // The agent's own engine, served beside the renderer document.
      (engineBase ? "&engine=" + encodeURIComponent(engineBase) : "");
    frame.addEventListener("load", function () {
      attached = true;
    });
    document.body.appendChild(frame);

    window.addEventListener("message", receive);

    window.setTimeout(function () {
      if (connected) return;
      /*
        The frame loaded and said nothing. Left visible rather than replaced: the
        engine may still be downloading its own bundle behind this, and it draws
        its own notice when it fails in a way it can describe.
      */
      report("error", "The renderer loaded but has not connected.");
      // Nothing more is coming, so the window stops waiting and shows what there
      // is — which is this page's own sentence rather than a spinner.
      reportedDrawn = true;
    }, HANDSHAKE_GRACE_MS);
  }

  /**
   * What the application can call on this page without a channel, over
   * `runJavaScript` — and what a test reads to see where the page stands.
   */
  window.__simorgSurface = {
    /**
     * Repaint in the other mood, without reloading anything.
     *
     * Called when the application's own theme flips. The engine caches the
     * theme module by URL, so re-sending the same source with the other column
     * costs nothing — which is why this sends a resolved mode rather than
     * "system": the choice is made once, by the window around this.
     */
    setThemeChoice: function (choice) {
      if (!config.theme) return;
      config.theme.choice = choice === "dark" ? "dark" : "light";
      document.documentElement.style.colorScheme = config.theme.choice;
      sendTheme();
    },
    isConnected: function () {
      return connected;
    },
    state: function () {
      return {
        connected: connected,
        channel: app !== null,
        engineReady: engineReady,
        hasWorld: hasWorld,
        revision: revision,
        nodes: nodes.length,
        programRan: programRunFor !== null,
      };
    },
  };

  // ------------------------------------------------------------ the channel

  /**
   * Open the channel to the application.
   *
   * Asynchronous by nature — the objects arrive in a message — so the engine can
   * say hello before this is done. Nothing is lost when it does: a report waits
   * in `unsent`, and a world that arrives later is sent as a snapshot, which is
   * what an engine that has been sent an empty one expects.
   */
  function connectToApplication() {
    var qt = window.qt;
    if (!qt || !qt.webChannelTransport || typeof window.QWebChannel !== "function") {
      console.error(
        "[agent surface] this page has no channel to the application, so it can " +
          "neither report nor carry events."
      );
      return;
    }
    new window.QWebChannel(qt.webChannelTransport, function (channel) {
      var surface = channel.objects.surface;
      if (!surface) {
        console.error("[agent surface] the application registered no surface on the channel.");
        return;
      }
      app = surface;
      app.serverEvent.connect(deliverServerEvent);
      app.worldChanged.connect(readWorld);
      for (var i = 0; i < unsent.length; i += 1) app.report(unsent[i][0], unsent[i][1]);
      unsent = [];
      readWorld();
    });
  }

  /**
   * The world and its program, from the application, whenever they change.
   *
   * Nothing is sent until there is something to send. An empty snapshot is not
   * a neutral starting state — a snapshot always wins — so sending one while the
   * world is still being read would tell the engine authoritatively that the
   * agent published nothing and then correct it a moment later.
   */
  function readWorld() {
    if (!app || !app.worldLoaded) return;

    var body = null;
    try {
      body = app.worldResponse ? JSON.parse(app.worldResponse) : null;
    } catch (error) {
      body = null;
    }
    var engineVersion =
      body && body.wom && typeof body.wom.engine_version === "string" && body.wom.engine_version
        ? body.wom.engine_version
        : null;
    if (!frame) {
      // A page with no renderer said so at the start, and frames nothing.
      if (!engineOrigin) return;
      mountFrame(engineVersion);
    } else if (body && body.wom && engineVersion !== frameEngine) {
      /*
        The agent moved to another engine — said by a world that was read, not
        by a read that failed. A program written for one release is not run in a
        machine started on another, so the page starts again on it.
      */
      window.location.reload();
      return;
    }

    programSource = typeof app.program === "string" && app.program.trim() ? app.program : null;

    var document = body && body.wom && body.wom.document;
    if (!document || !document.node_map || typeof document.node_map !== "object") return;

    setWorld(document, app.worldSources || {});
  }

  /**
   * Replace the world in one frame.
   *
   * A snapshot rather than a run of `add` ops, because that is what "this is
   * what the agent wants shown" means: it *is* the world now. Each node carries
   * its codename, the name the world's program includes it by, and its vibration
   * map as published — references included, which is where the engine reads
   * where every node sits. The snapshot carries an `artifact_map` as well: the
   * script each artifact declares its fields with, as the platform published
   * it, with the document's own map laid over the few it overrides. A world
   * does not list the artifacts it uses, so this is built here.
   */
  function setWorld(document, resolved) {
    nodes = [];
    byId = {};
    // A snapshot replaces the world, artifacts and all.
    artifacts = {};
    var ids = Object.keys(document.node_map);
    for (var index = 0; index < ids.length; index += 1) {
      var instanceId = ids[index];
      var node = document.node_map[instanceId] || {};
      var specifier =
        typeof node.artifact_specifier === "string" ? node.artifact_specifier.trim() : "";
      var wire = {
        instance_id: instanceId,
        artifact_specifier: node.artifact_specifier,
        driver: NODE_DRIVER,
        vibration_map: node.vibration_map || {},
      };
      if (node.codename) wire.codename = node.codename;
      var source = resolved[specifier];
      if (source && source.url) {
        wire.source = { url: source.url };
        if (source.integrity) wire.source.integrity = source.integrity;
        sources[node.artifact_specifier] = wire.source;
      }
      if (specifier && !artifacts[specifier]) {
        artifacts[specifier] =
          source && typeof source.simorg_initialization_script === "string" &&
          source.simorg_initialization_script
            ? { simorg_initialization_script: source.simorg_initialization_script }
            : {};
      }
      nodes.push(wire);
      byId[instanceId] = wire;
    }
    /*
      The world's own entries on top, field by field: an entry overrides what it
      names and nothing else, so one carrying no script leaves the artifact's
      own in place.
    */
    var overrides = document.artifact_map || {};
    var overridden = Object.keys(overrides);
    for (var overrideIndex = 0; overrideIndex < overridden.length; overrideIndex += 1) {
      var specifierKey = overridden[overrideIndex];
      var merged = {};
      var current = artifacts[specifierKey] || {};
      var currentKeys = Object.keys(current);
      for (var currentIndex = 0; currentIndex < currentKeys.length; currentIndex += 1) {
        merged[currentKeys[currentIndex]] = current[currentKeys[currentIndex]];
      }
      var override = overrides[specifierKey] || {};
      var overrideKeys = Object.keys(override);
      for (var keyIndex = 0; keyIndex < overrideKeys.length; keyIndex += 1) {
        merged[overrideKeys[keyIndex]] = override[overrideKeys[keyIndex]];
      }
      artifacts[specifierKey] = merged;
    }
    hasWorld = true;
    revision += 1;
    send({ __wom: snapshot() });
    runProgramIfDue();
  }

  /**
   * Run the surface's program — `brain.sim` for the Brain — once it is due.
   *
   * Three things have to be true: a world has been sent, the engine said it is
   * up, and this engine has not run this program already. The renderer does the
   * rest in its fixed order: a blueprint for every artifact the world defines,
   * the program, then every component's initialization script. A new engine — a
   * reload — runs it again, because nothing survives in a machine that was
   * replaced.
   */
  function runProgramIfDue() {
    if (!frame || !engineReady || !hasWorld) return;
    if (!programSource || programRunFor === programSource) {
      /*
        Nothing left to wait for, in either of the two ways there can be
        nothing.

        A surface with no program of its own is finished the moment the world
        is in: the engine draws what the world holds and there is nothing to
        run. And a surface whose program the engine has **already run** is
        finished too — that is an engine which came up before this page
        attached to it, or a page attaching to one that outlived the last
        visit, and `status` answered `running`, `released` or `failed`.

        Both are said here so that the window covering this page uncovers it,
        rather than waiting for an answer that is never coming. The second was
        not, and the cost was exactly the twenty seconds of the window's
        fallback: a Brain or a Workbench that was already drawn sat behind a
        spinner until the timer gave up on it.

        Not while a run is in flight, though. `programRunFor` is set before the
        request goes out, so it equals `programSource` for as long as the
        engine is working, and uncovering then would show the half-drawn world
        this whole arrangement exists to hide. The answer calls `drawn` itself.
      */
      if (!programRequestId) drawn();
      return;
    }
    programRunFor = programSource;
    programRequestId = "program-" + (requestCount += 1);
    send({
      __engine_req: { id: programRequestId, action: "run_program", source: programSource },
    });
  }

  /**
   * The surface is on screen, as far as this page can tell.
   *
   * *Connected* is the engine saying hello: it has booted and nothing is drawn
   * yet. Between the two it fetches its own modules, takes the world and runs
   * the program, drawing its own waiting state while it does — so a window that
   * uncovered this page at `connected` swapped its spinner for somebody else's.
   * This is the later moment, said once, and it is what the application waits
   * for. An engine that fails to run the program still reports it: what is on
   * screen then is the engine's own account of the failure, which is a great
   * deal more useful than a spinner that never stops.
   */
  function drawn() {
    if (reportedDrawn) return;
    reportedDrawn = true;
    report("drawn", "");
  }

  /**
   * The agent, saying something to the world on screen.
   *
   * A delivery the Hub made on the connection the application holds into this
   * agent, handed to `simorg-comm` in the frame on its own envelope — it vibrates
   * the variable the event's codename names. Not held and not replayed: a frame
   * is a moment, and one that arrives before anything listens was not meant to
   * wait.
   */
  function deliverServerEvent(delivery) {
    if (!frame || !frame.contentWindow || !attached) return;
    var envelope = { frame: { __server_event: delivery } };
    envelope[COMM_CHANNEL] = 1;
    frame.contentWindow.postMessage(envelope, engineOrigin);
  }

  /**
   * Tell the application something about this page.
   *
   * `connected`, `drawn` or `error`, and nothing here is trusted on the other
   * side: a state the application does not recognise is ignored, and the detail
   * is only ever shown as text. The first two are different moments and the
   * window waits on the second — see `drawn`.
   */
  function report(state, detail) {
    if (app) {
      app.report(state, detail || "");
      return;
    }
    unsent.push([state, detail || ""]);
  }

  /** A line for the application's log, when component logs are on. */
  function log(level, line) {
    if (app && app.componentLogs) app.log(level, line);
  }

  // ---------------------------------------------------------------- inbound

  function receive(event) {
    if (event.origin !== engineOrigin) return;
    /*
      From this page's own frame and no other. The engine is the only frame here
      today, and this is what keeps it that way: a second frame on the same
      origin — a component that opens one — would otherwise be answered as the
      engine, handed the world and allowed to speak for the page.
    */
    if (event.source && frame.contentWindow && event.source !== frame.contentWindow) return;
    attached = true;

    var data = event.data;
    if (!data || typeof data !== "object") return;
    var received = data.frame;
    if (!received || typeof received !== "object") return;
    var keys = Object.keys(received);

    if (COMM_CHANNEL in data) {
      for (var i = 0; i < keys.length; i += 1) handleComm(keys[i], received[keys[i]]);
      return;
    }
    if (!(CHANNEL in data)) return;
    for (var j = 0; j < keys.length; j += 1) handle(keys[j], received[keys[j]]);
  }

  /**
   * A frame from `simorg-comm`: the surface's program saying something.
   *
   * Only `__client_event` means anything on this envelope. The feature is not
   * added here — the application stamps the surface it opened this page for,
   * and overwrites whatever a page put there.
   */
  function handleComm(key, payload) {
    if (key !== "__client_event") return;
    if (!payload || typeof payload !== "object") return;
    if (!app) {
      console.warn(
        "[agent surface] " + config.surface + "/" + String(payload.codename) +
          " was not sent: the page has no channel to the application yet, and events are not queued."
      );
      return;
    }
    app.sendClientEvent(payload);
  }

  function handle(key, payload) {
    if (key === "__initialization_req") {
      connected = true;
      send({ __initialization_res: { environment: config.environment || {} } });
      /*
        The mood before the world, deliberately. The engine writes tokens onto
        one element and everything below inherits them, so sending the theme
        first means the first thing that paints is already in the right
        colours. The other order shows a flash of unstyled world.
      */
      sendTheme();
      send({ __wom: snapshot() });
      /*
        A renderer that asks to be initialized is a new one, with a machine
        nothing has run in. It may already be up — the engine can start before
        the handshake — so it is asked rather than waited on.
      */
      forgetEngine();
      statusRequestId = "status-" + (requestCount += 1);
      send({ __engine_req: { id: statusRequestId, action: "status" } });
      hide();
      report("connected", "");
      return;
    }

    if (key === "__engine_status") {
      engineReady = !!payload && payload.ready === true;
      runProgramIfDue();
      return;
    }

    if (key === "__engine_res") {
      var answer = payload || {};
      /*
        An answer that names no request is still an answer.

        The id exists so a reply can be matched to its request, and a published
        engine does not always echo it: it replies `{id: null, ok: true,
        result: …}`. It also never has more than one of these outstanding — the
        status is asked and settled before a program is ever sent — so the one
        that is waiting is the one being answered, and taking it that way costs
        nothing and is what the engine on the other side actually does.

        Insisting on the echo meant the status answer was dropped, and then the
        program's answer after it, and `drawn` was never said. What that looked
        like was every Brain and every Workbench sitting behind a spinner for
        the whole of the pane's twenty-second fallback and then appearing,
        perfectly, having been ready the entire time.
      */
      var id = answer.id || statusRequestId || programRequestId;
      if (id && id === statusRequestId) {
        statusRequestId = null;
        engineReady = answer.ok === true && !!answer.result && answer.result.ready === true;
        /*
          An engine that already has a program is not asked for another run of
          it. Its includes would create every component a second time in the
          same machine.
        */
        var state = answer.result && answer.result.program;
        if (state === "running" || state === "released" || state === "failed") {
          programRunFor = programSource;
        }
        runProgramIfDue();
        return;
      }
      if (id && id === programRequestId) {
        programRequestId = null;
        // Run or refused, this is the end of the wait: see `drawn`.
        drawn();
        if (answer.ok !== true) {
          log(
            "ERROR",
            "[agent surface] " + config.surface + " program: " +
              (typeof answer.error === "string"
                ? answer.error
                : "The engine did not run the surface's program.")
          );
        }
      }
      return;
    }

    if (key === "__wom_req") {
      send({ __wom: snapshot() });
      return;
    }

    if (key === "__driver_req") {
      var wanted = payload && payload.artifact_specifier;
      var source = sources[wanted];
      var response = { artifact_specifier: wanted, driver: payload && payload.driver };
      if (source) response.source = source;
      else response.error = "Simorg Desktop has not resolved " + wanted + ".";
      send({ __driver_res: response });
      return;
    }

    if (key === "__instance_vibration") {
      /*
        A component asking for a field value. It becomes the value once this
        echoes it back, and not before — which is why a component that needs
        keystroke-rate feedback keeps a local draft and commits.
      */
      var target = payload && payload.instance_id ? byId[payload.instance_id] : null;
      if (!target || !payload.vibration_map) return;
      /*
        Fields only. A reference — or a value written over the name of a slot
        this node holds — would move nodes on a component's say-so, and
        structure changes only through `__wom_op`, which this host decides.
      */
      var current = target.vibration_map || {};
      var values = {};
      var any = false;
      Object.keys(payload.vibration_map).forEach(function (name) {
        var entry = payload.vibration_map[name];
        if (referenceTargets(entry) !== null || referenceTargets(current[name]) !== null) return;
        values[name] = entry;
        any = true;
      });
      if (!any) return;
      var fields = {};
      Object.keys(current).forEach(function (name) {
        fields[name] = current[name];
      });
      Object.keys(values).forEach(function (name) {
        fields[name] = values[name];
      });
      target.vibration_map = fields;
      send({
        __instance_vibration: {
          instance_id: payload.instance_id,
          vibration_map: values,
        },
      });
      return;
    }

    if (key === "__wom_op") {
      // A request, not a change. The host decides and answers with the patch.
      var ops = (payload && payload.ops) || [];
      for (var i = 0; i < ops.length; i += 1) {
        var op = ops[i] || {};
        if (op.op === "move") {
          var moved = move(
            String(op.instance_id),
            typeof op.parent_instance_id === "string" ? op.parent_instance_id : null,
            typeof op.slot === "string" ? op.slot : undefined,
            typeof op.index === "number" ? op.index : undefined
          );
          if (moved) patch([moved]);
        }
        if (op.op === "reference") {
          var children = Array.isArray(op.children)
            ? op.children
            : typeof op.children === "string"
              ? [op.children]
              : null;
          if (!children) continue;
          var produced = reference(
            String(op.instance_id),
            typeof op.slot === "string" ? op.slot : CHILDREN_SLOT,
            children.filter(function (id) {
              return typeof id === "string";
            })
          );
          if (produced.length > 0) patch(produced);
        }
        if (op.op === "remove") remove(String(op.instance_id));
      }
      return;
    }

    if (key === "__log_request") {
      /*
        Component logs, forwarded by the engine. The agent's own diagnostics,
        so printed only in a development build — where they are the only record
        of what a component did after it initialized.
      */
      if (!payload || typeof payload !== "object") return;
      var level = String(payload.level || "INFO").toUpperCase();
      log(
        level,
        "[component " + String(payload.instance_id || "?") + "] " + level + " " +
          String(payload.code || "") + " " + String(payload.message || "")
      );
      return;
    }

    if (key === "__error" || key === "__engine_error") {
      report(
        "error",
        payload && typeof payload.message === "string"
          ? payload.message
          : "The renderer reported an error."
      );
    }
  }

  /** A new engine is a new machine: nothing has run in it yet. */
  function forgetEngine() {
    engineReady = false;
    programRunFor = null;
    programRequestId = null;
    statusRequestId = null;
  }

  /**
   * Put a node in `parentInstanceId`'s `slot` at `index` — the end when absent —
   * or make it a root. Answers the op to send, or null when it was refused.
   *
   * The same edit the engine's store makes for the same op: out of the list that
   * holds it, then into the new one at the index that list has once it is out.
   * Both sides doing it the same way is what keeps this world and the engine's
   * one world.
   */
  function move(instanceId, parentInstanceId, slot, index) {
    if (!byId[instanceId]) return null;
    var slotName = slot === undefined ? CHILDREN_SLOT : slot;
    var parent = parentInstanceId ? byId[parentInstanceId] : null;
    if (parentInstanceId) {
      if (!parent || parentInstanceId === instanceId) return null;
      // A node cannot be its own ancestor. The engine refuses it too, but a host
      // that sends the op anyway has told the engine something untrue.
      if (isDescendant(parentInstanceId, instanceId)) return null;
      // A field is data. A slot is never written over one.
      var existing = (parent.vibration_map || {})[slotName];
      if (existing !== undefined && referenceTargets(existing) === null) return null;
    }

    detach(instanceId);
    if (parent) {
      var list = (referenceTargets((parent.vibration_map || {})[slotName]) || []).filter(
        function (id) {
          return id !== instanceId;
        }
      );
      var at =
        index === undefined ? list.length : Math.max(0, Math.min(list.length, Math.trunc(index)));
      list.splice(at, 0, instanceId);
      setReference(parent, slotName, list);
    }

    var op = { op: "move", instance_id: instanceId, parent_instance_id: parentInstanceId };
    if (slot !== undefined) op.slot = slot;
    if (index !== undefined) op.index = index;
    return op;
  }

  /**
   * Make one slot hold exactly `children`, in that order.
   *
   * Sent on as the moves that produce it: a node sits in exactly one place, so
   * every node the list gains leaves wherever it was and every node it loses
   * becomes a root, and a move says both. A child that is not in the world, is
   * the holder, or already holds it is dropped.
   */
  function reference(holderId, slot, children) {
    var holder = byId[holderId];
    if (!holder) return [];
    var existing = (holder.vibration_map || {})[slot];
    if (existing !== undefined && referenceTargets(existing) === null) return [];

    var wanted = [];
    for (var i = 0; i < children.length; i += 1) {
      var id = children[i];
      if (wanted.indexOf(id) !== -1 || id === holderId || !byId[id]) continue;
      if (isDescendant(holderId, id)) continue;
      wanted.push(id);
    }
    var ops = [];
    var current = referenceTargets(existing) || [];
    for (var j = 0; j < current.length; j += 1) {
      if (wanted.indexOf(current[j]) !== -1) continue;
      var out = move(current[j], null);
      if (out) ops.push(out);
    }
    for (var k = 0; k < wanted.length; k += 1) {
      var into = move(wanted[k], holderId, slot, k);
      if (into) ops.push(into);
    }
    return ops;
  }

  function remove(instanceId) {
    if (!byId[instanceId]) return;
    var gone = descendants(instanceId);
    detach(instanceId);
    for (var i = 0; i < gone.length; i += 1) delete byId[gone[i]];
    nodes = nodes.filter(function (node) {
      return byId[node.instance_id] === node;
    });
    patch([{ op: "remove", instance_id: instanceId }]);
  }

  /** Where a node sits: the node and slot whose reference names it, or null. */
  function holderOf(instanceId) {
    for (var i = 0; i < nodes.length; i += 1) {
      var map = nodes[i].vibration_map || {};
      var names = Object.keys(map);
      for (var j = 0; j < names.length; j += 1) {
        var targets = referenceTargets(map[names[j]]);
        if (targets && targets.indexOf(instanceId) !== -1) {
          return { holder: nodes[i], slot: names[j] };
        }
      }
    }
    return null;
  }

  /** Take a node out of the list that holds it. */
  function detach(instanceId) {
    var where = holderOf(instanceId);
    if (!where) return;
    var list = referenceTargets(where.holder.vibration_map[where.slot]) || [];
    setReference(
      where.holder,
      where.slot,
      list.filter(function (id) {
        return id !== instanceId;
      })
    );
  }

  function setReference(node, slot, ids) {
    var fields = {};
    var current = node.vibration_map || {};
    Object.keys(current).forEach(function (name) {
      fields[name] = current[name];
    });
    fields[slot] = { value: ids, is_reference: true };
    node.vibration_map = fields;
  }

  /** The node and everything it holds, however deep. */
  function descendants(instanceId) {
    var found = [];
    var seen = {};
    var queue = [instanceId];
    while (queue.length > 0) {
      var current = queue.shift();
      if (seen[current] || !byId[current]) continue;
      seen[current] = true;
      found.push(current);
      var map = byId[current].vibration_map || {};
      Object.keys(map).forEach(function (name) {
        var targets = referenceTargets(map[name]);
        if (targets) queue.push.apply(queue, targets);
      });
    }
    return found;
  }

  /** Whether `candidate` sits somewhere under `ancestor`, or is it. */
  function isDescendant(candidate, ancestor) {
    var cursor = candidate;
    var seen = {};
    while (cursor) {
      if (cursor === ancestor || seen[cursor]) return true;
      seen[cursor] = true;
      var where = holderOf(cursor);
      cursor = where ? where.holder.instance_id : null;
    }
    return false;
  }

  /**
   * The instance ids a vibration entry holds when it is a reference, in order,
   * or null for an ordinary field.
   */
  function referenceTargets(entry) {
    if (!entry || typeof entry !== "object" || entry.is_reference !== true) return null;
    if (typeof entry.value === "string") return [entry.value];
    if (Array.isArray(entry.value)) {
      return entry.value.filter(function (id) {
        return typeof id === "string";
      });
    }
    return [];
  }

  // ---------------------------------------------------------------- outbound

  function send(body) {
    /*
      Nothing is lost by not sending before the engine is there: it asks to be
      initialized when it boots, and is sent the mood and the world then.
    */
    if (!frame || !frame.contentWindow || !attached) return;
    var envelope = { frame: body };
    envelope[CHANNEL] = 1;
    frame.contentWindow.postMessage(envelope, engineOrigin);
  }

  function patch(ops) {
    revision += 1;
    send({ __wom_patch: { revision: revision, ops: ops } });
  }

  function sendTheme() {
    if (!config.theme) return;
    send({
      __theme: {
        artifact_specifier: config.theme.artifactSpecifier,
        driver: config.theme.driver,
        choice: config.theme.choice,
        source: config.theme.source,
      },
    });
  }

  /** The whole world. Where each node is drawn is its holder's references. */
  function snapshot() {
    return { revision: revision, nodes: nodes.slice(), artifact_map: artifacts };
  }

  // ------------------------------------------------------------------ helpers

  function say(message) {
    noticeText.textContent = message;
    notice.setAttribute("data-shown", "1");
  }

  function hide() {
    notice.removeAttribute("data-shown");
  }

  function readConfig() {
    var tag = document.getElementById("surface-config");
    if (!tag || !tag.textContent) return null;
    try {
      return JSON.parse(tag.textContent);
    } catch (error) {
      return null;
    }
  }

  /** `https://host:port` from an absolute URL, or an empty string. */
  function originOf(url) {
    try {
      return new URL(url).origin;
    } catch (error) {
      return "";
    }
  }
})();
