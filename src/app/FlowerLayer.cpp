// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "FlowerLayer.h"

#include "FlowerShape.h"

#include <QPainter>
#include <QQuickWindow>

#include <algorithm>
#include <cmath>

namespace simorg::app {

FlowerLayer::FlowerLayer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setOpaquePainting(false);
}

void FlowerLayer::setKind(Kind kind)
{
    if (m_kind == kind)
        return;
    m_kind = kind;
    Q_EMIT kindChanged();
    Q_EMIT reachChanged();
    update();
}

void FlowerLayer::setAvatarSize(qreal size)
{
    if (qFuzzyCompare(m_avatarSize, size))
        return;
    m_avatarSize = size;
    Q_EMIT avatarSizeChanged();
    Q_EMIT reachChanged();
    update();
}

int FlowerLayer::shadowOffset(qreal size)
{
    // `drop-shadow(0 max(1, round(size × 0.035))px …)`, as IdentityAvatar writes it.
    return std::max(1, int(std::lround(size * 0.035)));
}

int FlowerLayer::shadowBlur(qreal size)
{
    return std::max(2, int(std::lround(size * 0.07)));
}

qreal FlowerLayer::reach() const
{
    if (m_kind != Shadow || m_avatarSize <= 0)
        return 0;
    // Three standard deviations of the blur past the silhouette, and the offset under it.
    return shadowOffset(m_avatarSize) + std::ceil(shadowBlur(m_avatarSize) * 1.5) + 1;
}

void FlowerLayer::paint(QPainter *painter)
{
    if (m_avatarSize <= 0)
        return;
    const qreal ratio = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    const int pixels = int(std::lround(m_avatarSize * ratio));

    QImage picture;
    if (m_kind == Lighting) {
        picture = FlowerShape::lighting(pixels, m_avatarSize >= kLitFrom);
    } else {
        picture = FlowerShape::shadow(pixels, int(std::lround(shadowOffset(m_avatarSize) * ratio)),
                                      shadowBlur(m_avatarSize) * ratio, int(std::lround(reach() * ratio)));
    }
    if (picture.isNull())
        return;
    // One device pixel of the picture to one of the screen, so nothing is resampled.
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(QRectF(0, 0, width(), height()), picture);
}

void FlowerLayer::itemChange(ItemChange change, const ItemChangeData &value)
{
    // Moved to a screen of another density: the picture is worked out again at that one.
    if (change == ItemDevicePixelRatioHasChanged)
        update();
    QQuickPaintedItem::itemChange(change, value);
}

} // namespace simorg::app
