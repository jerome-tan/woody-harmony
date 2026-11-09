import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Theme.js" as T

Button {
    id: control
    property string tone: "default"
    property string iconName: ""
    property bool small: false
    property string hint: ""
    property int textAlignment: Text.AlignHCenter
    implicitHeight: small ? 28 : 36
    implicitWidth: Math.max(implicitHeight, contentItem.implicitWidth + 24)
    padding: 8
    leftPadding: 12
    rightPadding: 12
    font.pixelSize: small ? 12 : 14
    font.weight: tone === "primary" || tone === "selected" ? Font.DemiBold : Font.Normal
    hoverEnabled: true
    Accessible.name: text || hint
    contentItem: RowLayout {
        spacing: control.iconName && control.text ? 8 : 0
        WIcon {
            visible: control.iconName.length > 0
            name: control.iconName
            tone: control.tone === "primary" || control.tone === "selected" ? "accent" : "text"
            opacity: control.enabled ? 1 : .4
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: control.small ? 14 : 18
            Layout.preferredHeight: control.small ? 14 : 18
        }
        WText {
            visible: control.text.length > 0
            Layout.fillWidth: true
            text: control.text
            font: control.font
            horizontalAlignment: control.textAlignment
            color: !control.enabled ? T.disabled : control.tone === "danger" ? T.error : control.tone === "primary" ? T.primaryText : control.tone === "selected" ? T.accent : T.text
        }
    }
    background: Rectangle {
        radius: 5
        color: !control.enabled ? T.chrome : control.tone === "primary" ? (control.down ? T.focus : T.primary) : control.tone === "selected" || control.down || control.hovered ? T.selected : control.tone === "quiet" ? "transparent" : "white"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? T.accent : control.tone === "selected" ? "transparent" : control.tone === "primary" ? T.primary : control.tone === "quiet" ? "transparent" : T.border
    }
    ToolTip.visible: hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 500
}
