import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control
    spacing: 7
    implicitHeight: 26
    padding: 0
    indicator: Rectangle {
        x: 0
        y: (control.height - height) / 2
        width: 16
        height: 16
        radius: 3
        color: control.checked ? "#1677ff" : "white"
        border.color: !control.enabled ? "#d9d9d9" : control.checked || control.hovered ? "#1677ff" : "#d9d9d9"
        opacity: control.enabled ? 1 : .5
        Text {
            anchors.centerIn: parent
            text: control.checked ? "✓" : ""
            color: "white"
            font.pixelSize: 14
            font.bold: true
        }
    }
    contentItem: WText {
        text: control.text
        font.pixelSize: 13
        leftPadding: control.indicator.width + control.spacing
        color: control.enabled ? "#262626" : "#bfbfbf"
    }
}
