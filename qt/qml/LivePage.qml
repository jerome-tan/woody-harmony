import QtQuick
import QtQuick.Layouts
import "Format.js" as F

ColumnLayout {
    id: root
    property bool watch: false
    readonly property var report: backend.live
    readonly property var stats: report.stats
    spacing: 14
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 78
        radius: 8
        border.color: "#91caff"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "#f0f7ff"
            }
            GradientStop {
                position: 1
                color: "white"
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14
            Rectangle {
                width: 38
                height: 38
                radius: 10
                color: root.watch ? "#52c41a" : "#1677ff"
                WText {
                    anchors.centerIn: parent
                    text: root.watch ? "📡" : "📈"
                    font.pixelSize: 20
                }
            }
            Column {
                Layout.fillWidth: true
                spacing: 6
                Row {
                    spacing: 8
                    WText {
                        text: root.report.meta.bundleName || "正在启动…"
                        font.bold: true
                    }
                    WTag {
                        text: root.watch ? "查看中 · 不落盘" : backend.status.state === "sampling" ? "采样中" : backend.status.state === "starting" ? "启动中" : backend.status.state === "stopping" ? "停止中" : "已结束"
                    }
                }
                WText {
                    width: parent.width
                    text: (root.report.meta.startedAt ? Qt.formatDateTime(new Date(root.report.meta.startedAt), "HH:mm:ss") + " 开始 · " : "") + (backend.status.message || "") + (root.watch ? " · 数据仅保留在内存中，结束后不生成报告" : root.report.meta.config && root.report.meta.config.maxDurationMs ? " · 预计 " + Qt.formatDateTime(new Date(root.report.meta.startedAt + root.report.meta.config.maxDurationMs), "HH:mm:ss") + " 自动结束" : "")
                    font.pixelSize: 12
                    color: "#8c8c8c"
                }
            }
            WButton {
                visible: !root.watch
                text: "↗ 采集目录"
                enabled: !!root.report.meta.sessionDir
                onClicked: backend.revealPath(root.report.meta.sessionDir)
            }
            WButton {
                objectName: "stopButton"
                text: root.watch ? "□ 结束查看" : "□ 结束采样"
                tone: "danger"
                enabled: backend.sampling && backend.status.state !== "stopping"
                onClicked: backend.stopSampling()
            }
        }
    }
    StatCards {
        Layout.fillWidth: true
        Layout.preferredHeight: 90
        values: [
            {
                label: "当前 Total Pss",
                value: F.bytes(root.stats.last),
                color: "#1677ff"
            },
            {
                label: "Private Dirty",
                value: F.bytes(root.stats.privateDirty)
            },
            {
                label: "采样点数",
                value: root.report.count + (root.stats.pid ? " · PID " + root.stats.pid : "")
            },
            {
                label: "已采样时长",
                value: F.duration(root.stats.durationMs) + (root.stats.growth ? "  " + F.delta(root.stats.growth) : "")
            }
        ]
    }
    MemoryChart {
        Layout.fillWidth: true
        Layout.fillHeight: true
        reports: [root.report]
        live: backend.sampling
        title: root.watch ? "实时内存" : "实时趋势"
    }
}
