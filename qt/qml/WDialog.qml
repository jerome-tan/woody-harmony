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
    header: Item {
        implicitHeight: 44
        Rectangle {
            anchors.fill: parent
            color: T.chrome
            radius: 8
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 8
            color: T.chrome
        }
        WText {
            anchors.fill: parent
            anchors.leftMargin: 44
            anchors.rightMargin: 44
            text: dialog.title
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        WButton {
            objectName: "dialogDismiss"
            visible: dialog.standardButtons !== Dialog.NoButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            iconName: "CloseOutlined"
            small: true
            tone: "quiet"
            hint: "关闭"
            onClicked: dialog.reject()
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: T.border
        }
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
