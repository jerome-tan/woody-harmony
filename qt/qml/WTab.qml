import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control
    property bool selected: false
    implicitHeight: 38
    implicitWidth: contentItem.implicitWidth + 8
    leftPadding: 4
    rightPadding: 4
    contentItem: WText {
        text: control.text
        font.pixelSize: 14
        font.bold: control.selected
        color: control.selected || control.hovered ? "#1677ff" : "#262626"
    }
    background: Item {
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: "#1677ff"
            visible: control.selected
        }
    }
}
