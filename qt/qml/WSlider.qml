import "Theme.js" as T
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
        color: T.border
        Rectangle {
            width: control.visualPosition * parent.width
            height: 4
            radius: 2
            color: T.primary
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
        border.color: control.pressed ? T.accent : T.primary
    }
}
