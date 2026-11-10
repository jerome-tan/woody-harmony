import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as NativeDialogs
import Woody.Native
import "Format.js" as F
import "Theme.js" as T

WindowBase {
    id: win
    objectName: "compareWindow"
    initialWidth: 1440
    initialHeight: 960
    property var reports: []
    readonly property var ordered: baseline ? [baseline].concat(reports.filter(function(r) { return r !== baseline; })) : reports
    readonly property var activeReports: ordered.filter(function(r) { return hiddenReports.indexOf(r.meta.sessionDir) < 0; })
    property int baselineIndex: 0
    readonly property var baseline: reports.length ? reports[Math.min(baselineIndex, reports.length - 1)] : null
    property var picked: ({})
    property int tab: 1
    property string metric: "Total"
    property string alignment: "start"
    property real tipAlpha: .8
    property var hiddenReports: []
    property real split: Math.max(25, Math.min(75, Number(backend.uiPreference("compare.chartWidth.v4", 42))))
    property bool exporting: false
    readonly property bool snapshots: ordered.length > 0 && ordered[0].meta.type === "snapshot"
    readonly property bool snapshotPair: snapshots && ordered.length === 2
    readonly property int otherSnapshotIndex: baselineIndex === 0 ? 1 : 0
    property int snapshotFilter: 0
    readonly property var snapshotRows: differenceRows.map(function (r) {
        return Object.assign({}, r, {
            delta: r["d" + otherSnapshotIndex],
            ratio: r.base && r["d" + otherSnapshotIndex] !== null ? r["d" + otherSnapshotIndex] / r.base : null
        });
    }).filter(function (r) {
        return r.fixed || snapshotFilter === 0 || (snapshotFilter === 1 ? r.delta > 0 : snapshotFilter === 2 ? r.delta < 0 : r.delta !== null && r.delta !== 0);
    })
    readonly property var metricOptions: {
        var a = ["Total", "Private Dirty", "Swap Pss", "Heap Alloc"];
        ordered.forEach(function (r) {
            r.categories.forEach(function (c) {
                if (a.indexOf(c) < 0)
                    a.push(c);
            });
        });
        return a;
    }
    readonly property var differenceColumns: {
        var result = [
            {
                key: "name",
                title: "分类",
                format: F.categoryName,
                width: 130,
                bold: true,
                locked: true
            }
        ];
        activeReports.forEach(function (r) {
            var i = reports.indexOf(r);
            result.push({
                key: "v" + i,
                title: win.label(r) + (i === baselineIndex ? "（基准）" : ""),
                headerColor: Qt.darker(win.color(r), 1.25),
                headerBackground: Qt.tint("white", Qt.rgba(win.color(r).r, win.color(r).g, win.color(r).b, .09)),
                width: ordered.length >= 4 ? (i === baselineIndex ? 130 : 180) : 220,
                align: "right",
                format: function (v) {
                    return v === null ? "—" : F.bytes(v);
                },
                secondaryInline: true,
                secondary: function (v, row) {
                    return i === baselineIndex ? "" : row["d" + i] === null ? "(—)" : "(" + F.delta(row["d" + i]) + ")";
                },
                secondaryColor: function (v, row) {
                    return win.deltaColor(row["d" + i]);
                }
            });
        });
        return result;
    }
    readonly property var differenceRows: buildDifferences()
    transientParent: null
    caption: snapshots ? "快照对比" : "趋势对比"
    function label(r) {
        var name = F.title(r.meta), duplicate = reports.filter(function (o) {
            return F.title(o.meta) === name;
        }).length > 1;
        return String.fromCharCode(65 + reports.indexOf(r)) + " · " + name + (duplicate ? " · " + F.date(r.meta.startedAt) : "");
    }
    function color(r) {
        return Qt.color(backend.comparisonColor(reports.indexOf(r)));
    }
    function deltaColor(v) {
        return T.memoryDeltaColor(v);
    }
    function percent(delta, base) {
        return base === null || base === 0 || delta === null ? "—" : (delta >= 0 ? "+" : "−") + (Math.abs(delta / base) * 100).toFixed(1) + "%";
    }
    function selected(r) {
        var key = r.meta.sessionDir;
        return picked[key] === undefined ? r.peakIndex("Total") : picked[key];
    }
    function selectPoint(r, index) {
        var next = Object.assign({}, picked);
        next[r.meta.sessionDir] = Math.max(0, Math.min(r.count - 1, index));
        picked = next;
    }
    function buildDifferences() {
        var values = reports.map(function (r) {
            var sample = snapshots ? r.snapshot : r.sampleAt(selected(r));
            return snapshots || F.validSample(sample) ? sample : ({});
        });
        var names = ["Total"];
        values.forEach(function (s, i) {
            if (hiddenReports.indexOf(reports[i].meta.sessionDir) >= 0) return;
            Object.keys(s.categories || {}).forEach(function (k) {
                if (names.indexOf(k) < 0)
                    names.push(k);
            });
        });
        return names.map(function (name) {
            var row = {
                name: name,
                fixed: name === "Total",
                maxDiff: 0
            };
            var raw = values.map(function (s) {
                return name === "Total" ? (s.total ? s.total.pssTotalKb : null) : (s.categories && s.categories[name] ? s.categories[name].pssTotalKb : null);
            });
            row.base = raw[win.baselineIndex] === undefined ? null : raw[win.baselineIndex];
            raw.forEach(function (v, i) {
                row["v" + i] = v;
                row["d" + i] = v === null || row.base === null ? null : v - row.base;
                if (i !== win.baselineIndex && hiddenReports.indexOf(reports[i].meta.sessionDir) < 0)
                    row.maxDiff = Math.max(row.maxDiff, Math.abs(row["d" + i] || 0));
            });
            return row;
        }).sort(function (a, b) {
            return a.fixed ? -1 : b.fixed ? 1 : b.maxDiff - a.maxDiff;
        });
    }
    Component.onCompleted: {
        var map = {};
        reports.forEach(function (r, i) {
            map[r.meta.sessionDir] = r.peakIndex("Total");
            r.compareColor = backend.comparisonColor(i);
        });
        picked = map;
    }
    Component.onDestruction: reports.forEach(function (r) {
        backend.releaseReport(r);
    })
    function setBaseline(r) {
        hiddenReports = hiddenReports.filter(function(key) { return key !== r.meta.sessionDir; });
        baselineIndex = reports.indexOf(r);
        Qt.callLater(function() {
            if (!win.snapshots && win.tab === 1 && comparisonLoader.item)
                comparisonLoader.item.resetScroll();
        });
    }
    function toggleReport(r) {
        if (r === baseline) return;
        var next = hiddenReports.slice(), index = next.indexOf(r.meta.sessionDir);
        if (index < 0) next.push(r.meta.sessionDir); else next.splice(index, 1);
        hiddenReports = next;
    }
    function exportOptions() {
        var table = comparisonLoader.item.exportTable;
        var columns = table.visibleColumns;
        return {
            title: caption,
            mode: snapshots ? "snapshot" : tab === 0 ? "overlay" : "picked",
            baseline: 0,
            names: activeReports.map(function(r) { return win.label(r); }),
            indices: activeReports.map(function(r) { return win.selected(r); }),
            metric: metric, alignment: alignment,
            headers: columns.map(function(c) { return {text:c.title, width:c.width || 150, align:c.align || "left", color:c.headerColor || T.text, background:c.headerBackground || T.chrome}; }),
            rows: table.sortedRows.map(function(row) {
                return {fixed: !!row.fixed, cells: columns.map(function(c) {
                    var v = row[c.key];
                    return {text: c.format ? c.format(v,row) : v === null || v === undefined ? "—" : String(v),
                        secondary: c.secondary ? c.secondary(v,row) : "",
                        secondaryInline: !!c.secondaryInline,
                        color: c.color ? c.color(v,row) : T.text,
                        secondaryColor: c.secondaryColor ? c.secondaryColor(v,row) : T.muted};
                })};
            })
        };
    }
    function exportImage(action) {
        if (exporting || !comparisonLoader.item) return;
        exporting = true;
        Qt.callLater(function() {
            if (!imageExporter.prepare(win.activeReports, win.exportOptions())) {
                win.notify(imageExporter.error);
                exporting = false;
                return;
            }
            if (action === "copy") {
                if (imageExporter.copy()) win.notify("完整对比图片已复制");
                else win.notify(imageExporter.error);
                imageExporter.clear();
                exporting = false;
            } else {
                imageFile.selectedFile = imageExporter.defaultFile();
                imageFile.open();
            }
        });
    }
    ComparisonImageExporter { id: imageExporter; objectName: "comparisonImageExporter" }
    NativeDialogs.FileDialog {
        id: imageFile
        objectName: "comparisonImageFile"
        title: "另存为完整对比图片"
        fileMode: NativeDialogs.FileDialog.SaveFile
        nameFilters: ["PNG 图片 (*.png)"]
        defaultSuffix: "png"
        onAccepted: {
            if (imageExporter.save(selectedFile)) win.notify("完整对比图片已保存");
            else win.notify(imageExporter.error);
            imageExporter.clear(); exporting = false;
        }
        onRejected: { imageExporter.clear(); exporting = false; }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.width < 900 ? 12 : 16
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            WButton {
                objectName: "pickedTab"
                visible: !win.snapshots
                text: "采样点对比"
                tone: win.tab === 1 ? "selected" : "default"
                onClicked: win.tab = 1
            }
            WButton {
                objectName: "overlayTab"
                visible: !win.snapshots
                text: "趋势叠加"
                tone: win.tab === 0 ? "selected" : "default"
                onClicked: win.tab = 0
            }
            Item { Layout.fillWidth: true }
            WButton {
                id: exportButton
                objectName: "exportComparison"
                text: win.exporting ? "生成中…" : "一键截图"
                iconName: "CameraOutlined"
                enabled: !win.exporting
                hint: "生成完整趋势图和表格，不受滚动位置影响"
                onClicked: exportMenu.open()
                WMenu {
                    id: exportMenu
                    objectName: "comparisonExportMenu"
                    y: exportButton.height + 4
                    x: exportButton.width - width
                    Action { text: "复制图片"; onTriggered: win.exportImage("copy") }
                    Action { text: "另存为…"; onTriggered: win.exportImage("save") }
                }
            }
        }
        Flow {
            visible: win.snapshots || win.tab === 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            spacing: 12
            Repeater {
                model: win.ordered
                Row {
                    required property var modelData
                    required property int index
                    spacing: 6
                    WCheck {
                        objectName: "overlayReportVisible-" + win.reports.indexOf(modelData)
                        enabled: modelData !== win.baseline
                        checked: win.hiddenReports.indexOf(modelData.meta.sessionDir) < 0
                        Accessible.name: "显示 " + win.label(modelData)
                        onClicked: win.toggleReport(modelData)
                    }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: win.color(modelData) }
                    WText { width: Math.min(240, implicitWidth); height: 28; text: win.label(modelData); font.pixelSize: 12; color: Qt.darker(win.color(modelData), 1.25) }
                    WTag {
                        visible: modelData === win.baseline
                        anchors.verticalCenter: parent.verticalCenter
                        text: "当前基准"
                        ink: T.error
                        tint: "white"
                    }
                    WButton {
                        objectName: "reportBaseline-" + win.reports.indexOf(modelData)
                        visible: modelData !== win.baseline
                        text: "设为基准"
                        small: true
                        onClicked: win.setBaseline(modelData)
                    }
                }
            }
        }
        Loader {
            id: comparisonLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: win.snapshots ? snapshotCompare : win.tab === 0 ? overlayCompare : pickedCompare
        }
    }
    Component {
        id: overlayCompare
        ColumnLayout {
            property alias exportTable: summaryTable
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                WText {
                    visible: win.width >= 800
                    text: "对比指标"
                    color: T.muted
                    font.pixelSize: 12
                }
                WCombo {
                    objectName: "metricPicker"
                    Layout.preferredWidth: win.width < 800 ? 140 : 180
                    model: win.metricOptions
                    currentIndex: win.metricOptions.indexOf(win.metric)
                    onActivated: win.metric = win.metricOptions[currentIndex]
                }
                Item {
                    Layout.fillWidth: true
                }
                WText {
                    visible: win.width >= 900
                    text: "时间对齐"
                    color: T.muted
                    font.pixelSize: 12
                }
                Repeater {
                    model: [
                        {
                            key: "start",
                            label: "开始"
                        },
                        {
                            key: "peak",
                            label: "峰值"
                        },
                        {
                            key: "end",
                            label: "结束"
                        }
                    ]
                    WButton {
                        required property var modelData
                        text: modelData.label
                        small: true
                        tone: win.alignment === modelData.key ? "selected" : "default"
                        onClicked: win.alignment = modelData.key
                    }
                }
                WButton {
                    objectName: "comparisonDisplayOptions"
                    text: "显示选项"
                    small: true
                    onClicked: overlayChart.openDisplayOptions(this)
                }
                WButton {
                    objectName: "maximizeChart"
                    iconName: "ExpandOutlined"
                    hint: "展开图表"
                    small: true
                    onClicked: overlayChart.expandChart()
                }
            }
            SplitView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: Qt.Vertical
                handle: Rectangle {
                    implicitHeight: 8
                    color: SplitHandle.hovered ? T.selected : T.chrome
                }
                MemoryChart {
                    id: overlayChart
                    comparison: true
                    SplitView.fillHeight: true
                    SplitView.minimumHeight: 160
                    reports: win.ordered
                    hiddenReports: win.hiddenReports
                    metric: win.metric
                    alignment: win.alignment
                    controls: false
                    legend: false
                    tooltipAlpha: win.tipAlpha
                    points: false
                }
                WCard {
                    SplitView.preferredHeight: Math.min(288, Math.max(150, win.height - 580))
                    SplitView.minimumHeight: 110
                    title: "指标差异"
                    padding: 0
                    extras: WText {
                        width: Math.min(400, win.width * .5)
                        height: 26
                        text: "相对：" + (win.baseline ? win.label(win.baseline) : "")
                        color: T.muted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                    }
                    DataTable {
                        id: summaryTable
                    objectName: "summaryTable"
                        fillColumns: true
                        anchors.fill: parent
                        rows: win.activeReports.map(function (r) {
                            var i = win.reports.indexOf(r);
                            return Object.assign({
                                name: win.label(r) + (i === win.baselineIndex ? "  基准" : ""),
                                color: win.color(r),
                                baseline: i === win.baselineIndex,
                                peakDiff: win.baseline && win.baseline.stats.validCount && r.stats.validCount ? r.stats.peak - win.baseline.stats.peak : null,
                                index: i
                            }, r.stats);
                        })
                        columns: [
                            {
                                key: "name",
                                title: "报告",
                                width: Math.max(230, (win.width - 80) * .27),
                                swatch: function (v, r) {
                                    return r.color;
                                }
                            },
                            {
                                key: "peak",
                                title: "峰值 PSS",
                                width: 120,
                                align: "right",
                                format: function (v, r) {
                                    return r.validCount ? F.bytes(v) : "—";
                                }
                            },
                            {
                                key: "avg",
                                title: "均值",
                                width: 120,
                                align: "right",
                                format: function (v, r) {
                                    return r.validCount ? F.bytes(v) : "—";
                                }
                            },
                            {
                                key: "last",
                                title: "结束值",
                                width: 120,
                                align: "right",
                                format: function (v, r) {
                                    return r.validCount ? F.bytes(v) : "—";
                                }
                            },
                            {
                                key: "growth",
                                title: "增长量",
                                width: 130,
                                align: "right",
                                format: function (v, r) {
                                    return r.validCount ? F.delta(v) : "—";
                                },
                                color: function (v) {
                                    return win.deltaColor(v);
                                }
                            },
                            {
                                key: "peakDiff",
                                title: "峰值差值",
                                width: 200,
                                align: "right",
                                format: function (v, r) {
                                    return r.baseline || v === null ? "—" : F.delta(v) + " (" + win.percent(v, win.baseline.stats.peak) + ")";
                                },
                                color: function (v, r) {
                                    return r.baseline ? T.muted : win.deltaColor(v);
                                }
                            }
                        ]
                    }
                }
            }
        }
    }
    Component {
        id: pickedCompare
        SplitView {
            id: pickedSplit
            objectName: "pickedSplit"
            property alias exportTable: pickedTable
            function resetScroll() { miniScroll.contentItem.contentY = 0; }
            orientation: Qt.Horizontal
            onResizingChanged: if (!resizing && width > 0) {
                win.split = Math.max(25, Math.min(75, miniScroll.width / width * 100));
                backend.setUiPreference("compare.chartWidth.v4", win.split);
                miniScroll.SplitView.preferredWidth = Qt.binding(function() {
                    return Math.max(280, pickedSplit.width * win.split / 100);
                });
            }
            handle: Rectangle {
                objectName: "comparisonSplitHandle"
                implicitWidth: 10
                color: SplitHandle.hovered || SplitHandle.pressed ? T.selected : T.chrome
                Rectangle {
                    width: 3; height: 32; radius: 1.5
                    anchors.centerIn: parent
                    color: SplitHandle.hovered ? T.accent : T.border
                }
            }
            ScrollView {
                id: miniScroll
                objectName: "miniScroll"
                SplitView.preferredWidth: Math.max(280, pickedSplit.width * win.split / 100)
                SplitView.minimumWidth: 280
                SplitView.maximumWidth: Math.max(280, pickedSplit.width - 330)
                clip: true
                contentWidth: availableWidth
                contentHeight: chartColumn.height
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Column {
                    id: chartColumn
                    width: miniScroll.availableWidth
                    spacing: 8
                    Repeater {
                        model: win.ordered
                        CompareSampleCard {
                            required property var modelData
                            required property int index
                            objectName: "sampleCard-" + win.reports.indexOf(modelData)
                            width: chartColumn.width
                            height: shown ? Math.max(280, (miniScroll.availableHeight - (win.ordered.length - 1) * 8) / Math.max(1, win.ordered.length)) : 84
                            report: modelData
                            ordinal: win.reports.indexOf(modelData)
                            isBaseline: modelData === win.baseline
                            onBaselineRequested: win.setBaseline(modelData)
                            reportTitle: win.label(modelData)
                            selectedIndex: win.selected(modelData)
                            shown: win.hiddenReports.indexOf(modelData.meta.sessionDir) < 0
                            tooltipAlpha: win.tipAlpha
                            onPointPicked: function(point) { win.selectPoint(modelData, point); }
                            onVisibilityToggled: win.toggleReport(modelData)
                        }
                    }
                }
            }
            DataTable {
                id: pickedTable
                objectName: "differenceTable"
                SplitView.fillWidth: true
                SplitView.minimumWidth: 320
                rows: win.differenceRows
                columns: win.differenceColumns
                fillColumns: true
                rowHeight: 44
            }
        }
    }
    Component {
        id: snapshotCompare
        ColumnLayout {
            property alias exportTable: snapshotTable
            spacing: 16
            Rectangle {
                objectName: "snapshotSummary"
                visible: win.snapshotPair && win.activeReports.length === 2
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: T.selected
                radius: 6
                property var total: win.differenceRows.length ? win.differenceRows[0] : ({})
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16
                    WText {
                        text: "Total PSS"
                        font.weight: Font.DemiBold
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    WText {
                        text: parent.parent.total.base === null ? "—" : F.bytes(parent.parent.total.base)
                        font.pixelSize: win.width < 900 ? 16 : 20
                        font.weight: Font.DemiBold
                    }
                    WIcon {
                        name: "RightOutlined"
                        tone: "muted"
                    }
                    WText {
                        text: parent.parent.total["v" + win.otherSnapshotIndex] === null ? "—" : F.bytes(parent.parent.total["v" + win.otherSnapshotIndex])
                        font.pixelSize: win.width < 900 ? 16 : 20
                        font.weight: Font.DemiBold
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    WText {
                        property var total: parent.parent.total
                        text: total["d" + win.otherSnapshotIndex] === null ? "—" : F.delta(total["d" + win.otherSnapshotIndex]) + " (" + win.percent(total["d" + win.otherSnapshotIndex], total.base) + ")"
                        font.pixelSize: win.width < 900 ? 14 : 20
                        font.weight: Font.DemiBold
                        color: win.deltaColor(total["d" + win.otherSnapshotIndex])
                    }
                }
            }
            WCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "分类差异"
                padding: 0
                extras: Row {
                    spacing: 16
                    WText {
                        visible: win.width >= 900
                        width: Math.min(350, win.width * .25)
                        height: 28
                        text: "相对：" + (win.baseline ? win.label(win.baseline) : "")
                        color: T.muted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                    }
                    WCombo {
                        objectName: "snapshotDifferenceFilter"
                        visible: win.snapshotPair
                        width: 160
                        implicitHeight: 28
                        model: ["显示：全部分类", "显示：仅增长", "显示：仅下降", "显示：有变化"]
                        currentIndex: win.snapshotFilter
                        onActivated: win.snapshotFilter = currentIndex
                    }
                }
                DataTable {
                    id: snapshotTable
                    objectName: "differenceTable"
                    anchors.fill: parent
                    rows: win.snapshotPair ? win.snapshotRows : win.differenceRows
                    columns: win.differenceColumns
                    fillColumns: true
                    rowHeight: 44
                }
            }
        }
    }
}
