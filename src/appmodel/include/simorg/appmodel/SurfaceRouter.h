// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QString>
#include <QUrl>

namespace simorg::app {

/**
 * One answer to one request on the surface scheme.
 *
 * A plain value with no Qt WebEngine anywhere in it, which is the point: the
 * routing, the document and the status channel are all decided here, in code a
 * test can call with a `QUrl` and read the bytes back out of. What the browser
 * layer adds is a reply object to write them into.
 */
struct SurfaceReply
{
    /** False for a path this scheme does not serve. The browser gets a 404. */
    bool found = false;
    QByteArray body;
    QByteArray mimeType;
};

/**
 * The scheme an agent surface is hosted on, and everything served over it.
 *
 * ## Why there is a scheme at all
 *
 * The engine cannot be the top-level page. It speaks its half of the protocol
 * over `postMessage` to `window.parent`, and a top-level document's parent is
 * itself — so an engine loaded directly would post every frame straight back
 * into its own listener and answer its own handshake. It has to run in an
 * **iframe**, which means something has to be the document above it.
 *
 * That document cannot come from `qrc:` or `file:` either. Both give an opaque
 * origin, and an opaque origin cannot be named as a `postMessage` target, which
 * is the one thing the whole arrangement depends on. So this build registers a
 * scheme of its own — secure, CORS-enabled, with host syntax — and serves the
 * host document from it. The page then has a real origin (`simorg-surface://…`)
 * that the engine can be told to post to, and that the host can check inbound
 * frames against.
 *
 * ```
 *   simorg-surface://agent/index.html?surface=WORKBENCH&agent=12   the host page
 *   simorg-surface://agent/host.js                                 its script
 * ```
 *
 * ## The page's way back is not here
 *
 * This scheme serves bytes and nothing else. Everything the page tells the
 * application — the engine said hello, a component's program said something to
 * the agent — goes over the web view's `QWebChannel` to an
 * {@link SurfaceSessionModel}, which is the bridge Qt provides for exactly that
 * and the one that carries both directions.
 */
class SurfaceRouter
{
public:
    /** `simorg-surface`. Registered before the application object is created. */
    static QString scheme();
    /** The host component of every URL on it. One origin, not one per agent. */
    static QString host();

    /** Where a web view is pointed for one surface of one agent. */
    static QUrl documentUrl(const QString &surface, int agentId);

    /** The surface named on a URL, or an empty string. */
    static QString surfaceOf(const QUrl &url);
    /** The agent named on a URL, or 0. */
    static int agentOf(const QUrl &url);

    /**
     * Answer one request.
     *
     * `config` is what {@link SurfaceRendererModel::pageConfig} produced for the
     * surface being asked for. An **empty** object is not an error here: it
     * means nothing has resolved yet, and the page renders that as a wait
     * rather than as an engine with no theme.
     */
    static SurfaceReply route(const QUrl &url, const QJsonObject &config);

    /**
     * The host document, with its configuration baked in.
     *
     * Built rather than fetched by the page for one reason: a document that
     * arrives complete cannot be seen half-configured, and there is no second
     * request to fail.
     */
    static QByteArray document(const QJsonObject &config);
};

} // namespace simorg::app
