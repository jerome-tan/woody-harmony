import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

Column {
    id: root
    property string selectedBundle: ""
    property bool locked: false
    readonly property var selectedApp: backend.apps.find(function (a) {
        return a.bundleName === selectedBundle;
    }) || null
    property string notRunningHint: "应用未运行，您可以开始采样后，再手动运行该应用。"
    spacing: 14
    function selectDefault() {
        if (!selectedApp) {
            var running = backend.apps.find(function (a) {
                return a.pid;
            });
            selectedBundle = running ? running.bundleName : "";
        }
    }
    Component.onCompleted: selectDefault()
    Connections {
        target: backend
        function onAppsChanged() {
            root.selectDefault();
        }
    }
    Timer {
        interval: 1500
        repeat: true
        running: root.visible && backend.target.length > 0 && !root.locked
        onTriggered: backend.refreshApps()
    }
    RowLayout {
        width: parent.width
        spacing: 12
        WText {
            text: "* 目标设备"
            Layout.preferredWidth: 84
            font.pixelSize: 13
        }
        WCombo {
            id: devices
            objectName: "devicePicker"
            Layout.fillWidth: true
            enabled: !root.locked
            textRole: "label"
            valueRole: "value"
            model: backend.devices.map(function (d) {
                return {
                    value: d.targetId,
                    label: d.targetId === backend.target ? F.device(backend.deviceInfo, d.targetId) : d.targetId
                };
            })
            currentIndex: backend.devices.findIndex(function (d) {
                return d.targetId === backend.target;
            })
            displayText: currentIndex >= 0 ? textAt(currentIndex) : "未检测到设备"
            onActivated: function (index) {
                root.selectedBundle = "";
                backend.selectDevice(model[index].value);
            }
        }
        WButton {
            text: backend.discovering ? "…" : "↻"
            hint: "刷新设备"
            enabled: !root.locked && !backend.discovering
            onClicked: backend.refreshDevices()
        }
    }
    RowLayout {
        width: parent.width
        spacing: 12
        WText {
            text: "* 目标应用"
            Layout.preferredWidth: 84
            font.pixelSize: 13
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 8
        }
        Column {
            Layout.fillWidth: true
            spacing: 5
            WButton {
                id: appButton
                objectName: "appPicker"
                width: parent.width
                text: root.selectedApp ? root.selectedApp.bundleName : "请选择应用"
                enabled: !root.locked && backend.target.length > 0
                onClicked: {
                    appSearch.text = "";
                    appPopup.open();
                    backend.refreshApps();
                    appSearch.forceActiveFocus();
                }
            }
            WTag {
                visible: !!root.selectedApp && !!root.selectedApp.pid
                text: root.selectedApp ? "运行中 · PID " + root.selectedApp.pid : ""
                ink: "#389e0d"
                tint: "#f6ffed"
            }
            WText {
                visible: !!root.selectedApp && !root.selectedApp.pid
                width: parent.width
                text: root.notRunningHint
                color: "#ff4d4f"
                font.pixelSize: 12
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
    }
    Popup {
        id: appPopup
        parent: appButton
        y: appButton.height + 4
        width: Math.max(340, appButton.width)
        height: Math.min(360, appList.contentHeight + 58)
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 6
            color: "white"
            border.color: "#d9d9d9"
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                WField {
                    id: appSearch
                    Layout.fillWidth: true
                    placeholderText: "搜索应用包名"
                }
                WButton {
                    text: backend.loadingApps ? "…" : "↻"
                    hint: "刷新应用列表"
                    onClicked: backend.refreshApps()
                }
            }
            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: backend.apps.filter(function (a) {
                    return a.bundleName.toLowerCase().indexOf(appSearch.text.toLowerCase()) >= 0;
                })
                reuseItems: true
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: appList.width
                    height: 43
                    background: Rectangle {
                        color: root.selectedBundle === modelData.bundleName ? "#e6f4ff" : parent.hovered ? "#f5f5f5" : "white"
                        radius: 4
                    }
                    contentItem: RowLayout {
                        WText {
                            Layout.fillWidth: true
                            text: modelData.bundleName
                            font.pixelSize: 12
                        }
                        WTag {
                            visible: !!modelData.pid
                            text: "PID " + modelData.pid
                            ink: "#389e0d"
                            tint: "#f6ffed"
                        }
                    }
                    onClicked: {
                        root.selectedBundle = modelData.bundleName;
                        appPopup.close();
                    }
                }
                WText {
                    anchors.centerIn: parent
                    visible: appList.count === 0
                    text: backend.loadingApps ? "正在获取应用列表…" : "暂无匹配应用"
                    color: "#8c8c8c"
                    font.pixelSize: 12
                }
            }
        }
    }
}
