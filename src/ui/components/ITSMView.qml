pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * ServiceNow ITSM KB Template Prompt Generator.
 * Provides a manual paste box for HTML, error codes, or rough notes and
 * wraps the pasted content into the selected template prompt on click.
 */
Item {
    id: root

    readonly property bool inputFocused: htmlInputBox.activeFocus
    signal collapseRequested()

    function focusInput() {
        htmlInputBox.forceActiveFocus()
    }

    readonly property var templateCategories: [
        {
            category: "Knowledge",
            accent: "#00e5a3",
            templates: [
                { label: "How-To", templateFile: "Knowledge_HowTo.html" },
                { label: "Known Error", templateFile: "Knowledge_KnownError.html" },
                { label: "FAQ", templateFile: "Knowledge_FAQ.html" },
                { label: "Reference", templateFile: "Knowledge_Reference.html" },
                { label: "Comprehensive Guide", templateFile: "Knowledge_ComprehensiveGuide.html" }
            ]
        },
        {
            category: "Apps & Systems",
            accent: "#38bdf8",
            templates: [
                { label: "Full", templateFile: "AppsSystems_Full.html" },
                { label: "Limited", templateFile: "AppsSystems_Limited.html" },
                { label: "Technical", templateFile: "AppsSystems_Technical.html" },
                { label: "Migration", templateFile: "AppsSystems_Migration.html" }
            ]
        },
        {
            category: "Processes",
            accent: "#a78bfa",
            templates: [
                { label: "Definition", templateFile: "Processes_Definition.html" },
                { label: "Sub-Process", templateFile: "Processes_SubProcess.html" },
                { label: "Handoff", templateFile: "Processes_Handoff.html" }
            ]
        },
        {
            category: "Self-Service",
            accent: "#2dd4bf",
            templates: [
                { label: "Teal StepCard", templateFile: "SelfService_TealStepCard.html" },
                { label: "Teal / Neutral / Grey", templateFile: "SelfService_TealNeutralGrey.html" },
                { label: "Literacy Bite", templateFile: "SelfService_LiteracyBite.html" }
            ]
        }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Manual Paste Container (#1E1E2E dark glassmorphism)
        Rectangle {
            id: pasteFrame
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            radius: 12
            color: Qt.rgba(0.118, 0.118, 0.180, 0.92)
            border.width: 1
            border.color: htmlInputBox.activeFocus
                          ? "#00e5a3"
                          : Qt.rgba(1, 1, 1, 0.14)

            ScrollView {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: pasteFooter.top
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 4
                anchors.bottomMargin: 2
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: htmlInputBox
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: "#f8fafc"
                    placeholderText: "Paste ServiceNow HTML, error codes, or rough notes here..."
                    placeholderTextColor: "#64748b"
                    font.pixelSize: 11
                    background: null
                    onActiveFocusChanged: {
                        if (!activeFocus) {
                            root.collapseRequested()
                        }
                    }
                }
            }

            // Subtle bottom status & Clear action anchored inside the box
            RowLayout {
                id: pasteFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                anchors.bottomMargin: 5
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: "#64748b"
                    font.pixelSize: 10
                    text: htmlInputBox.text.length > 0
                          ? (htmlInputBox.text.length + " chars ready"
                             + (itsmController.lastTemplateName !== ""
                                ? (" • Last: " + itsmController.lastTemplateName)
                                : ""))
                          : (itsmController.lastTemplateName !== ""
                             ? ("Last copied: " + itsmController.lastTemplateName)
                             : "Click any template below to copy prompt + pasted text")
                }

                Rectangle {
                    id: clearBtn
                    Layout.preferredWidth: clearLbl.implicitWidth + 14
                    Layout.preferredHeight: 20
                    radius: 6
                    opacity: htmlInputBox.text.length > 0 ? 1.0 : 0.45
                    color: clearMouse.pressed
                           ? Qt.rgba(1, 1, 1, 0.18)
                           : (clearHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05))
                    border.width: 1
                    border.color: clearHover.hovered && htmlInputBox.text.length > 0
                                  ? Qt.rgba(1, 1, 1, 0.28)
                                  : Qt.rgba(1, 1, 1, 0.12)

                    HoverHandler { id: clearHover }

                    Label {
                        id: clearLbl
                        anchors.centerIn: parent
                        color: "#cbd5e1"
                        font.pixelSize: 10
                        text: "Clear"
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        enabled: htmlInputBox.text.length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            htmlInputBox.clear()
                            htmlInputBox.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Scrollable 4-Category Template Matrix
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: root.width - 14
                spacing: 10

                Repeater {
                    model: root.templateCategories

                    delegate: Rectangle {
                        id: categoryCard
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: cardInner.implicitHeight + 18
                        radius: 12
                        color: Qt.rgba(0.16, 0.16, 0.24, 0.62)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.09)

                        ColumnLayout {
                            id: cardInner
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 9
                            spacing: 7

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.preferredWidth: 6
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: categoryCard.modelData.accent
                                }

                                Label {
                                    color: "#e2e8f0"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    text: categoryCard.modelData.category
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: categoryCard.modelData.templates

                                    delegate: Rectangle {
                                        id: tplBtn
                                        required property var modelData
                                        readonly property bool hasContent: htmlInputBox.text.trim().length > 0

                                        implicitWidth: tplLabel.implicitWidth + 20
                                        implicitHeight: 28
                                        radius: 8
                                        opacity: hasContent ? 1.0 : 0.72
                                        color: tplMouse.pressed
                                               ? Qt.rgba(0.0, 0.90, 0.64, 0.24)
                                               : (tplHover.hovered
                                                  ? Qt.rgba(0.0, 0.90, 0.64, 0.14)
                                                  : Qt.rgba(0.11, 0.12, 0.19, 0.85))
                                        border.width: 1
                                        border.color: tplHover.hovered
                                                      ? "#00e5a3"
                                                      : Qt.rgba(1, 1, 1, 0.12)

                                        HoverHandler { id: tplHover }

                                        ToolTip.visible: tplHover.hovered
                                        ToolTip.delay: 350
                                        ToolTip.text: "Copy prompt for " + tplBtn.modelData.templateFile

                                        Label {
                                            id: tplLabel
                                            anchors.centerIn: parent
                                            color: tplHover.hovered ? "#00e5a3" : "#f8fafc"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            text: tplBtn.modelData.label
                                        }

                                        MouseArea {
                                            id: tplMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: itsmController.generatePrompt(
                                                           tplBtn.modelData.templateFile,
                                                           htmlInputBox.text)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
