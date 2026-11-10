import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Theme.js" as T

Column {
    id: root
    objectName: "targetPicker"
    readonly property string selectedBundle: backend.selectedBundle
    property string pendingBundle: ""
    property bool locked: false
    readonly property var selectedApp: backend.apps.find(function (a) {
        return a.bundleName === selectedBundle;
    }) || null
    // Keep delegate identities while background queries update their roles.
    // A fresh JS array as ListView.model resets the view on every reply.
    ListModel { id: appRows }
    function syncAppRows(reset) {
        if (!appDialog.visible)
            return;
        var query = appSearch.text.toLowerCase();
        var apps = backend.apps.filter(function (a) {
            return a.bundleName.toLowerCase().indexOf(query) >= 0;
        });
        var byBundle = {};
        apps.forEach(function (a) { byBundle[a.bundleName] = a; });
        if (reset)
            appRows.clear();
        for (var i = appRows.count - 1; i >= 0; --i) {
            if (!byBundle[appRows.get(i).bundleName])
                appRows.remove(i);
        }
        var existing = {};
        for (var row = 0; row < appRows.count; ++row)
            existing[appRows.get(row).bundleName] = row;
        apps.forEach(function (a) {
            var roles = {
                bundleName: a.bundleName,
                pid: Number(a.pid) || 0
            };
            var index = existing[a.bundleName];
            if (index === undefined) {
                appRows.append(roles);
            } else {
                // Do not reorder running apps underneath the user's pointer.
                // Refresh their initial ordering when the dialog is reopened.
                if (appRows.get(index).pid !== roles.pid)
                    appRows.setProperty(index, "pid", roles.pid);
            }
        });
        if (reset)
            appList.positionViewAtBeginning();
    }
    property string notRunningHint: "开始后将等待应用启动。"
    spacing: 16
    Connections {
        target: backend
        function onAppsChanged() { root.syncAppRows(false); }
        function onDeviceChanged() {
            if (!backend.target.length) {
                root.pendingBundle = "";
                appDialog.close();
            }
        }
    }
    RowLayout {
        width: parent.width
        spacing: 12
        WText {
            text: "目标设备"
            Layout.preferredWidth: 84
        }
        WCombo {
            id: devices
            objectName: "devicePicker"
            Layout.fillWidth: true
            enabled: !root.locked
            textRole: "label"
            valueRole: "value"
            model: {
                var info = backend.deviceInfo;
                return backend.devices.map(function (d) {
                    var name = d.targetId === backend.target ? (info.marketName || info.model || "") : "";
                    return {
                        value: d.targetId,
                        label: name && name !== d.targetId ? name + " · " + d.targetId : d.targetId
                    };
                });
            }
            currentIndex: backend.devices.findIndex(function (d) {
                return d.targetId === backend.target;
            })
            displayText: currentIndex >= 0 && model[currentIndex] ? model[currentIndex].label
                         : backend.devices.length ? "设备通信尚未就绪，请稍后刷新" : "未检测到设备"
            onActivated: function (index) {
                backend.selectDevice(model[index].value);
            }
        }
        WButton {
            iconName: "ReloadOutlined"
            hint: "刷新设备"
            enabled: !root.locked && !backend.discovering
            onClicked: backend.refreshDevices()
        }
    }
    RowLayout {
        visible: backend.target.length === 0
        width: parent.width
        WText {
            Layout.fillWidth: true
            text: "连接设备并开启 USB 调试。"
            color: T.muted
            font.pixelSize: 12
        }
        WButton {
            text: "设备设置"
            small: true
            onClicked: root.Window.window.go("settings")
        }
    }
    RowLayout {
        width: parent.width
        spacing: 12
        WText {
            text: "目标应用"
            Layout.preferredWidth: 84
        }
        WButton {
            id: appButton
            objectName: "appPicker"
            Layout.fillWidth: true
            implicitHeight: Math.max(40, selectedBundleLabel.implicitHeight + 16)
            text: root.selectedBundle || "请选择应用"
            enabled: !root.locked && backend.target.length > 0
            Accessible.name: text + (root.selectedApp ? "，" + selectedDebug.text + "，" + selectedStatus.text : "")
            contentItem: RowLayout {
                spacing: 12
                WText {
                    id: selectedBundleLabel
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: appButton.text
                    color: appButton.enabled ? T.text : T.disabled
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                }
                AppDebugTag {
                    id: selectedDebug
                    objectName: "selectedAppDebug"
                    application: root.selectedApp
                }
                AppStatusTag {
                    id: selectedStatus
                    objectName: "selectedAppStatus"
                    application: root.selectedApp
                }
                WIcon {
                    name: "DownOutlined"
                    tone: "muted"
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                }
            }
            onClicked: {
                root.pendingBundle = root.selectedBundle;
                appSearch.text = "";
                appDialog.open();
                backend.refreshApps();
                appSearch.forceActiveFocus();
            }
        }
    }
    WText {
        visible: !!root.selectedApp && !root.selectedApp.pid
        x: 96
        width: parent.width - 96
        text: root.notRunningHint
        color: T.muted
        font.pixelSize: 12
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    WDialog {
        id: appDialog
        objectName: "appDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 48)
        height: Math.min(550, parent.height - 48)
        title: "选择应用"
        standardButtons: Dialog.Ok | Dialog.Cancel
        acceptText: "选择应用"
        acceptEnabled: backend.apps.some(function (a) {
            return a.bundleName === root.pendingBundle;
        })
        onOpened: root.syncAppRows(true)
        onAccepted: backend.selectApp(root.pendingBundle)
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                WField {
                    id: appSearch
                    objectName: "appSearch"
                    Layout.fillWidth: true
                    placeholderText: "搜索完整包名"
                    onTextChanged: root.syncAppRows(true)
                }
                WButton {
                    iconName: "ReloadOutlined"
                    hint: "刷新应用列表"
                    enabled: !backend.loadingApps
                    onClicked: backend.refreshApps()
                }
            }
            ListView {
                id: appList
                objectName: "appList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                model: appRows
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    id: appRow
                    objectName: "app-" + bundleName
                    required property string bundleName
                    required property int pid
                    function confirmSelection() {
                        root.pendingBundle = bundleName;
                        if (appDialog.acceptEnabled)
                            appDialog.accept();
                    }
                    readonly property var application: ({
                        bundleName: bundleName, pid: pid
                    })
                    width: appList.width
                    height: Math.max(52, appBundleLabel.implicitHeight + 12)
                    topPadding: 6
                    bottomPadding: 6
                    background: Rectangle {
                        radius: 5
                        color: root.pendingBundle === appRow.bundleName ? T.selected : appRow.hovered ? T.chrome : "white"
                    }
                    contentItem: RowLayout {
                        spacing: 12
                        RadioButton {
                            checked: root.pendingBundle === appRow.bundleName
                            onClicked: root.pendingBundle = appRow.bundleName
                            onDoubleClicked: appRow.confirmSelection()
                            Accessible.name: appRow.bundleName
                        }
                        WText {
                            id: appBundleLabel
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: appRow.bundleName
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideNone
                        }
                        AppStatusTag {
                            application: appRow.application
                        }
                    }
                    onClicked: root.pendingBundle = bundleName
                    onDoubleClicked: confirmSelection()
                }
                WText {
                    anchors.centerIn: parent
                    visible: appList.count === 0
                    text: backend.loadingApps ? "正在获取应用列表…" : "暂无匹配应用"
                    color: T.muted
                }
            }
            WText {
                text: appList.count + " 个应用"
                color: T.muted
                font.pixelSize: 12
            }
        }
    }
}
