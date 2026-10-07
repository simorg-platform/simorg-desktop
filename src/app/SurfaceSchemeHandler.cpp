// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "SurfaceSchemeHandler.h"

#include "simorg/appmodel/SurfaceModels.h"
#include "simorg/frontend/Logging.h"
#include "simorg/appmodel/SurfaceRouter.h"

#include <QBuffer>
#include <QWebEngineUrlRequestJob>
#include <QWebEngineUrlScheme>

namespace simorg::app {

void SurfaceSchemeHandler::registerScheme()
{
    QWebEngineUrlScheme scheme(SurfaceRouter::scheme().toUtf8());
    /*
      Host syntax, so the origin is a real tuple — `simorg-surface://agent` —
      rather than the opaque one a path-only scheme produces. An opaque origin
      cannot be named as a `postMessage` target, and naming it is the entire
      arrangement between this page and the engine inside it.
    */
    scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
    scheme.setDefaultPort(QWebEngineUrlScheme::PortUnspecified);
    /*
      Secure, so the page counts as a secure context: the engine is fetched over
      https in production, and a document that is not secure cannot frame one
      without being treated as mixed content.

      CORS-enabled and fetch-allowed, because the page reports its state back by
      fetching a URL on this same scheme. Without those two the request is
      refused before it reaches this handler and the application never learns
      whether the engine connected.

      Not `LocalScheme`, and that is deliberate rather than an omission. Local
      schemes may read `file:` URLs, which is precisely what a document hosting
      third-party code should not be able to do.
    */
    scheme.setFlags(QWebEngineUrlScheme::SecureScheme
                    | QWebEngineUrlScheme::CorsEnabled
                    | QWebEngineUrlScheme::FetchApiAllowed);
    QWebEngineUrlScheme::registerScheme(scheme);
}

SurfaceSchemeHandler::SurfaceSchemeHandler(SurfaceRendererModel *surfaces, QObject *parent)
    : QWebEngineUrlSchemeHandler(parent)
    , m_surfaces(surfaces)
{
}

void SurfaceSchemeHandler::requestStarted(QWebEngineUrlRequestJob *job)
{
    const QUrl url = job->requestUrl();
    const QString surface = SurfaceRouter::surfaceOf(url);
    const int agentId = SurfaceRouter::agentOf(url);

    const QJsonObject config =
        m_surfaces ? m_surfaces->pageConfig(surface, agentId) : QJsonObject();
    const SurfaceReply reply = SurfaceRouter::route(url, config);

    if (!reply.found) {
        qCWarning(lcApp) << "surface scheme: nothing at" << url.path();
        job->fail(QWebEngineUrlRequestJob::UrlNotFound);
        return;
    }

    /*
      The buffer is parented to the job, which is how Qt's own examples do it
      and the only lifetime that is correct: the reply is read asynchronously
      after this function returns, and a buffer on the stack would be gone by
      then.
    */
    auto *buffer = new QBuffer(job);
    buffer->setData(reply.body);
    job->reply(reply.mimeType, buffer);
}

} // namespace simorg::app
