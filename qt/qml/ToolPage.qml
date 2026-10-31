import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

ScrollView {
    id: root
    property string kind: "peak"
    signal back
    readonly property bool locked: backend.sampling || backend.snapshotting
    clip: true
    Column {
        width: root.availableWidth
        spacing: 14
        WButton {
            text: "‹ 返回工具集"
            small: true
            onClicked: root.back()
        }
        Row {
            visible: root.kind === "peak"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 60
            height: 34
            WText {
                text: "① 配置参数"
                color: "#1677ff"
            }
            WText {
                text: "② 实时采样"
                color: "#8c8c8c"
            }
            WText {
                text: "③ 采样报告"
                color: "#8c8c8c"
            }
        }
        WCard {
            width: Math.min(720, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
            height: form.implicitHeight + 76
            visible: !backend.snapshotting
            title: root.kind === "watch" ? "📡 实时内存" : root.kind === "snap" ? "📷 内存快照" : "📈 持续内存采样"
            padding: 24
            Column {
                id: form
                width: parent.width
                spacing: 14
                WText {
                    visible: root.kind === "watch"
                    width: parent.width
                    text: "仅用于查看实时内存：数据不落盘、不写入本地文件、不产生测试报告"
                    font.pixelSize: 12
                    color: "#8c8c8c"
                }
                RowLayout {
                    visible: root.kind !== "watch"
                    width: parent.width
                    spacing: 12
                    WText {
                        text: "* 任务名称"
                        Layout.preferredWidth: 84
                        font.pixelSize: 13
                    }
                    WField {
                        id: taskName
                        objectName: "taskNameField"
                        Layout.fillWidth: true
                        text: F.taskName()
                        maximumLength: 80
                        enabled: !root.locked
                        placeholderText: "Task-YYYYMMDD-HHmmss"
                    }
                }
                TargetPicker {
                    id: target
                    width: parent.width
                    locked: root.locked
                    notRunningHint: root.kind === "snap" ? "应用未运行，请先在设备上启动该应用。" : root.kind === "watch" ? "应用未运行，您可以开始查看后，再手动运行该应用。" : "应用未运行，您可以开始采样后，再手动运行该应用。"
                }
                RowLayout {
                    visible: root.kind !== "snap"
                    width: parent.width
                    spacing: 12
                    WText {
                        text: "* 采样间隔"
                        Layout.preferredWidth: 84
                        font.pixelSize: 13
                    }
                    WField {
                        id: interval
                        objectName: "intervalField"
                        Layout.preferredWidth: 92
                        text: "1000"
                        validator: IntValidator {
                            bottom: 0
                            top: 3600000
                        }
                        enabled: !root.locked
                    }
                    WText {
                        text: "毫秒"
                        font.pixelSize: 12
                        color: "#8c8c8c"
                    }
                    Repeater {
                        model: [200, 500, 1000, 2000]
                        WButton {
                            required property int modelData
                            text: modelData + "ms"
                            small: true
                            tone: Number(interval.text) === modelData ? "primary" : "default"
                            enabled: !root.locked
                            onClicked: interval.text = String(modelData)
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                WText {
                    visible: root.kind !== "snap" && Number(interval.text) < 200
                    width: parent.width
                    text: "采样间隔不能低于 200ms（hidumper 单次执行约 100ms，过小会导致采样堆积）"
                    font.pixelSize: 12
                    color: "#ff4d4f"
                }
                RowLayout {
                    visible: root.kind === "peak"
                    width: parent.width
                    spacing: 12
                    WText {
                        text: "* 采样时长"
                        Layout.preferredWidth: 84
                        font.pixelSize: 13
                    }
                    WCombo {
                        id: duration
                        objectName: "durationPicker"
                        Layout.preferredWidth: 290
                        enabled: !root.locked
                        model: ["5 分钟", "10 分钟（默认）", "30 分钟", "1 小时", "2 小时", "不限（不推荐，文件会持续增大）"]
                        currentIndex: 1
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                RowLayout {
                    visible: root.kind !== "watch"
                    width: parent.width
                    spacing: 12
                    WText {
                        text: "高级选项"
                        Layout.preferredWidth: 84
                        Layout.alignment: Qt.AlignTop
                        font.pixelSize: 13
                        height: 26
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 6
                        WCheck {
                            id: ashmem
                            text: "ashmem 明细"
                            enabled: !root.locked
                        }
                        WCheck {
                            id: dmabuf
                            text: "dmabuf 明细"
                            enabled: !root.locked
                        }
                        WCheck {
                            id: gpumem
                            text: "gpumem 明细"
                            enabled: !root.locked
                        }
                        WCheck {
                            id: smaps
                            visible: root.kind === "snap"
                            text: "含 smaps 明细（逐 VMA，较慢）"
                            enabled: !root.locked
                        }
                    }
                }
                WText {
                    visible: backend.sampling
                    width: parent.width
                    text: "已有采样任务进行中，请先在实时页结束当前采样"
                    color: "#d48806"
                    font.pixelSize: 12
                }
                WButton {
                    objectName: "startButton"
                    width: parent.width
                    height: 40
                    text: root.kind === "watch" ? "◉ 开始查看" : root.kind === "snap" ? "📷 拍摄快照" : "▷ 开始采样"
                    tone: root.kind === "watch" ? "green" : "primary"
                    enabled: !root.locked && !!target.selectedApp && (root.kind === "watch" || taskName.text.trim().length > 0) && (root.kind === "snap" ? !!target.selectedApp.pid : Number(interval.text) >= 200)
                    onClicked: {
                        var a = target.selectedApp, options = {
                            showAshmem: ashmem.checked,
                            showDmabuf: dmabuf.checked,
                            showGpumem: gpumem.checked,
                            includeSmaps: smaps.checked
                        };
                        if (root.kind === "snap")
                            backend.takeSnapshot(a.bundleName, a.label || a.bundleName, taskName.text, options);
                        else
                            backend.startSampling({
                                intervalMs: Number(interval.text),
                                maxDurationMs: root.kind === "peak" ? [300000, 600000, 1800000, 3600000, 7200000, 0][duration.currentIndex] : 0,
                                showAshmem: root.kind === "peak" && ashmem.checked,
                                showDmabuf: root.kind === "peak" && dmabuf.checked,
                                showGpumem: root.kind === "peak" && gpumem.checked
                            }, a.bundleName, a.label || a.bundleName, root.kind === "peak", root.kind === "peak" ? taskName.text : "");
                    }
                }
            }
        }
        WCard {
            visible: backend.snapshotting
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(720, parent.width)
            height: 280
            title: "📷 正在采集内存快照"
            Column {
                anchors.centerIn: parent
                spacing: 18
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: backend.snapshotting
                }
                WText {
                    text: "正在执行 hidumper --mem，请稍候…"
                }
                WText {
                    text: "采集完成后将自动打开快照报告"
                    font.pixelSize: 12
                    color: "#8c8c8c"
                }
            }
        }
    }
}
