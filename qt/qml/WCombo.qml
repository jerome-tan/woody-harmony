import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control
    implicitHeight: 32
    implicitWidth: 180
    leftPadding: 11
    rightPadding: 28
    font.pixelSize: 14
    contentItem: WText {
        text: control.displayText
        color: control.enabled ? "#262626" : "#bfbfbf"
        font: control.font
    }
    indicator: WText {
        x: control.width - 23
        y: (control.height - height) / 2
        text: "⌄"
        color: "#bfbfbf"
    }
    background: Rectangle {
        radius: 6
        color: control.enabled ? "white" : "#f5f5f5"
        border.color: control.activeFocus || control.hovered ? "#4096ff" : "#d9d9d9"
    }
    delegate: ItemDelegate {
        required property int index
        required property var modelData
        width: control.width
        height: 32
        highlighted: control.highlightedIndex === index
        contentItem: WText {
            text: control.textRole ? modelData[control.textRole] : modelData
            font.pixelSize: 13
        }
        background: Rectangle {
            color: parent.highlighted ? "#e6f4ff" : parent.hovered ? "#f5f5f5" : "white"
            radius: 4
        }
    }
    popup: Popup {
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
            border.color: "#e5e5e5"
        }
    }
}
