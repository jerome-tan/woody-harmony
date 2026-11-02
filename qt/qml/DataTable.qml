import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: table
    property var rows: []
    property var columns: []
    property bool selectable: false
    property int rowHeight: 44
    property bool fillColumns: false
    property var selected: []
    property string keyRole: "sessionDir"
    property string sortKey: ""
    property bool descending: false
    property string emptyText: "暂无数据"
    property string preferenceKey: ""
    property bool editableColumns: false
    property var layoutColumns: columns
    readonly property var visibleColumns: layoutColumns.filter(function (c) {
        return !c.hidden;
    })
    readonly property real tableWidth: visibleColumns.reduce(function (s, c) {
        return s + (c.width || 150);
    }, selectable ? 48 : 0)
    readonly property var sortedRows: {
        var result = rows.slice();
        if (!sortKey)
            return result;
        var key = sortKey, desc = descending;
        result.sort(function (a, b) {
            if (a.fixed && !b.fixed)
                return -1;
            if (b.fixed && !a.fixed)
                return 1;
            var av = a[key], bv = b[key];
            var n = typeof av === "number" ? av - bv : String(av || "").localeCompare(String(bv || ""));
            return desc ? -n : n;
        });
        return result;
    }
    signal cellClicked(var row, string key)
    signal action(var row, string name)
    signal selectionChangedByUser(var keys)
    function columnWidth(c) {
        return (c.width || 150) + (fillColumns ? Math.max(0, horizontal.width - tableWidth) / Math.max(1, visibleColumns.length) : 0);
    }
    function toggle(row) {
        var result = selected.slice(), k = row[keyRole], i = result.indexOf(k);
        if (i >= 0)
            result.splice(i, 1);
        else
            result.push(k);
        selectionChangedByUser(result);
    }
    function saveLayout() {
        if (preferenceKey)
            backend.setUiPreference(preferenceKey, layoutColumns.map(function (c) {
                return {
                    key: c.key,
                    width: c.width,
                    hidden: !!c.hidden
                };
            }));
    }
    function toggleColumn(key) {
        layoutColumns = layoutColumns.map(function (c) {
            return c.key === key && !c.locked ? Object.assign({}, c, {
                hidden: !c.hidden
            }) : c;
        });
        saveLayout();
    }
    function resetLayout() {
        layoutColumns = columns.map(function (c) {
            return Object.assign({}, c);
        });
        saveLayout();
    }
    function moveColumn(from, to) {
        if (from === to || layoutColumns[from].locked || layoutColumns[to].locked || layoutColumns[from].lockedRight || layoutColumns[to].lockedRight)
            return;
        var copy = layoutColumns.slice();
        copy.splice(to, 0, copy.splice(from, 1)[0]);
        layoutColumns = copy;
        saveLayout();
    }
    onColumnsChanged: {
        layoutColumns = columns.map(function (c) {
            return Object.assign({}, c);
        });
    }
    Component.onCompleted: {
        if (!preferenceKey)
            return;
        var saved = backend.uiPreference(preferenceKey, []), by = {};
        columns.forEach(function (c) {
            by[c.key] = c;
        });
        var next = [];
        saved.forEach(function (s) {
            if (by[s.key]) {
                next.push(Object.assign({}, by[s.key], {
                    hidden: by[s.key].locked ? false : !!s.hidden,
                    width: Math.max(70, Number(s.width) || by[s.key].width)
                }));
                delete by[s.key];
            }
        });
        columns.forEach(function (c) {
            if (by[c.key])
                next.push(Object.assign({}, c));
        });
        if (next.length === columns.length)
            layoutColumns = next;
    }
    Flickable {
        id: horizontal
        objectName: "tableScroll"
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, table.tableWidth)
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar {
            policy: table.tableWidth > horizontal.width ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
        }
        Rectangle {
            width: horizontal.contentWidth
            height: 38
            color: T.chrome
        }
        Row {
            id: header
            height: 38
            Rectangle {
                visible: table.selectable
                width: visible ? 48 : 0
                height: 38
                color: T.chrome
                z: 2
                transform: Translate {
                    x: horizontal.contentX
                }
                WCheck {
                    anchors.centerIn: parent
                    checked: table.rows.length > 0 && table.rows.every(function (r) {
                        return table.selected.indexOf(r[table.keyRole]) >= 0;
                    })
                    onClicked: table.selectionChangedByUser(checked ? table.rows.map(function (r) {
                        return r[table.keyRole];
                    }) : [])
                }
            }
            Repeater {
                model: table.visibleColumns
                Rectangle {
                    id: headerCell
                    objectName: "header-" + modelData.key
                    z: modelData.lockedRight ? 3 : modelData.locked ? 1 : 0
                    transform: Translate {
                        x: headerCell.modelData.lockedRight ? horizontal.contentX + horizontal.width - table.tableWidth : headerCell.modelData.locked ? horizontal.contentX : 0
                    }
                    required property var modelData
                    required property int index
                    width: table.columnWidth(modelData)
                    height: 38
                    color: T.chrome
                    WText {
                        anchors.fill: parent
                        anchors.margins: 10
                        text: headerCell.modelData.title + (table.sortKey === headerCell.modelData.key ? (table.descending ? " ▾" : " ▴") : "")
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: headerCell.modelData.align === "right" ? Text.AlignRight : Text.AlignLeft
                    }
                    Rectangle {
                        width: 1
                        height: 16
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: T.border
                    }
                    MouseArea {
                        id: headerMouse
                        anchors.fill: parent
                        anchors.rightMargin: 7
                        cursorShape: table.editableColumns && !headerCell.modelData.locked ? Qt.OpenHandCursor : Qt.PointingHandCursor
                        property real pressedX: 0
                        onPressed: function (mouse) {
                            pressedX = mouse.x;
                        }
                        onReleased: function (mouse) {
                            if (Math.abs(mouse.x - pressedX) > 25 && table.editableColumns && !headerCell.modelData.locked) {
                                var targetX = headerCell.x + mouse.x, pos = table.selectable ? 48 : 0, to = 0;
                                for (var i = 0; i < table.visibleColumns.length; ++i) {
                                    if (targetX >= pos)
                                        to = i;
                                    pos += table.visibleColumns[i].width || 150;
                                }
                                table.moveColumn(table.layoutColumns.findIndex(function (c) {
                                    return c.key === headerCell.modelData.key;
                                }), table.layoutColumns.findIndex(function (c) {
                                    return c.key === table.visibleColumns[to].key;
                                }));
                            } else if (headerCell.modelData.sortable !== false) {
                                if (table.sortKey === headerCell.modelData.key)
                                    table.descending = !table.descending;
                                else {
                                    table.sortKey = headerCell.modelData.key;
                                    table.descending = false;
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.right: parent.right
                        width: 7
                        height: parent.height
                        cursorShape: Qt.SplitHCursor
                        enabled: table.editableColumns
                        property real startX: 0
                        property real startWidth: 0
                        onPressed: function (mouse) {
                            startX = mapToItem(table, mouse.x, 0).x;
                            startWidth = headerCell.width;
                        }
                        onPositionChanged: function (mouse) {
                            if (!pressed)
                                return;
                            var copy = table.layoutColumns.slice();
                            var at = table.layoutColumns.findIndex(function (c) {
                                return c.key === headerCell.modelData.key;
                            });
                            copy[at] = Object.assign({}, copy[at], {
                                width: Math.max(70, startWidth + mapToItem(table, mouse.x, 0).x - startX)
                            });
                            table.layoutColumns = copy;
                        }
                        onReleased: table.saveLayout()
                    }
                }
            }
        }
        ListView {
            id: list
            x: 0
            y: 38
            width: horizontal.contentWidth
            height: horizontal.height - 38 - (table.tableWidth > horizontal.width ? 12 : 0)
            clip: true
            model: table.sortedRows
            reuseItems: true
            ScrollBar.vertical: ScrollBar {
                x: Math.min(list.width, horizontal.width + horizontal.contentX) - width
            }
            delegate: Rectangle {
                id: rowItem
                required property var modelData
                required property int index
                width: list.width
                height: table.rowHeight
                color: (modelData.fixed || modelData.baseline || table.selected.indexOf(modelData[table.keyRole]) >= 0) ? T.selected : rowHover.hovered ? T.chrome : "white"
                HoverHandler {
                    id: rowHover
                }
                Row {
                    height: parent.height
                    Rectangle {
                        color: rowItem.color
                        z: 2
                        transform: Translate {
                            x: horizontal.contentX
                        }
                        visible: table.selectable
                        width: visible ? 48 : 0
                        height: table.rowHeight
                        WCheck {
                            anchors.centerIn: parent
                            checked: table.selected.indexOf(rowItem.modelData[table.keyRole]) >= 0
                            onClicked: table.toggle(rowItem.modelData)
                        }
                    }
                    Repeater {
                        model: table.visibleColumns
                        Rectangle {
                            id: cell
                            color: rowItem.color
                            z: modelData.lockedRight ? 3 : modelData.locked ? 1 : 0
                            transform: Translate {
                                x: cell.modelData.lockedRight ? horizontal.contentX + horizontal.width - table.tableWidth : cell.modelData.locked ? horizontal.contentX : 0
                            }
                            required property var modelData
                            width: table.columnWidth(modelData)
                            height: table.rowHeight
                            readonly property var raw: rowItem.modelData[modelData.key]
                            readonly property string display: modelData.format ? modelData.format(raw, rowItem.modelData) : raw === null || raw === undefined ? "—" : String(raw)
                            Rectangle {
                                visible: !!cell.modelData.swatch
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: cell.modelData.swatch ? cell.modelData.swatch(cell.raw, rowItem.modelData) : "transparent"
                            }
                            Column {
                                x: cell.modelData.swatch ? 28 : 12
                                width: cell.width - x - 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                visible: cell.modelData.key !== "actions"
                                WText {
                                    width: parent.width
                                    text: cell.display
                                    font.pixelSize: 14
                                    font.weight: rowItem.modelData.fixed || cell.modelData.bold ? Font.DemiBold : Font.Normal
                                    color: cell.modelData.color ? cell.modelData.color(cell.raw, rowItem.modelData) : cell.modelData.link ? T.accent : T.text
                                    horizontalAlignment: cell.modelData.align === "right" ? Text.AlignRight : Text.AlignLeft
                                    HoverHandler {
                                        id: textHover
                                    }
                                    ToolTip.visible: textHover.hovered && truncated
                                    ToolTip.text: cell.display
                                    ToolTip.delay: 600
                                }
                                WText {
                                    visible: !!cell.modelData.secondary
                                    width: parent.width
                                    text: cell.modelData.secondary ? cell.modelData.secondary(cell.raw, rowItem.modelData) : ""
                                    color: cell.modelData.secondaryColor ? cell.modelData.secondaryColor(cell.raw, rowItem.modelData) : T.muted
                                    font.pixelSize: 12
                                    horizontalAlignment: cell.modelData.align === "right" ? Text.AlignRight : Text.AlignLeft
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !!cell.modelData.link
                                cursorShape: Qt.PointingHandCursor
                                onClicked: table.cellClicked(rowItem.modelData, cell.modelData.key)
                            }
                            WButton {
                                id: rowMore
                                objectName: "rowActions-" + rowItem.index
                                visible: cell.modelData.key === "actions"
                                anchors.centerIn: parent
                                iconName: "MoreOutlined"
                                small: true
                                hint: "报告操作"
                                onClicked: rowMenu.open()
                                WMenu {
                                    id: rowMenu
                                    x: rowMore.width - width
                                    y: rowMore.height + 3
                                    Action {
                                        text: "重命名"
                                        onTriggered: table.action(rowItem.modelData, "rename")
                                    }
                                    Action {
                                        text: "打开所在文件夹"
                                        onTriggered: table.action(rowItem.modelData, "folder")
                                    }
                                    Action {
                                        text: "删除报告"
                                        onTriggered: table.action(rowItem.modelData, "delete")
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: T.border
                }
            }
        }
        WText {
            x: Math.max(0, horizontal.contentX)
            y: 90
            width: horizontal.width
            visible: table.rows.length === 0
            text: table.emptyText
            color: T.muted
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
