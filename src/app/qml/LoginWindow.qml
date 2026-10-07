// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Simorg

/**
 * The sign-in window.
 *
 * Split shell: the market diagram and the brand story on the left, the form on
 * the right — the same arrangement as the web console's AuthPageLayout, so
 * someone who signed in on the Simorg web console recognises this immediately. Below
 * 900px the brand half drops away and the form takes the window on its own.
 *
 * Sign-up and password recovery are deliberately not implemented here: both
 * open the web app in the system browser, which keeps email verification and
 * everything else that follows in one place.
 */
ApplicationWindow {
    id: win

    title: qsTr("Sign in to Simorg")
    width: 1060
    height: 760
    minimumWidth: 520
    /*
      Tall enough for the form, and no taller.

      The narrow layout drops the brand half and stacks the whole of the form in
      one column: mark, heading, two fields, the consent tick box with its note,
      the button, and the two lines under it. Measured, that column is about
      660px, and it is centred in a pane whose bottom edge carries the version
      line — so the window needs the column plus room for that, which is where
      730 comes from. The old 640 put the bottom of the card through the line
      beneath it. A minimum smaller than the content is not a minimum, it is a
      promise the window cannot keep.
    */
    minimumHeight: 730
    color: Theme.base

    /** Below this the brand panel is dropped and the form centres. */
    readonly property bool wide: width >= 900

    property string errorText: ""
    /** Draws {@link errorText} as a notice rather than as a refusal. */
    property bool errorIsNotice: false

    /**
     * Whether signing in is still under way, which outlasts the password check.
     *
     * The credentials being accepted is not the end of it: until the platform
     * has said whether this computer owes a setup wizard, nothing knows which
     * window this person is going to, and this one stays up rather than handing
     * over to a dashboard that would be replaced a moment later. So the button
     * keeps saying "Signing in…" for that last fraction of a second, because
     * that is what is still happening. See `DesktopApplication::surfaceWindow`.
     */
    readonly property bool working: Auth.busy || MachineSetup.undecided

    /**
     * Whether the window is asking for a code rather than a password.
     *
     * Read straight off the service rather than mirrored into a local flag, so
     * there is one answer to "which step is this" and the window cannot end up
     * showing a code field for a sign-in the service has already abandoned.
     */
    readonly property bool awaitingCode: Auth.awaitingSecondFactor
    /** Somebody without their phone, spending one of the ten printed codes. */
    property bool useRecoveryCode: false

    /**
     * Whether there is enough in the field to be worth sending.
     *
     * An authenticator code is exactly six digits, and five of them can only
     * come back refused — a refusal nobody could have avoided reads as the
     * window being broken. A recovery code has no one shape, so anything typed
     * counts and the platform judges it.
     */
    readonly property bool codeIsComplete: win.useRecoveryCode ? codeField.text.trim() !== "" : codeField.text.length === 6

    /**
     * The agreement's own title, as the website publishes it and the service
     * serves it, so the box names what the terms window opens on. A generic name
     * only until the service has answered.
     */
    readonly property string agreementTitle: {
        const documents = Legal.documents;
        for (let i = 0; i < documents.length; ++i) {
            if (documents[i].id === "terms" && documents[i].title)
                return documents[i].title;
        }
        return qsTr("Simorg agreement");
    }

    onVisibleChanged: {
        if (visible) {
            win.errorText = "";
            win.errorIsNotice = false;
            passwordField.text = "";
            codeField.text = "";
            win.useRecoveryCode = false;
            /*
              Ticked already for anybody who has accepted this edition on this
              computer. Not remembering would be asking somebody to agree to the
              same document every morning, which is how a consent box turns into
              a thing people click without reading.
            */
            consent.checked = Legal.accepted;
            /*
              The field this step shows. A window that comes back while a sign-in
              is waiting for its code is the code step, where the email field is
              hidden and cannot take the keyboard.
            */
            if (win.awaitingCode)
                win.focusCode();
            else
                emailField.forceInputFocus();
        }
    }

    /*
      The step can start from either end: the sign-in reply that says a code is
      needed, or the service's state saying the sign-in is waiting for one, which
      is what shows the field. They arrive in either order, and a hidden field
      takes no focus, so both ends ask.
    */
    onAwaitingCodeChanged: {
        if (win.awaitingCode)
            Qt.callLater(win.focusCode);
    }

    /**
     * The code field, ready to be typed into: somebody reading six digits off
     * their phone types them straight in, without clicking into the field first.
     *
     * Only once the field is showing. Called a moment later rather than at once
     * by both of its callers, so the field's own binding to the step has caught up.
     */
    function focusCode() {
        if (win.awaitingCode && codeField.visible)
            codeField.forceInputFocus();
    }

    /** Ticks the box, for the "I agree" button in the terms window. */
    function acceptTerms() {
        consent.checked = true;
        win.errorText = "";
        win.errorIsNotice = false;
    }

    // Closing is not quitting: the app carries on behind the tray icon, which
    // is the whole point of it being there. With no tray to fall back to,
    // closing has to mean what it says, and it is Quit Simorg: the window going
    // on its own would leave the app running with nothing on screen and nothing
    // to reach it by.
    onClosing: function (close) {
        close.accepted = false;
        if (App.trayAvailable)
            App.hideToTray();
        else
            App.quit();
    }

    function submit() {
        // Return in a text field, while the button is already saying it is
        // working, is not a second sign-in.
        if (win.working)
            return;

        // The second step has its own submission: the password is long gone by
        // then, and what this sends is a challenge and six digits.
        if (win.awaitingCode) {
            win.submitCode();
            return;
        }

        /*
          The button is disabled without the tick, so this only catches Return
          pressed in a text field. Saying why is the point: a form that does
          nothing when you hit Enter reads as broken rather than as refused.
        */
        if (!consent.checked) {
            win.errorIsNotice = true;
            win.errorText = qsTr("Please accept the %1 and its privacy notice first, because this computer can only be signed in under them.").arg(win.agreementTitle);
            shake.restart();
            return;
        }
        win.errorText = "";
        win.errorIsNotice = false;
        Auth.signIn(emailField.text, passwordField.text);
    }

    function submitCode() {
        if (win.working || !win.codeIsComplete)
            return;
        win.errorText = "";
        win.errorIsNotice = false;
        Auth.submitSecondFactor(codeField.text, win.useRecoveryCode);
    }

    /** Back to the password, discarding the challenge. */
    function backToPassword() {
        Auth.cancelSecondFactor();
    }

    /**
     * Swaps between an authenticator code and a recovery code.
     *
     * The field is cleared as well as relabelled. Half a typed six-digit code is
     * not half a recovery code, and leaving the characters behind would submit a
     * mixture of the two on the next Return.
     */
    function toggleRecoveryCode() {
        win.useRecoveryCode = !win.useRecoveryCode;
        codeField.text = "";
        win.errorText = "";
        win.errorIsNotice = false;
        codeField.forceInputFocus();
    }

    Connections {
        target: Auth

        function onSignInFailed(message) {
            win.errorIsNotice = false;
            win.errorText = message;
            shake.restart();
            passwordField.forceInputFocus();
        }

        function onSecondFactorRequired() {
            /*
              Not a failure, so nothing shakes and nothing is coloured red. The
              password was accepted; this is the next question.
            */
            win.errorText = "";
            win.errorIsNotice = false;
            win.useRecoveryCode = false;
            codeField.text = "";
            Qt.callLater(win.focusCode);
        }

        function onSecondFactorFailed(message) {
            win.errorIsNotice = false;
            win.errorText = message;
            /*
              The digits stay where they are. It is nearly always one character
              read wrong off a phone, and emptying the field makes somebody type
              the whole code again for a mistake they can see. The field takes
              focus with everything selected, so typing a fresh code over the
              top is still one action.
            */
            shake.restart();
            codeField.selectAllText();
        }

        function onSecondFactorEnded(reason) {
            /*
              The attempt is over: expired, locked out, or stepped back from.
              Only the first two have anything to say — pressing Back is not a
              thing to explain to the person who pressed it.
            */
            win.errorIsNotice = false;
            win.errorText = reason;
            win.useRecoveryCode = false;
            codeField.text = "";
            passwordField.text = "";
            if (reason !== "")
                shake.restart();
            passwordField.forceInputFocus();
        }

        function onSignInSucceeded() {
            win.errorText = "";
            win.errorIsNotice = false;
            /*
              Recorded here rather than when the box was ticked. Ticking a box
              and then closing the window is not an agreement; this is the
              moment there is one, and it is the moment worth writing down.

              A failed write is not a failed sign-in. The consequence is being
              asked again next time, which is a far better outcome than a
              read-only config directory locking somebody out of the app.
            */
            Legal.accept();
        }
    }

    background: Rectangle { color: Theme.base }

    AuroraBackground {
        anchors.fill: parent
    }

    // ---- Environment badge ------------------------------------------------
    // A build pointed at localhost should never be mistaken for the real thing.
    Rectangle {
        visible: App.devMode
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width: devLabel.implicitWidth + 20
        height: 24
        radius: 5
        color: Theme.alpha(Theme.amber, 0.12)
        border.width: 1
        border.color: Theme.alpha(Theme.amber, 0.45)
        z: 10

        Text {
            id: devLabel
            anchors.centerIn: parent
            text: qsTr("DEV · %1").arg(App.apiEndpoint.replace(/^https?:\/\//, ""))
            color: Theme.amber
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Brand half ---------------------------------------------------
        Item {
            id: brandPane
            visible: win.wide
            Layout.fillHeight: true
            Layout.preferredWidth: win.width * 0.52
            Layout.minimumWidth: 380

            // No rule down this edge. The two halves sit on one continuous
            // hexagon field, and a line drawn across it cuts the pattern rather
            // than separating anything — the diagram and the form are already
            // far enough apart to read as two things.

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 72, 460)
                spacing: Theme.spaceMd

                Reveal {
                    step: 0
                    Layout.fillWidth: true

                    Text {
                        width: parent.width
                        text: qsTr("SIMORG PLATFORM")
                        color: Theme.alpha(Theme.sky, 0.9)
                        font.pixelSize: Theme.fontEyebrow
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 2
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Reveal {
                    step: 1
                    Layout.fillWidth: true

                    GradientText {
                        width: parent.width
                        text: qsTr("Making AI-native\ntransformation possible")
                        pixelSize: 27
                        lineHeight: 1.18
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Reveal {
                    step: 2
                    Layout.fillWidth: true
                    // The diagram stands up now: a 340×620 grid, so the taller
                    // box is what lets it fill the half it is given.
                    Layout.preferredHeight: Math.min(width * 1.82, win.height * 0.56)

                    BrandDiagram {
                        anchors.fill: parent
                    }
                }

                Reveal {
                    step: 3
                    Layout.fillWidth: true

                    ColumnLayout {
                        width: parent.width
                        spacing: Theme.spaceSm

                        Repeater {
                            /*
                              What *this application* does, which is not what
                              the platform does. Somebody reading these is about
                              to sign a computer into Simorg, and the question
                              they have is what that computer is taking on — so
                              each line names something this window can show
                              them and the web console cannot.
                            */
                            model: [
                                qsTr("Your agents run here, each one in its own container"),
                                qsTr("You decide what each of them may reach on this computer")
                            ]

                            delegate: RowLayout {
                                id: highlight
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 7
                                    width: 6
                                    height: 6
                                    radius: 3
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Theme.cyan }
                                        GradientStop { position: 1.0; color: Theme.violet }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: highlight.modelData
                                    color: Theme.textBody
                                    font.pixelSize: Theme.fontSmall
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.5
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Form half ----------------------------------------------------
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: true

            ColumnLayout {
                id: formColumn
                anchors.centerIn: parent
                width: Math.min(parent.width - 56, 400)
                spacing: Theme.spaceMd

                // The card shakes rather than flashes when credentials are
                // refused: it draws the eye without adding another colour.
                transform: Translate { id: shakeOffset }

                SequentialAnimation {
                    id: shake
                    running: false
                    NumberAnimation { target: shakeOffset; property: "x"; to: Theme.motion ? -9 : 0; duration: 55 }
                    NumberAnimation { target: shakeOffset; property: "x"; to: Theme.motion ? 8 : 0; duration: 65 }
                    NumberAnimation { target: shakeOffset; property: "x"; to: Theme.motion ? -5 : 0; duration: 60 }
                    NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 70 }
                }

                Reveal {
                    step: win.wide ? 1 : 0
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    Item {
                        width: parent.width
                        implicitHeight: header.implicitHeight

                        ColumnLayout {
                            id: header
                            width: parent.width
                            spacing: 10

                            // Same reason as the dashboard toolbar: inside a
                            // layout an Image is sized from sourceSize, so plain
                            // width and height do nothing and the mark would
                            // render at 180px in the narrow layout.
                            Image {
                                visible: !win.wide
                                Layout.alignment: Qt.AlignHCenter
                                source: "qrc:/simorg/branding/simorg-logo.svg"
                                sourceSize: Qt.size(180, 180)
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 62
                                smooth: true
                                mipmap: true
                            }

                            GradientText {
                                objectName: "loginHeading"
                                Layout.fillWidth: true
                                text: win.awaitingCode ? qsTr("Two-step verification") : qsTr("Welcome back")
                                pixelSize: 30
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                text: win.awaitingCode ? qsTr("Your password was accepted. One more step to finish signing in.") : qsTr("Sign in to your Simorg control panel.")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSmall
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Reveal {
                    step: win.wide ? 2 : 1
                    Layout.fillWidth: true

                    GlassPanel {
                        width: parent.width
                        implicitHeight: form.implicitHeight + 44

                        ColumnLayout {
                            id: form
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 22
                            anchors.rightMargin: 22
                            anchors.topMargin: 22
                            spacing: 14

                            AlertBanner {
                                Layout.fillWidth: true
                                text: win.errorText
                                tone: win.errorIsNotice ? "info" : "error"
                            }

                            SimorgTextField {
                                id: emailField
                                objectName: "emailField"
                                visible: !win.awaitingCode
                                Layout.fillWidth: true
                                label: qsTr("Email")
                                glyph: "mail"
                                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                                onAccepted: passwordField.forceInputFocus()
                            }

                            SimorgTextField {
                                id: passwordField
                                objectName: "passwordField"
                                visible: !win.awaitingCode
                                Layout.fillWidth: true
                                label: qsTr("Password")
                                glyph: "lock"
                                echoMode: revealPassword ? TextInput.Normal : TextInput.Password
                                actionGlyph: revealPassword ? "eye-off" : "eye"
                                onActionTriggered: revealPassword = !revealPassword
                                onAccepted: win.submit()

                                property bool revealPassword: false
                            }

                            Item {
                                visible: !win.awaitingCode
                                Layout.fillWidth: true
                                implicitHeight: forgotLink.implicitHeight

                                LinkLabel {
                                    id: forgotLink
                                    anchors.right: parent.right
                                    text: qsTr("Forgot your password?")
                                    onActivated: App.openForgotPassword()
                                }
                            }

                            /*
                              ---- The second step -----------------------

                              Everything below is drawn only while the platform
                              is waiting for a code, and everything above is
                              hidden while it is. A layout skips items that are
                              not visible, so this is a genuine swap rather than
                              two panes fighting over the same space.
                            */

                            // Which account is being signed in to. Worth saying:
                            // by the time somebody has their phone out, the
                            // address they typed is off the screen, and on a
                            // shared computer it is the one thing that tells
                            // them whose code they should be reading.
                            Text {
                                visible: win.awaitingCode
                                Layout.fillWidth: true
                                text: emailField.text.trim()
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSmall
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: win.awaitingCode
                                Layout.fillWidth: true
                                text: win.useRecoveryCode ? qsTr("Enter one of the recovery codes you saved when you turned this on.") : qsTr("Open your authenticator app and enter the code it shows for Simorg.")
                                color: Theme.textFaint
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                lineHeight: 1.35
                            }

                            SimorgTextField {
                                id: codeField
                                objectName: "codeField"
                                visible: win.awaitingCode
                                Layout.fillWidth: true
                                label: win.useRecoveryCode ? qsTr("Recovery code") : qsTr("Authentication code")
                                glyph: "lock"
                                /*
                                  Digits only for an app code, so a numeric
                                  keypad comes up and a paste with spaces in it
                                  cannot arrive. A recovery code is letters and
                                  a hyphen, so it gets neither hint.
                                */
                                inputMethodHints: win.useRecoveryCode ? (Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText) : (Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText)
                                maximumLength: win.useRecoveryCode ? 32 : 6

                                /*
                                  Nothing happens when the sixth digit lands.

                                  Submitting there, on the reasoning that a code
                                  has exactly one length so a button under it
                                  carries no information, holds until a digit is
                                  wrong, and then it is the worst thing on the
                                  window: the attempt goes out before the
                                  person has finished reading what they typed, it
                                  comes back refused, and the field they were
                                  reading is gone. The Verify button and Return
                                  are the two ways through, and both are things
                                  somebody chose.
                                */
                                onAccepted: win.submit()
                            }

                            Item {
                                visible: win.awaitingCode
                                Layout.fillWidth: true
                                implicitHeight: Math.max(backLink.implicitHeight, recoveryLink.implicitHeight)

                                LinkLabel {
                                    id: backLink
                                    anchors.left: parent.left
                                    text: qsTr("Back")
                                    onActivated: win.backToPassword()
                                }

                                LinkLabel {
                                    id: recoveryLink
                                    anchors.right: parent.right
                                    text: win.useRecoveryCode ? qsTr("Use your authenticator app") : qsTr("Use a recovery code")
                                    onActivated: win.toggleRecoveryCode()
                                }
                            }

                            /*
                              ---- Consent -------------------------------

                              Above the button and inside the form, because it
                              is part of signing in rather than a footnote about
                              it. Unticked, the button below is disabled: the
                              agreement is a precondition of the account, not a
                              thing to be reversed afterwards.
                            */
                            ColumnLayout {
                                /*
                                  Hidden on the second step. The agreement was
                                  made a moment ago on the first, and asking
                                  again halfway through one sign-in would read as
                                  the first tick not having counted.
                                */
                                visible: !win.awaitingCode
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: 6

                                SimorgCheckBox {
                                    id: consent
                                    Layout.fillWidth: true
                                    checked: Legal.accepted
                                    text: qsTr("I have read and agree to the")
                                    linkText: qsTr("%1 and its privacy notice").arg(win.agreementTitle)
                                    onLinkClicked: App.openLegal("terms")
                                    onToggled: function (checked) {
                                        if (checked && win.errorIsNotice) {
                                            win.errorText = "";
                                            win.errorIsNotice = false;
                                        }
                                    }
                                }

                                // Said here as well as in the document, because
                                // the one place everybody looks at is this one.
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 30
                                    text: qsTr("Simorg collects anonymous diagnostics to make the app faster and easier to use. Nothing in them identifies you or this computer.")
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.35
                                }
                            }

                            PrimaryButton {
                                objectName: "primaryAction"
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                /*
                                  The consent tick gates the first step only. On
                                  the second there is nothing left to agree to,
                                  and a button disabled by a box that is no
                                  longer on screen would be a dead end.
                                */
                                enabled: win.awaitingCode ? (!win.working && win.codeIsComplete) : (consent.checked && !win.working)
                                text: win.awaitingCode ? (win.working ? qsTr("Verifying…") : qsTr("Verify")) : (win.working ? qsTr("Signing in…") : qsTr("Sign in"))
                                busy: win.working
                                onClicked: win.submit()
                            }

                            // Divider with a label sitting in the gap.
                            Item {
                                // Nobody halfway through signing in to an
                                // account they own is looking to create another.
                                visible: !win.awaitingCode
                                Layout.fillWidth: true
                                implicitHeight: 18

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 1
                                    color: Theme.borderSubtle
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: newHere.implicitWidth + 14
                                    height: 18
                                    color: Theme.baseMid

                                    Text {
                                        id: newHere
                                        anchors.centerIn: parent
                                        text: qsTr("new to Simorg?")
                                        color: Theme.textFaint
                                        font.pixelSize: 10
                                        font.letterSpacing: 0.6
                                    }
                                }
                            }

                            LinkLabel {
                                visible: !win.awaitingCode
                                Layout.alignment: Qt.AlignHCenter
                                text: qsTr("Create an account →")
                                pixelSize: Theme.fontBody
                                weight: Font.Bold
                                onActivated: App.openSignUp()
                            }
                        }
                    }
                }

                Reveal {
                    step: win.wide ? 3 : 2
                    Layout.fillWidth: true

                    Text {
                        visible: !win.awaitingCode
                        width: parent.width
                        text: qsTr("Sign-up and password recovery open in your browser.")
                        color: Theme.textFaint
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- Footer -------------------------------------------------
            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 14
                // GPLv3 does not require a notice in the interface — §5(d) only
                // obliges a modified version to keep showing one where the
                // original already does. The full notice lives in `simorg
                // version`, which is the conventional place for it.
                text: qsTr("Simorg %1 · GPL-3.0").arg(App.version)
                color: Theme.alpha(Theme.textMuted, 0.5)
                font.pixelSize: 10
            }
        }
    }

    /*
      The one tooltip this window can show, in its overlay so it is above
      everything and clipped by nothing. Declared here rather than beside each
      elided label: there is one pointer, so there is one bubble. See `Tip.qml`.
    */
    TipLayer {}
}
