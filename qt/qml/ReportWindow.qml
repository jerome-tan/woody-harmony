import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

WindowBase {
    id: win
    objectName: "reportWindow"
    property var report: null
    readonly property var meta: report ? report.meta : {}
    readonly property var stats: report ? report.stats : {}
    readonly property bool snapshot: meta.type === "snapshot"
    transientParent: null
    caption: F.title(meta)
    extraModalOpen: environment.opened

    Component.onDestruction: if (report)
        backend.releaseReport(report)
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.width < 800 ? 12 : 24
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            WTag {
                visible: win.width >= 800
                text: win.snapshot ? "内存快照" : "持续采样"
            }
            WText {
                Layout.fillWidth: true
                text: (win.meta.appLabel || win.meta.bundleName || "") + (win.width >= 900 ? "  ·  " + ((win.meta.device || {}).marketName || (win.meta.device || {}).model || "") + "  ·  " + F.date(win.meta.startedAt) : "") + (win.snapshot ? "" : "  ·  " + F.duration(win.stats.durationMs) + " · " + win.report.count + " 点")
                color: T.muted
                font.pixelSize: 12
            }
            WButton {
                objectName: "environmentButton"
                iconName: "InfoCircleOutlined"
                text: win.width >= 800 ? "环境信息" : ""
                hint: "环境信息"
                tone: "quiet"
                small: true
                onClicked: environment.open()
            }
            WButton {
                id: moreButton
                objectName: "reportMore"
                iconName: "MoreOutlined"
                hint: "报告操作"
                small: true
                onClicked: reportMenu.open()
                WMenu {
                    id: reportMenu
                    objectName: "reportMenu"
                    x: moreButton.width - width
                    y: moreButton.height + 4
                    Action {
                        text: "重命名"
                        onTriggered: win.rename(win.meta.sessionDir, F.title(win.meta))
                    }
                    Action {
                        text: "打开所在文件夹"
                        onTriggered: backend.revealPath(win.meta.sessionDir)
                    }
                }
            }
        }
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: !!win.report
            sourceComponent: win.snapshot ? snapshotComponent : trendComponent
        }
    }
    Component {
        id: trendComponent
        ColumnLayout {
            spacing: 12
            StatCards {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                values: [
                    {
                        label: "峰值 PSS",
                        value: win.stats.validCount ? F.bytes(win.stats.peak) : "—",
                        color: T.accent
                    },
                    {
                        label: "均值 PSS",
                        value: win.stats.validCount ? F.bytes(win.stats.avg) : "—"
                    },
                    {
                        label: "结束 PSS",
                        value: win.stats.validCount ? F.bytes(win.stats.last) : "—"
                    },
                    {
                        label: "增长量",
                        value: win.stats.validCount ? F.delta(win.stats.growth) : "—",
                        memoryDelta: win.stats.validCount ? win.stats.growth : null
                    }
                ]
            }
            MemoryChart {
                Layout.fillWidth: true
                Layout.fillHeight: true
                reports: [win.report]
            }
        }
    }
    Component {
        id: snapshotComponent
        ScrollView {
            id: snapshotScroll
            objectName: "snapshotScroll"
            clip: true
            contentWidth: availableWidth
            contentHeight: snapshotBody.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            SnapshotBody {
                id: snapshotBody
                width: snapshotScroll.availableWidth
                height: implicitHeight
                snapshot: win.report.snapshot
            }
        }
    }
    WDialog {
        id: environment
        objectName: "environmentDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 40)
        height: Math.min(Math.ceil(environmentSections.height) + topPadding + bottomPadding + header.implicitHeight + footer.implicitHeight + 2 * spacing, parent.height - 32)
        modal: true
        title: "环境信息"
        standardButtons: Dialog.Close
        readonly property var sections: [
            {
                title: "设备",
                rows: [
                    {
                        key: "model",
                        name: "型号",
                        value: (win.meta.device || {}).marketName || (win.meta.device || {}).model
                    },
                    {
                        key: "system",
                        name: "系统",
                        value: (win.meta.device || {}).softwareVersion
                    },
                    {
                        key: "api",
                        name: "API",
                        value: (win.meta.device || {}).apiVersion
                    },
                    {
                        key: "serial",
                        name: "序列号",
                        value: (win.meta.device || {}).serialNumber || (win.meta.device || {}).targetId
                    },
                    {
                        key: "ram",
                        name: "设备内存",
                        value: (win.meta.device || {}).ramTotalKb ? F.bytes(win.meta.device.ramTotalKb) : "—"
                    },
                    {
                        key: "resolution",
                        name: "屏幕分辨率",
                        value: (win.meta.device || {}).screenResolution
                    }
                ]
            },
            {
                title: "采集",
                rows: [
                    {
                        key: "task",
                        name: "报告名称",
                        value: F.title(win.meta)
                    },
                    {
                        key: "bundle",
                        name: "应用",
                        value: win.meta.bundleName
                    },
                    {
                        key: "time",
                        name: "开始时间",
                        value: F.date(win.meta.startedAt)
                    },
                    {
                        key: "duration",
                        name: win.snapshot ? "进程 PID" : "采样时长",
                        value: win.snapshot ? (win.report.snapshot.pid || "—") : F.duration(win.stats.durationMs)
                    },
                    {
                        key: "count",
                        name: "采样点数",
                        value: win.snapshot ? 1 : win.report.count
                    },
                    {
                        key: "interval",
                        name: "采样间隔",
                        value: win.snapshot ? "—" : win.meta.config ? win.meta.config.intervalMs + " ms" : "—"
                    },
                    {
                        key: "command",
                        name: "采集命令",
                        value: "hidumper --mem <pid>"
                    }
                ]
            }
        ]
        function valueText(value) {
            return value === undefined || value === null || value === "" ? "—" : String(value);
        }
        function escapeHtml(value) {
            return valueText(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        }
        readonly property string plainText: sections.map(function (section) {
            return section.title + "\n" + section.rows.map(function (row) {
                return row.name + "：" + environment.valueText(row.value);
            }).join("\n");
        }).join("\n\n")
        ScrollView {
            id: environmentScroll
            objectName: "environmentScroll"
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            Column {
                id: environmentSections
                width: environmentScroll.availableWidth
                spacing: 12
                Repeater {
                    model: environment.sections
                    delegate: WCard {
                        required property var modelData
                        required property int index
                        width: environmentSections.width
                        height: 44 + padding * 2 + sectionText.contentHeight
                        title: modelData.title
                        headerColor: T.chrome
                        padding: 12
                        TextEdit {
                            id: sectionText
                            objectName: index === 0 ? "environmentText" : "environmentCaptureText"
                            width: parent.width
                            readOnly: true
                            selectByMouse: true
                            selectByKeyboard: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.RichText
                            font.pixelSize: 14
                            color: T.text
                            selectionColor: T.selected
                            selectedTextColor: T.text
                            text: "<table width='100%' cellspacing='0' cellpadding='3'>" + modelData.rows.map(function (row) {
                                return "<tr><td width='88' valign='top' style='color:" + T.muted + "'>" + environment.escapeHtml(row.name) + "</td><td valign='top'>" + environment.escapeHtml(row.value) + "</td></tr>";
                            }).join("") + "</table>"
                        }
                    }
                }
            }
        }
        footer: Item {
            implicitHeight: 58
            WButton {
                objectName: "environmentCopyAll"
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                text: "一键复制"
                iconName: "CopyOutlined"
                tone: "primary"
                onClicked: {
                    backend.copyText(environment.plainText);
                    win.notify("已复制全部环境信息");
                }
            }
        }
    }
}
