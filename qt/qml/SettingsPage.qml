import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "Theme.js" as T

ColumnLayout {
    id: root
    objectName: "settingsPage"
    property string selectedDirectory: backend.sessionsDir
    property bool automatic: backend.hdcPath.length === 0
    property bool pathValid: automatic || backend.toolPathExists(hdc.text)
    spacing: 18
    WText {
        text: "设置"
        font.pixelSize: 20
        font.weight: Font.DemiBold
    }
    WCard {
        Layout.fillWidth: true
        Layout.maximumWidth: 840
        implicitHeight: 130
        title: "报告存储"
        RowLayout {
            anchors.fill: parent
            spacing: 12
            WText {
                text: "保存目录"
                Layout.preferredWidth: 72
            }
            WField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.selectedDirectory || backend.defaultSessionsDir
                readOnly: true
            }
            WButton {
                text: "浏览…"
                onClicked: choose.open()
            }
            WButton {
                text: "恢复默认"
                onClicked: root.selectedDirectory = ""
            }
        }
    }
    WCard {
        Layout.fillWidth: true
        Layout.maximumWidth: 840
        implicitHeight: 222
        title: "设备工具"
        Column {
            width: parent.width
            spacing: 16
            Row {
                spacing: 0
                WButton {
                    text: "自动查找"
                    width: 150
                    tone: root.automatic ? "selected" : "default"
                    onClicked: root.automatic = true
                }
                WButton {
                    text: "手动指定"
                    width: 150
                    tone: !root.automatic ? "selected" : "default"
                    onClicked: root.automatic = false
                }
            }
            RowLayout {
                width: parent.width
                spacing: 12
                WText {
                    text: "hdc 路径"
                    Layout.preferredWidth: 72
                }
                WField {
                    id: hdc
                    objectName: "hdcPathField"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    enabled: !root.automatic
                    text: backend.hdcPath
                    placeholderText: root.automatic ? "启动时从 SDK 和系统路径查找" : "选择 hdc 可执行文件"
                }
                WButton {
                    text: "浏览…"
                    enabled: !root.automatic
                    onClicked: toolFile.open()
                }
            }
            WText {
                visible: !root.automatic
                x: 84
                text: root.pathValid ? "可执行文件存在" : "请选择有效的可执行文件"
                color: root.pathValid ? T.accent : T.error
                font.pixelSize: 12
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: 840
        Item {
            Layout.fillWidth: true
        }
        WButton {
            text: "取消更改"
            onClicked: {
                root.selectedDirectory = backend.sessionsDir;
                hdc.text = backend.hdcPath;
                root.automatic = !backend.hdcPath.length;
            }
        }
        WButton {
            objectName: "saveSettingsButton"
            text: "保存设置"
            tone: "primary"
            enabled: root.pathValid
            onClicked: {
                var path = root.automatic ? "" : hdc.text.trim();
                if (path !== backend.hdcPath)
                    backend.saveHdcPath(path);
                if (root.selectedDirectory !== backend.sessionsDir)
                    backend.saveSessionsDir(root.selectedDirectory);
                root.Window.window.notify("设置已保存");
            }
        }
    }
    Item {
        Layout.fillHeight: true
    }
    FolderDialog {
        id: choose
        title: "选择报告存储目录"
        onAccepted: root.selectedDirectory = backend.fromFileUrl(selectedFolder)
    }
    FileDialog {
        id: toolFile
        title: "选择 hdc 可执行文件"
        fileMode: FileDialog.OpenFile
        onAccepted: hdc.text = backend.fromFileUrl(selectedFile)
    }
}
