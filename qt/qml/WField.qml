import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    implicitHeight: 32
    padding: 7
    leftPadding: 11
    rightPadding: 11
    font.pixelSize: 14
    color: enabled ? "#262626" : "#8c8c8c"
    placeholderTextColor: "#bfbfbf"
    selectByMouse: true
    selectionColor: "#bae0ff"
    selectedTextColor: "#262626"
    background: Rectangle {
        radius: 6
        color: control.enabled ? "white" : "#f5f5f5"
        border.color: control.activeFocus ? "#1677ff" : control.hovered ? "#4096ff" : "#d9d9d9"
    }
}
