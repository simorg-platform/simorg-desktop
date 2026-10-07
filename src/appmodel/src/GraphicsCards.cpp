// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/GraphicsCards.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonObject>
#include <QVariantMap>

#include <cmath>

namespace simorg::app::graphicscards {

QList<Card> cardsOf(const QJsonValue &gpus)
{
    QList<Card> cards;
    const QJsonArray list = gpus.toArray();
    for (const QJsonValue &entry : list) {
        const QJsonObject object = entry.toObject();
        const QString model = object.value(QStringLiteral("model")).toString().trimmed();
        if (model.isEmpty())
            continue;
        const double memory = object.value(QStringLiteral("memory_mb")).toDouble();
        cards.append(Card{model, memory > 0 ? qint64(memory) : 0,
                          object.value(QStringLiteral("shared_memory")).toBool()});
    }
    return cards;
}

QString memoryText(const Card &card)
{
    if (!card.sharedMemory) {
        if (card.memoryMb <= 0)
            return {};
        return card.memoryMb >= 1024
                   ? QCoreApplication::translate("GraphicsCards", "%1 GB").arg(std::llround(double(card.memoryMb) / 1024.0))
                   : QCoreApplication::translate("GraphicsCards", "%1 MB").arg(card.memoryMb);
    }
    if (card.memoryMb <= 0)
        return QCoreApplication::translate("GraphicsCards", "Shares the computer's memory");
    const double gb = std::round(double(card.memoryMb) / 1024.0 * 10.0) / 10.0;
    return QCoreApplication::translate("GraphicsCards", "Up to %1 GB, shared")
        .arg(gb, 0, 'f', gb == std::floor(gb) ? 0 : 1);
}

QString describe(const Card &card, const QString &separator)
{
    const QString memory = memoryText(card);
    if (memory.isEmpty())
        return card.model;
    // Lower case after the separator: it continues the line rather than starting one.
    return card.model + separator + (card.sharedMemory ? memory.left(1).toLower() + memory.mid(1) : memory);
}

const Card *mainCard(const QList<Card> &cards)
{
    // A card with memory of its own before one sharing the computer's: a laptop's integrated graphics may be
    // allowed more of the computer's memory than its own card has, and is still not the card.
    const Card *best = nullptr;
    for (const Card &card : cards) {
        if (best == nullptr || (!card.sharedMemory && best->sharedMemory)
            || (card.sharedMemory == best->sharedMemory && card.memoryMb > best->memoryMb))
            best = &card;
    }
    return best;
}

QVariantList toVariantList(const QList<Card> &cards)
{
    QVariantList list;
    for (const Card &card : cards) {
        list.append(QVariantMap{
            {QStringLiteral("model"), card.model},
            {QStringLiteral("memory"), memoryText(card)},
            {QStringLiteral("text"), describe(card)},
        });
    }
    return list;
}

} // namespace simorg::app::graphicscards
