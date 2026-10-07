// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/frontend/ResourceRef.h"

#include <QCoreApplication>

namespace simorg {
namespace {

/**
 * Every spelling of every kind, in one table.
 *
 * A table rather than a chain of comparisons so that adding a kind is one row
 * and so that the help text and the parser cannot drift apart — the CLI prints
 * the canonical names from {@link resourceKindName}, and everything else here
 * is an alias nobody has to be told about.
 */
struct Alias
{
    const char *word;
    ResourceKind kind;
};

constexpr Alias kAliases[]{
    {"agent", ResourceKind::Agent},
    {"agents", ResourceKind::Agent},
    {"ag", ResourceKind::Agent},
    {"virtual-machine", ResourceKind::VirtualMachine},
    {"virtual-machines", ResourceKind::VirtualMachine},
    {"virtualmachine", ResourceKind::VirtualMachine},
    {"virtualmachines", ResourceKind::VirtualMachine},
    {"vm", ResourceKind::VirtualMachine},
    {"vms", ResourceKind::VirtualMachine},
    {"container", ResourceKind::Container},
    {"containers", ResourceKind::Container},
    {"co", ResourceKind::Container},
    {"ctr", ResourceKind::Container},
};

} // namespace

QString resourceKindName(ResourceKind kind)
{
    switch (kind) {
    case ResourceKind::Agent:
        return QStringLiteral("agents");
    case ResourceKind::VirtualMachine:
        return QStringLiteral("virtual-machines");
    case ResourceKind::Container:
        return QStringLiteral("containers");
    }
    return {};
}

QString resourceKindSingular(ResourceKind kind)
{
    switch (kind) {
    case ResourceKind::Agent:
        return QStringLiteral("agent");
    case ResourceKind::VirtualMachine:
        return QStringLiteral("virtual machine");
    case ResourceKind::Container:
        return QStringLiteral("container");
    }
    return {};
}

bool parseResourceKind(const QString &text, ResourceKind *kind)
{
    const QString needle = text.trimmed().toLower();
    if (needle.isEmpty())
        return false;

    for (const Alias &alias : kAliases) {
        if (needle == QLatin1String(alias.word)) {
            if (kind)
                *kind = alias.kind;
            return true;
        }
    }
    return false;
}

ResourceRef ResourceRef::parse(const QString &text)
{
    ResourceRef ref;

    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty())
        return ref; // everything

    ref.everything = false;

    const int slash = trimmed.indexOf(QLatin1Char('/'));
    if (slash < 0) {
        /*
          A bare word is an agent.

          The alternative — refusing anything without a kind — would be correct
          and unhelpful: somebody typing one name means the thing they named,
          and on this computer that is an agent far more often than it is
          anything else. Naming a container or a slice takes the prefix, which
          is one word of typing against a guess nobody can predict.
        */
        ref.kind = ResourceKind::Agent;
        ref.name = trimmed;
        return ref;
    }

    const QString kindText = trimmed.left(slash);
    ref.name = trimmed.mid(slash + 1).trimmed();

    if (!parseResourceKind(kindText, &ref.kind)) {
        ref.error = QCoreApplication::translate(
                        "ResourceRef", "'%1' is not something Simorg has. Use agent/, vm/ or container/.")
                        .arg(kindText);
        return ref;
    }

    if (ref.name.isEmpty()) {
        ref.error = QCoreApplication::translate("ResourceRef", "'%1' names no %2.")
                        .arg(trimmed, resourceKindSingular(ref.kind));
    }

    return ref;
}

QString ResourceRef::toString() const
{
    if (everything)
        return QStringLiteral("everything");

    switch (kind) {
    case ResourceKind::Agent:
        return QStringLiteral("agent/%1").arg(name);
    case ResourceKind::VirtualMachine:
        return QStringLiteral("vm/%1").arg(name);
    case ResourceKind::Container:
        return QStringLiteral("container/%1").arg(name);
    }
    return name;
}

} // namespace simorg
