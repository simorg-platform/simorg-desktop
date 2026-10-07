// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "AvatarCache.h"

#include "FlowerShape.h"

#include "simorg/frontend/Logging.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QPainterPath>
#include <QRegularExpression>

#include <cmath>

#include <utility>

namespace simorg::app {
namespace {

/**
 * How big the cut-out is kept on disk.
 *
 * The largest this app draws an avatar is 34 points, which on a three-times
 * display is 102 pixels — so 256 is generous at every scale factor anybody has,
 * and it is still a quarter of a megabyte. Storing the original instead would
 * mean holding somebody's four-megapixel photograph in the scene graph to draw
 * a shape the size of a fingernail.
 */
constexpr int kAvatarPixels = 256;

/**
 * A ceiling on what will be decoded.
 *
 * The body is a picture from the platform rather than from a stranger, but it
 * is still the one thing in this app that arrives as bytes and is handed to an
 * image decoder — and a decoder is the wrong place to find out that a reply was
 * eight hundred megabytes.
 */
constexpr qint64 kMaxAvatarBytes = 8 * 1024 * 1024;

/** `directory`, created on demand. Empty when it cannot be made. */
QString ensured(const QString &directory)
{
    if (directory.isEmpty() || !QDir().mkpath(directory)) {
        qCWarning(lcApp) << "no avatar cache at" << directory;
        return {};
    }
    return directory;
}

/**
 * The file one avatar URL is kept as.
 *
 * Named after the address rather than after the account or the agent, so a
 * changed picture is a **different file**. Qt's pixmap cache is keyed by URL and
 * holds what it has already loaded for the life of the process; a fixed file
 * name would mean somebody who changed their avatar kept looking at the old one
 * until they quit.
 *
 * The name also carries the **shape** it was cut to, as the shape's own
 * signature, worked out from the drawing (`FlowerShape::signature`). A picture
 * cut to one shape laid inside the frame of another shows the ground through
 * wherever the two differ, so any change to the outline is a change of name,
 * and the picture is fetched and cut again.
 */
QString shapeSuffix()
{
    static const QString suffix = QStringLiteral("-flower-%1.png").arg(FlowerShape::signature());
    return suffix;
}

QString fileNameFor(const QString &url)
{
    const QByteArray digest =
        QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha256).toHex().left(24);
    return QString::fromLatin1(digest) + shapeSuffix();
}

/**
 * The pictures in `directory` cut to a shape this build no longer draws.
 *
 * They can never be drawn again — a new name is fetched instead — so they are
 * removed rather than left to be swept at sign-out. Only files named the way this
 * cache names them: a digest, a dash, a shape.
 */
void removeOtherShapes(const QString &directory)
{
    static const QRegularExpression ours(QStringLiteral("^[0-9a-f]{24}-.+\\.png$"));
    const QFileInfoList files = QDir(directory).entryInfoList({QStringLiteral("*.png")}, QDir::Files);
    for (const QFileInfo &file : files) {
        if (ours.match(file.fileName()).hasMatch() && !file.fileName().endsWith(shapeSuffix()))
            QFile::remove(file.absoluteFilePath());
    }
}

/**
 * The picture, centre-cropped to a square and cut to the shape an account or an
 * agent has on the Logos.
 *
 * `KeepAspectRatioByExpanding` and then a centred draw rather than a squash: a
 * portrait photograph scaled to fit a square is a person made narrow, and every
 * avatar on the web is cropped rather than distorted.
 *
 * The square it fills is the **face's** (`FlowerShape::faceSquare`), exactly the
 * web's `faceHalf`, so a picture is framed the same way in this app as on the
 * web: filling the whole drawing instead framed every face a size smaller, with
 * more of whatever stood round it.
 *
 * The outline is {@link FlowerShape}'s, which is also the outline the window
 * draws the frame from — one piece of arithmetic, so the picture cannot end up a
 * corner wider than the line around it.
 */
QImage cutToShape(const QImage &source)
{
    const QRectF square = FlowerShape::faceSquare(kAvatarPixels);
    const QImage scaled = source.scaled(QSize(int(std::ceil(square.width())), int(std::ceil(square.height()))),
                                        Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);

    QImage out(kAvatarPixels, kAvatarPixels, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);

    QPainter painter(&out);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setClipPath(FlowerShape::faceRegion(kAvatarPixels), Qt::ReplaceClip);

    painter.drawImage(QPointF(square.center().x() - scaled.width() / 2.0,
                              square.center().y() - scaled.height() / 2.0),
                      scaled);
    return out;
}

} // namespace

AvatarCache::AvatarCache(QObject *parent)
    : QObject(parent)
{
}

void AvatarCache::configure(const QString &apiEndpoint, const QString &cacheRoot)
{
    const QString directory = cacheRoot.isEmpty() ? QString() : QDir(cacheRoot).filePath(QStringLiteral("avatars"));
    if (apiEndpoint == m_apiEndpoint && directory == m_directory)
        return;
    m_apiEndpoint = apiEndpoint;
    m_directory = directory;
    if (!directory.isEmpty() && QFileInfo::exists(directory))
        removeOtherShapes(directory);

    /*
      Whatever was asked for before the service said where things are.

      Every window is drawn before the first connection answers, so the first
      face anybody asks for is almost always asked for too early. Remembering
      the address and fetching it here is what makes that a delay rather than a
      picture that never appears.
    */
    const QSet<QString> waiting = std::exchange(m_waiting, {});
    for (const QString &url : waiting)
        fileFor(url);
}

QUrl AvatarCache::fileFor(const QString &url)
{
    const QString wanted = url.trimmed();
    if (wanted.isEmpty())
        return {};

    /*
      Checked on the disk as well as in the table.

      A cache somebody emptied underneath us — signing out sweeps it — is fetched
      again rather than remembered as done, and this is also how a picture
      downloaded on a previous run is drawn with no request at all, which is what
      makes a laptop opened offline show faces rather than initials.
    */
    const auto known = m_files.constFind(wanted);
    if (known != m_files.constEnd()) {
        if (QFileInfo::exists(known->toLocalFile()))
            return *known;
        m_files.remove(wanted);
    }

    if (m_fetching.contains(wanted) || m_refused.contains(wanted))
        return {};

    if (m_apiEndpoint.isEmpty() || m_directory.isEmpty()) {
        // Asked before the service said where anything is, which is what every
        // window does: the profile arrives on a topic snapshot and `/v1/config`
        // answers a moment later.
        m_waiting.insert(wanted);
        m_unanswered.insert(wanted);
        return {};
    }

    const QUrl address = addressOf(wanted);
    if (address.isEmpty()) {
        m_refused.insert(wanted);
        return {};
    }

    const QString directory = ensured(m_directory);
    if (directory.isEmpty())
        return {};

    const QString destination = QDir(directory).filePath(fileNameFor(address.toString()));
    if (QFileInfo::exists(destination)) {
        // Here from a previous run, so there is nothing to fetch — but somebody
        // may have asked for it before this cache could say so.
        keep(wanted, destination);
        return m_files.value(wanted);
    }

    m_fetching.insert(wanted);
    m_unanswered.insert(wanted);
    fetch(wanted, address, destination);
    return {};
}

void AvatarCache::keep(const QString &source, const QString &file)
{
    m_files.insert(source, QUrl::fromLocalFile(file));
    if (!m_unanswered.remove(source))
        return;
    // Queued: see the note on the declaration. `arrived` is what a window binds
    // its next look at this face to.
    QMetaObject::invokeMethod(
        this, [this, source] { Q_EMIT arrived(source); }, Qt::QueuedConnection);
}

QUrl AvatarCache::addressOf(const QString &url) const
{
    /*
      Resolved against the API, which is where the files are.

      Relative is the normal shape and the safe one; absolute is what a
      deployment that has moved its files to a CDN sends, and it is taken as it
      stands. Anything that is neither — a `file:` path, say — is refused rather
      than turned into a local read.
    */
    QUrl resolved(url);
    if (resolved.isRelative()) {
        const QString path = url.startsWith(QLatin1Char('/')) ? url : QLatin1Char('/') + url;
        resolved = QUrl(m_apiEndpoint + path);
    }

    const QString scheme = resolved.scheme().toLower();
    if (scheme != QLatin1String("http") && scheme != QLatin1String("https")) {
        qCWarning(lcApp) << "refusing to fetch an avatar from" << resolved.toString();
        return {};
    }
    return resolved;
}

void AvatarCache::fetch(const QString &source, const QUrl &from, const QString &destination)
{
    if (!m_network)
        m_network = new QNetworkAccessManager(this);

    QNetworkRequest request(from);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    /*
      No bearer token, on purpose.

      This is `/api/v1/files/public/<id>` — the address the platform hands out
      precisely so that anybody rendering the profile or the agent can fetch it.
      Attaching this computer's session to a request that may be redirected to a
      CDN would send the credential somewhere it has no business being.
    */
    QNetworkReply *reply = m_network->get(request);

    connect(reply, &QNetworkReply::finished, this, [this, reply, source, from, destination] {
        reply->deleteLater();
        m_fetching.remove(source);

        if (reply->error() != QNetworkReply::NoError) {
            /*
              Not refused for the run: a network that is down comes back, and an
              agent's face should appear when it does rather than at the next
              launch. What is refused below is a body this app cannot use.
            */
            qCDebug(lcApp) << "avatar not fetched:" << reply->errorString();
            return;
        }

        const QByteArray body = reply->readAll();
        if (body.isEmpty() || body.size() > kMaxAvatarBytes) {
            qCDebug(lcApp) << "avatar ignored:" << body.size() << "bytes from" << from.toString();
            m_refused.insert(source);
            return;
        }

        QImage decoded;
        if (!decoded.loadFromData(body)) {
            qCDebug(lcApp) << "avatar could not be decoded:" << from.toString();
            m_refused.insert(source);
            return;
        }

        if (!cutToShape(decoded).save(destination, "PNG")) {
            qCWarning(lcApp) << "avatar could not be written to" << destination;
            return;
        }

        m_files.insert(source, QUrl::fromLocalFile(destination));
        m_unanswered.remove(source);
        // Already outside any binding — this is a network reply — so it is said
        // where it happened rather than queued.
        Q_EMIT arrived(source);
    });
}

} // namespace simorg::app
