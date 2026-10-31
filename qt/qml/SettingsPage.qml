import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: root
    property string selectedDirectory: backend.sessionsDir
    Column {
        width: Math.min(640, parent.width)
        spacing: 16
        WText {
            text: "设置"
            font.pixelSize: 20
            font.bold: true
        }
        WCard {
            width: parent.width
            height: 294
            title: "存储与工具链"
            Column {
                width: parent.width
                spacing: 18
                Column {
                    width: parent.width
                    spacing: 4
                    WText {
                        text: "报告默认存储路径"
                        font.pixelSize: 12
                        color: "#8c8c8c"
                    }
                    RowLayout {
                        width: parent.width
                        spacing: 0
                        WField {
                            Layout.fillWidth: true
                            text: root.selectedDirectory
                            placeholderText: backend.defaultSessionsDir
                            readOnly: true
                        }
                        WButton {
                            text: "选择…"
                            onClicked: choose.open()
                        }
                        WButton {
                            text: "恢复默认"
                            enabled: root.selectedDirectory.length > 0
                            onClicked: root.selectedDirectory = ""
                        }
                    }
                    WText {
                        width: parent.width
                        text: "留空则使用默认路径；目录变更后报告列表自动按新路径重新扫描。"
                        font.pixelSize: 12
                        color: "#8c8c8c"
                    }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    WText {
                        text: "hdc 可执行文件路径"
                        font.pixelSize: 12
                        color: "#8c8c8c"
                    }
                    WField {
                        id: hdc
                        width: parent.width
                        text: backend.hdcPath
                        placeholderText: "留空则自动查找（PATH / 常见安装目录）"
                    }
                    WText {
                        width: parent.width
                        text: "hdc 来自 HarmonyOS SDK / DevEco Studio，用于与设备通信执行 hidumper。"
                        font.pixelSize: 12
                        color: "#8c8c8c"
                    }
                }
                WButton {
                    text: "保存设置"
                    tone: "primary"
                    onClicked: {
                        if (hdc.text.trim() !== backend.hdcPath)
                            backend.saveHdcPath(hdc.text);
                        if (root.selectedDirectory !== backend.sessionsDir)
                            backend.saveSessionsDir(root.selectedDirectory);
                        root.Window.window.notify("设置已保存");
                    }
                }
            }
        }
    }
    FolderDialog {
        id: choose
        title: "选择报告存储目录"
        onAccepted: root.selectedDirectory = backend.fromFileUrl(selectedFolder)
    }
}
