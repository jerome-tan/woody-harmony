import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Theme.js" as T

WDialog {
    id: dialog
    objectName: "updateDialog"
    title: "软件更新"
    width: Math.min(540, parent.width - 40)
    standardButtons: Dialog.Close
    readonly property bool downloading: updater.state === "downloading" || updater.state === "preparing"
    ColumnLayout {
        width: parent.width
        spacing: 16
        WText {
            Layout.fillWidth: true
            text: "Woody " + buildInfo.version + (updater.version ? " → " + updater.version : "")
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        WText {
            Layout.fillWidth: true
            text: updater.message || "从 GitHub Release 获取正式版本更新"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: updater.state === "error" ? T.error : T.text
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: dialog.downloading || updater.state === "checking"
            value: updater.progress
            indeterminate: updater.state !== "downloading" || updater.progress === 0
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(220, updateNotes.implicitHeight + 12)
            visible: updater.notes.length > 0
            clip: true
            TextArea {
                id: updateNotes
                text: updater.notes
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: T.muted
                font.pixelSize: 13
                background: Rectangle {
                    color: T.chrome
                    radius: 6
                }
            }
        }
        WText {
            Layout.fillWidth: true
            visible: updater.state === "ready"
            text: backend.sampling || backend.snapshotting ? "请先结束当前采集，再安装更新。" : "安装将关闭所有 Woody 窗口并重新打开应用，已保存的设置和报告会保留。"
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: T.muted
            font.pixelSize: 12
        }
    }
    footer: Item {
        implicitHeight: 64
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            WButton {
                text: "Release 页面"
                tone: "quiet"
                onClicked: updater.openRelease()
            }
            Item {
                Layout.fillWidth: true
            }
            WButton {
                visible: dialog.downloading
                text: "取消下载"
                onClicked: updater.cancel()
            }
            WButton {
                objectName: "updatePrimary"
                text: updater.state === "available" ? "下载更新" : updater.state === "ready" ? "安装并重启" : "检查更新"
                tone: "primary"
                enabled: !dialog.downloading && updater.state !== "checking" && updater.state !== "installing" && !(updater.state === "ready" && (backend.sampling || backend.snapshotting))
                onClicked: {
                    if (updater.state === "available")
                        updater.download();
                    else if (updater.state === "ready")
                        updater.install();
                    else
                        updater.check();
                }
            }
        }
    }
}
