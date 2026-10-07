// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QQuickPaintedItem>

namespace simorg::app {

/**
 * The light on an identity's face, or the weight under it, as QML draws them.
 *
 * The web lights every avatar as one raised piece of glossy plastic and gives it
 * a soft shadow, and both are made of blurs
 * and masks. Qt Quick has no blur this app can use everywhere — `MultiEffect`
 * is a shader, and shaders are dead on the software backend the interface
 * tests draw with — so the two are painted here, from {@link FlowerShape}'s
 * pictures, which are worked out once per size in device pixels and kept.
 *
 * `Lighting` is the size of the avatar and goes over the picture or the
 * initials. `Shadow` goes under everything and reaches {@link reach} points past
 * the avatar's square on every side, which is where the QML puts it.
 */
class FlowerLayer : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(Kind kind READ kind WRITE setKind NOTIFY kindChanged)
    /** The avatar's size in points: what the shadow's offset and blur, and whether it is lit, are worked out from. */
    Q_PROPERTY(qreal avatarSize READ avatarSize WRITE setAvatarSize NOTIFY avatarSizeChanged)
    /** How far the shadow reaches past the avatar's square, in points; nothing for the lighting. */
    Q_PROPERTY(qreal reach READ reach NOTIFY reachChanged)

public:
    enum Kind { Lighting, Shadow };
    Q_ENUM(Kind)

    explicit FlowerLayer(QQuickItem *parent = nullptr);

    Kind kind() const { return m_kind; }
    void setKind(Kind kind);
    qreal avatarSize() const { return m_avatarSize; }
    void setAvatarSize(qreal size);
    qreal reach() const;

    /** The web's shadow for an avatar `size` CSS pixels across: how far down, and how soft. */
    static int shadowOffset(qreal size);
    static int shadowBlur(qreal size);

    /** Under this size the web draws the face flat, with its crease and nothing else. */
    static constexpr qreal kLitFrom = 26.0;

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void kindChanged();
    void avatarSizeChanged();
    void reachChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    Kind m_kind = Lighting;
    qreal m_avatarSize = 0;
};

} // namespace simorg::app
