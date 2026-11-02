import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control
    hoverEnabled: true
    ToolTip.text: displayText
    ToolTip.visible: hovered && contentItem.truncated
    ToolTip.delay: 600
    implicitHeight: 36
    implicitWidth: 180
    leftPadding: 11
    rightPadding: 28
    font.pixelSize: 14
    contentItem: WText {
        text: control.displayText
        color: control.enabled ? T.text : T.disabled
        font: control.font
    }
    indicator: WIcon {
        name: "DownOutlined"
        tone: "muted"
        width: 12
        height: 12
        x: control.width - 24
        y: (control.height - height) / 2
    }
    background: Rectangle {
        radius: 6
        color: control.enabled ? "white" : T.chrome
        border.color: control.activeFocus || control.hovered ? T.accent : T.border
    }
    delegate: ItemDelegate {
        required property int index
        required property var modelData
        width: control.width
        height: 36
        highlighted: control.highlightedIndex === index
        ToolTip.text: contentItem.text
        ToolTip.visible: hovered && contentItem.truncated
        ToolTip.delay: 600
        contentItem: WText {
            text: control.textRole ? modelData[control.textRole] : modelData
            font.pixelSize: 13
        }
        background: Rectangle {
            color: parent.highlighted ? T.selected : parent.hovered ? T.chrome : "white"
            radius: 4
        }
    }
    popup: Popup {
        margins: 8
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(300, contentItem.implicitHeight + 8)
        padding: 4
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
        background: Rectangle {
            radius: 6
            color: "white"
            border.color: T.border
        }
    }
}
