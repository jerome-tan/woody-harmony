import QtQuick

Rectangle {
    id: root
    property string title: ""
    property int padding: 16
    property alias body: body
    property alias extras: extras.data
    default property alias content: body.data
    radius: 8
    color: "white"
    border.color: "#f0f0f0"
    WText {
        x: root.padding
        y: 0
        height: 44
        width: Math.max(0, parent.width - root.padding * 2 - extras.width - 10)
        visible: root.title.length > 0
        text: root.title
        font.bold: true
    }
    Row {
        id: extras
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: 9
        spacing: 10
    }
    Rectangle {
        x: 1
        y: 43
        width: parent.width - 2
        height: 1
        color: "#f0f0f0"
        visible: root.title.length > 0
    }
    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
        anchors.topMargin: root.title.length ? 44 + root.padding : root.padding
    }
}
