import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import "Format.js" as F

Popup {
    id: tip
    popupType: Popup.Item
    property var data: ({})
    property var retained: ({})
    onSourceChanged: if (!source)
        retained = ({})
    onDataChanged: {
        if (!source) {
            retained = ({});
            leaveDelay.stop();
            return;
        }
        // The pointer may still generate plot hover events beneath this popup.
        // Keep the current rows and position stable while it is being read.
        if (tipHover.hovered) {
            leaveDelay.stop();
            return;
        }
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
    property bool allowAboveSource: false
    function topBoundary() {
        if (!source || !parent)
            return 6;
        var top = allowAboveSource ? 6 : Math.max(6, source.mapToItem(parent, 0, 0).y);
        // Miniatures share the scroll viewport's space: a low chart must be
        // able to place its full tooltip above itself instead of clipping rows.
        for (var item = source.parent; item; item = item.parent)
            if (item.clip)
                top = Math.max(top, item.mapToItem(parent, 0, 0).y);
        return top;
    }
    parent: Overlay.overlay
    visible: !!retained.heading && !!source && source.visible
    closePolicy: Popup.NoAutoClose
    modal: false
    focus: false
    padding: 12
    width: Math.min(parent ? parent.width - 12 : 500, 500, Math.max(380, table.implicitWidth + 24))
    height: Math.min(implicitHeight, parent ? parent.height * (allowAboveSource ? 1 : .6) : 500, parent && source ? Math.max(60, parent.height - topBoundary() - 6) : 500)
    implicitHeight: head.implicitHeight + table.implicitHeight + 38
    x: {
        if (!source || !parent)
            return 0;
        var p = source.mapToItem(parent, retained.x || 0, retained.y || 0);
        var preferred = p.x + width + 22 <= parent.width ? p.x + 16 : p.x - width - 16;
        return Math.max(6, Math.min(parent.width - width - 6, preferred));
    }
    y: {
        if (!source || !parent)
            return 0;
        var p = source.mapToItem(parent, retained.x || 0, retained.y || 0);
        var top = topBoundary();
        return Math.max(top, Math.min(parent.height - height - 6, p.y - height - 16 > top ? p.y - height - 16 : p.y + 20));
    }
    background: Rectangle {
        color: Qt.rgba(1, 1, 1, tip.alpha)
        radius: 6
        border.color: T.border
    }
    contentItem: Column {
        spacing: 8
        HoverHandler {
            id: tipHover
            objectName: "tooltipHover"
            blocking: true
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
            color: T.muted
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
                    MemoryDetailRow {
                        required property var modelData
                        width: table.width
                        detail: modelData
                    }
                }
            }
        }
    }
}
