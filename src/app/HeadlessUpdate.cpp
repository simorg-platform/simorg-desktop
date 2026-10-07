// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "HeadlessUpdate.h"

#include "simorg/appmodel/DesktopUpdateModel.h"
#include "simorg/client/ServiceClient.h"
#include "simorg/frontend/BuildInfo.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSysInfo>
#include <QTimer>

#include <cstdio>
#include <memory>

namespace simorg::app {

namespace {

using client::ServiceClient;
using client::ServiceReply;
namespace desktopupdate = app::desktopupdate;

constexpr int ExitOk = 0;
constexpr int ExitError = 1;
constexpr int ExitService = 5;

QString text(const QJsonObject &object, const char *key)
{
    return object.value(QLatin1String(key)).toString();
}

/** One JSON document on standard output, the whole of what this mode says. */
void answer(const QJsonObject &document)
{
    std::fputs(QJsonDocument(document).toJson(QJsonDocument::Compact).constData(), stdout);
    std::fputc('\n', stdout);
    std::fflush(stdout);
}

void refuse(const QString &sentence, const QString &code)
{
    answer({{QStringLiteral("ok"), false}, {QStringLiteral("error"), sentence}, {QStringLiteral("code"), code}});
}

QByteArray clientName()
{
#if defined(Q_OS_MACOS)
    const QString os = QStringLiteral("macos");
#elif defined(Q_OS_WIN)
    const QString os = QStringLiteral("windows");
#else
    const QString os = QStringLiteral("linux");
#endif
    QString arch = QSysInfo::currentCpuArchitecture();
    if (arch == QLatin1String("x86_64"))
        arch = QStringLiteral("x64");
    return QStringLiteral("simorg-desktop/%1 (%2; %3)").arg(QStringLiteral(SIMORG_VERSION), os, arch).toUtf8();
}

/** One update, from opening the service to the hand-over, as UpdateCommand ran it in the `simorg` command. */
class HeadlessUpdate : public QObject
{
public:
    explicit HeadlessUpdate(QString environment) : m_environment(std::move(environment)) {}

    void run()
    {
        ServiceClient::Options options;
        options.environment = m_environment;
        options.clientName = clientName();
        // The service runs this; one that has gone is not started again for it.
        options.startIfAbsent = false;
        m_service = new ServiceClient(options, this);
        connect(m_service, &ServiceClient::opened, this, [this] { readPlatform(); });
        connect(m_service, &ServiceClient::unavailable, this,
                [this](ServiceClient::Unavailable, const QString &detail) {
                    refuse(QStringLiteral("the Simorg machine service could not be reached%1")
                               .arg(detail.isEmpty() ? QString() : QStringLiteral(": ") + detail),
                           QStringLiteral("SERVICE_UNREACHABLE"));
                    done(ExitService);
                });
        m_service->open();
    }

private:
    void done(int exitCode) { QCoreApplication::exit(exitCode); }

    void failed(const client::ServiceProblem &problem)
    {
        refuse(problem.message(), problem.code.isEmpty() ? QStringLiteral("UPDATE_FAILED") : problem.code);
        done(problem.status == 0 ? ExitService : ExitError);
    }

    void readPlatform()
    {
        ServiceReply *config = m_service->get(QStringLiteral("/v1/config"));
        connect(config, &ServiceReply::finished, this, [this, config] {
            if (config->isError())
                return failed(config->problem());
            start(config->object()
                      .value(QStringLiteral("endpoints"))
                      .toObject()
                      .value(QStringLiteral("api_endpoint"))
                      .toString());
        });
    }

    void start(const QString &api)
    {
        app::DesktopUpdateModel::Options options = app::DesktopUpdateModel::defaults();
        options.archiveBuild = SIMORG_ARCHIVE_BUILD != 0;
        options.platformApi = api;
        options.checkOnItsOwn = false;
        // Registered as the program the service runs, which is never the open app: it downloads nothing
        // ahead and applies nothing it did not download itself.
        options.client = QStringLiteral("cli");
        options.announceOpen = false;
        options.prepareAhead = false;
        options.applyPreparedAtStart = false;
        // Nothing was open, so nothing is reopened; where a running file can be replaced, this waits.
        options.reopen = false;
        options.detached = false;
        options.serviceRequest = [this](const QByteArray &method, const QString &path, const QJsonObject &body) {
            return m_service->request(method, path, QJsonDocument(body));
        };
        m_desktop = new app::DesktopUpdateModel(nullptr, nullptr, options, this);
        connect(m_desktop, &app::DesktopUpdateModel::handedOver, this, [this](bool succeeded) {
            answer(m_desktop->row());
            done(succeeded ? ExitOk : ExitError);
        });
        // Windows: the move happens once this process has exited.
        connect(m_desktop, &app::DesktopUpdateModel::exitRequested, this, [this] {
            answer(m_desktop->row());
            done(ExitOk);
        });
        connect(
            m_desktop, &app::DesktopUpdateModel::registered, this,
            [this](bool supported) {
                if (!supported) {
                    // A service before API 1.3: the copy looks for its release itself, as it always did.
                    follow();
                    return m_desktop->check();
                }
                // The service reads the release now, so the update is the newest one there is.
                ServiceReply *checked = m_service->post(QStringLiteral("/v1/updates/check"));
                connect(checked, &ServiceReply::finished, this, [this, checked] {
                    if (checked->isError())
                        return failed(checked->problem());
                    QJsonObject item;
                    for (const QJsonValue &value : checked->object().value(QStringLiteral("items")).toArray()) {
                        if (text(value.toObject(), "item") == QLatin1String("desktop"))
                            item = value.toObject();
                    }
                    if (item.isEmpty()) {
                        refuse(QStringLiteral("the Simorg machine service did not list Simorg Desktop, so there is "
                                              "nothing to update"),
                               QStringLiteral("UPDATE_NOT_AVAILABLE"));
                        return done(ExitError);
                    }
                    follow();
                    m_desktop->applyServiceItem(item);
                });
            },
            Qt::SingleShotConnection);
        m_desktop->registerInstallation();
    }

    /** Starts the update once the check has answered, and ends on a failure before the hand-over. */
    void follow()
    {
        const auto started = std::make_shared<bool>(false);
        const auto handing = std::make_shared<bool>(false);
        connect(m_desktop, &app::DesktopUpdateModel::changed, this, [this, started, handing] {
            const QJsonObject row = m_desktop->row();
            if (*started) {
                const QJsonObject operation = row.value(QStringLiteral("operation")).toObject();
                if (text(operation, "phase") == QLatin1String("handing_over"))
                    *handing = true;
                // A failure before the hand-over: the download, its checksum or the unpacking. One after it is the
                // hand-over's to say.
                if (!*handing && text(operation, "outcome") == QLatin1String("failed")) {
                    answer(row);
                    done(ExitError);
                }
                return;
            }
            if (!m_desktop->checked())
                return;
            *started = true;
            if (text(row, "available").isEmpty()) {
                answer(row);
                return done(text(row, "unavailable_reason").isEmpty() ? ExitOk : ExitError);
            }
            if (!row.value(QStringLiteral("can_update")).toBool()) {
                refuse(text(row, "unavailable_reason"), QStringLiteral("UPDATE_UNSUPPORTED"));
                return done(ExitError);
            }
            if (desktopupdate::desktopRunning(desktopupdate::thisSystem(), m_desktop->install())) {
                refuse(QStringLiteral("Simorg Desktop from this folder is open, and replacing a running app's files "
                                      "would break it, so it is updated from Settings, Updates in the app"),
                       QStringLiteral("DESKTOP_OPEN"));
                return done(ExitError);
            }
            m_desktop->start();
        });
    }

    QString m_environment;
    ServiceClient *m_service = nullptr;
    app::DesktopUpdateModel *m_desktop = nullptr;
};

} // namespace

bool isHeadlessUpdate(const QStringList &arguments)
{
    return arguments.size() >= 2 && arguments.at(0) == QLatin1String("update") &&
           arguments.at(1) == QLatin1String("desktop");
}

int runHeadlessUpdate(int &argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral(SIMORG_ORGANIZATION));
    QCoreApplication::setOrganizationDomain(QStringLiteral(SIMORG_ORGANIZATION_DOMAIN));
    QCoreApplication::setApplicationName(QStringLiteral(SIMORG_ORGANIZATION));
    QCoreApplication::setApplicationVersion(QStringLiteral(SIMORG_VERSION));

    // The service names its environment as it runs this; `--env` as anywhere else in the app.
    QString environment = qEnvironmentVariable("SIMORG_ENV");
    const QStringList arguments = QCoreApplication::arguments();
    const qsizetype env = arguments.indexOf(QStringLiteral("--env"));
    if (env >= 0 && env + 1 < arguments.size())
        environment = arguments.at(env + 1);
    if (environment.isEmpty())
        environment = QStringLiteral("prod");

    HeadlessUpdate update(environment);
    // From the running loop: a service that is not there is said at once, inside open(), and an exit asked for
    // before the loop runs would be lost.
    QTimer::singleShot(0, &update, &HeadlessUpdate::run);
    return QCoreApplication::exec();
}

} // namespace simorg::app
