// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import Simorg

/**
 * Naming this machine, which is the step with consequences.
 *
 * Passing it is what puts the computer on its owner's panel and makes it
 * something an agent's slot can be pointed at. Everything before this is
 * explanation; this is the screen the wizard exists for.
 *
 * ## Why there is a readme box on a setup screen
 *
 * Because an **agent** reads it. A machine's readme is the only place that says
 * what the box is for, what lives on it and what it must not touch, and an
 * agent placed here has no other way to find that out. Writing it while somebody
 * is thinking about the machine is far more likely to happen than a form they
 * would have to go looking for later. The hint under the box says who reads it,
 * because that is the part nobody guesses.
 *
 * ## The handle, and why it is suggested rather than demanded
 *
 * The platform's naming rule is narrow: lowercase letters and digits, single
 * hyphens between the words. Somebody typing "Build box 2" into a name field
 * should not have to learn that; the handle is derived as they type, and stops
 * being derived the moment they edit it themselves. See {@link MachineSetupModel::suggestSlug},
 * which is the same rule the server will apply.
 */
Item {
    id: root

    /** Whether the fields hold enough for the platform to accept them. */
    readonly property bool valid: titleField.text.trim().length > 0
                                  && MachineSetup.slugProblem(slugField.text.trim()) === ""

    /** Sends the step. The window's primary button and Enter both land here. */
    function submit() {
        if (!root.valid || MachineSetup.busy)
            return;
        MachineSetup.saveIdentity(titleField.text.trim(),
                                  slugField.text.trim(),
                                  descriptionField.text.trim(),
                                  readmeField.text);
    }

    /**
     * True once the handle is somebody's choice rather than a derivation.
     *
     * After that the name stops driving it. A field that kept overwriting what
     * somebody had deliberately typed would be the worst kind of helpful.
     *
     * Two things set it, and the second is the one that matters here: typing in
     * the handle field, and arriving with a handle the name does not suggest.
     * See {@link loadFromMachine}.
     */
    property bool handleEdited: false

    /*
      Filled from the machine, once.

      The values arrive from the platform — the title is whatever the operating
      system calls this computer, and the readme may already hold what somebody
      wrote last night before the app was closed. Binding the fields to them
      would make the boxes un-editable; copying them in when they arrive is what
      makes this a form.
    */
    function loadFromMachine() {
        titleField.text = MachineSetup.title;
        slugField.text = MachineSetup.slug.length > 0
                         ? MachineSetup.slug
                         : MachineSetup.suggestSlug(MachineSetup.title);
        descriptionField.text = MachineSetup.description;
        readmeField.text = MachineSetup.readme;
        /*
          Whether that handle was *chosen*, which is a different question from
          whether there is one.

          Every machine arrives with a handle — the enrolment derives one from
          the hostname, because the column cannot be empty — so treating any
          handle as somebody's choice froze it on the screen where it is first
          seen: typing "Build box" over "MacBook-Pro-3" left the handle saying
          `mac-book-pro`, which is the opposite of what the field is for.

          A handle that is still what the name suggests has been chosen by
          nobody and goes on following the name. One that says something else
          was typed by a person — here, on the web, or by the platform breaking
          a tie between two computers with the same hostname — and that is a
          decision this screen must not quietly undo.
        */
        root.handleEdited =
            slugField.text !== MachineSetup.suggestSlug(titleField.text);
    }

    /*
      Sized by the column, which is anchored rather than filling: an Item takes
      no height from what is anchored inside it, and the wizard measures its
      scrolling area from this. This is the tallest of the three steps, so it is
      the one where a step that measured zero was cut off by the footer.
    */
    implicitHeight: body.implicitHeight

    Component.onCompleted: root.loadFromMachine()

    Connections {
        target: MachineSetup
        function onMachineChanged() {
            // Only while nobody is typing: a refresh that landed mid-sentence
            // and replaced what somebody was writing would be unforgivable.
            if (!titleField.editing && !slugField.editing && !descriptionField.editing
                && !readmeField.focused) {
                root.loadFromMachine();
            }
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spaceLg

        Reveal {
            step: 0
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.spaceXs

                GradientText {
                    Layout.fillWidth: true
                    text: qsTr("Name this machine")
                    pixelSize: 24
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("This is how it appears on your account, and what your agents call it.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        Reveal {
            step: 1
            Layout.fillWidth: true

            GlassPanel {
                width: parent.width
                implicitHeight: form.implicitHeight + 44

                ColumnLayout {
                    id: form
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 22
                    spacing: Theme.spaceMd

                    SimorgTextField {
                        id: titleField
                        Layout.fillWidth: true
                        label: qsTr("Name")
                        glyph: "server"
                        onTextChanged: {
                            if (!root.handleEdited)
                                slugField.text = MachineSetup.suggestSlug(text);
                        }
                        onAccepted: slugField.forceInputFocus()
                    }

                    SimorgTextField {
                        id: slugField
                        Layout.fillWidth: true
                        label: qsTr("Handle")
                        glyph: "terminal"
                        /*
                          The message under the field is the local copy of the
                          platform's rule, and it is only shown once somebody
                          has typed something. A field that turned red before it
                          had been filled in would be scolding somebody for not
                          having started yet.
                        */
                        errorText: text.length > 0
                                   ? MachineSetup.slugProblem(text.trim())
                                   : ""
                        onTextChanged: if (editing) root.handleEdited = true
                        onAccepted: root.submit()
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Lowercase letters and single hyphens. This is the short name you type in a terminal and the one your agents match on.")
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.45
                    }

                    SimorgTextField {
                        id: descriptionField
                        Layout.fillWidth: true
                        label: qsTr("One line about it")
                        glyph: "info"
                        onAccepted: root.submit()
                    }

                    SimorgTextArea {
                        id: readmeField
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spaceXs
                        label: qsTr("README.md")
                        rows: 7
                        placeholder: qsTr("# What this machine is for\n\nThe build box in the study. Nightly builds and nothing else.")
                        hint: qsTr("Your agents read this. Say what you set this machine up to do, what lives on it, and anything it should leave alone. Markdown, like every other readme on Simorg.")
                    }
                }
            }
        }

        /*
          A refusal from the platform, which is the only side that can tell you
          the handle is taken. Shown here rather than beside the field: it can
          be about any of the four values, and the platform's sentence already
          says which.
        */
        Reveal {
            step: 2
            Layout.fillWidth: true
            visible: MachineSetup.lastError.length > 0

            InfoCallout {
                width: parent.width
                glyph: "alert"
                tone: Theme.danger
                title: qsTr("That did not save")
                body: MachineSetup.lastError
            }
        }
    }
}
