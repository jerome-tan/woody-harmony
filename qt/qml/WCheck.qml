import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control
    property int selectionNumber: 0
    spacing: 7
    implicitHeight: 26
    padding: 0
    indicator: Rectangle {
        x: 0
        y: (control.height - height) / 2
        width: control.checked && control.selectionNumber > 0 ? Math.max(20, numberLabel.implicitWidth + 6) : 16
        height: 16
        radius: 3
        color: control.checked ? T.accent : "white"
        border.width: control.activeFocus ? 2 : 1
        border.color: !control.enabled ? T.border : control.checked || control.hovered ? T.accent : T.border
        opacity: control.enabled ? 1 : .5
        WIcon {
            anchors.centerIn: parent
            name: "CheckOutlined"
            tone: "white"
            width: 12
            height: 12
            visible: control.checked && control.selectionNumber <= 0
        }
        Text {
            id: numberLabel
            anchors.centerIn: parent
            text: control.selectionNumber > 0 ? control.selectionNumber : ""
            color: "white"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            visible: control.checked && control.selectionNumber > 0
        }
    }
    contentItem: WText {
        text: control.text
        font.pixelSize: 13
        leftPadding: control.indicator.width + control.spacing
        color: control.enabled ? T.text : T.disabled
    }
}
