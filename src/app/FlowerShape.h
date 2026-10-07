// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QImage>
#include <QObject>
#include <QPainterPath>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QVector>

namespace simorg::app {

/**
 * The shape an account wears on the Logos, for the windows and for the cutter.
 *
 * On the Logos a person, a team or an agent is **seven cells of the honeycomb**
 * with their picture spread across them — the middle cell and its six
 * neighbours. The web panel draws the same figure at the top of every public
 * page and wherever an identity is drawn, and this is that figure in C++, so the face somebody
 * recognises on the sheet and on the web is the face they see in this app —
 * the same outline, the same margin, the same square the picture fills, and the
 * same light on it.
 *
 * ## Why the arithmetic is here and not in QML
 *
 * Two things need it and they need it in different forms. QML draws the frame
 * with Qt Quick Shapes, which wants an SVG path; {@link AvatarCache} cuts the
 * downloaded picture to the same outline with QPainter, which wants a
 * `QPainterPath`. Working it out twice is how the two would drift a corner
 * apart — and a picture cut a corner wider than the frame around it is visible
 * at any size.
 *
 * ## The numbers are the Logos's
 *
 * A cell is 34 units across and a node is seven of them, exactly as in
 * `logosLattice.ts`; everything below — the margin the picture keeps inside the
 * frame, how far each corner is rounded — is in those units and scaled at the
 * end to whatever the caller is drawing at. So the mark has the same
 * proportions at twenty-seven pixels in a toolbar and at two hundred in a
 * cache file.
 */
class FlowerShape : public QObject
{
    Q_OBJECT
    /** The width the outline is drawn in, before it is scaled: 106 units. */
    Q_PROPERTY(qreal viewSize READ viewSize CONSTANT)

public:
    explicit FlowerShape(QObject *parent = nullptr);

    static qreal viewSize();

    /**
     * The outer edge of the seven cells, as an SVG path fitted to a `pixels`
     * square with its top-left corner at the origin.
     *
     * Every corner is rounded, the lobes' tips and the notches between them
     * alike — the seams *between* the cells are not drawn at all, because those
     * belong to the sheet rather than to the account standing on it.
     */
    Q_INVOKABLE QString framePath(qreal pixels) const;

    /**
     * The picture's own edge: the same outline brought inward by the Logos's
     * margin, so the frame is a line around a picture rather than a border
     * drawn on top of one.
     */
    Q_INVOKABLE QString facePath(qreal pixels) const;

    /**
     * The initials' pixel size for an avatar `pixels` across: the web's
     * `round(faceHalf × 0.68)` in the Logos's units, scaled, so two letters sit in
     * the face the way they do on the web.
     */
    Q_INVOKABLE qreal initialsSize(qreal pixels) const;

    /** {@link facePath} as a region, for cutting a picture to it. */
    static QPainterPath faceRegion(qreal pixels);

    /**
     * The square a picture fills before it is cut, in a `pixels` square.
     *
     * The web's `faceHalf`: the face's own reach, not the whole drawing. A
     * picture drawn across the view instead would be framed a size smaller than
     * the same picture on the web, with more of whatever was around the face.
     */
    static QRectF faceSquare(qreal pixels);

    /**
     * A name for the shape as it is drawn now, derived from the drawing itself.
     *
     * {@link AvatarCache} puts it in the name of every picture it cuts, so a
     * change to the outline — a margin, a radius, the flower turned — is a
     * change of file name, and a picture cut to an old shape is never laid inside
     * a new frame, where its side lobes would show the ground through.
     */
    static QString signature();

    /**
     * The light the web gives an identity, as a picture to lay over its face.
     *
     * One raised piece of glossy plastic with the sun low in the east, worked out
     * exactly as `IdentityAvatar` works it out: a faint swell toward the middle,
     * the shoulder turned away from the sun in soft shade, gloss and a hairline
     * on the edges facing it, each edge lit from its own direction, and a crease
     * where the face meets the frame. `lit` false keeps only the crease, which is
     * what the web draws under 26 pixels, where the rest would be mud.
     *
     * `pixels` square, transparent outside the face, and the same for every
     * picture, so it is worked out once per size and kept.
     */
    static QImage lighting(int pixels, bool lit);

    /**
     * The soft weight under the piece: the web's drop shadow, in no colour.
     *
     * An `pixels + 2 * reach` square with the figure's silhouette `offset` pixels
     * below its middle, blurred by `blur` (the CSS blur radius, a standard
     * deviation of half that) at 32 per cent black.
     */
    static QImage shadow(int pixels, int offset, qreal blur, int reach);

private:
    static QVector<QPointF> outline();
    static QVector<QPointF> inset(const QVector<QPointF> &corners, qreal distance);
};

} // namespace simorg::app
