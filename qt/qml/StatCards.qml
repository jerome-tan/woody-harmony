import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

Rectangle {
    id: root
    objectName: "statCards"
    property var values: []
    readonly property int columns: width < 740 ? 2 : Math.max(1, values.length)
    readonly property bool narrow: columns === 2
    implicitHeight: narrow ? 106 : 86
    Layout.minimumHeight: implicitHeight
    Layout.maximumHeight: implicitHeight
    Layout.fillHeight: false
    color: "white"
    border.color: T.border
    radius: 6
    GridLayout {
        anchors.fill: parent
        anchors.margins: 12
        columns: root.columns
        rowSpacing: 8
        columnSpacing: 16
        Repeater {
            model: root.values
            Item {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                Rectangle {
                    x: -8
                    y: 2
                    height: parent.height - 4
                    width: 1
                    visible: index % root.columns !== 0
                    color: T.border
                }
                Column {
                    width: parent.width
                    spacing: root.narrow ? 2 : 6
                    WText {
                        width: parent.width
                        text: modelData.label
                        color: T.muted
                        font.pixelSize: 12
                    }
                    WText {
                        width: parent.width
                        text: modelData.value
                        color: modelData.memoryDelta !== undefined ? T.memoryDeltaColor(modelData.memoryDelta) : T.text
                        font.pixelSize: root.narrow ? 18 : 24
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
