// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// `simorg-desktop` — the tray-resident desktop app.

#include "AppIdentity.h"
#include "DesktopApplication.h"
#include "HeadlessUpdate.h"

#include "simorg/frontend/BuildInfo.h"
#include "simorg/frontend/Logging.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QLoggingCategory>
#include <QQuickStyle>

#ifdef SIMORG_WITH_WEBENGINE
#include "SurfaceSchemeHandler.h"
#include "WebEngineSupport.h"

#include <QtWebEngineQuick>
#endif

int main(int argc, char *argv[])
{
    // The machine service updating a closed Simorg Desktop runs this program with these words: no window,
    // no browser engine, no tray, so before anything that would start one.
    QStringList words;
    for (int i = 1; i < argc; ++i)
        words << QString::fromLocal8Bit(argv[i]);
    if (simorg::app::isHeadlessUpdate(words))
        return simorg::app::runHeadlessUpdate(argc, argv);

#ifdef SIMORG_WITH_WEBENGINE
    // First of all, while this is the only thread: it forks a child to try what
    // Chromium's sandbox needs (WebEngineSupport.h).
    const QString sandboxNote = simorg::app::prepareWebEngineSandbox();

    /*
      Both of these happen **before the application object exists**, and both
      are Chromium's rules rather than Qt's.

      The scheme registry is read once when the web engine initialises, so a
      scheme added afterwards is accepted silently and then behaves like an
      unknown one — the surface simply never loads, with nothing said. And
      `QtWebEngineQuick::initialize` has to run before a `QGuiApplication` is
      constructed so it can set the shared OpenGL context the render process
      needs; called later it aborts.

      Nothing else in this file may move above them.
    */
    simorg::app::SurfaceSchemeHandler::registerScheme();
    QtWebEngineQuick::initialize();
#endif

    // QApplication rather than QGuiApplication: QSystemTrayIcon and its native
    // context menu live in Qt Widgets, and a tray icon is the whole point of a
    // background app.
    QApplication app(argc, argv);

    // Names, the Linux desktop entry and the window icon: see AppIdentity.h.
    simorg::app::applyApplicationIdentity(QStringLiteral(SIMORG_VERSION));

    // Closing the last window must not end the process: the app carries on
    // behind the tray icon until someone chooses Quit.
    QApplication::setQuitOnLastWindowClosed(false);

    // The interface is styled end to end, so pin the neutral style rather than
    // inherit macOS or Windows defaults that would fight it.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Simorg desktop"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption envOption(QStringLiteral("env"),
                                 QStringLiteral("Environment to talk to: dev or prod."),
                                 QStringLiteral("environment"));
    QCommandLineOption backgroundOption(QStringLiteral("background"),
                                        QStringLiteral("Start in the tray with no window shown."));
    QCommandLineOption verboseOption(QStringLiteral("verbose"),
                                     QStringLiteral("Log every request and state change."));
    parser.addOption(envOption);
    parser.addOption(backgroundOption);
    parser.addOption(verboseOption);
#ifdef SIMORG_WITH_WEBENGINE
    QCommandLineOption checkWebEngineOption(
        QStringLiteral("check-web-engine"),
        QStringLiteral("Load a page in the browser engine agent surfaces use, say whether it drew, and exit. "
                       "With no URL the page is built in; give one to prove the network path too."));
    parser.addOption(checkWebEngineOption);
    parser.addPositionalArgument(QStringLiteral("url"),
                                 QStringLiteral("With --check-web-engine, the page to load."),
                                 QStringLiteral("[url]"));
#endif
    parser.process(app);

    if (parser.isSet(verboseOption))
        QLoggingCategory::setFilterRules(QStringLiteral("simorg.*.debug=true"));

#ifdef SIMORG_WITH_WEBENGINE
    if (!sandboxNote.isEmpty())
        qCWarning(lcApp).noquote() << sandboxNote;
    if (parser.isSet(checkWebEngineOption))
        return simorg::app::checkWebEngine(app, parser.positionalArguments().value(0));
#endif

    simorg::app::DesktopApplication::Options options;
    options.environment = parser.value(envOption);
    options.background = parser.isSet(backgroundOption);

    simorg::app::DesktopApplication desktop(options);
    if (!desktop.start())
        return 0; // another instance took over; nothing went wrong

    return QApplication::exec();
}
