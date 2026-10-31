import QtQuick
import QtQuick.Controls.Basic

Item {
    id: table
    property var rows: []
    property var columns: []
    property bool selectable: false
    property var selected: []
    property string keyRole: "sessionDir"
    property string sortKey: ""
    property bool descending: false
    property string emptyText: "暂无数据"
    property string preferenceKey: ""
    property bool editableColumns: false
    property var layoutColumns: columns
    readonly property real tableWidth: layoutColumns.reduce(function (s, c) {
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
                    width: c.width
                };
            }));
    }
    function resetLayout() {
        layoutColumns = columns.map(function (c) {
            return Object.assign({}, c);
        });
        saveLayout();
    }
    function moveColumn(from, to) {
        if (from === to || layoutColumns[from].locked || layoutColumns[to].locked)
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
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, table.tableWidth)
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar {
            policy: table.tableWidth > horizontal.width ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
        }
        Row {
            id: header
            height: 38
            Rectangle {
                visible: table.selectable
                width: visible ? 48 : 0
                height: 38
                color: "#fafafa"
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
                model: table.layoutColumns
                Rectangle {
                    id: headerCell
                    required property var modelData
                    required property int index
                    width: modelData.width || 150
                    height: 38
                    color: "#fafafa"
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
                        color: "#f0f0f0"
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
                                for (var i = 0; i < table.layoutColumns.length; ++i) {
                                    if (targetX >= pos)
                                        to = i;
                                    pos += table.layoutColumns[i].width || 150;
                                }
                                table.moveColumn(headerCell.index, to);
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
                            copy[headerCell.index] = Object.assign({}, copy[headerCell.index], {
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
                height: 42
                color: table.selected.indexOf(modelData[table.keyRole]) >= 0 ? "#e6f4ff" : rowHover.hovered ? "#fafafa" : "white"
                HoverHandler {
                    id: rowHover
                }
                Row {
                    height: parent.height
                    Item {
                        visible: table.selectable
                        width: visible ? 48 : 0
                        height: 42
                        WCheck {
                            anchors.centerIn: parent
                            checked: table.selected.indexOf(rowItem.modelData[table.keyRole]) >= 0
                            onClicked: table.toggle(rowItem.modelData)
                        }
                    }
                    Repeater {
                        model: table.layoutColumns
                        Item {
                            id: cell
                            required property var modelData
                            width: modelData.width || 150
                            height: 42
                            readonly property var raw: rowItem.modelData[modelData.key]
                            readonly property string display: modelData.format ? modelData.format(raw, rowItem.modelData) : raw === null || raw === undefined ? "—" : String(raw)
                            WText {
                                anchors.fill: parent
                                anchors.margins: 10
                                visible: cell.modelData.key !== "actions"
                                text: cell.display
                                font.pixelSize: 13
                                font.bold: !!rowItem.modelData.fixed || !!cell.modelData.bold
                                color: cell.modelData.color ? cell.modelData.color(cell.raw, rowItem.modelData) : cell.modelData.link ? "#1677ff" : "#262626"
                                horizontalAlignment: cell.modelData.align === "right" ? Text.AlignRight : Text.AlignLeft
                                HoverHandler {
                                    id: textHover
                                }
                                ToolTip.visible: textHover.hovered && truncated
                                ToolTip.text: cell.display
                                ToolTip.delay: 600
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !!cell.modelData.link
                                cursorShape: Qt.PointingHandCursor
                                onClicked: table.cellClicked(rowItem.modelData, cell.modelData.key)
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                visible: cell.modelData.key === "actions"
                                WButton {
                                    text: "↗"
                                    small: true
                                    hint: "打开目录"
                                    onClicked: table.action(rowItem.modelData, "folder")
                                }
                                WButton {
                                    text: "×"
                                    small: true
                                    tone: "danger"
                                    hint: "删除报告"
                                    onClicked: table.action(rowItem.modelData, "delete")
                                }
                            }
                            WButton {
                                visible: !!cell.modelData.rename
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 3
                                text: "✎"
                                small: true
                                hint: "编辑任务名称"
                                onClicked: table.action(rowItem.modelData, "rename")
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: "#f0f0f0"
                }
            }
        }
        WText {
            x: Math.max(0, horizontal.contentX)
            y: 90
            width: horizontal.width
            visible: table.rows.length === 0
            text: table.emptyText
            color: "#8c8c8c"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
