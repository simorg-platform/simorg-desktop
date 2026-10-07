// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QObject>
#include <QString>

#include <QWebEngineUrlSchemeHandler>

class QWebEngineUrlRequestJob;



namespace simorg::app {

class SurfaceRendererModel;

/**
 * Serves the agent-surface host page, on a scheme this build registers.
 *
 * A thin adapter and nothing more: every decision — which paths exist, what the
 * document contains, what a status report means — is made by
 * {@link SurfaceRouter} in the core library, where it can be tested with a
 * `QUrl` and no browser. What is here is the part that cannot be: turning a
 * `QWebEngineUrlRequestJob` into that call and back.
 *
 * ## Why this exists rather than `qrc:`
 *
 * Because the engine has to be an **iframe**, and an iframe needs a parent with
 * a real origin. `qrc:` and `file:` both give an opaque one, which cannot be
 * named as a `postMessage` target — and naming it is the whole of the protocol
 * between this application and the renderer. See `SurfaceRouter`, which carries
 * the long version.
 *
 * ## What the page can reach through it
 *
 * Two paths, matched exactly: the document and its script. There is no
 * directory behind either — both are compiled into this build, so there is
 * nothing on the disk a crafted path could reach even if one were accepted. The
 * page speaks back over the view's `QWebChannel`, not over this scheme; see
 * `SurfaceSessionModel`.
 */
class SurfaceSchemeHandler : public QWebEngineUrlSchemeHandler
{
    Q_OBJECT

public:
    /**
     * Registers the scheme with Chromium.
     *
     * **Must be called before the `QCoreApplication` is constructed**, which is
     * a Chromium rule rather than a Qt one: the scheme registry is read once
     * when the web engine initialises, and a scheme added afterwards is
     * accepted silently and then behaves like an unknown one. There is no
     * warning for getting this wrong; the surface simply never loads.
     */
    static void registerScheme();

    explicit SurfaceSchemeHandler(SurfaceRendererModel *surfaces,
                                  QObject *parent = nullptr);

    void requestStarted(QWebEngineUrlRequestJob *job) override;

private:
    SurfaceRendererModel *m_surfaces;
};

} // namespace simorg::app
