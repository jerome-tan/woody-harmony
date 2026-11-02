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
                visible: win.width >= 800
                iconName: "InfoCircleOutlined"
                text: "环境信息"
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
                    x: moreButton.width - width
                    y: moreButton.height + 4
                    Action {
                        text: "环境信息"
                        onTriggered: environment.open()
                    }
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
                        color: win.stats.growth > 0 ? T.error : T.negative
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
            clip: true
            SnapshotBody {
                width: snapshotScroll.availableWidth
                height: Math.max(width < 800 ? 720 : 660, snapshotScroll.availableHeight)
                snapshot: win.report.snapshot
            }
        }
    }
    WDialog {
        id: environment
        objectName: "environmentDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 40)
        height: Math.min(650, parent.height - 32)
        modal: true
        title: "环境信息"
        standardButtons: Dialog.Close
        ScrollView {
            id: environmentScroll
            anchors.fill: parent
            clip: true
            Column {
                width: environmentScroll.availableWidth
                spacing: 16
                Repeater {
                    model: [
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
                    Column {
                        required property var modelData
                        width: parent.width
                        spacing: 8
                        WText {
                            text: modelData.title
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: modelData.rows
                            RowLayout {
                                id: environmentRow
                                required property var modelData
                                readonly property string value: modelData.value === undefined || modelData.value === "" ? "—" : String(modelData.value)
                                width: parent.width
                                spacing: 12
                                WText {
                                    Layout.preferredWidth: 96
                                    text: environmentRow.modelData.name
                                    color: T.muted
                                }
                                WText {
                                    Layout.fillWidth: true
                                    text: environmentRow.value
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideNone
                                }
                                WButton {
                                    objectName: "environment-copy-" + environmentRow.modelData.key
                                    small: true
                                    tone: "quiet"
                                    iconName: "CopyOutlined"
                                    hint: "复制" + environmentRow.modelData.name
                                    enabled: environmentRow.value !== "—"
                                    onClicked: backend.copyText(environmentRow.value)
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: T.border
                        }
                    }
                }
            }
        }
    }
}
