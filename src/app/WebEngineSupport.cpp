// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// See WebEngineSupport.h.

#include "WebEngineSupport.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QUrl>
#include <QtGlobal>

#include <cstdio>

#if defined(Q_OS_LINUX)
#include <cerrno>
#include <fcntl.h>
#include <sched.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace simorg::app {

#if defined(Q_OS_LINUX)
namespace {

bool writeProcFile(const char *path, const std::string &text)
{
    const int fd = ::open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    const bool written = ::write(fd, text.data(), text.size()) == static_cast<ssize_t>(text.size());
    ::close(fd);
    return written;
}

/*
  What Chromium's zygote does before anything else, in a child that is thrown
  away: a new user namespace, this user mapped into it, then mount, pid and
  network namespaces inside it. Each exit code names the step that failed, for
  the log.

  The second unshare is the one that tells Ubuntu apart: its AppArmor lets the
  first succeed and then withholds every capability inside the namespace, so
  creating a mount namespace there is refused. A container's default seccomp
  profile refuses the first.
*/
int userNamespaceProbe()
{
    const std::string uidMap = "0 " + std::to_string(::getuid()) + " 1";
    const std::string gidMap = "0 " + std::to_string(::getgid()) + " 1";
    const pid_t child = ::fork();
    if (child < 0)
        return 10;
    if (child == 0) {
        if (::unshare(CLONE_NEWUSER) != 0)
            ::_exit(1);
        writeProcFile("/proc/self/setgroups", "deny");
        if (!writeProcFile("/proc/self/uid_map", uidMap) || !writeProcFile("/proc/self/gid_map", gidMap))
            ::_exit(2);
        if (::unshare(CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWNET) != 0)
            ::_exit(3);
        ::_exit(0);
    }
    int status = 0;
    while (::waitpid(child, &status, 0) < 0) {
        if (errno != EINTR)
            return 11;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 12;
}

} // namespace
#endif

QString prepareWebEngineSandbox()
{
#if defined(Q_OS_LINUX)
    if (qEnvironmentVariableIsSet("QTWEBENGINE_DISABLE_SANDBOX"))
        return {};
    QString reason;
    if (::geteuid() == 0) {
        reason = QStringLiteral("it runs as root, which Chromium does not sandbox");
    } else {
        switch (userNamespaceProbe()) {
        case 0:
            return {};
        case 1:
            reason = QStringLiteral("this system does not give it a user namespace");
            break;
        case 2:
            reason = QStringLiteral("it cannot map its user into a user namespace");
            break;
        case 3:
            reason = QStringLiteral("the user namespaces this system gives it carry no capabilities "
                                    "(AppArmor on Ubuntu 23.10 and later)");
            break;
        default:
            reason = QStringLiteral("the check for user namespaces could not run");
            break;
        }
    }
    qputenv("QTWEBENGINE_DISABLE_SANDBOX", "1");
    return QStringLiteral("Agent surfaces render without Chromium's sandbox, because %1.").arg(reason);
#else
    return {};
#endif
}

int checkWebEngine(QGuiApplication &app, const QString &url)
{
    /*
      A page that proves more than a load: it runs a script, and the script's
      answer is read back from the page, so a renderer that started and could
      not execute JavaScript — a missing V8 snapshot, a sandbox that killed it
      after the first paint — does not pass as a page that loaded.
    */
    static const QByteArray kBuiltIn =
        "data:text/html,<!doctype html><title>simorg-web-check</title>"
        "<script>document.title = 'simorg-web-ok ' + navigator.userAgent;</script>";

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("checkUrl"),
                                             url.isEmpty() ? QUrl(QString::fromLatin1(kBuiltIn)) : QUrl(url));
    engine.rootContext()->setContextProperty(QStringLiteral("checkScript"), url.isEmpty());

    int result = 5;
    QObject::connect(&engine, &QQmlApplicationEngine::quit, &app, [&] { QGuiApplication::quit(); });
    QObject::connect(&engine, &QQmlApplicationEngine::exit, &app, [&](int code) {
        result = code;
        QGuiApplication::quit();
    });

    engine.loadData(R"qml(
        import QtQuick
        import QtQuick.Window
        import QtWebEngine

        Window {
            width: 480; height: 320; visible: true
            WebEngineView {
                anchors.fill: parent
                url: checkUrl
                // The status enum lives on WebEngineView and, since Qt 6.2, on
                // WebEngineLoadingInfo too; either spelling is accepted.
                function succeeded(status) {
                    return status === WebEngineView.LoadSucceededStatus
                        || status === WebEngineLoadingInfo.LoadSucceededStatus
                }
                function failed(status) {
                    return status === WebEngineView.LoadFailedStatus
                        || status === WebEngineLoadingInfo.LoadFailedStatus
                }
                onLoadingChanged: (request) => {
                    if (succeeded(request.status)) {
                        if (!checkScript) {
                            console.info("web engine: loaded " + request.url)
                            Qt.exit(0)
                            return
                        }
                        runJavaScript("document.title", (title) => {
                            const ok = String(title).startsWith("simorg-web-ok")
                            console.info("web engine: " + (ok ? "script ran, " + title : "the script did not run: " + title))
                            Qt.exit(ok ? 0 : 3)
                        })
                    } else if (failed(request.status)) {
                        console.warn("web engine: could not load " + request.url + ": " + request.errorString)
                        Qt.exit(2)
                    }
                }
                onRenderProcessTerminated: (status, code) => {
                    console.warn("web engine: the renderer ended (" + status + ", " + code + ")")
                    Qt.exit(4)
                }
            }
        }
    )qml");
    if (engine.rootObjects().isEmpty()) {
        std::fputs("web engine: the check page did not load into QML\n", stderr);
        return 6;
    }

    // A renderer that never answers is the failure this exists to catch.
    QTimer::singleShot(45'000, &app, [&] {
        std::fputs("web engine: nothing within 45 seconds\n", stderr);
        result = 7;
        QGuiApplication::quit();
    });
    QGuiApplication::exec();
    return result;
}

} // namespace simorg::app
