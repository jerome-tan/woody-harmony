import QtQuick
import QtQuick.Controls.Basic
import "Format.js" as F

Popup {
    id: tip
    popupType: Popup.Item
    property var data: ({})
    property var retained: ({})
    onDataChanged: {
        if (data.heading) {
            retained = data;
            leaveDelay.stop();
        } else
            leaveDelay.restart();
    }
    Timer {
        id: leaveDelay
        interval: 220
        onTriggered: {
            if (!tipHover.hovered)
                tip.retained = ({});
        }
    }
    property Item source: null
    property real alpha: .8
    parent: Overlay.overlay
    visible: !!retained.heading && !!source && source.visible
    closePolicy: Popup.NoAutoClose
    modal: false
    focus: false
    padding: 12
    width: Math.min(500, Math.max(300, table.implicitWidth + 24))
    height: Math.min(implicitHeight, parent ? parent.height * .6 : 500)
    implicitHeight: head.implicitHeight + table.implicitHeight + 38
    x: {
        if (!source || !parent)
            return 0;
        var p = source.mapToItem(parent, retained.x || 0, retained.y || 0);
        return Math.max(6, Math.min(parent.width - width - 6, p.x + 16));
    }
    y: {
        if (!source || !parent)
            return 0;
        var p = source.mapToItem(parent, retained.x || 0, retained.y || 0);
        return Math.max(6, Math.min(parent.height - height - 6, p.y - height - 16 > 6 ? p.y - height - 16 : p.y + 20));
    }
    background: Rectangle {
        color: Qt.rgba(1, 1, 1, tip.alpha)
        radius: 6
        border.color: "#d9d9d9"
    }
    contentItem: Column {
        spacing: 8
        HoverHandler {
            id: tipHover
            onHoveredChanged: {
                if (hovered)
                    leaveDelay.stop();
                else
                    leaveDelay.restart();
            }
        }
        WText {
            id: head
            width: parent.width
            text: tip.retained.heading || ""
            font.pixelSize: 12
            color: "#595959"
        }
        ScrollView {
            width: parent.width
            height: tip.height - head.height - 32
            clip: true
            Column {
                id: table
                width: parent.width
                spacing: 6
                Repeater {
                    model: tip.retained.items || []
                    Row {
                        required property var modelData
                        width: table.width
                        spacing: 8
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 1
                            color: modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        WText {
                            width: Math.max(80, table.width - 178)
                            text: modelData.name
                            font.pixelSize: 12
                            font.bold: modelData.name === "Total"
                        }
                        Column {
                            width: 88
                            WText {
                                width: 88
                                text: modelData.kb === null || modelData.kb === undefined ? "—" : F.mb(modelData.kb) + " MB"
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 12
                                font.bold: modelData.name === "Total"
                            }
                            WText {
                                visible: modelData.name === "Total" && modelData.kb >= 1048576
                                width: 88
                                text: (Number(modelData.kb) / 1048576).toFixed(2) + " GB"
                                horizontalAlignment: Text.AlignRight
                                color: "#8c8c8c"
                                font.pixelSize: 11
                            }
                        }
                        Column {
                            width: 56
                            visible: modelData.percent >= 0
                            spacing: 3
                            WText {
                                width: 56
                                text: Number(modelData.percent).toFixed(1) + "%"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                            }
                            Rectangle {
                                width: 48
                                height: 4
                                radius: 2
                                color: "#f0f0f0"
                                anchors.right: parent.right
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, modelData.percent / 100))
                                    height: 4
                                    radius: 2
                                    color: modelData.color
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
