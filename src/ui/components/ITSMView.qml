pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * ServiceNow ITSM KB HTML Template Prompt Generator.
 * Triggered automatically when copied clipboard text contains HTML markup
 * while Bespoke ITSM integration is enabled.
 */
Item {
    id: root

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

        // HTML Capture Status Banner
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: 10
            color: itsmController.isHtmlReady
                   ? Qt.rgba(0.0, 0.90, 0.64, 0.14)
                   : Qt.rgba(0.16, 0.16, 0.24, 0.66)
            border.width: 1
            border.color: itsmController.isHtmlReady
                          ? "#00e5a3"
                          : Qt.rgba(1, 1, 1, 0.10)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: itsmController.isHtmlReady
                           ? "#00e5a3"
                           : (itsmController.htmlLength > 0 ? "#38bdf8" : "#64748b")
                }

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: itsmController.isHtmlReady ? "#f8fafc" : "#cbd5e1"
                    font.pixelSize: 11
                    font.weight: itsmController.isHtmlReady ? Font.DemiBold : Font.Normal
                    text: itsmController.isHtmlReady
                          ? ("HTML Detected in Clipboard (" + itsmController.htmlLength + " chars) — Pick a template")
                          : (itsmController.lastTemplateName !== ""
                             ? ("Copied " + itsmController.lastTemplateName + " prompt • Pick another template or copy new HTML")
                             : (itsmController.htmlLength > 0
                                ? ("Cached HTML (" + itsmController.htmlLength + " chars) — Select a template to copy prompt")
                                : "Copy ServiceNow article HTML to auto-arm prompt formatting"))
                }

                Rectangle {
                    visible: itsmController.isHtmlReady
                    implicitWidth: clearLbl.implicitWidth + 14
                    implicitHeight: 22
                    radius: 7
                    color: clearHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    HoverHandler { id: clearHover }

                    Label {
                        id: clearLbl
                        anchors.centerIn: parent
                        color: "#cbd5e1"
                        font.pixelSize: 10
                        text: "Dismiss"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: itsmController.clearReady()
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
                                        readonly property bool enabledAction: itsmController.htmlLength > 0

                                        implicitWidth: tplLabel.implicitWidth + 20
                                        implicitHeight: 28
                                        radius: 8
                                        opacity: enabledAction ? 1.0 : 0.55
                                        color: tplMouse.pressed
                                               ? Qt.rgba(0.0, 0.90, 0.64, 0.24)
                                               : (tplHover.hovered
                                                  ? Qt.rgba(0.0, 0.90, 0.64, 0.14)
                                                  : Qt.rgba(0.11, 0.12, 0.19, 0.85))
                                        border.width: 1
                                        border.color: tplHover.hovered && enabledAction
                                                      ? "#00e5a3"
                                                      : Qt.rgba(1, 1, 1, 0.12)

                                        HoverHandler { id: tplHover }

                                        ToolTip.visible: tplHover.hovered
                                        ToolTip.delay: 350
                                        ToolTip.text: tplBtn.enabledAction
                                                      ? ("Copy prompt for " + tplBtn.modelData.templateFile)
                                                      : ("Template: " + tplBtn.modelData.templateFile + " (copy HTML first)")

                                        Label {
                                            id: tplLabel
                                            anchors.centerIn: parent
                                            color: tplHover.hovered && tplBtn.enabledAction ? "#00e5a3" : "#f8fafc"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            text: tplBtn.modelData.label
                                        }

                                        MouseArea {
                                            id: tplMouse
                                            anchors.fill: parent
                                            enabled: tplBtn.enabledAction
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: itsmController.generatePrompt(tplBtn.modelData.templateFile)
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
