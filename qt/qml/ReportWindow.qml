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
    badge: snapshot ? "📷 内存快照" : "📈 持续采样"
    captionNote: "独立窗口 · 关闭后不影响原报告"
    Component.onDestruction: if (report)
        backend.releaseReport(report)
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                width: 36
                height: 36
                radius: 10
                color: win.snapshot ? "#fffbe6" : "#e6f4ff"
                WText {
                    anchors.centerIn: parent
                    text: win.snapshot ? "📷" : "📈"
                    font.pixelSize: 20
                }
            }
            Column {
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    width: parent.width
                    WText {
                        Layout.fillWidth: true
                        text: F.title(win.meta)
                        font.pixelSize: 20
                        font.bold: true
                    }
                    WButton {
                        text: "✎"
                        small: true
                        hint: "编辑任务名称"
                        onClicked: win.rename(win.meta.sessionDir, F.title(win.meta))
                    }
                }
                WText {
                    width: parent.width
                    text: win.meta.bundleName || ""
                    font.pixelSize: 12
                    color: "#8c8c8c"
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            WTag {
                text: win.snapshot ? "内存快照" : "持续采样"
                ink: win.snapshot ? "#d48806" : "#1677ff"
                tint: win.snapshot ? "#fffbe6" : "#e6f4ff"
            }
            Item {
                Layout.fillWidth: true
            }
            WButton {
                text: "ⓘ 环境信息"
                small: true
                onClicked: environment.open()
            }
            WButton {
                text: "↗ 打开目录"
                small: true
                onClicked: backend.revealPath(win.meta.sessionDir)
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
            spacing: 14
            StatCards {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                values: [
                    {
                        label: "峰值 Total Pss",
                        value: F.bytes(win.stats.peak),
                        color: "#1677ff"
                    },
                    {
                        label: "均值",
                        value: F.bytes(win.stats.avg)
                    },
                    {
                        label: "结束值",
                        value: F.bytes(win.stats.last)
                    },
                    {
                        label: "增长幅度（起始 → 结束）",
                        value: F.delta(win.stats.growth),
                        color: win.stats.growth > 0 ? "#ff4d4f" : "#389e0d"
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
                snapshot: win.report.snapshot
            }
        }
    }
    Dialog {
        id: environment
        objectName: "environmentDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 620
        modal: true
        title: "环境信息"
        standardButtons: Dialog.Close
        Column {
            width: parent.width
            spacing: 10
            Repeater {
                model: [
                    {
                        name: "任务名称",
                        value: F.title(win.meta)
                    },
                    {
                        name: "采样时间",
                        value: F.date(win.meta.startedAt)
                    },
                    {
                        name: "目标应用",
                        value: win.meta.bundleName
                    },
                    {
                        name: "设备",
                        value: F.device(win.meta.device)
                    },
                    {
                        name: "系统版本",
                        value: (win.meta.device || {}).softwareVersion
                    },
                    {
                        name: "API 版本",
                        value: (win.meta.device || {}).apiVersion
                    },
                    {
                        name: "设备内存",
                        value: F.bytes((win.meta.device || {}).ramTotalKb)
                    },
                    {
                        name: "屏幕分辨率",
                        value: (win.meta.device || {}).screenResolution
                    },
                    {
                        name: "采集命令",
                        value: "hidumper --mem <pid>"
                    },
                    {
                        name: win.snapshot ? "进程 PID" : "采样时长",
                        value: win.snapshot ? (win.report.snapshot.pid || "—") : F.duration(win.stats.durationMs)
                    },
                    {
                        name: "采样点数",
                        value: win.snapshot ? 1 : win.report.count
                    },
                    {
                        name: "采样间隔",
                        value: win.meta.config ? (win.meta.config.intervalMs + " ms") : "—"
                    }
                ]
                RowLayout {
                    required property var modelData
                    width: parent.width
                    spacing: 12
                    WText {
                        Layout.preferredWidth: 90
                        text: modelData.name
                        font.pixelSize: 13
                        color: "#8c8c8c"
                    }
                    WText {
                        Layout.fillWidth: true
                        text: modelData.value === undefined ? "—" : String(modelData.value)
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
