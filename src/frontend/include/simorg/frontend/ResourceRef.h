// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QString>

namespace simorg {

/**
 * The kinds of thing the platform places on this computer.
 *
 * Deliberately the same three words the interface uses, because they are the
 * three the product has: an **agent** is what somebody made, a **virtual
 * machine** is the slice of this computer it was given, and a **container** is
 * what actually runs. Anything else — images, volumes, the engine itself — is
 * Docker's vocabulary and lives under Simorg CLI's `sim docker`.
 */
enum class ResourceKind {
    Agent,
    VirtualMachine,
    Container,
};

/** The canonical plural: `agents`, `virtual-machines`, `containers`. */
QString resourceKindName(ResourceKind kind);
/** The canonical singular, for a one-line message about a single thing. */
QString resourceKindSingular(ResourceKind kind);

/**
 * Resolves a kind somebody typed.
 *
 * Singular, plural and short forms all work — `agent`, `agents`, `ag`; `vm`,
 * `vms`, `virtual-machine`, `virtualmachine`, `virtual-machines`; `container`,
 * `containers`, `co`. That is the grammar `kubectl` taught a generation of
 * operators, and a tool that accepted only one of the three would be a tool
 * people mistype twice before every correct invocation.
 */
bool parseResourceKind(const QString &text, ResourceKind *kind);

/**
 * One `kind/name` selector, as `sim logs` and `sim list` take it.
 *
 * `agent/paprika`, `container/paprika`, `vm/Ax`. A bare word with no slash is
 * read as an **agent**, which is the thing somebody naming one thing almost
 * always means; every other kind has to say so. Nothing at all selects
 * everything, which is what `sim logs` on its own prints.
 *
 * Parsing lives here, in the core, rather than in the CLI: the same selector is
 * what a future command palette in the app would take, and a grammar
 * implemented twice is a grammar that disagrees with itself by the second
 * release.
 */
struct ResourceRef
{
    /** True when nothing was selected: every kind, everything in it. */
    bool everything = true;
    ResourceKind kind = ResourceKind::Agent;
    /** The codename, container name or id. Empty when {@link everything}. */
    QString name;
    /** Empty when it parsed; a sentence written for a person when it did not. */
    QString error;

    /** An empty or whitespace-only string parses as {@link everything}. */
    static ResourceRef parse(const QString &text);

    bool isValid() const { return error.isEmpty(); }
    /** `agent/paprika`, or `everything`. */
    QString toString() const;
};

} // namespace simorg
