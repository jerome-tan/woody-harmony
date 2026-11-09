import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F
import "Theme.js" as T

Item {
    id: root
    objectName: "toolPage"
    property string kind: "peak"
    property bool advanced: false
    readonly property bool locked: backend.sampling || backend.snapshotting
    readonly property string pageTitle: kind === "watch" ? "实时查看" : kind === "snap" ? "内存快照" : "持续采样"
    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        WText {
            text: root.pageTitle
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
        WText {
            text: root.kind === "watch" ? "即时观察内存，不保存报告。" : root.kind === "snap" ? "记录当前时刻的内存构成。" : "按间隔记录，结束后生成报告。"
            color: T.muted
            font.pixelSize: 12
        }
        ScrollView {
            id: formScroll
            objectName: "formScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !backend.snapshotting
            clip: true
            Column {
                width: formScroll.availableWidth
                spacing: 16
                WCard {
                    width: parent.width
                    height: target.implicitHeight + 76
                    title: "设备与应用"
                    headerColor: T.sectionHeader
                    TargetPicker {
                        id: target
                        width: parent.width
                        locked: root.locked
                        notRunningHint: root.kind === "snap" ? "请先在设备上启动该应用。" : "开始后将等待应用启动。"
                    }
                }
                WCard {
                    width: parent.width
                    height: settings.implicitHeight + 76
                    title: root.kind === "watch" ? "查看设置" : "采集设置"
                    headerColor: T.sectionHeader
                    Column {
                        id: settings
                        width: parent.width
                        spacing: 16
                        RowLayout {
                            visible: root.kind !== "watch"
                            width: parent.width
                            spacing: 16
                            WText {
                                text: "报告名称"
                                Layout.preferredWidth: 80
                            }
                            WField {
                                id: taskName
                                objectName: "taskNameField"
                                Layout.fillWidth: true
                                text: F.taskName()
                                maximumLength: 80
                                enabled: !root.locked
                            }
                        }
                        RowLayout {
                            visible: root.kind !== "snap"
                            width: parent.width
                            spacing: 10
                            WText {
                                text: root.kind === "watch" ? "刷新间隔" : "采样间隔"
                                Layout.preferredWidth: 86
                            }
                            WField {
                                id: interval
                                objectName: "intervalField"
                                Layout.preferredWidth: 100
                                text: "1000"
                                validator: IntValidator {
                                    bottom: 0
                                    top: 3600000
                                }
                                enabled: !root.locked
                                Accessible.name: "采样间隔（毫秒）"
                            }
                            WText {
                                text: "ms"
                                color: T.muted
                            }
                            Repeater {
                                model: [200, 500, 1000, 2000]
                                WButton {
                                    required property int modelData
                                    text: String(modelData)
                                    Layout.fillWidth: true
                                    tone: Number(interval.text) === modelData ? "selected" : "default"
                                    enabled: !root.locked
                                    onClicked: interval.text = String(modelData)
                                }
                            }
                        }
                        WText {
                            visible: root.kind !== "snap" && Number(interval.text) < 200
                            text: "间隔需大于或等于 200 ms"
                            color: T.error
                            font.pixelSize: 12
                        }
                        RowLayout {
                            visible: root.kind === "peak"
                            width: parent.width
                            spacing: 16
                            WText {
                                text: "采样时长"
                                Layout.preferredWidth: 80
                            }
                            WCombo {
                                id: duration
                                objectName: "durationPicker"
                                Layout.preferredWidth: 240
                                model: ["5 分钟", "10 分钟", "30 分钟", "1 小时", "2 小时", "不限时"]
                                currentIndex: 1
                                enabled: !root.locked
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                        }
                        WButton {
                            objectName: "advancedOptions"
                            visible: root.kind !== "watch"
                            text: "高级采集选项"
                            iconName: root.advanced ? "DownOutlined" : "RightOutlined"
                            tone: "quiet"
                            small: true
                            onClicked: root.advanced = !root.advanced
                        }
                        GridLayout {
                            visible: root.kind !== "watch" && root.advanced
                            width: parent.width
                            columns: 2
                            columnSpacing: 36
                            rowSpacing: 12
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
                                text: "smaps 明细"
                                enabled: !root.locked
                            }
                        }
                        WText {
                            visible: smaps.checked && root.advanced && root.kind === "snap"
                            text: "采集 smaps 耗时较长。"
                            color: T.muted
                            font.pixelSize: 12
                        }
                    }
                }
                WText {
                    visible: backend.sampling
                    text: "已有采样任务进行中，请先结束当前采样。"
                    color: T.positive
                    font.pixelSize: 12
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: backend.snapshotting
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: T.border
        }
        RowLayout {
            objectName: "captureFooter"
            Layout.fillWidth: true
            spacing: 16
            WButton {
                visible: root.kind !== "watch"
                iconName: "FolderOutlined"
                tone: "quiet"
                text: "保存至"
                onClicked: backend.revealPath(backend.sessionsDir || backend.defaultSessionsDir)
            }
            WText {
                visible: root.kind !== "watch"
                Layout.fillWidth: true
                text: backend.sessionsDir || backend.defaultSessionsDir
                font.pixelSize: 12
                color: T.muted
            }
            Item {
                visible: root.kind === "watch"
                Layout.fillWidth: true
            }
            WButton {
                objectName: "startButton"
                text: root.kind === "watch" ? "开始查看" : root.kind === "snap" ? "采集快照" : "开始采样"
                iconName: root.kind === "snap" ? "CameraOutlined" : "PlayCircleOutlined"
                tone: "primary"
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
    WDialog {
        id: snapshotProgress
        objectName: "snapshotProgress"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460
        title: "正在采集快照"
        visible: backend.snapshotting
        closePolicy: Popup.NoAutoClose
        property int seconds: 0
        property bool cancelling: false
        onVisibleChanged: if (visible) {
            seconds = 0;
            cancelling = false;
        }
        Timer {
            interval: 1000
            repeat: true
            running: backend.snapshotting
            onTriggered: snapshotProgress.seconds++
        }
        Column {
            width: parent.width
            spacing: 16
            RowLayout {
                width: parent.width
                BusyIndicator {
                    running: backend.snapshotting
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 8
                    WText {
                        text: snapshotProgress.cancelling ? "正在取消…" : "正在读取内存数据…"
                    }
                    WText {
                        text: "已用时 " + snapshotProgress.seconds + " 秒"
                        color: T.muted
                        font.pixelSize: 12
                    }
                }
            }
            WButton {
                objectName: "cancelSnapshotButton"
                anchors.right: parent.right
                text: "取消采集"
                enabled: !snapshotProgress.cancelling
                onClicked: {
                    snapshotProgress.cancelling = true;
                    backend.cancelSnapshot();
                }
            }
        }
    }
}
