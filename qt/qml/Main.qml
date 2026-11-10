import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

WindowBase {
    id: appWindow
    extraModalOpen: quitDialog.opened
    objectName: "mainWindow"
    // main.cpp sizes and centers the native frame before showing it.
    visible: false
    initialWidth: 1000
    initialHeight: 740
    minimumWidth: 720
    minimumHeight: 560
    mainWindow: true
    caption: "Woody"
    captionNote: backend.target ? F.device(backend.deviceInfo, backend.target) : "未连接设备"
    property string page: "watch"
    property bool watching: false
    property bool quitting: false
    property var childWindows: []
    function go(next) {
        if (next === "home" || next === "tools")
            next = "watch";
        if (backend.sampling && next === (watching ? "watch" : "peak"))
            next = "live";
        page = next;
        if (next === "reports")
            backend.refreshRecords();
    }
    function openReportObject(report) {
        var w = reportWindow.createObject(appWindow, {
            report: report
        });
        childWindows = childWindows.concat([w]);
        backend.showWindowCentered(w, appWindow);
    }
    function openCompareObjects(reports) {
        var w = compareWindow.createObject(appWindow, {
            reports: reports
        });
        childWindows = childWindows.concat([w]);
        backend.showWindowCentered(w, appWindow);
    }
    function forgetWindow(window) {
        childWindows = childWindows.filter(function (w) {
            return w !== window;
        });
    }
    function requestQuit() {
        if (backend.sampling || backend.snapshotting) {
            quitDialog.open();
            appWindow.raise();
            appWindow.requestActivate();
        } else
            backend.requestQuit();
    }
    WDialog {
        id: quitDialog
        objectName: "quitDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 480
        title: backend.snapshotting ? "采集尚未结束" : appWindow.watching ? "监测尚未结束" : "录制尚未结束"
        standardButtons: Dialog.Ok | Dialog.Cancel
        acceptText: backend.snapshotting ? "取消采集并退出" : appWindow.watching ? "结束监测并退出" : "结束录制并退出"
        rejectText: backend.snapshotting ? "继续采集" : appWindow.watching ? "继续监测" : "继续录制"
        WText {
            width: parent.width
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: backend.snapshotting ? "取消当前快照采集后退出。" : appWindow.watching ? "内存监测的数据不会保存为报告。" : "结束录制并保存报告后再退出。"
        }
        onAccepted: {
            if (backend.snapshotting)
                backend.cancelSnapshot();
            backend.requestQuit();
        }
    }
    onClosing: function (close) {
        if (quitting) {
            close.accepted = true;
            return;
        }
        close.accepted = false;
        appWindow.requestQuit();
    }
    Rectangle {
        id: sidebar
        objectName: "sidebar"
        width: appWindow.width < 1000 ? 160 : 180
        height: parent.height
        color: T.chrome
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: T.border
        }
        Column {
            x: 12
            y: 24
            width: parent.width - 24
            spacing: 8
            WText {
                x: 12
                height: 28
                text: "工具"
                font.pixelSize: 12
                color: T.muted
            }
            Repeater {
                id: toolNavigation
                model: [
                    {
                        key: "watch",
                        icon: "EyeOutlined",
                        label: "内存监测"
                    },
                    {
                        key: "snap",
                        icon: "CameraOutlined",
                        label: "内存快照"
                    },
                    {
                        key: "peak",
                        icon: "LineChartOutlined",
                        label: "内存录制"
                    }
                ]
                WButton {
                    required property var modelData
                    required property int index
                    objectName: "nav-" + modelData.key
                    width: sidebar.width - 24
                    height: 42
                    text: modelData.label
                    iconName: modelData.icon
                    textAlignment: Text.AlignLeft
                    readonly property bool selected: appWindow.page === modelData.key || (appWindow.page === "live" && modelData.key === (appWindow.watching ? "watch" : "peak"))
                    tone: selected ? "selected" : "quiet"
                    onClicked: appWindow.go(modelData.key)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 3
                        color: T.accent
                        visible: backend.sampling && modelData.key === (appWindow.watching ? "watch" : "peak")
                    }
                    Rectangle {
                        x: 12
                        y: parent.height + 4
                        width: parent.width - 24
                        height: 1
                        color: T.border
                        opacity: .65
                        visible: index < toolNavigation.count - 1
                    }
                }
            }
            Item {
                width: sidebar.width - 24
                height: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: T.border
                }
            }
            WButton {
                id: reportsButton
                objectName: "nav-reports"
                width: sidebar.width - 24
                height: 42
                text: "报告库"
                iconName: "FolderOutlined"
                textAlignment: Text.AlignLeft
                rightPadding: reportCount.width + 20
                tone: appWindow.page === "reports" ? "selected" : "quiet"
                Accessible.name: "报告库，" + backend.records.length + " 份报告"
                onClicked: appWindow.go("reports")
                WTag {
                    id: reportCount
                    objectName: "reportCountBadge"
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(22, implicitWidth)
                    text: String(backend.records.length)
                    ink: reportsButton.tone === "selected" ? T.accent : T.muted
                    tint: reportsButton.tone === "selected" ? "white" : T.chrome
                }
            }
        }
        WButton {
            objectName: "nav-settings"
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: sidebar.width - 24
            height: 42
            text: "设置"
            iconName: "SettingOutlined"
            textAlignment: Text.AlignLeft
            tone: appWindow.page === "settings" ? "selected" : "quiet"
            onClicked: appWindow.go("settings")
        }
    }
    Item {
        x: sidebar.width + (appWindow.width < 1100 ? 16 : 24)
        y: 24
        width: parent.width - x - (appWindow.width < 1100 ? 16 : 24)
        height: parent.height - 40
        Loader {
            anchors.fill: parent
            active: ["watch", "peak", "snap"].indexOf(appWindow.page) >= 0
            sourceComponent: Component {
                ToolPage {
                    kind: appWindow.page
                }
            }
        }
        Loader {
            anchors.fill: parent
            active: appWindow.page === "live"
            sourceComponent: Component {
                LivePage {
                    watch: appWindow.watching
                }
            }
        }
        Loader {
            anchors.fill: parent
            active: appWindow.page === "reports"
            sourceComponent: Component {
                ReportsPage {}
            }
        }
        Loader {
            anchors.fill: parent
            active: appWindow.page === "settings"
            sourceComponent: Component {
                SettingsPage {}
            }
        }
    }
    Component {
        id: reportWindow
        ReportWindow {
            onClosing: {
                rememberMaximizedState();
                appWindow.forgetWindow(this);
                Qt.callLater(destroy);
            }
        }
    }
    Component {
        id: compareWindow
        CompareWindow {
            onClosing: {
                rememberMaximizedState();
                appWindow.forgetWindow(this);
                Qt.callLater(destroy);
            }
        }
    }
    Connections {
        target: backend
        function onQuitRequested() {
            appWindow.requestQuit();
        }
        function onQuitReady() {
            appWindow.childWindows.forEach(function (window) {
                window.rememberMaximizedState();
            });
            appWindow.quitting = true;
        }
        function onReportOpened(report) {
            appWindow.openReportObject(report);
        }
        function onCompareOpened(reports) {
            appWindow.openCompareObjects(reports);
        }
        function onSamplingStarted(persist) {
            appWindow.watching = !persist;
            appWindow.go("live");
        }
        function onSamplingFinished(persist, directory, automatic) {
            if (appWindow.page === "live")
                appWindow.go(persist ? "peak" : "watch");
            if (automatic)
                appWindow.notify("已到设定时长，内存录制报告已保存");
        }
    }
}
