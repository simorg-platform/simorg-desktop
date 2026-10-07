// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/SurfaceRouter.h"

#include "EmbeddedSurface.h"

#include <QJsonDocument>
#include <QUrlQuery>

namespace simorg::app {
namespace {

constexpr auto kScheme = "simorg-surface";
constexpr auto kHost = "agent";

/** The placeholders the served document has substituted into it. */
constexpr auto kConfigPlaceholder = "__SURFACE_CONFIG__";
constexpr auto kColorSchemePlaceholder = "__SURFACE_COLOR_SCHEME__";

/**
 * JSON that cannot escape the script element it sits in.
 *
 * `<` is the only character that can start a tag, so escaping it is enough and
 * leaves the JSON valid — `<` parses back to `<`. Nothing in this
 * configuration is written by a stranger today, and every value in it does come
 * from somewhere else: an artifact specifier an operator typed into
 * `platform_params`, a URL a second service composed. A document that can be
 * closed early by one of them is a document that runs whatever came after.
 */
QByteArray inertJson(const QJsonObject &object)
{
    QByteArray json = QJsonDocument(object).toJson(QJsonDocument::Compact);
    json.replace("<", "\\u003c");
    return json;
}

} // namespace

QString SurfaceRouter::scheme()
{
    return QString::fromLatin1(kScheme);
}

QString SurfaceRouter::host()
{
    return QString::fromLatin1(kHost);
}

QUrl SurfaceRouter::documentUrl(const QString &surface, int agentId)
{
    QUrl url;
    url.setScheme(scheme());
    url.setHost(host());
    url.setPath(QStringLiteral("/index.html"));

    /*
      On the URL rather than only in the document, because the router is asked
      for a document *by* a URL: the handler has to know which surface and which
      agent it is being asked about before it can build one. It is also what
      makes the two panes two pages rather than one page told to change — a
      surface switching identity underneath a booted engine is a reload wearing
      a disguise.
    */
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("surface"), surface);
    if (agentId > 0)
        query.addQueryItem(QStringLiteral("agent"), QString::number(agentId));
    url.setQuery(query);
    return url;
}

QString SurfaceRouter::surfaceOf(const QUrl &url)
{
    return QUrlQuery(url).queryItemValue(QStringLiteral("surface"));
}

int SurfaceRouter::agentOf(const QUrl &url)
{
    return QUrlQuery(url).queryItemValue(QStringLiteral("agent")).toInt();
}

SurfaceReply SurfaceRouter::route(const QUrl &url, const QJsonObject &config)
{
    SurfaceReply reply;

    /*
      An allowlist of two paths, matched exactly. Not a directory: this scheme
      serves what this build embedded and nothing else, so there is no path to
      traverse out of and no file on the disk it could reach if there were.
    */
    const QString path = url.path();

    if (path == QLatin1String("/") || path == QLatin1String("/index.html")) {
        reply.found = true;
        reply.mimeType = "text/html";
        reply.body = document(config);
        return reply;
    }

    if (path == QLatin1String("/host.js")) {
        reply.found = true;
        reply.mimeType = "text/javascript";
        reply.body = embeddedSurfaceScript();
        return reply;
    }

    return reply;
}

QByteArray SurfaceRouter::document(const QJsonObject &config)
{
    QByteArray html = embeddedSurfaceDocument();

    /*
      The mood is written into the document rather than only sent to the engine,
      and it is the more important half. A `color-scheme` declaration is acted
      on by the browser at parse time, before the engine has been fetched and
      long before a theme artifact has been read — without it a dark window
      shows a white rectangle for as long as those two downloads take.

      Light when nothing has resolved, which is the same thing the browser would
      do on its own and never worse than it.
    */
    const QString choice =
        config.value(QStringLiteral("theme")).toObject().value(QStringLiteral("choice")).toString();
    html.replace(kColorSchemePlaceholder, choice == QLatin1String("dark") ? "dark" : "light");

    html.replace(kConfigPlaceholder, config.isEmpty() ? QByteArray("null") : inertJson(config));
    return html;
}

} // namespace simorg::app
