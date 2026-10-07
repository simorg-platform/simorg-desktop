// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/MachineSetupModel.h"

#include "Support.h"
#include "simorg/appmodel/Slug.h"
#include "simorg/client/ServiceSession.h"

namespace simorg::app {

using client::ServiceReply;
using support::number;
using support::text;

MachineSetupModel::MachineSetupModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_topic(session->subscribe(QStringLiteral("machine.setup")))
{
    connect(m_topic, &client::TopicSubscription::received, this, &MachineSetupModel::apply);
    if (m_topic->hasValue())
        apply(m_topic->value());
}

void MachineSetupModel::apply(const QJsonObject &setup)
{
    if (setup == m_setup)
        return;
    const QJsonObject previous = m_setup;
    const bool wasFinished = isFinished();
    m_setup = setup;

    // The service's error stands until the next request replaces it with its own answer.
    const QString serviceError = support::problemMessage(setup.value(QStringLiteral("last_error")));
    if (!serviceError.isEmpty())
        m_lastError = serviceError;

    /*
      A sign-out ends a wizard as well, and takes the machine with it; a wizard that
      finished still has its machine named. Only the runtime answer finishes one —
      a jump straight to `done` from an earlier step is a handshake saying nothing
      is owed, not a setup somebody completed. The answer that closes a reopened
      wizard clears `reopened` in the same state, so the state before it is the one
      that says which wizard this was. Decided before anything is told, so the
      dashboard the finish brings up already knows whether to welcome anybody.
    */
    const bool finished = !wasFinished && isFinished() && !previous.isEmpty() && machineId() > 0;
    if (machineId() <= 0) {
        setWelcomeOwed(false);
    } else if (finished && text(previous, "step") == QLatin1String("runtime")
               && !previous.value(QStringLiteral("reopened")).toBool()) {
        setWelcomeOwed(true);
    }

    Q_EMIT stateChanged();
    if (previous.value(QStringLiteral("machine")) != setup.value(QStringLiteral("machine")))
        Q_EMIT machineChanged();
    if (finished)
        Q_EMIT completed();
}

void MachineSetupModel::setWelcomeOwed(bool owed)
{
    if (owed == m_welcomeOwed)
        return;
    m_welcomeOwed = owed;
    Q_EMIT welcomeOwedChanged();
}

void MachineSetupModel::acknowledgeWelcome()
{
    setWelcomeOwed(false);
}

QJsonObject MachineSetupModel::machine() const
{
    return m_setup.value(QStringLiteral("machine")).toObject();
}

MachineSetupModel::Step MachineSetupModel::step() const
{
    const QString name = text(m_setup, "step");
    if (name == QLatin1String("welcome"))
        return Welcome;
    if (name == QLatin1String("identity"))
        return Identity;
    if (name == QLatin1String("runtime"))
        return Runtime;
    return Done;
}

bool MachineSetupModel::isRequired() const
{
    return m_setup.value(QStringLiteral("required")).toBool();
}

bool MachineSetupModel::isListed() const
{
    return m_setup.value(QStringLiteral("listed")).toBool();
}

bool MachineSetupModel::isBusy() const
{
    return m_requests > 0 || m_setup.value(QStringLiteral("busy")).toBool();
}

bool MachineSetupModel::isUndecided() const
{
    return m_setup.value(QStringLiteral("undecided")).toBool();
}

int MachineSetupModel::machineId() const
{
    return int(number(machine(), "machine_id"));
}

QString MachineSetupModel::title() const
{
    return text(machine(), "title");
}

QString MachineSetupModel::slug() const
{
    return text(machine(), "slug");
}

QString MachineSetupModel::description() const
{
    return text(machine(), "description");
}

QString MachineSetupModel::readme() const
{
    return text(machine(), "readme");
}

QString MachineSetupModel::deviceName() const
{
    return text(machine(), "device_name");
}

QString MachineSetupModel::runtimeState() const
{
    return text(m_setup, "runtime_state");
}

QString MachineSetupModel::suggestSlug(const QString &title) const
{
    return slug::fromText(title);
}

QString MachineSetupModel::slugProblem(const QString &value) const
{
    return slug::problem(value);
}

void MachineSetupModel::follow(ServiceReply *reply, bool nested)
{
    ++m_requests;
    m_lastError.clear();
    Q_EMIT stateChanged();
    connect(reply, &ServiceReply::finished, this, [this, reply, nested] {
        --m_requests;
        if (reply->isError()) {
            m_lastError = reply->problem().message();
            Q_EMIT stateChanged();
            return;
        }
        // The answer is the state the topic brings as well; applying it now means the next screen does not wait.
        const QJsonObject body = reply->object();
        apply(nested ? body.value(QStringLiteral("setup")).toObject() : body);
        Q_EMIT stateChanged();
    });
}

void MachineSetupModel::reopen()
{
    follow(m_session->post(QStringLiteral("/v1/machine/setup/reopen")));
}

void MachineSetupModel::completeWelcome()
{
    follow(m_session->post(QStringLiteral("/v1/machine/setup/welcome")));
}

void MachineSetupModel::saveIdentity(const QString &title, const QString &handle, const QString &description,
                                     const QString &readme)
{
    // Refused here first so the message beside the field is immediate; the service refuses it again, and is the
    // only one that knows whether the handle is taken.
    const QString problem = slug::problem(handle);
    if (!problem.isEmpty()) {
        m_lastError = problem;
        Q_EMIT stateChanged();
        return;
    }
    const auto optional = [](const QString &value) {
        return value.trimmed().isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(value);
    };
    follow(m_session->put(QStringLiteral("/v1/machine/setup/identity"),
                          {{QStringLiteral("title"), title},
                           {QStringLiteral("slug"), handle},
                           {QStringLiteral("description"), optional(description)},
                           {QStringLiteral("readme"), optional(readme)}}));
}

void MachineSetupModel::reportRuntime(RuntimeState, const QString &, const QString &, const QString &)
{
    // The window has just shown a finished check, so that one is reported rather than a second run.
    follow(m_session->post(QStringLiteral("/v1/machine/setup/runtime"), {{QStringLiteral("recheck"), false}}), true);
}

} // namespace simorg::app
