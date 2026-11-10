import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: table
    property var rows: []
    property var columns: []
    property bool selectable: false
    property bool numberedSelection: false
    property int rowHeight: 44
    property bool fillColumns: false
    // Let an enclosing page own vertical scrolling while retaining horizontal columns.
    property bool expandVertically: false
    implicitHeight: expandVertically ? 38 + Math.max(rows.length * rowHeight, rows.length ? 0 : 100) + (tableWidth > width ? 12 : 0) : 0
    property var selected: []
    property string keyRole: "sessionDir"
    property string sortKey: ""
    property bool descending: false
    property string emptyText: "暂无数据"
    property string preferenceKey: ""
    property bool editableColumns: false
    property bool resizableColumns: true
    // Keep widths outside the column model: replacing the Repeater model while
    // dragging destroys the MouseArea that owns the pointer grab.
    property var columnWidths: ({})
    property bool resizingColumn: false
    signal columnWidthsEdited(var widths)
    property var layoutColumns: columns
    readonly property var visibleColumns: layoutColumns.filter(function (c) {
        return !c.hidden;
    })
    readonly property real tableWidth: visibleColumns.reduce(function (s, c) {
        return s + baseColumnWidth(c);
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
    function baseColumnWidth(c) {
        return columnWidths[c.key] === undefined ? (c.width || 150) : columnWidths[c.key];
    }
    function columnWidth(c) {
        return baseColumnWidth(c) + (fillColumns && Object.keys(columnWidths).length === 0 ? Math.max(0, horizontal.width - tableWidth) / Math.max(1, visibleColumns.length) : 0);
    }
    readonly property real renderedTableWidth: visibleColumns.reduce(function (s, c) {
        return s + columnWidth(c);
    }, selectable ? 48 : 0)
    function beginResize() {
        var widths = Object.assign({}, columnWidths);
        visibleColumns.forEach(function (c) { widths[c.key] = columnWidth(c); });
        resizingColumn = true;
        columnWidths = widths;
    }
    function finishResize() {
        resizingColumn = false;
        saveLayout();
        columnWidthsEdited(columnWidths);
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
                    width: baseColumnWidth(c),
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
        columnWidths = ({});
        layoutColumns = columns.map(function (c) {
            return Object.assign({}, c);
        });
        saveLayout();
        columnWidthsEdited(columnWidths);
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
        boundsBehavior: Flickable.StopAtBounds
        interactive: !table.resizingColumn
        ScrollBar.horizontal: ScrollBar {
            policy: table.tableWidth > horizontal.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
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
                id: headerCells
                model: table.visibleColumns
                Rectangle {
                    id: headerCell
                    objectName: "header-" + modelData.key
                    z: modelData.lockedRight ? 3 : modelData.locked ? 1 : 0
                    transform: Translate {
                        x: headerCell.modelData.lockedRight ? horizontal.contentX + horizontal.width - table.renderedTableWidth : headerCell.modelData.locked ? horizontal.contentX : 0
                    }
                    required property var modelData
                    required property int index
                    width: table.columnWidth(modelData)
                    height: 38
                    color: modelData.headerBackground || T.chrome
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: headerCell.modelData.align === "right" ? headerCell.width - width - 10 : 10
                        spacing: 8
                        WText {
                            width: Math.min(implicitWidth, Math.max(0, headerCell.width - 20 - (sortIndicator.visible ? 22 : 0)))
                            text: headerCell.modelData.title
                            color: headerCell.modelData.headerColor || T.text
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Canvas {
                            id: sortIndicator
                            objectName: "sortIndicator-" + headerCell.modelData.key
                            visible: table.sortKey === headerCell.modelData.key
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 10
                            rotation: table.descending ? 0 : 180
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = T.accent;
                                ctx.beginPath();
                                ctx.moveTo(0, 1);
                                ctx.lineTo(width, 1);
                                ctx.lineTo(width / 2, height - 1);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
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
                        anchors.rightMargin: table.resizableColumns && !headerCell.modelData.lockedRight ? 9 : 0
                        preventStealing: table.editableColumns && !headerCell.modelData.locked && !headerCell.modelData.lockedRight
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
                                    pos += table.columnWidth(table.visibleColumns[i]);
                                }
                                table.moveColumn(table.layoutColumns.findIndex(function (c) {
                                    return c.key === headerCell.modelData.key;
                                }), table.layoutColumns.findIndex(function (c) {
                                    return c.key === table.visibleColumns[to].key;
                                }));
                            } else if (headerCell.modelData.sortable !== false) {
                                if (table.sortKey !== headerCell.modelData.key) {
                                    table.sortKey = headerCell.modelData.key;
                                    table.descending = false;
                                } else if (!table.descending) {
                                    table.descending = true;
                                } else {
                                    table.sortKey = "";
                                    table.descending = false;
                                }
                            }
                        }
                    }

                }
            }
        }
        ListView {
            id: list
            objectName: "tableRows"
            interactive: !table.expandVertically
            x: 0
            y: 38
            width: horizontal.contentWidth
            height: horizontal.height - 38 - (table.tableWidth > horizontal.width ? 12 : 0)
            clip: true
            model: table.sortedRows
            reuseItems: true
            ScrollBar.vertical: ScrollBar {
                policy: table.expandVertically ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
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
                            selectionNumber: table.numberedSelection ? table.selected.indexOf(rowItem.modelData[table.keyRole]) + 1 : 0
                            Accessible.name: table.numberedSelection ? (checked ? "已选第 " + selectionNumber + " 份报告" + (selectionNumber === 1 ? "，默认基准" : "") : "选择报告") : text
                            checked: table.selected.indexOf(rowItem.modelData[table.keyRole]) >= 0
                            onClicked: table.toggle(rowItem.modelData)
                        }
                    }
                    Repeater {
                        model: table.visibleColumns
                        Rectangle {
                            id: cell
                            objectName: "cell-" + modelData.key + "-" + rowItem.index
                            color: rowItem.color
                            z: modelData.lockedRight ? 3 : modelData.locked ? 1 : 0
                            transform: Translate {
                                x: cell.modelData.lockedRight ? horizontal.contentX + horizontal.width - table.renderedTableWidth : cell.modelData.locked ? horizontal.contentX : 0
                            }
                            required property var modelData
                            width: table.columnWidth(modelData)
                            height: table.rowHeight
                            readonly property var raw: rowItem.modelData[modelData.key]
                            readonly property string display: modelData.format ? modelData.format(raw, rowItem.modelData) : raw === null || raw === undefined ? "—" : String(raw)
                            WIcon {
                                objectName: "cellIcon-" + cell.modelData.key + "-" + rowItem.index
                                visible: !!cell.modelData.icon
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                name: cell.modelData.icon ? cell.modelData.icon(cell.raw, rowItem.modelData) : ""
                                width: 18
                                height: 18
                            }
                            Rectangle {
                                visible: !!cell.modelData.swatch
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: cell.modelData.swatch ? cell.modelData.swatch(cell.raw, rowItem.modelData) : "transparent"
                            }
                            Rectangle {
                                visible: !!cell.modelData.bar
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, cell.width - 132)
                                height: 8
                                radius: 2
                                color: T.border
                                Rectangle {
                                    width: parent.width * (cell.modelData.bar ? Math.max(0, Math.min(1, cell.modelData.bar(cell.raw, rowItem.modelData))) : 0)
                                    height: parent.height
                                    radius: parent.radius
                                    color: cell.modelData.color ? cell.modelData.color(cell.raw, rowItem.modelData) : T.accent
                                }
                            }
                            Column {
                                x: cell.modelData.icon ? 38 : cell.modelData.swatch ? 28 : cell.modelData.bar ? Math.max(12, cell.width - 118) : 12
                                width: cell.width - x - 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                visible: cell.modelData.key !== "actions" && !cell.modelData.secondaryInline
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
                                    visible: !!cell.modelData.secondary && text.length > 0
                                    width: parent.width
                                    text: cell.modelData.secondary ? cell.modelData.secondary(cell.raw, rowItem.modelData) : ""
                                    color: cell.modelData.secondaryColor ? cell.modelData.secondaryColor(cell.raw, rowItem.modelData) : T.muted
                                    font.pixelSize: 12
                                    horizontalAlignment: cell.modelData.align === "right" ? Text.AlignRight : Text.AlignLeft
                                }
                            }
                            Row {
                                id: inlineValues
                                objectName: "inlineValues-" + cell.modelData.key + "-" + rowItem.index
                                visible: !!cell.modelData.secondaryInline
                                property string delta: cell.modelData.secondary ? cell.modelData.secondary(cell.raw, rowItem.modelData) : ""
                                width: Math.min(implicitWidth, cell.width - 24)
                                x: cell.modelData.align === "right" ? cell.width - width - 12 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: delta.length ? 6 : 0
                                WText {
                                    objectName: "inlinePrimary-" + cell.modelData.key + "-" + rowItem.index
                                    text: cell.display
                                    width: Math.min(implicitWidth, Math.max(0, cell.width - 24 - inlineDelta.width - inlineValues.spacing))
                                    height: 22
                                    font.pixelSize: 14
                                    font.weight: rowItem.modelData.fixed || cell.modelData.bold ? Font.DemiBold : Font.Normal
                                    color: cell.modelData.color ? cell.modelData.color(cell.raw, rowItem.modelData) : T.text
                                }
                                WText {
                                    id: inlineDelta
                                    objectName: "inlineDelta-" + cell.modelData.key + "-" + rowItem.index
                                    text: inlineValues.delta
                                    width: Math.min(implicitWidth, Math.max(0, cell.width - 24))
                                    height: 22
                                    font.pixelSize: 12
                                    color: cell.modelData.secondaryColor ? cell.modelData.secondaryColor(cell.raw, rowItem.modelData) : T.muted
                                }
                                HoverHandler { id: inlineHover }
                                ToolTip.visible: inlineHover.hovered
                                ToolTip.text: cell.display + (delta.length ? " " + delta : "")
                                ToolTip.delay: 600
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
    // Own the drag in stable table coordinates. A moving column edge (or a
    // clamped horizontal scroll position) must not change the drag delta.
    MouseArea {
        id: resizeHandle
        objectName: "columnResizeHandle"
        width: table.width
        height: 38
        z: 10
        enabled: table.resizableColumns
        hoverEnabled: true
        preventStealing: true
        property string activeKey: ""
        property real startX: 0
        property real startWidth: 0
        function columnAt(pointerX) {
            for (var i = 0; i < headerCells.count; ++i) {
                var h = headerCells.itemAt(i);
                if (!h || h.modelData.lockedRight) continue;
                var edge = h.mapToItem(table, h.width, 0).x;
                if (pointerX < edge - 9 || pointerX > edge) continue;
                var covered = false;
                for (var j = 0; j < headerCells.count; ++j) {
                    var other = headerCells.itemAt(j);
                    if (!other || other.z <= h.z) continue;
                    var left = other.mapToItem(table, 0, 0).x;
                    if (pointerX >= left && pointerX < left + other.width) covered = true;
                }
                if (!covered) return h;
            }
            return null;
        }
        cursorShape: activeKey || columnAt(mouseX) ? Qt.SplitHCursor : Qt.ArrowCursor
        onPressed: function(mouse) {
            var h = columnAt(mouse.x);
            if (!h) { mouse.accepted = false; return; }
            activeKey = h.modelData.key;
            startX = mouse.x;
            startWidth = h.width;
            table.beginResize();
        }
        onPositionChanged: function(mouse) {
            if (!pressed || !activeKey) return;
            var widths = Object.assign({}, table.columnWidths);
            widths[activeKey] = Math.max(70, startWidth + mouse.x - startX);
            table.columnWidths = widths;
        }
        onReleased: {
            if (!activeKey) return;
            activeKey = "";
            table.finishResize();
        }
        onCanceled: {
            if (!activeKey) return;
            activeKey = "";
            table.finishResize();
        }
    }

}
