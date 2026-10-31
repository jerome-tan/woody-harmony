import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control
    property string tone: "default"
    property bool small: false
    property string hint: ""
    implicitHeight: small ? 26 : 32
    implicitWidth: Math.max(small ? 26 : 32, contentItem.implicitWidth + 24)
    leftPadding: 12
    rightPadding: 12
    font.pixelSize: small ? 12 : 14
    hoverEnabled: true
    contentItem: WText {
        text: control.text
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        color: !control.enabled ? "#bfbfbf" : control.tone === "primary" || control.tone === "green" ? "white" : control.tone === "danger" ? "#ff4d4f" : control.hovered ? "#4096ff" : "#262626"
    }
    background: Rectangle {
        radius: 6
        color: !control.enabled ? "#f5f5f5" : control.tone === "primary" ? (control.down ? "#0958d9" : control.hovered ? "#4096ff" : "#1677ff") : control.tone === "green" ? (control.hovered ? "#73d13d" : "#52c41a") : control.down ? "#fafafa" : "white"
        border.color: !control.enabled ? "#d9d9d9" : control.tone === "primary" || control.tone === "green" ? color : control.tone === "danger" ? "#ff4d4f" : control.hovered || control.activeFocus ? "#4096ff" : "#d9d9d9"
    }
    ToolTip.visible: hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 500
}
