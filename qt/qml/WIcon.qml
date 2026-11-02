import QtQuick

Item {
    id: icon
    property string name: ""
    property string tone: "text"
    implicitWidth: 18
    implicitHeight: 18
    width: implicitWidth
    height: implicitHeight
    Accessible.ignored: true
    Image {
        anchors.fill: parent
        source: icon.name ? "qrc:/icons/" + icon.name + "-" + icon.tone + ".svg" : ""
        sourceSize.width: 48
        sourceSize.height: 48
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
