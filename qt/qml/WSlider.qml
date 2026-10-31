import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: control
    implicitHeight: 26
    leftPadding: 6
    rightPadding: 6
    background: Rectangle {
        x: control.leftPadding
        y: (control.height - height) / 2
        width: control.availableWidth
        height: 4
        radius: 2
        color: "#e8e8e8"
        Rectangle {
            width: control.visualPosition * parent.width
            height: 4
            radius: 2
            color: "#91caff"
        }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: (control.height - height) / 2
        width: 12
        height: 12
        radius: 6
        color: "white"
        border.width: 2
        border.color: control.pressed ? "#1677ff" : "#91caff"
    }
}
