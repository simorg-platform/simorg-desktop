// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QJsonValue>
#include <QList>
#include <QString>
#include <QVariantList>

/**
 * This computer's graphics cards, as the machine service reports them,
 * in the words every screen
 * and the terminal use for them — the same words as the machine's page in the
 * Logos, so one card is never described two ways.
 */
namespace simorg::app::graphicscards {

/** One `MachineGpu`: its name, its memory in MiB (0 when not said), and whether that memory is the computer's. */
struct Card
{
    QString model;
    qint64 memoryMb = 0;
    bool sharedMemory = false;
};

/** The `gpus` member of `MachineComputer` read back; empty for null, for an absent one and for none. */
QList<Card> cardsOf(const QJsonValue &gpus);

/**
 * A card's memory: its own in whole gigabytes, the size it is sold as (Windows
 * reports a 24 GB card as 23.6); a shared one as how much of the computer's it
 * may use. Empty when the service could not say.
 */
QString memoryText(const Card &card);

/** `NVIDIA GeForce RTX 4090 · 24 GB`, `Apple M3 Pro · up to 28.1 GB, shared`; `, ` in a sentence. */
QString describe(const Card &card, const QString &separator = QStringLiteral(" · "));

/** The card an agent given the graphics card computes on: one with memory of its own first, then the most memory. */
const Card *mainCard(const QList<Card> &cards);

/** Each card as `{model, memory, text}` for QML, `memory` being memoryText and `text` describe. */
QVariantList toVariantList(const QList<Card> &cards);

} // namespace simorg::app::graphicscards
