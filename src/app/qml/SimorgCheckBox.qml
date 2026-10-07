// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

import QtQuick
import QtQuick.Layouts

/**
 * A checkbox, with the label part of the target.
 *
 * The unchecked state is drawn with a visible border rather than the
 * near-invisible hairline the rest of the interface uses: a control nobody
 * notices is one nobody knowingly set.
 *
 * Reachable by keyboard, because one of these is the consent box on the
 * sign-in window and a control that gates signing in cannot be mouse-only.
 */
Item {
    id: root

    property bool checked: false
    property string text: ""
    /**
     * Rendered after the text, in accent colour, and emits {@link linkClicked}.
     *
     * Part of the same paragraph rather than a line under it, because "I agree
     * to the Terms of Use" is one sentence and the thing being agreed to has to
     * be reachable from inside it. The label is laid out as styled text for
     * that, so an `&`, a `<` or a `>` in either string would be read as markup;
     * neither is ever anything but a plain sentence.
     */
    property string linkText: ""

    signal toggled(bool checked)
    signal linkClicked

    function toggle() {
        if (!root.enabled)
            return;
        root.checked = !root.checked;
        root.toggled(root.checked);
    }

    implicitHeight: Math.max(22, row.implicitHeight)
    implicitWidth: row.implicitWidth
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: enabled
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter) {
            root.toggle();
            event.accepted = true;
        }
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 11

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            implicitWidth: 19
            implicitHeight: 19

            Rectangle {
                id: box
                anchors.fill: parent
                radius: 3
                color: root.checked ? Theme.alpha(Theme.blue, 0.9) : Theme.inset
                border.width: root.checked ? 0 : 1
                border.color: hover.hovered ? Theme.alpha(Theme.blue, 0.7) : Theme.borderStrong

                Behavior on color {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Theme.duration(Theme.durFast) }
                }

                Glyph {
                    anchors.centerIn: parent
                    name: "check"
                    size: 13
                    thickness: 2.4
                    tone: Theme.textPrimary
                    opacity: root.checked ? 1 : 0
                    scale: root.checked ? 1 : 0.5

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.duration(Theme.durFast) }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.duration(Theme.durBase)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.easeOut
                        }
                    }
                }
            }

            // Focus ring, around the box rather than the whole row: the box is
            // what the key press operates.
            Rectangle {
                anchors.fill: box
                anchors.margins: -4
                radius: Theme.radiusSmall
                color: "transparent"
                border.width: 2
                border.color: Theme.alpha(Theme.sky, 0.7)
                visible: root.activeFocus
            }
        }

        Text {
            id: label
            Layout.fillWidth: true
            /*
              One paragraph, with the link inside it.

              StyledText rather than a second Text beside this one: the sentence
              wraps, and a link laid out as a sibling would end up on a line of
              its own as soon as the window narrowed.
            */
            textFormat: Text.StyledText
            text: root.linkText.length > 0
                  ? root.text + " <a href=\"#\">" + root.linkText + "</a>"
                  : root.text
            color: Theme.textBody
            linkColor: Theme.sky
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.4

            /*
              A click on the link never reaches the TapHandler below: Text takes
              the press itself when there is a link under the cursor, and the
              handler on the row is only offered what Text left alone. The guard
              is there for the case where that stops being true.
            */
            onLinkActivated: root.linkClicked()
        }
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.enabled
        onTapped: {
            if (label.hoveredLink.length > 0)
                return;
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.toggle();
        }
    }
}
