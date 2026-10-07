// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Simorg

/**
 * The welcome after a first setup: this computer is on the account, and here is
 * what it is for.
 *
 * ## When it appears
 *
 * Once, over the dashboard's Overview, the moment the wizard that followed the
 * sign-in which registered this computer is finished — see
 * `MachineSetupModel::isWelcomeOwed`. Running setup again from Settings does not
 * bring it back, and neither does any later launch: a greeting that came back
 * would stop being a greeting.
 *
 * ## Why the wizard does not simply say it
 *
 * Because the wizard's last answer is the platform's, not this window's: the
 * moment the runtime step is answered the platform owes nothing more, and the
 * app goes to the dashboard. The welcome is what somebody sees *on arriving*,
 * over the page they will be using, which is where the next thing to do is best
 * said — and it is a thing done on the Logos, so the one button goes there.
 *
 * ## In the middle, and only once
 *
 * The Logos's own welcome began in a corner and read as a toast, which people
 * close without reading; for a message sent once that is the same as not sending
 * it. The middle of the window is where something meant to be read goes, and the
 * cost is exactly one press, exactly one time. Every way out counts as having
 * seen it — the buttons, Escape, a click outside — because a person who pressed
 * Escape closed it just as deliberately as one who found the button.
 *
 * ## What it says
 *
 * That the machine is registered and to whom; that on the Logos it can power the
 * agents it is connected to; and the three moves that do it, in the Logos's own
 * words. When the setup found
 * no Docker here it says that too, with the reason, since an agent connected to
 * this computer cannot start until there is one.
 */
Item {
    id: root

    /** Whether it is on screen. The owner decides; this only draws it. */
    property bool shown: false

    /** Open my Logos was pressed; {@link closed} follows. */
    signal openLogos()
    /** Any way of leaving it: either button, Escape, or a click outside the card. */
    signal closed()

    readonly property string machineTitle: MachineSetup.title.length > 0
                                           ? MachineSetup.title
                                           : qsTr("This computer")
    readonly property bool dockerMissing: MachineSetup.runtimeState === "unavailable"

    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    // Under every question the dashboard can ask (200 and up): an application
    // waiting to be allowed, or a Quit, matters more than a greeting.
    z: 190
    focus: root.shown

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.duration(Theme.durBase)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeInOut
        }
    }

    // Nothing in it answers while it fades away.
    enabled: root.shown

    onShownChanged: if (root.shown) entrance.restart()

    /*
      Return opens the Logos: the one thing this card is for. Asked for once the
      card can be seen and pressed — an item that is hidden or disabled cannot take
      the keyboard, and `visible` and `enabled` turn true in no promised order —
      and on the next turn of the event loop, when both have.
    */
    readonly property bool answering: root.visible && root.enabled
    onAnsweringChanged: {
        if (root.answering)
            Qt.callLater(function () { openButton.forceActiveFocus(); });
    }

    Keys.onEscapePressed: root.closed()

    /** A value for a StyledText sentence, with anything that would read as markup made harmless. */
    function escaped(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    /** A rounded rectangle as a path, its corners as curves, since Qt misreads packed arc syntax. */
    function roundedRect(x, y, w, h, r) {
        const k = 0.5523 * r;
        return "M " + (x + r) + " " + y
            + " L " + (x + w - r) + " " + y
            + " C " + (x + w - r + k) + " " + y + " " + (x + w) + " " + (y + r - k) + " " + (x + w) + " " + (y + r)
            + " L " + (x + w) + " " + (y + h - r)
            + " C " + (x + w) + " " + (y + h - r + k) + " " + (x + w - r + k) + " " + (y + h) + " " + (x + w - r) + " " + (y + h)
            + " L " + (x + r) + " " + (y + h)
            + " C " + (x + r - k) + " " + (y + h) + " " + x + " " + (y + h - r + k) + " " + x + " " + (y + h - r)
            + " L " + x + " " + (y + r)
            + " C " + x + " " + (y + r - k) + " " + (x + r - k) + " " + y + " " + (x + r) + " " + y
            + " Z";
    }

    // The shade the card opens over; a click on it is a way out.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.base, 0.72)

        TapHandler { onTapped: root.closed() }
    }

    /*
      The card rising into place, as the Logos's does: a short lift on the settle
      curve. Nothing at all with motion off, where it is simply there.
    */
    ParallelAnimation {
        id: entrance
        NumberAnimation {
            target: lift
            property: "y"
            from: 16
            to: 0
            duration: Theme.duration(560)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: Theme.duration(560)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.easeOut
        }
    }

    Item {
        id: card
        objectName: "machineWelcomeCard"

        /** Inside the ring, around the words. */
        readonly property int pad: 26
        /** How much of the ring shows round the panel. */
        readonly property real ring: 1.5
        /** The ring's travelling light, in degrees. */
        property real spin: 0
        /**
         * Everything on the card but the picture, which is what the picture's
         * height is worked out from. None of it depends on the picture, so this
         * is no loop: the words are laid out by the card's width alone.
         */
        readonly property real rest: header.implicitHeight + stepsBox.implicitHeight
                                     + (root.dockerMissing ? dockerNote.implicitHeight + content.spacing : 0)
                                     + actions.implicitHeight + content.spacing * 3 + card.pad * 2
        /** The height the words leave for the picture in the window. */
        readonly property real sceneRoom: root.height - 48 - card.rest
        /**
         * The picture takes the height the words leave in the window, between a
         * floor where it still reads and a ceiling where it stops growing — so
         * the card fits the dashboard at its smallest, and the words are never
         * what gives.
         *
         * Where not even the floor is left, the picture goes rather than the card
         * running off the window: at the smallest window, with a desktop face
         * wider than the one this was drawn with (DejaVu Sans, a common Linux
         * default), the words alone are 4 pixels too tall.
         */
        readonly property real sceneHeight: card.sceneRoom < 64
                                            ? 0
                                            : Math.min(170, card.sceneRoom, content.width * 100 / 260)

        anchors.centerIn: parent
        width: Math.min(root.width - 80, 560)
        height: content.implicitHeight + card.pad * 2
        transform: Translate { id: lift }

        Accessible.role: Accessible.Dialog
        Accessible.name: title.text

        NumberAnimation on spin {
            running: root.visible && Theme.motion
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 11000
        }

        // The card itself must not close the welcome when clicked.
        TapHandler { onTapped: {} }

        /*
          The Logos welcome's ring: a faint gradient hairline, and a light that
          travels round it. The ring is the band between two rounded rectangles,
          filled even-odd, and the light is a conical gradient turning under it —
          so nothing repaints per pixel and the panel on top is untouched.
        */
        Shape {
            id: ring
            anchors.fill: parent
            antialiasing: true

            readonly property string ringPath: root.roundedRect(0, 0, card.width, card.height,
                                                                Theme.radiusLarge + card.ring)
                                               + " " + root.roundedRect(card.ring, card.ring,
                                                                        card.width - card.ring * 2,
                                                                        card.height - card.ring * 2,
                                                                        Theme.radiusLarge)

            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: card.width; y2: card.height
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.cyan, 0.34) }
                    GradientStop { position: 0.45; color: Theme.alpha(Theme.sky, 0.24) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.violet, 0.3) }
                }
                PathSvg { path: ring.ringPath }
            }

            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: ConicalGradient {
                    centerX: card.width / 2
                    centerY: card.height / 2
                    angle: card.spin
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.violet, 0) }
                    GradientStop { position: 0.08; color: Theme.violet }
                    GradientStop { position: 0.12; color: Theme.sky }
                    GradientStop { position: 0.16; color: Theme.cyan }
                    GradientStop { position: 0.24; color: Theme.alpha(Theme.cyan, 0) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.cyan, 0) }
                }
                PathSvg { path: ring.ringPath }
            }
        }

        GlassPanel {
            anchors.fill: parent
            anchors.margins: card.ring
            radius: Theme.radiusLarge
            border.width: 0
            opaque: true
        }

        // Sparks drifting up from the bottom edge, behind the words.
        Item {
            anchors.fill: parent
            anchors.margins: card.ring
            clip: true
            visible: Theme.motion

            Repeater {
                model: [
                    { at: 0.10, delay: 0, tone: Theme.cyan },
                    { at: 0.28, delay: 1300, tone: Theme.violet },
                    { at: 0.52, delay: 500, tone: Theme.sky },
                    { at: 0.71, delay: 1900, tone: Theme.cyan },
                    { at: 0.88, delay: 900, tone: Theme.violet }
                ]

                delegate: Rectangle {
                    id: speck
                    required property var modelData
                    /** Along its climb, 0 to 1. */
                    property real drift: 1

                    width: 5
                    height: 5
                    radius: 2.5
                    color: speck.modelData.tone
                    x: parent.width * speck.modelData.at
                    y: parent.height - 14 - 34 * speck.drift
                    scale: 0.6 + 0.4 * speck.drift
                    opacity: speck.drift < 0.35 ? 0.9 * speck.drift / 0.35 : 0.9 * (1 - speck.drift) / 0.65

                    SequentialAnimation on drift {
                        running: root.visible && Theme.motion
                        loops: Animation.Infinite
                        PauseAnimation { duration: speck.modelData.delay }
                        NumberAnimation { from: 0; to: 1; duration: 4600; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 14

            MachineWelcomeScene {
                objectName: "machineWelcomeScene"
                // Hidden, it takes no height and no spacing in the column.
                visible: card.sceneHeight > 0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: card.sceneHeight
                Layout.preferredWidth: card.sceneHeight * 260 / 100
                running: root.visible
            }

            ColumnLayout {
                id: header
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 7

                    Glyph {
                        name: "check-circle"
                        size: 14
                        thickness: 1.8
                        tone: Theme.emerald
                    }

                    Text {
                        text: qsTr("MACHINE REGISTERED")
                        color: Theme.emerald
                        font.pixelSize: Theme.fontEyebrow
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                    }
                }

                GradientText {
                    id: title
                    Layout.fillWidth: true
                    text: qsTr("Welcome to Simorg Desktop")
                    pixelSize: 25
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 440
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.StyledText
                    text: (Auth.user.handle.length > 0
                           ? qsTr("<b>%1</b> is now registered under <b>%2</b>. Place it on your Logos and connect it to your agents, so this computer can power their work.")
                                 .arg(root.escaped(root.machineTitle))
                                 .arg(root.escaped(Auth.user.handle))
                           : qsTr("<b>%1</b> is now registered to your account. Place it on your Logos and connect it to your agents, so this computer can power their work.")
                                 .arg(root.escaped(root.machineTitle)))
                    color: Theme.textBody
                    font.pixelSize: Theme.fontSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }

            /*
              The three moves, numbered the way the wizard's three steps were a
              moment ago, and worded as the Logos words them.
            */
            Rectangle {
                id: stepsBox
                Layout.fillWidth: true
                implicitHeight: steps.implicitHeight + 32
                radius: Theme.radiusBase
                color: Theme.alpha(Theme.base, 0.35)
                border.width: 1
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: steps
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 11

                    Repeater {
                        model: [
                            {
                                title: qsTr("Open your Logos"),
                                body: qsTr("Your machines are listed in its Machines tab.")
                            },
                            {
                                title: qsTr("Place %1 on it").arg(root.machineTitle),
                                body: qsTr("Press + beside it, or drag its row onto the sheet.")
                            },
                            {
                                title: qsTr("Connect it to your agents"),
                                body: qsTr("Drag from one of its dots onto an agent, and that agent runs here.")
                            }
                        ]

                        delegate: RowLayout {
                            id: stepRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 13

                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                width: 24
                                height: 24
                                radius: 12
                                color: Theme.alpha(Theme.blue, 0.16)
                                border.width: 1
                                border.color: Theme.alpha(Theme.blue, 0.5)

                                Text {
                                    anchors.centerIn: parent
                                    text: String(stepRow.index + 1)
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: stepRow.modelData.title
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: stepRow.modelData.body
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.4
                                }
                            }
                        }
                    }
                }
            }

            InfoCallout {
                id: dockerNote
                Layout.fillWidth: true
                visible: root.dockerMissing
                glyph: "container"
                tone: Theme.amber
                title: qsTr("Docker comes first")
                body: qsTr("Agents run in containers, so the ones you connect start here once Docker is running. Install it, then run setup again from Settings.")
            }

            RowLayout {
                id: actions
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                // Said before it happens: the button leaves this app for the browser.
                Glyph {
                    name: "external"
                    size: 13
                    thickness: 1.6
                    tone: Theme.textFaint
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Opens in your browser")
                    color: Theme.textFaint
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                GhostButton {
                    text: qsTr("Close")
                    implicitHeight: 40
                    onClicked: root.closed()
                }

                PrimaryButton {
                    id: openButton
                    text: qsTr("Open my Logos")
                    onClicked: {
                        root.openLogos();
                        root.closed();
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }
            }
        }
    }
}
