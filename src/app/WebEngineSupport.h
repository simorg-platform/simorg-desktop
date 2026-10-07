// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
//
// What the browser engine behind an agent's Workbench and Brain needs from the
// computer it runs on, and a way to prove it has it.
#pragma once

#include <QString>

class QGuiApplication;

namespace simorg::app {

/**
 * Decides, before the web engine starts, whether Chromium may sandbox its
 * renderers on this computer, and turns the sandbox off where it cannot.
 *
 * Chromium's Linux sandbox is built from user namespaces. Where they are not to
 * be had — Ubuntu 23.10 and later, whose AppArmor gives an unprofiled program a
 * user namespace with no capabilities in it; a container whose seccomp profile
 * refuses one; a kernel with them switched off — or where the program runs as
 * root, which Chromium refuses to sandbox, every renderer exits on start and an
 * agent's surfaces stay blank, with nothing on screen to say why.
 *
 * So a child process tries what the sandbox does first — a user namespace, its
 * own id maps, then mount, pid and network namespaces inside it — and when that
 * fails the engine is started with `QTWEBENGINE_DISABLE_SANDBOX`, and the reason
 * is kept for the log. The pages still run in their own processes; what is lost
 * is the sandbox around them. A package that installs an AppArmor profile for
 * the renderer would keep it; an archive unpacked by a person cannot.
 *
 * Nothing happens on macOS and Windows, whose sandboxes need no permission, or
 * when `QTWEBENGINE_DISABLE_SANDBOX` is already set either way.
 *
 * Returns the sentence to log when the sandbox was turned off, empty otherwise.
 * Must run before `QtWebEngineQuick::initialize` and before any thread starts.
 */
QString prepareWebEngineSandbox();

/**
 * `simorg-desktop --check-web-engine [url]`: loads a page in the web engine the
 * way an agent's surface is loaded and says whether it drew.
 *
 * With no URL the page is built in, runs JavaScript and needs no network; with
 * one, it proves the network path too — TLS and its certificates. Exits 0 when
 * the page loaded (and, for the built-in page, its script ran), otherwise not,
 * with the reason on stderr. Used by the Linux release build to prove a bundle
 * renders before it is allowed out, and by a person whose surfaces stay blank.
 */
int checkWebEngine(QGuiApplication &app, const QString &url);

} // namespace simorg::app
