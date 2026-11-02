import QtQuick
import QtQuick.Controls.Basic
import "Theme.js" as T

Menu {
    id: menu
    padding: 5
    implicitWidth: 184
    delegate: MenuItem {
        id: item
        implicitHeight: 34
        contentItem: WText {
            text: item.text
            color: item.enabled ? T.text : T.disabled
            font.pixelSize: 14
            leftPadding: 8
        }
        background: Rectangle {
            color: item.highlighted ? T.selected : "transparent"
            radius: 4
        }
    }
    background: Rectangle {
        color: "white"
        border.color: T.border
        radius: 6
    }
}
