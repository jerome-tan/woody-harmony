import QtQuick
import QtQuick.Layouts
import "Format.js" as F
import "Theme.js" as T

ColumnLayout {
    id: root
    objectName: "livePage"
    property bool watch: false
    readonly property var report: backend.live
    readonly property var stats: report.stats
    readonly property bool waiting: backend.sampling && !stats.currentValid
    readonly property real limit: (report.meta.config || {}).maxDurationMs || 0
    spacing: 16
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Column {
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                width: parent.width
                WText {
                    Layout.fillWidth: true
                    text: root.watch ? "实时查看" : F.title(root.report.meta)
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                WTag {
                    visible: root.waiting || backend.status.state === "stopping"
                    text: root.waiting ? "等待应用" : "正在结束"
                }
            }
            WText {
                width: parent.width
                text: (root.report.meta.appLabel || root.report.meta.bundleName || "") + " · " + ((root.report.meta.device || {}).marketName || backend.target) + " · " + ((root.report.meta.config || {}).intervalMs || 1000) + " ms"
                color: T.muted
                font.pixelSize: 12
            }
        }
        WButton {
            id: stopButton
            objectName: "stopButton"
            text: root.waiting ? "结束等待" : root.watch ? "结束查看" : "结束采样"
            contentItem: RowLayout {
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    color: T.error
                    opacity: stopButton.enabled ? 1 : .4
                }
                WText {
                    text: stopButton.text
                    font: stopButton.font
                    color: stopButton.enabled ? T.text : T.disabled
                }
            }
            enabled: backend.sampling && backend.status.state !== "stopping"
            onClicked: backend.stopSampling()
        }
    }
    WText {
        visible: root.waiting
        text: "在设备上打开应用后开始记录有效数据。"
        color: T.muted
        font.pixelSize: 12
    }
    RowLayout {
        visible: !root.watch && root.limit > 0 && !root.waiting
        Layout.fillWidth: true
        WText {
            text: F.duration(root.stats.durationMs) + " / " + F.duration(root.limit)
            font.pixelSize: 12
        }
        Rectangle {
            Layout.fillWidth: true
            height: 5
            radius: 3
            color: T.border
            Rectangle {
                width: parent.width * Math.min(1, root.stats.durationMs / Math.max(1, root.limit))
                height: 5
                radius: 3
                color: T.focus
            }
        }
        WText {
            text: Math.min(100, Math.round(root.stats.durationMs / Math.max(1, root.limit) * 100)) + "%"
            font.pixelSize: 12
            color: T.muted
        }
    }
    StatCards {
        Layout.fillWidth: true
        values: [
            {
                label: "当前 PSS",
                value: root.waiting ? "—" : F.bytes(root.stats.last)
            },
            {
                label: "Private Dirty",
                value: root.waiting ? "—" : F.bytes(root.stats.privateDirty)
            },
            {
                label: "采样点",
                value: String(root.stats.validCount || 0)
            },
            {
                label: "有效时长",
                value: root.stats.validCount ? F.duration(root.stats.validDurationMs) : "—"
            }
        ]
    }
    MemoryChart {
        Layout.fillWidth: true
        Layout.fillHeight: true
        reports: [root.report]
        live: backend.sampling
        title: "内存趋势"
    }
}
