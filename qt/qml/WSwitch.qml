import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

Switch {
    id: control
    padding: 0
    spacing: 7
    implicitHeight: 26
    indicator: Rectangle {
        width: 28
        height: 16
        y: (control.height - height) / 2
        radius: 8
        color: control.checked ? T.accent : T.disabled
        Rectangle {
            x: control.checked ? 14 : 2
            y: 2
            width: 12
            height: 12
            radius: 6
            color: "white"
        }
    }
    contentItem: WText {
        text: control.text
        font.pixelSize: 12
        color: T.muted
        leftPadding: control.indicator.width + control.spacing
    }
}
