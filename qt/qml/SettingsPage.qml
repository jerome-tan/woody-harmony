import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "Theme.js" as T

ScrollView {
    id: root
    objectName: "settingsPage"
    property string selectedDirectory: backend.sessionsDir
    property bool automatic: backend.hdcPath.length === 0
    property bool automaticUpdates: updater.automatic
    property bool pathValid: automatic || backend.toolPathExists(hdc.text)
    readonly property bool compact: width < 660
    clip: true
    ColumnLayout {
        width: root.availableWidth
        spacing: 18
        WText {
            text: "设置"
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
        WCard {
            Layout.fillWidth: true
            Layout.maximumWidth: 840
            implicitHeight: root.compact ? 174 : 130
            title: "报告存储"
            headerColor: T.sectionHeader
            GridLayout {
                anchors.fill: parent
                columns: root.compact ? 2 : 3
                columnSpacing: 12
                rowSpacing: 12
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
                RowLayout {
                    Layout.columnSpan: root.compact ? 2 : 1
                    Layout.alignment: Qt.AlignRight
                    spacing: 12
                    WButton {
                        text: "浏览…"
                        onClicked: choose.open()
                    }
                    WButton {
                        objectName: "openReportsDirectory"
                        text: "打开目录"
                        onClicked: backend.revealPath(root.selectedDirectory || backend.defaultSessionsDir)
                    }
                    WButton {
                        text: "恢复默认"
                        onClicked: root.selectedDirectory = ""
                    }
                }
            }
        }
        WCard {
            Layout.fillWidth: true
            Layout.maximumWidth: 840
            implicitHeight: root.compact ? 266 : 222
            title: "设备工具"
            headerColor: T.sectionHeader
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
                GridLayout {
                    width: parent.width
                    columns: root.compact ? 2 : 3
                    columnSpacing: 12
                    rowSpacing: 12
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
                    RowLayout {
                        Layout.columnSpan: root.compact ? 2 : 1
                        Layout.alignment: Qt.AlignRight
                        spacing: 12
                        WButton {
                            text: "浏览…"
                            enabled: !root.automatic
                            onClicked: toolFile.open()
                        }
                        WButton {
                            objectName: "openHdcDirectory"
                            text: "打开目录"
                            enabled: backend.toolPathExists(root.automatic ? backend.hdcPath : hdc.text)
                            onClicked: backend.revealFileDirectory(root.automatic ? backend.hdcPath : hdc.text)
                        }
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
        WCard {
            Layout.fillWidth: true
            Layout.maximumWidth: 840
            implicitHeight: 112
            title: "软件更新"
            headerColor: T.sectionHeader
            RowLayout {
                anchors.fill: parent
                WCheck {
                    objectName: "automaticUpdates"
                    text: "启动时检查更新"
                    checked: root.automaticUpdates
                    onClicked: root.automaticUpdates = checked
                }
                Item {
                    Layout.fillWidth: true
                }
                WButton {
                    objectName: "checkUpdates"
                    text: "检查更新"
                    onClicked: updater.check()
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
                    root.automaticUpdates = updater.automatic;
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
                    updater.automatic = root.automaticUpdates;
                    root.Window.window.notify("设置已保存");
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
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
