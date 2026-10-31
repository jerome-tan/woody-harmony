import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    objectName: "statCards"
    implicitHeight: 90
    Layout.minimumHeight: 90
    Layout.maximumHeight: 90
    Layout.fillHeight: false
    property var values: []
    spacing: 12
    Repeater {
        model: root.values
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: "white"
            border.color: "#f0f0f0"
            WText {
                x: 12
                y: 13
                width: parent.width - 24
                text: modelData.label
                color: "#8c8c8c"
                font.pixelSize: 14
            }
            WText {
                x: 12
                y: 43
                width: parent.width - 24
                text: modelData.value
                color: modelData.color || "#262626"
                font.pixelSize: 24
            }
        }
    }
}
