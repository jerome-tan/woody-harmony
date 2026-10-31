import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

WindowBase {
    id: appWindow
    objectName: "mainWindow"
    visible: true
    width: 1280
    height: 820
    minimumWidth: 1024
    minimumHeight: 680
    mainWindow: true
    caption: "Woody"
    captionNote: backend.target ? F.device(backend.deviceInfo, backend.target) : "未连接设备"
    property string page: "home"
    property bool watching: false
    property var childWindows: []
    function go(next) {
        page = next;
        if (next === "reports")
            backend.refreshRecords();
    }
    function openReportObject(report) {
        var w = reportWindow.createObject(appWindow, {
            report: report,
            visible: true
        });
        childWindows = childWindows.concat([w]);
        w.raise();
        w.requestActivate();
    }
    function openCompareObjects(reports) {
        var w = compareWindow.createObject(appWindow, {
            reports: reports,
            visible: true
        });
        childWindows = childWindows.concat([w]);
        w.raise();
        w.requestActivate();
    }
    function forgetWindow(window) {
        childWindows = childWindows.filter(function (w) {
            return w !== window;
        });
    }
    onClosing: function (close) {
        close.accepted = false;
        backend.requestQuit();
    }
    Rectangle {
        width: 172
        height: parent.height
        color: "white"
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: "#f0f0f0"
        }
        Column {
            x: 10
            y: 14
            width: 152
            spacing: 18
            Row {
                x: 12
                spacing: 10
                height: 46
                Image {
                    source: "qrc:/assets/icon.png"
                    width: 38
                    height: 38
                }
                Column {
                    spacing: 4
                    WText {
                        text: "Woody"
                        font.pixelSize: 15
                        font.bold: true
                    }
                    WText {
                        text: "v" + buildInfo.version
                        font.pixelSize: 10
                        color: "#8c8c8c"
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        {
                            key: "home",
                            icon: "⌂",
                            label: "首页"
                        },
                        {
                            key: "tools",
                            icon: "▦",
                            label: "工具集"
                        },
                        {
                            key: "reports",
                            icon: "▤",
                            label: "查看报告"
                        },
                        {
                            key: "settings",
                            icon: "⚙",
                            label: "设置"
                        }
                    ]
                    Rectangle {
                        required property var modelData
                        width: 152
                        height: 40
                        radius: 8
                        property bool selected: appWindow.page === modelData.key || (modelData.key === "tools" && ["watch", "peak", "snap", "live"].indexOf(appWindow.page) >= 0)
                        color: selected ? "#e6f4ff" : navHover.hovered ? "#f5f5f5" : "transparent"
                        WText {
                            x: 14
                            width: 124
                            height: 40
                            text: modelData.icon + "   " + modelData.label
                            color: parent.selected ? "#1677ff" : "#595959"
                            font.pixelSize: 13
                        }
                        HoverHandler {
                            id: navHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: appWindow.go(modelData.key)
                        }
                    }
                }
                WButton {
                    visible: backend.sampling
                    width: 152
                    text: appWindow.watching ? "● 返回实时查看" : "● 返回采样"
                    tone: "primary"
                    small: true
                    onClicked: appWindow.go("live")
                }
            }
        }
        WText {
            x: 20
            y: parent.height - 45
            width: 130
            text: "HarmonyOS 内存工具"
            font.pixelSize: 10
            color: "#bfbfbf"
        }
    }
    Item {
        x: 196
        y: 20
        width: parent.width - 220
        height: parent.height - 52
        HomePage {
            anchors.fill: parent
            visible: appWindow.page === "home" || appWindow.page === "tools"
            toolsOnly: appWindow.page === "tools"
            onNavigate: function (page) {
                appWindow.go(page);
            }
        }
        Loader {
            anchors.fill: parent
            active: ["watch", "peak", "snap"].indexOf(appWindow.page) >= 0
            sourceComponent: Component {
                ToolPage {
                    kind: appWindow.page
                    onBack: appWindow.go("tools")
                }
            }
        }
        LivePage {
            anchors.fill: parent
            visible: appWindow.page === "live"
            watch: appWindow.watching
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
                appWindow.forgetWindow(this);
                Qt.callLater(destroy);
            }
        }
    }
    Component {
        id: compareWindow
        CompareWindow {
            onClosing: {
                appWindow.forgetWindow(this);
                Qt.callLater(destroy);
            }
        }
    }
    Connections {
        target: backend
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
                appWindow.notify("已到设定时长，采样报告已保存");
        }
    }
}
