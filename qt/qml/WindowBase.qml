import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: win
    property string caption: "Woody"
    property string badge: ""
    property string captionNote: ""
    property bool mainWindow: false
    default property alias contents: body.data
    property alias bodyItem: body
    property string renameDirectory: ""
    property string messageText: ""
    title: caption.length ? caption + " · Woody" : "Woody"
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 480
    color: "#f4f5fa"
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    flags: Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint
    function edit(action) {
        var item = activeFocusItem;
        if (item && typeof item[action] === "function")
            item[action]();
    }
    function toggleMaximize() {
        visibility === Window.Maximized ? showNormal() : showMaximized();
    }
    function rename(directory, name) {
        renameDirectory = directory;
        renameField.text = name;
        renameDialog.open();
        renameField.forceActiveFocus();
        renameField.selectAll();
    }
    function notify(text) {
        toast.text = text;
        toast.visible = true;
        toastTimer.restart();
    }
    menuBar: MenuBar {
        visible: Qt.platform.os === "osx"
        Menu {
            title: "Woody"
            Action {
                text: "关于 Woody"
                onTriggered: about.open()
            }
            MenuSeparator {}
            Action {
                text: "退出 Woody"
                shortcut: StandardKey.Quit
                onTriggered: backend.requestQuit()
            }
        }
        Menu {
            title: "编辑"
            Action {
                text: "撤销"
                shortcut: StandardKey.Undo
                onTriggered: win.edit("undo")
            }
            Action {
                text: "重做"
                shortcut: StandardKey.Redo
                onTriggered: win.edit("redo")
            }
            MenuSeparator {}
            Action {
                text: "剪切"
                shortcut: StandardKey.Cut
                onTriggered: win.edit("cut")
            }
            Action {
                text: "拷贝"
                shortcut: StandardKey.Copy
                onTriggered: win.edit("copy")
            }
            Action {
                text: "粘贴"
                shortcut: StandardKey.Paste
                onTriggered: win.edit("paste")
            }
            Action {
                text: "全选"
                shortcut: StandardKey.SelectAll
                onTriggered: win.edit("selectAll")
            }
        }
        Menu {
            title: "窗口"
            Action {
                text: "最小化"
                shortcut: Qt.platform.os === "osx" ? "Meta+M" : "Ctrl+M"
                onTriggered: win.showMinimized()
            }
            Action {
                text: "最大化 / 还原"
                onTriggered: win.toggleMaximize()
            }
            MenuSeparator {}
            Action {
                text: "关闭窗口"
                shortcut: StandardKey.Close
                onTriggered: win.close()
            }
        }
    }
    Rectangle {
        id: titlebar
        x: 0
        y: 0
        width: win.width
        height: 46
        color: "white"
        MouseArea {
            anchors.fill: parent
            onPressed: win.startSystemMove()
            onDoubleClicked: win.toggleMaximize()
        }
        WButton {
            id: menuButton
            x: 10
            y: 8
            visible: Qt.platform.os !== "osx"
            text: "☰"
            hint: "菜单"
            implicitWidth: 32
            onClicked: compactMenu.open()
        }
        RowLayout {
            x: Qt.platform.os === "osx" ? 100 : 52
            height: 46
            width: parent.width - x - (Qt.platform.os === "windows" ? 146 : 18)
            spacing: 12
            WTag {
                visible: win.badge.length > 0
                text: win.badge
            }
            WText {
                Layout.fillWidth: true
                text: win.caption
                font.bold: true
                font.pixelSize: 14
            }
            WText {
                visible: win.captionNote.length > 0 && win.width >= 900
                Layout.maximumWidth: parent.width * .46
                text: win.captionNote
                font.pixelSize: 12
                color: "#8c8c8c"
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: "#f0f0f0"
        }
        Menu {
            id: compactMenu
            x: 10
            y: 42
            Menu {
                title: "编辑"
                Action {
                    text: "撤销"
                    onTriggered: win.edit("undo")
                }
                Action {
                    text: "重做"
                    onTriggered: win.edit("redo")
                }
                MenuSeparator {}
                Action {
                    text: "剪切"
                    onTriggered: win.edit("cut")
                }
                Action {
                    text: "拷贝"
                    onTriggered: win.edit("copy")
                }
                Action {
                    text: "粘贴"
                    onTriggered: win.edit("paste")
                }
                Action {
                    text: "全选"
                    onTriggered: win.edit("selectAll")
                }
            }
            Menu {
                title: "窗口"
                Action {
                    text: "最小化"
                    onTriggered: win.showMinimized()
                }
                Action {
                    text: "最大化 / 还原"
                    onTriggered: win.toggleMaximize()
                }
                Action {
                    text: "关闭窗口"
                    onTriggered: win.close()
                }
            }
            MenuSeparator {}
            Action {
                text: "关于 Woody"
                onTriggered: about.open()
            }
            Action {
                text: "退出 Woody"
                onTriggered: backend.requestQuit()
            }
        }
    }
    Shortcut {
        sequence: "Alt"
        enabled: Qt.platform.os !== "osx"
        onActivated: compactMenu.open()
    }
    Shortcut {
        sequence: "F10"
        enabled: Qt.platform.os !== "osx"
        onActivated: compactMenu.open()
    }
    Item {
        id: body
        x: 0
        y: 46
        width: win.width
        height: win.height - 46
    }
    Dialog {
        id: about
        objectName: "aboutDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460
        modal: true
        title: "关于 Woody"
        standardButtons: Dialog.Close
        Column {
            width: parent.width
            spacing: 16
            Row {
                spacing: 14
                Image {
                    source: "qrc:/assets/icon.png"
                    width: 54
                    height: 54
                }
                Column {
                    spacing: 6
                    WText {
                        text: "Woody"
                        font.pixelSize: 24
                        font.bold: true
                    }
                    WText {
                        text: "HarmonyOS 设备内存分析工具"
                        color: "#8c8c8c"
                        font.pixelSize: 12
                    }
                }
            }
            WText {
                width: parent.width
                text: "版本：" + buildInfo.version + "\nGit 提交：" + buildInfo.commit + "\nQt：" + buildInfo.qt + "\n运行系统：" + buildInfo.os + " (" + buildInfo.arch + ")"
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                lineHeight: 1.6
                font.pixelSize: 13
            }
        }
    }
    Dialog {
        id: renameDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460
        modal: true
        title: "编辑任务名称"
        standardButtons: Dialog.Ok | Dialog.Cancel
        WField {
            id: renameField
            objectName: "renameField"
            width: parent.width
            maximumLength: 80
            onAccepted: if (text.trim()) {
                backend.renameReport(win.renameDirectory, text);
                renameDialog.close();
            }
        }
        onAccepted: backend.renameReport(win.renameDirectory, renameField.text)
    }
    Dialog {
        id: errorDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(540, parent.width - 48)
        modal: true
        title: "操作失败"
        standardButtons: Dialog.Ok
        WText {
            width: parent.width
            text: win.messageText
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            lineHeight: 1.4
        }
    }
    Rectangle {
        id: toast
        property string text: ""
        visible: false
        z: 1000
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64
        width: Math.min(700, toastLabel.implicitWidth + 32)
        height: toastLabel.implicitHeight + 20
        radius: 6
        color: "white"
        border.color: "#e5e5e5"
        WText {
            id: toastLabel
            anchors.centerIn: parent
            width: Math.min(668, implicitWidth)
            text: toast.text
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 13
        }
    }
    Timer {
        id: toastTimer
        interval: 4000
        onTriggered: toast.visible = false
    }
    Connections {
        target: backend
        function onError(message) {
            if (win.active) {
                win.messageText = message;
                errorDialog.open();
            }
        }
        function onNotification(message) {
            if (win.active)
                win.notify(message);
        }
    }
}
