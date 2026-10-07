// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "FlowerShape.h"

#include <QCryptographicHash>
#include <QHash>
#include <QLineF>
#include <QMutex>
#include <QMutexLocker>
#include <QPainter>
#include <QPainterPathStroker>
#include <QRectF>

#include <algorithm>
#include <cmath>
#include <vector>

namespace simorg::app {

namespace {

/*
  The Logos's own units. A cell is 34 across, a node
  is seven of them, and everything else on this page is measured in the same
  units so the figure keeps its proportions at any size.
*/

/** Distance between the centres of two neighbouring cells. */
constexpr qreal kCell = 34.0;

/** Centre of a cell to one of its six corners. */
const qreal kCircumradius = kCell / std::sqrt(3.0);

/** Half the figure's larger side: the top and bottom lobes' flat edges, the larger of the two reaches. */
const qreal kHalfExtent = std::max(kCell + kCell / 2.0, kCell * std::sqrt(3.0) / 2.0 + kCircumradius);

/** Room around the outline for the frame's own line, and nothing more. */
constexpr qreal kViewPadding = 2.0;

/**
 * How far inside the frame the picture keeps its edge: the web's `FLOWER_MARGIN`.
 *
 * It was 4 here for a while, a unit short of the web's, which is enough for the
 * same account to wear a visibly thicker ring in one app than in the other.
 */
constexpr qreal kMargin = 5.0;

/** The picture's corners: a little rounder than the sheet's cells, so the outline reads as soft. */
constexpr qreal kFaceConvex = 6.0;
constexpr qreal kFaceConcave = 7.0;

/** The frame's corners, concentric with the picture's at the margin between them. */
constexpr qreal kFrameConvex = kFaceConvex + kMargin;
const qreal kFrameConcave = std::max(kFaceConcave - kMargin, 2.0);

qreal length(const QPointF &point)
{
    return std::hypot(point.x(), point.y());
}

QPointF unit(const QPointF &point)
{
    const qreal size = length(point);
    return size > 0 ? point / size : QPointF{};
}

/** Twice the signed area; positive when the corners run clockwise on screen, where y grows downward. */
qreal signedArea2(const QVector<QPointF> &points)
{
    qreal sum = 0;
    for (int i = 0; i < points.size(); ++i) {
        const QPointF &a = points[i];
        const QPointF &b = points[(i + 1) % points.size()];
        sum += a.x() * b.y() - b.x() * a.y();
    }
    return sum;
}

/** Every edge's outward normal, whichever way the corners run. */
QVector<QPointF> outwardNormals(const QVector<QPointF> &points)
{
    const qreal outward = signedArea2(points) > 0 ? 1.0 : -1.0;
    QVector<QPointF> normals;
    normals.reserve(points.size());
    for (int i = 0; i < points.size(); ++i) {
        const QPointF edge = points[(i + 1) % points.size()] - points[i];
        const qreal size = length(edge);
        normals.append(QPointF(outward * edge.y() / size, -outward * edge.x() / size));
    }
    return normals;
}

/** One corner turned into the arc that replaces it. */
struct Turn
{
    QPointF start;
    QPointF end;
    QPointF centre;
    qreal radius = 0;
    /** The arc bends clockwise as it is drawn, with y downward. */
    bool clockwise = false;
};

/**
 * Each corner of `points` as an arc tangent to both of its edges.
 *
 * The lobes' tips and the notches between them are rounded by different amounts
 * — a notch is a corner turning *into* the shape, and rounding it as hard as a
 * tip would flatten the waist between two lobes. No arc reaches past the middle
 * of either edge it is tangent to, so two of them cannot overlap.
 */
QVector<Turn> turns(const QVector<QPointF> &points, qreal convexRadius, qreal concaveRadius)
{
    const qreal winding = signedArea2(points) > 0 ? 1.0 : -1.0;
    QVector<Turn> arcs;
    arcs.reserve(points.size());

    for (int i = 0; i < points.size(); ++i) {
        const QPointF corner = points[i];
        const QPointF previous = points[(i - 1 + points.size()) % points.size()];
        const QPointF next = points[(i + 1) % points.size()];
        const QPointF back = previous - corner;
        const QPointF ahead = next - corner;
        const qreal backLength = length(back);
        const qreal aheadLength = length(ahead);

        // Which way the outline turns here, against the way it runs overall.
        const qreal turn = (corner.x() - previous.x()) * (next.y() - corner.y())
                           - (corner.y() - previous.y()) * (next.x() - corner.x());
        const bool convex = (turn > 0 ? 1.0 : -1.0) == winding;
        const qreal radius = convex ? convexRadius : concaveRadius;

        const qreal cosine = (back.x() * ahead.x() + back.y() * ahead.y()) / (backLength * aheadLength);
        const qreal halfAngle = std::acos(std::clamp(cosine, -1.0, 1.0)) / 2.0;
        const qreal reach = std::min({radius / std::tan(halfAngle), backLength / 2, aheadLength / 2});

        Turn arc;
        arc.radius = reach * std::tan(halfAngle);
        arc.start = corner + unit(back) * reach;
        arc.end = corner + unit(ahead) * reach;
        arc.centre = corner + unit(unit(back) + unit(ahead)) * (arc.radius / std::sin(halfAngle));
        arc.clockwise = turn > 0;
        arcs.append(arc);
    }
    return arcs;
}

/** Where the figure is drawn: `pixels` square, the outline centred in it. */
struct Fitting
{
    qreal scale = 1;
    qreal offset = 0;

    QPointF operator()(const QPointF &point) const
    {
        return QPointF(offset + point.x() * scale, offset + point.y() * scale);
    }
};

Fitting fitting(qreal pixels)
{
    const qreal half = kHalfExtent + kViewPadding;
    return Fitting{pixels / (half * 2), pixels / 2};
}

QString svgPath(const QVector<QPointF> &points, qreal convexRadius, qreal concaveRadius, qreal pixels)
{
    const Fitting fit = fitting(pixels);
    const QVector<Turn> arcs = turns(points, convexRadius, concaveRadius);
    QString path;
    for (int i = 0; i < arcs.size(); ++i) {
        const QPointF start = fit(arcs[i].start);
        const QPointF end = fit(arcs[i].end);
        const qreal radius = arcs[i].radius * fit.scale;
        path += QStringLiteral("%1%2 %3 A%4 %4 0 0 %5 %6 %7 ")
                    .arg(i == 0 ? QStringLiteral("M") : QStringLiteral("L"))
                    .arg(start.x(), 0, 'f', 3)
                    .arg(start.y(), 0, 'f', 3)
                    .arg(radius, 0, 'f', 3)
                    // SVG's sweep flag is 1 for an arc drawn clockwise on screen.
                    .arg(arcs[i].clockwise ? 1 : 0)
                    .arg(end.x(), 0, 'f', 3)
                    .arg(end.y(), 0, 'f', 3);
    }
    return path + QStringLiteral("Z");
}

QPainterPath painterPath(const QVector<QPointF> &points, qreal convexRadius, qreal concaveRadius, qreal pixels)
{
    const Fitting fit = fitting(pixels);
    const QVector<Turn> arcs = turns(points, convexRadius, concaveRadius);
    QPainterPath path;

    for (int i = 0; i < arcs.size(); ++i) {
        const QPointF start = fit(arcs[i].start);
        const QPointF end = fit(arcs[i].end);
        const QPointF centre = fit(arcs[i].centre);
        const qreal radius = arcs[i].radius * fit.scale;

        if (i == 0)
            path.moveTo(start);
        else
            path.lineTo(start);

        /*
          Qt measures an arc's angles anticlockwise **on screen** from three
          o'clock, in a space whose y grows downward — so the y of a direction
          is negated on the way in, and an arc that bends clockwise on screen
          sweeps a negative number of degrees.
        */
        const auto degrees = [centre](const QPointF &point) {
            return std::atan2(-(point.y() - centre.y()), point.x() - centre.x()) * 180.0 / M_PI;
        };
        const qreal from = degrees(start);
        qreal sweep = degrees(end) - from;
        // The short way round, which every one of these corners is.
        while (sweep <= -180.0)
            sweep += 360.0;
        while (sweep > 180.0)
            sweep -= 360.0;

        path.arcTo(QRectF(centre.x() - radius, centre.y() - radius, radius * 2, radius * 2), from, sweep);
    }
    path.closeSubpath();
    return path;
}

} // namespace

FlowerShape::FlowerShape(QObject *parent)
    : QObject(parent)
{
}

qreal FlowerShape::viewSize()
{
    return (kHalfExtent + kViewPadding) * 2;
}

/**
 * The eighteen corners of the seven cells' outline.
 *
 * Each outer cell shows three of its edges: the one facing its own direction and
 * the ones 60° either side. Walking round, that is two corners on a lobe's tip
 * and then the notch it shares with the next lobe, six times over — twelve
 * corners turning out of the shape and six turning into it.
 *
 * The flower stands with one lobe straight above its middle and one straight
 * below, as on the Logos and everywhere an account is drawn, so the lobes face
 * 90° + 60°·k.
 * Qt's y runs downward, and the shape is the same either way up.
 */
QVector<QPointF> FlowerShape::outline()
{
    QVector<QPointF> corners;
    corners.reserve(18);
    for (int k = 0; k < 6; ++k) {
        const qreal facing = 90.0 + k * 60.0;
        const QPointF tile(kCell * std::cos(facing * M_PI / 180.0), kCell * std::sin(facing * M_PI / 180.0));
        for (const qreal offset : {-30.0, 30.0, 90.0}) {
            const qreal angle = (facing + offset) * M_PI / 180.0;
            corners.append(tile + QPointF(kCircumradius * std::cos(angle), kCircumradius * std::sin(angle)));
        }
    }
    return corners;
}

/**
 * The same polygon with every edge moved `distance` inward.
 *
 * Each corner lands where its two moved edges meet, so the margin is the same
 * all the way round — lobe tip and notch alike — which is what a uniform shrink
 * about the centre cannot give.
 */
QVector<QPointF> FlowerShape::inset(const QVector<QPointF> &corners, qreal distance)
{
    const QVector<QPointF> normals = outwardNormals(corners);
    QVector<QPointF> moved;
    moved.reserve(corners.size());
    for (int i = 0; i < corners.size(); ++i) {
        const QPointF before = normals[(i - 1 + normals.size()) % normals.size()];
        const QPointF after = normals[i];
        const qreal scale = distance / (1 + before.x() * after.x() + before.y() * after.y());
        moved.append(corners[i] - (before + after) * scale);
    }
    return moved;
}

QString FlowerShape::framePath(qreal pixels) const
{
    return svgPath(outline(), kFrameConvex, kFrameConcave, pixels);
}

QString FlowerShape::facePath(qreal pixels) const
{
    return svgPath(inset(outline(), kMargin), kFaceConvex, kFaceConcave, pixels);
}

QPainterPath FlowerShape::faceRegion(qreal pixels)
{
    return painterPath(inset(outline(), kMargin), kFaceConvex, kFaceConcave, pixels);
}

QRectF FlowerShape::faceSquare(qreal pixels)
{
    // The web's `faceHalf`: the furthest any corner of the face reaches along either axis.
    qreal half = 0;
    for (const QPointF &corner : inset(outline(), kMargin))
        half = std::max({half, std::abs(corner.x()), std::abs(corner.y())});
    const Fitting fit = fitting(pixels);
    return QRectF(fit.offset - half * fit.scale, fit.offset - half * fit.scale, half * fit.scale * 2,
                  half * fit.scale * 2);
}

qreal FlowerShape::initialsSize(qreal pixels) const
{
    const Fitting fit = fitting(pixels);
    const qreal faceHalf = faceSquare(pixels).width() / 2 / fit.scale;
    return std::round(faceHalf * 0.68) * fit.scale;
}

QString FlowerShape::signature()
{
    const QRectF square = faceSquare(256);
    const QByteArray drawing = (FlowerShape().facePath(256) + QStringLiteral("|%1,%2,%3")
                                                                  .arg(square.x(), 0, 'f', 3)
                                                                  .arg(square.y(), 0, 'f', 3)
                                                                  .arg(square.width(), 0, 'f', 3))
                                   .toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(drawing, QCryptographicHash::Sha256).toHex().left(10));
}

// ---- The light and the weight ------------------------------------------------------------------

namespace {

/*
  The web's numbers, in the Logos's units.
*/

/** How far the rounded shoulder reaches in from the picture's edge. */
constexpr qreal kShoulder = 7.0;

/** How far in the light along the edge is worked out before it is blurred away. */
constexpr qreal kLightDepth = 11.5;

/** How far out the wedges reach, so the rounded notches bulging outward still fall inside one. */
constexpr qreal kWedgeReach = 8.0;

/**
 * One channel of coverage, 0 to 1, over a square canvas.
 *
 * Every layer of the light is one colour — black or white — at some opacity, so
 * it is worked out as an amount and coloured only when the layers are laid
 * together, which is also what makes the blur a sum of floats.
 */
struct Plane
{
    int size = 0;
    std::vector<float> value;

    float at(int x, int y) const { return value[std::size_t(y) * std::size_t(size) + std::size_t(x)]; }
};

/** Whatever `draw` paints in opaque black, read back as coverage. */
template<typename Draw>
Plane rasterised(int size, Draw draw)
{
    QImage canvas(size, size, QImage::Format_ARGB32_Premultiplied);
    canvas.fill(Qt::transparent);
    {
        QPainter painter(&canvas);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.setPen(Qt::NoPen);
        draw(painter);
    }
    Plane plane{size, std::vector<float>(std::size_t(size) * std::size_t(size))};
    for (int y = 0; y < size; ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(canvas.constScanLine(y));
        for (int x = 0; x < size; ++x)
            plane.value[std::size_t(y) * std::size_t(size) + std::size_t(x)] = qAlpha(line[x]) / 255.0f;
    }
    return plane;
}

/**
 * A Gaussian blur with standard deviation `sigma` pixels, as SVG's
 * `feGaussianBlur` draws it: across, then down, reaching three deviations.
 */
void blur(Plane &plane, qreal sigma)
{
    if (sigma < 0.25)
        return;
    const int radius = int(std::ceil(sigma * 3));
    std::vector<float> kernel(std::size_t(radius * 2 + 1));
    float total = 0;
    for (int i = -radius; i <= radius; ++i) {
        kernel[std::size_t(i + radius)] = float(std::exp(-(i * i) / (2 * sigma * sigma)));
        total += kernel[std::size_t(i + radius)];
    }
    for (float &weight : kernel)
        weight /= total;

    const int n = plane.size;
    std::vector<float> pass(plane.value.size());
    for (int y = 0; y < n; ++y) {
        for (int x = 0; x < n; ++x) {
            float sum = 0;
            for (int k = -radius; k <= radius; ++k) {
                const int from = x + k;
                if (from >= 0 && from < n)
                    sum += plane.value[std::size_t(y * n + from)] * kernel[std::size_t(k + radius)];
            }
            pass[std::size_t(y * n + x)] = sum;
        }
    }
    for (int y = 0; y < n; ++y) {
        for (int x = 0; x < n; ++x) {
            float sum = 0;
            for (int k = -radius; k <= radius; ++k) {
                const int from = y + k;
                if (from >= 0 && from < n)
                    sum += pass[std::size_t(from * n + x)] * kernel[std::size_t(k + radius)];
            }
            plane.value[std::size_t(y * n + x)] = sum;
        }
    }
}

/**
 * How the light falls on an edge facing `normalX` along the east–west axis: the
 * web's `lightOn`. The sun is low in the east, so an edge facing it catches a
 * glint and an edge facing away sits in shade lifted by a fainter sky light.
 */
struct Light
{
    qreal glint = 0;
    qreal shade = 0;
};

Light lightOn(qreal normalX)
{
    const qreal east = std::max(normalX, 0.0);
    const qreal west = std::max(-normalX, 0.0);
    return {0.8 * std::pow(east, 1.5) + 0.28 * west, 0.3 * west + 0.08 * (1 - std::abs(normalX))};
}

/** A premultiplied pixel laid over another. */
void over(float &r, float &g, float &b, float &a, float colour, float alpha)
{
    r = colour * alpha + r * (1 - alpha);
    g = colour * alpha + g * (1 - alpha);
    b = colour * alpha + b * (1 - alpha);
    a = alpha + a * (1 - alpha);
}

QMutex g_paintingsLock;
QHash<QString, QImage> g_paintings;

} // namespace

QImage FlowerShape::lighting(int pixels, bool lit)
{
    if (pixels <= 0)
        return {};
    const QString key = QStringLiteral("light/%1/%2").arg(pixels).arg(lit ? 1 : 0);
    {
        const QMutexLocker locker(&g_paintingsLock);
        if (const auto kept = g_paintings.constFind(key); kept != g_paintings.constEnd())
            return *kept;
    }

    const Fitting fit = fitting(pixels);
    const qreal unitPx = fit.scale;
    const QVector<QPointF> facePoints = inset(outline(), kMargin);
    // Room round the drawing for what the blurs spread, so nothing near an edge is lost to it.
    const int pad = int(std::ceil((kShoulder + 3 * 2.6 + kWedgeReach) * unitPx)) + 2;
    const int size = pixels + pad * 2;
    const auto place = [&](const QPointF &point) { return QPointF(pad + fit(point).x(), pad + fit(point).y()); };

    QPainterPath face = painterPath(facePoints, kFaceConvex, kFaceConcave, pixels);
    face.translate(pad, pad);
    const auto stroked = [&face](qreal width) {
        QPainterPathStroker stroker;
        stroker.setWidth(width);
        stroker.setJoinStyle(Qt::RoundJoin);
        return stroker.createStroke(face);
    };

    const Plane coverage = rasterised(size, [&](QPainter &painter) { painter.fillPath(face, Qt::black); });
    Plane crease = rasterised(size, [&](QPainter &painter) { painter.fillPath(stroked(1.1 * unitPx), Qt::black); });

    Plane shoulder, gloss, hairline, sun, shade;
    if (lit) {
        const QVector<QPointF> outer = inset(facePoints, -kWedgeReach);
        const QVector<QPointF> inner = inset(facePoints, kLightDepth);
        const QVector<QPointF> normals = outwardNormals(facePoints);
        const auto wedges = [&](bool glint) {
            return rasterised(size, [&](QPainter &painter) {
                for (int i = 0; i < facePoints.size(); ++i) {
                    const int j = (i + 1) % facePoints.size();
                    const Light light = lightOn(normals[i].x());
                    const qreal amount = glint ? light.glint : light.shade;
                    if (amount <= 0)
                        continue;
                    const QPolygonF wedge({place(outer[i]), place(outer[j]), place(inner[j]), place(inner[i])});
                    painter.setBrush(QColor(0, 0, 0, std::clamp(int(std::lround(amount * 255)), 0, 255)));
                    painter.drawPolygon(wedge);
                }
            });
        };
        sun = wedges(true);
        shade = wedges(false);
        blur(sun, 2.2 * unitPx);
        blur(shade, 2.2 * unitPx);

        shoulder = rasterised(size, [&](QPainter &painter) { painter.fillPath(stroked(kShoulder * 2 * unitPx), Qt::black); });
        gloss = rasterised(size, [&](QPainter &painter) { painter.fillPath(stroked(kShoulder * unitPx), Qt::black); });
        hairline = rasterised(size, [&](QPainter &painter) { painter.fillPath(stroked(2.4 * unitPx), Qt::black); });
        blur(shoulder, 2.6 * unitPx);
        blur(gloss, 2.6 * unitPx);
        blur(hairline, 0.45 * unitPx);
    }

    // The swell's ellipse: the face's box, centred a touch east of middle and above it.
    const QRectF box = face.boundingRect();
    const qreal swellX = box.left() + box.width() * 0.6;
    const qreal swellY = box.top() + box.height() * 0.42;
    const qreal swellRx = box.width() * 0.62;
    const qreal swellRy = box.height() * 0.62;

    QImage out(pixels, pixels, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    for (int y = 0; y < pixels; ++y) {
        auto *line = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < pixels; ++x) {
            const int cx = x + pad;
            const int cy = y + pad;
            const float inside = coverage.at(cx, cy);
            if (inside <= 0)
                continue;
            float r = 0, g = 0, b = 0, a = 0;
            if (lit) {
                const qreal dx = (cx + 0.5 - swellX) / swellRx;
                const qreal dy = (cy + 0.5 - swellY) / swellRy;
                over(r, g, b, a, 1.0f, float(0.1 * std::max(0.0, 1 - std::sqrt(dx * dx + dy * dy))));
                over(r, g, b, a, 0.0f, shoulder.at(cx, cy) * shade.at(cx, cy));
                over(r, g, b, a, 1.0f, 0.22f * gloss.at(cx, cy) * sun.at(cx, cy));
                over(r, g, b, a, 1.0f, hairline.at(cx, cy) * sun.at(cx, cy));
            }
            over(r, g, b, a, 0.0f, 0.28f * crease.at(cx, cy));
            // Clipped to the face, as the web clips the whole group.
            const auto channel = [inside](float v) { return std::clamp(int(std::lround(v * inside * 255)), 0, 255); };
            line[x] = qRgba(channel(r), channel(g), channel(b), channel(a));
        }
    }

    const QMutexLocker locker(&g_paintingsLock);
    g_paintings.insert(key, out);
    return out;
}

QImage FlowerShape::shadow(int pixels, int offset, qreal blurRadius, int reach)
{
    if (pixels <= 0)
        return {};
    const QString key = QStringLiteral("shadow/%1/%2/%3/%4").arg(pixels).arg(offset).arg(blurRadius).arg(reach);
    {
        const QMutexLocker locker(&g_paintingsLock);
        if (const auto kept = g_paintings.constFind(key); kept != g_paintings.constEnd())
            return *kept;
    }

    const int size = pixels + reach * 2;
    /*
      The silhouette the web's drop shadow is cast from: the face, opaque, and the
      frame's ring around it at about the weight its tinted ground has.
    */
    QPainterPath frame = painterPath(outline(), kFrameConvex, kFrameConcave, pixels);
    QPainterPath face = faceRegion(pixels);
    frame.translate(reach, reach + offset);
    face.translate(reach, reach + offset);
    Plane silhouette = rasterised(size, [&](QPainter &painter) {
        painter.fillPath(frame, QColor(0, 0, 0, 115));
        painter.fillPath(face, Qt::black);
    });
    // CSS's blur radius is twice the standard deviation.
    blur(silhouette, blurRadius / 2);

    QImage out(size, size, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < size; ++y) {
        auto *line = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < size; ++x)
            line[x] = qRgba(0, 0, 0, std::clamp(int(std::lround(0.32 * silhouette.at(x, y) * 255)), 0, 255));
    }

    const QMutexLocker locker(&g_paintingsLock);
    g_paintings.insert(key, out);
    return out;
}

} // namespace simorg::app
