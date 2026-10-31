import QtQuick

Rectangle {
    id: root
    property string text: ""
    property color ink: "#1677ff"
    property color tint: "#e6f4ff"
    implicitWidth: label.implicitWidth + 14
    implicitHeight: 22
    radius: 3
    color: tint
    border.color: Qt.rgba(ink.r, ink.g, ink.b, .38)
    WText {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.ink
        font.pixelSize: 12
    }
}
