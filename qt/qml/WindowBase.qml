import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: win
    property string caption: "Woody"
    property string badge: ""
    property string captionNote: ""
    property bool mainWindow: false
    property string maximizedPreferenceKey: ""
    // Hidden/minimized transitions during closing must not erase the last
    // normal or maximized state.
    property bool lastMaximized: false
    onVisibilityChanged: {
        if (visibility === Window.Maximized)
            lastMaximized = true;
        else if (visibility === Window.Windowed)
            lastMaximized = false;
    }
    property bool windowsChrome: Qt.platform.os === "windows"
    default property alias contents: body.data
    property alias bodyItem: body
    property string renameDirectory: ""
    property string messageText: ""
    property bool extraModalOpen: false
    readonly property bool modalDialogOpen: extraModalOpen || about.opened || renameDialog.opened || errorDialog.opened
    title: mainWindow ? "Woody" : caption
    property int initialWidth: 1280
    property int initialHeight: 840
    width: initialWidth
    height: initialHeight
    minimumWidth: 640
    minimumHeight: 480
    color: "white"
    palette.highlight: T.accent
    palette.highlightedText: "white"
    palette.text: T.text
    palette.buttonText: T.text
    palette.button: T.chrome
    palette.base: "white"
    palette.window: "white"
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    // Qt's Windows titlebar overlay must explicitly omit WindowTitleHint while
    // retaining its platform caption buttons. The QML header supplies the title.
    flags: Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint | (Qt.platform.os === "windows" ? Qt.CustomizeWindowHint | Qt.WindowSystemMenuHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint : 0)
    Component.onCompleted: backend.prepareWindow(win)
    onVisibleChanged: if (visible)
        Qt.callLater(function () {
            backend.prepareWindow(win);
        })
    function edit(action) {
        var item = activeFocusItem;
        if (item && typeof item[action] === "function")
            item[action]();
    }
    function toggleMaximize() {
        visibility === Window.Maximized ? showNormal() : showMaximized();
    }
    function rememberMaximizedState() {
        if (maximizedPreferenceKey)
            backend.setUiPreference(maximizedPreferenceKey, lastMaximized);
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
            title: "Help"
            Action {
                text: "关于 Woody"
                onTriggered: about.open()
            }
        }
    }
    Rectangle {
        id: titlebar
        objectName: "titlebar"
        width: win.width
        height: 40
        color: T.chrome
        MouseArea {
            anchors.fill: parent
            // On Windows Qt's expanded-titlebar hit test forwards the press to
            // QML first. Accepting it here prevents the native HTCAPTION path
            // (including dragging, double-click maximize and window snapping).
            enabled: !win.windowsChrome
            onPressed: win.startSystemMove()
            onDoubleClicked: win.toggleMaximize()
        }
        Item {
            // Our 40px header can be taller than the native caption. Only its
            // extra client-area strip needs QML drag/double-click handlers.
            visible: win.windowsChrome
            y: win.contentItem.SafeArea.margins.top
            width: parent.width
            height: Math.max(0, parent.height - y)
            DragHandler {
                target: null
                onActiveChanged: if (active) win.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: win.toggleMaximize()
            }
        }
        Row {
            id: brand
            visible: win.windowsChrome
            x: 12
            height: parent.height
            spacing: 10
            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: "qrc:/assets/icon-win.png"
                width: 22
                height: 22
                sourceSize.width: 44
                sourceSize.height: 44
            }
            WText {
                text: "Woody"
                height: parent.height
                font.weight: Font.DemiBold
            }
            WButton {
                id: helpButton
                objectName: "helpButton"
                anchors.verticalCenter: parent.verticalCenter
                text: "Help"
                small: true
                tone: helpMenu.opened ? "selected" : "quiet"
                onClicked: helpMenu.open()
                WMenu {
                    id: helpMenu
                    objectName: "helpMenu"
                    y: helpButton.height + 3
                    Action {
                        text: "关于 Woody"
                        onTriggered: about.open()
                    }
                }
            }
        }
        WText {
            objectName: "windowCaption"
            x: win.windowsChrome ? brand.x + brand.width + 18 : 96
            width: Math.max(0, win.width - x - (win.windowsChrome ? 154 : 96))
            height: parent.height
            visible: !win.mainWindow
            text: win.caption
            horizontalAlignment: Text.AlignHCenter
            font.weight: Font.DemiBold
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: T.border
        }
    }
    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: win.close()
    }
    Shortcut {
        sequence: "Ctrl+M"
        onActivated: win.showMinimized()
    }
    Shortcut {
        sequences: [StandardKey.Quit]
        onActivated: backend.requestInteractiveQuit()
    }
    Shortcut {
        sequence: "Alt+H"
        enabled: win.windowsChrome
        onActivated: helpMenu.open()
    }
    Shortcut {
        sequence: "F10"
        enabled: win.windowsChrome
        onActivated: helpMenu.open()
    }
    Shortcut {
        sequences: [StandardKey.Copy]
        onActivated: win.edit("copy")
    }
    Shortcut {
        sequences: [StandardKey.Cut]
        onActivated: win.edit("cut")
    }
    Shortcut {
        sequences: [StandardKey.Paste]
        onActivated: win.edit("paste")
    }
    Shortcut {
        sequences: [StandardKey.SelectAll]
        onActivated: win.edit("selectAll")
    }
    Shortcut {
        sequences: [StandardKey.Undo]
        onActivated: win.edit("undo")
    }
    Shortcut {
        sequences: [StandardKey.Redo]
        onActivated: win.edit("redo")
    }
    Item {
        id: body
        x: 0
        y: 40
        width: win.width
        height: win.height - 40
    }
    WDialog {
        id: about
        objectName: "aboutDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460
        modal: true
        title: "关于 Woody"
        readonly property string versionText: "版本：" + buildInfo.version + "\nGit 提交：" + buildInfo.commit + "\nQt：" + buildInfo.qt + "\n运行系统：" + buildInfo.os + " (" + buildInfo.arch + ")"
        standardButtons: Dialog.Close
        footer: Item {
            implicitHeight: 62
            WButton {
                objectName: "copyVersionInfo"
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                text: "复制"
                iconName: "CopyOutlined"
                tone: "primary"
                onClicked: {
                    backend.copyText(about.versionText);
                    win.notify("版本信息已复制");
                }
            }
        }
        Column {
            width: parent.width
            spacing: 16
            Image {
                objectName: "aboutLogo"
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/assets/icon-win.png"
                width: 64
                height: 64
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
            }
            WText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "HarmonyOS开发者工具"
                font.pixelSize: 14
            }
            WText {
                width: parent.width
                text: about.versionText
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                lineHeight: 1.6
                font.pixelSize: 13
            }
        }
    }
    WDialog {
        id: renameDialog
        objectName: "renameDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 460
        modal: true
        title: "重命名报告"
        acceptText: "保存"
        acceptEnabled: renameField.text.trim().length > 0
        standardButtons: Dialog.Ok | Dialog.Cancel
        RowLayout {
            width: parent.width
            spacing: 16
            WText {
                text: "报告名称"
                color: T.muted
            }
            WField {
                id: renameField
                objectName: "renameField"
                Layout.fillWidth: true
                maximumLength: 80
                onAccepted: if (text.trim()) {
                    backend.renameReport(win.renameDirectory, text);
                    renameDialog.close();
                }
            }
        }
        onAccepted: backend.renameReport(win.renameDirectory, renameField.text)
    }
    WDialog {
        id: errorDialog
        objectName: "errorDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(540, parent.width - 48)
        modal: true
        title: "操作未完成"
        acceptText: "知道了"
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
        border.color: T.border
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
