// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QUrl>

class QNetworkAccessManager;

namespace simorg::app {

/**
 * Every picture this app draws, fetched once and kept in the shape it has on
 * the Logos.
 *
 * The signed-in account's is one of them. So is every agent's: an agent has a
 * face on its page in the web panel, on its card in the catalogue and on the
 * Logos, and until this held more than one address it had none here — the app
 * drew the first letter of its name and nothing else, on the one screen whose
 * whole job is telling several agents apart.
 *
 * ## Why the shape is cut here and not in QML
 *
 * Qt Quick has no way to mask an image to a shape that this app can use.
 * `clip` is rectangular, `MultiEffect` arrived in Qt 6.5 and this app still
 * builds on the 6.4 that current Ubuntu LTS ships, and every shader-based
 * route is dead on the software backend the interface tests render with. So
 * the alpha channel is cut with QPainter on the way in, and what QML gets is a
 * PNG that is already the right shape — which draws identically on every
 * backend, every Qt, and every scale factor, with no effect in the scene graph
 * at all. The outline is {@link FlowerShape}'s, the same one the window draws
 * the frame from.
 *
 * ## Why it is a file and not a pixmap
 *
 * An `Image` pointed at a local file is the one loading path in Qt Quick with
 * no failure states worth designing for, and a file survives the process — so
 * somebody who signs in on a train sees their own face, and their agents', from
 * the cache rather than a placeholder waiting on a network that is not there.
 * Each file is named after the address it came from, which is what makes a
 * changed picture a different file rather than a stale one Qt's pixmap cache
 * would go on drawing.
 *
 * Written under the cache root the service reports, because that is exactly what
 * it is: something downloaded, kept so it is not downloaded again, and safe to
 * delete at any moment. Clearing the cache costs one request per face.
 */
class AvatarCache : public QObject
{
    Q_OBJECT

public:
    explicit AvatarCache(QObject *parent = nullptr);

    /**
     * Where the API is and where Simorg's cache is, as the Simorg machine service is
     * configured. Until both are known an address is remembered and nothing is fetched.
     *
     * @param apiEndpoint what a **relative** avatar URL is resolved against.
     *
     * The platform returns `/api/v1/files/public/<id>` with no host on it, on
     * purpose — for an account on its profile and for an agent on the Hub's own
     * roster: a payload cannot know which origin will read it, and a URL with no
     * host in it cannot be wrong about which environment it belongs to. The
     * client supplies the host, and the client already knows which API it is
     * talking to. An absolute URL — which is what a deployment with
     * `FILES_BASE_URL` set sends — is used as it stands.
     */
    void configure(const QString &apiEndpoint, const QString &cacheRoot);

    /**
     * The cut PNG for one platform address, or an empty URL when there is not
     * one yet — which is also when this starts fetching it.
     *
     * Safe to call on every binding evaluation, which is how QML will call it:
     * a picture already on the disk costs a hash lookup, and an address already
     * being fetched, or already refused, starts nothing. {@link arrived} says
     * when an answer turns up, and the caller asks again.
     */
    Q_INVOKABLE QUrl fileFor(const QString &url);

Q_SIGNALS:
    /** That address has a picture on this disk now. */
    void arrived(const QString &url);

private:
    /** Resolved against the API; empty for an address this app will not fetch. */
    QUrl addressOf(const QString &url) const;
    /**
     * Remembers the file, and tells whoever asked too early.
     *
     * The announcement is queued rather than emitted where it is found: this is
     * reached from inside a QML binding being evaluated, and a signal that
     * re-entered the same binding would be a property changing while it is
     * being computed.
     */
    void keep(const QString &source, const QString &file);
    void fetch(const QString &source, const QUrl &from, const QString &destination);

    /** Where the API is, for the relative URLs it sends. */
    QString m_apiEndpoint;
    /** `<cache root>/avatars`: swept with the rest of the cache when somebody signs out. */
    QString m_directory;
    /**
     * Created on first use, so a build of this app that never draws a face
     * never opens a network stack.
     */
    QNetworkAccessManager *m_network = nullptr;
    /** Platform address → the cut PNG on this disk. */
    QHash<QString, QUrl> m_files;
    /** Asked for and not answered yet; one request per address, however many rows want it. */
    QSet<QString> m_fetching;
    /**
     * Addresses this app will not ask for again in this run.
     *
     * A picture that could not be decoded, or that the platform answered with an
     * error, is not going to become decodable by being asked for once per frame
     * — and a list of agents is a binding that would do exactly that.
     */
    QSet<QString> m_refused;
    /** Asked for before `configure` said where; fetched as soon as it does. */
    QSet<QString> m_waiting;
    /**
     * Addresses somebody asked for and got nothing back.
     *
     * A window binds to a face, is handed nothing, and then never looks again
     * until it is told to — so the *telling* is the whole of this. It is not
     * only the network that answers: the picture is usually already on the disk
     * from the last run, and the moment worth announcing is when this cache can
     * finally resolve the address, which is when `GET /v1/config` lands.
     *
     * Without this the account's own picture sat in the cache directory while
     * the toolbar drew two letters, for the whole session, every session.
     */
    QSet<QString> m_unanswered;
};

} // namespace simorg::app
