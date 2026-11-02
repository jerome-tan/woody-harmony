import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    implicitHeight: 36
    padding: 7
    leftPadding: 11
    rightPadding: 11
    font.pixelSize: 14
    color: enabled ? T.text : T.muted
    placeholderTextColor: T.disabled
    selectByMouse: true
    selectionColor: T.selected
    selectedTextColor: T.text
    background: Rectangle {
        radius: 6
        color: control.enabled ? "white" : T.chrome
        border.color: control.activeFocus ? T.accent : control.hovered ? T.accent : T.border
    }
}
