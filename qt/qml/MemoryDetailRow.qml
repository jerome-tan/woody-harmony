import "Theme.js" as T
import "Format.js" as F
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: row
    required property var detail
    spacing: 8
    Rectangle {
        Layout.preferredWidth: 8
        Layout.preferredHeight: 8
        radius: 1
        color: row.detail.color
    }
    WText {
        Layout.fillWidth: true
        Layout.minimumWidth: 60
        text: F.categoryName(row.detail.name)
        font.pixelSize: 12
        font.bold: row.detail.name === "Total"
    }
    Column {
        Layout.preferredWidth: 88
        WText {
            width: parent.width
            text: row.detail.kb === null || row.detail.kb === undefined ? "—" : F.mb(row.detail.kb) + " MB"
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 12
            font.bold: row.detail.name === "Total"
        }
        WText {
            visible: row.detail.name === "Total" && row.detail.kb >= 1048576
            width: parent.width
            text: (Number(row.detail.kb) / 1048576).toFixed(2) + " GB"
            horizontalAlignment: Text.AlignRight
            color: T.muted
            font.pixelSize: 11
        }
    }
    Column {
        Layout.preferredWidth: 56
        visible: row.detail.percent >= 0
        spacing: 3
        WText {
            width: parent.width
            text: Number(row.detail.percent).toFixed(1) + "%"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
        }
        Rectangle {
            width: 48
            height: 4
            radius: 2
            color: T.border
            anchors.right: parent.right
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, row.detail.percent / 100))
                height: 4
                radius: 2
                color: row.detail.color
            }
        }
    }
}
