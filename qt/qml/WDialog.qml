import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Theme.js" as T

Dialog {
    id: dialog
    property string acceptText: "确定"
    property string rejectText: "取消"
    property string acceptTone: "primary"
    property bool acceptEnabled: true
    padding: 24
    topPadding: 18
    bottomPadding: 18
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle {
        color: "white"
        radius: 8
        border.color: T.border
    }
    header: WText {
        text: dialog.title
        font.pixelSize: 16
        font.weight: Font.DemiBold
        leftPadding: 24
        rightPadding: 24
        topPadding: 22
        bottomPadding: 4
    }
    footer: Item {
        implicitHeight: dialog.standardButtons ? 62 : 0
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 8
            spacing: 10
            WButton {
                objectName: "dialogCancel"
                visible: !!(dialog.standardButtons & Dialog.Cancel)
                text: dialog.rejectText
                onClicked: dialog.reject()
            }
            WButton {
                objectName: "dialogAccept"
                visible: !!(dialog.standardButtons & (Dialog.Ok | Dialog.Save | Dialog.Yes))
                text: dialog.acceptText
                tone: dialog.acceptTone
                enabled: dialog.acceptEnabled
                onClicked: dialog.accept()
            }
            WButton {
                objectName: "dialogClose"
                visible: !!(dialog.standardButtons & Dialog.Close)
                text: "关闭"
                onClicked: dialog.close()
            }
        }
    }
}
