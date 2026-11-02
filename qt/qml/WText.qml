import "Theme.js" as T
import QtQuick

Text {
    color: T.text
    font.pixelSize: 14
    renderType: Text.QtRendering
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
