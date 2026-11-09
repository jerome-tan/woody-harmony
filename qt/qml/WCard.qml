import "Theme.js" as T
import QtQuick

Rectangle {
    id: root
    property string title: ""
    property color headerColor: "transparent"
    property int padding: 16
    property alias body: body
    property alias extras: extras.data
    default property alias content: body.data
    radius: 6
    color: "white"
    border.color: T.border
    Item {
        x: 1
        y: 1
        width: root.width - 2
        height: 42
        visible: root.title.length > 0
        clip: true
        Rectangle {
            width: parent.width
            height: parent.height + root.radius
            radius: root.radius - 1
            color: root.headerColor
        }
    }
    WText {
        x: Math.max(16, root.padding)
        y: 0
        height: 44
        width: Math.max(0, parent.width - root.padding * 2 - extras.width - 10)
        visible: root.title.length > 0
        text: root.title
        font.weight: Font.DemiBold
        font.pixelSize: 16
    }
    Row {
        id: extras
        anchors.right: parent.right
        anchors.rightMargin: Math.max(16, root.padding)
        y: 9
        spacing: 10
    }
    Rectangle {
        x: 1
        y: 43
        width: parent.width - 2
        height: 1
        color: T.border
        visible: root.title.length > 0
    }
    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
        anchors.topMargin: root.title.length ? 44 + root.padding : root.padding
    }
}
