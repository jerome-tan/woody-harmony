import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F
import "Theme.js" as T

WindowBase {
    id: win
    objectName: "compareWindow"
    width: 1440
    height: 960
    property var reports: []
    readonly property var ordered: reports
    property int baselineIndex: 0
    readonly property var baseline: ordered.length ? ordered[Math.min(baselineIndex, ordered.length - 1)] : null
    property var picked: ({})
    property int tab: 0
    property string metric: "Total"
    property string alignment: "start"
    property real tipAlpha: .8
    property var hiddenReports: []
    property real split: Number(backend.uiPreference("compare.split.v2", 50))
    readonly property bool snapshots: ordered.length > 0 && ordered[0].meta.type === "snapshot"
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
                width: 150,
                bold: true,
                locked: true
            }
        ];
        ordered.forEach(function (r, i) {
            result.push({
                key: "v" + i,
                title: win.label(r) + (i === baselineIndex ? "（基准）" : ""),
                width: 210,
                align: "right",
                format: function (v) {
                    return v === null ? "—" : F.bytes(v);
                },
                secondary: function (v, row) {
                    return i === baselineIndex ? "基准" : row["d" + i] === null ? "—" : F.delta(row["d" + i]) + "  " + win.percent(row["d" + i], row.base);
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
        return F.comparisonColors[reports.indexOf(r) % 4];
    }
    function deltaColor(v) {
        return v === null || v === 0 ? T.muted : v > 0 ? T.positive : T.negative;
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
        var values = ordered.map(function (r) {
            var sample = snapshots ? r.snapshot : r.sampleAt(selected(r));
            return snapshots || F.validSample(sample) ? sample : ({});
        });
        var names = ["Total"];
        values.forEach(function (s) {
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
                if (i !== win.baselineIndex)
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
            r.compareColor = F.comparisonColors[i % 4];
        });
        picked = map;
    }
    Component.onDestruction: reports.forEach(function (r) {
        backend.releaseReport(r);
    })
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.width < 900 ? 12 : 24
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            WText {
                text: "基准报告"
                font.weight: Font.DemiBold
            }
            WCombo {
                objectName: "baselinePicker"
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                model: win.ordered.map(function (r) {
                    return win.label(r);
                })
                currentIndex: win.baselineIndex
                onActivated: win.baselineIndex = currentIndex
            }
            WText {
                visible: win.width >= 850
                text: win.ordered.length + (win.snapshots ? " 份内存快照" : " 份持续采样报告")
                color: T.muted
                font.pixelSize: 12
            }
            Item {
                Layout.fillWidth: true
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 16
            Repeater {
                model: win.ordered
                Row {
                    required property var modelData
                    required property int index
                    spacing: 7
                    WCheck {
                        objectName: "reportVisible-" + index
                        visible: !win.snapshots
                        checked: win.hiddenReports.indexOf(modelData.meta.sessionDir) < 0
                        Accessible.name: "显示 " + win.label(modelData)
                        onClicked: {
                            var a = win.hiddenReports.slice(), i = a.indexOf(modelData.meta.sessionDir);
                            if (i < 0)
                                a.push(modelData.meta.sessionDir);
                            else
                                a.splice(i, 1);
                            win.hiddenReports = a;
                        }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: win.color(modelData)
                    }
                    WText {
                        height: 26
                        width: Math.min(250, implicitWidth)
                        text: win.label(modelData)
                        font.pixelSize: 12
                    }
                    WTag {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: index === win.baselineIndex
                        text: "基准"
                    }
                }
            }
        }
        Row {
            visible: !win.snapshots
            spacing: 24
            WTab {
                text: "趋势叠加"
                selected: win.tab === 0
                onClicked: win.tab = 0
            }
            WTab {
                objectName: "pickedTab"
                text: "采样点对比"
                selected: win.tab === 1
                onClicked: win.tab = 1
            }
        }
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: win.snapshots ? snapshotCompare : win.tab === 0 ? overlayCompare : pickedCompare
        }
    }
    Component {
        id: overlayCompare
        ColumnLayout {
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
                    SplitView.preferredHeight: 288
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
                        objectName: "summaryTable"
                        fillColumns: true
                        anchors.fill: parent
                        rows: win.ordered.map(function (r, i) {
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
            orientation: Qt.Horizontal
            handle: Rectangle {
                implicitWidth: 8
                color: SplitHandle.hovered ? T.selected : T.chrome
            }
            WCard {
                id: miniCard
                SplitView.preferredWidth: pickedSplit.width * win.split / 100
                SplitView.minimumWidth: 290
                title: "选择采样点"
                padding: 8
                onWidthChanged: if (pickedSplit.resizing) {
                    win.split = width / pickedSplit.width * 100;
                    backend.setUiPreference("compare.split.v2", win.split);
                }
                ScrollView {
                    id: miniScroll
                    objectName: "miniScroll"
                    anchors.fill: parent
                    clip: true
                    Column {
                        width: miniScroll.availableWidth
                        spacing: 12
                        Repeater {
                            model: win.ordered
                            WCard {
                                id: mini
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 250
                                padding: 10
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: win.color(mini.modelData)
                                        }
                                        WText {
                                            Layout.fillWidth: true
                                            text: win.label(mini.modelData)
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                        WTag {
                                            visible: mini.index === win.baselineIndex
                                            text: "基准"
                                        }
                                        WButton {
                                            text: "定位峰值"
                                            small: true
                                            onClicked: win.selectPoint(mini.modelData, mini.modelData.peakIndex("Total"))
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        WText {
                                            text: "采样点"
                                            font.pixelSize: 12
                                            color: T.muted
                                        }
                                        WField {
                                            objectName: "sampleIndex-" + mini.index
                                            Layout.preferredWidth: 62
                                            implicitHeight: 28
                                            font.pixelSize: 12
                                            enabled: mini.modelData.stats.validCount > 0
                                            text: win.selected(mini.modelData) < 0 ? "—" : String(win.selected(mini.modelData) + 1)
                                            validator: IntValidator {
                                                bottom: 1
                                                top: Math.max(1, mini.modelData.count)
                                            }
                                            onEditingFinished: {
                                                win.selectPoint(mini.modelData, Number(text) - 1);
                                                text = Qt.binding(function () {
                                                    return String(win.selected(mini.modelData) + 1);
                                                });
                                            }
                                        }
                                        WText {
                                            Layout.fillWidth: true
                                            text: F.duration(Number(mini.modelData.sampleAt(win.selected(mini.modelData)).timestamp || 0) - Number(mini.modelData.meta.startedAt || 0))
                                            font.pixelSize: 12
                                            color: T.muted
                                        }
                                        WText {
                                            text: F.validSample(mini.modelData.sampleAt(win.selected(mini.modelData))) ? F.bytes(mini.modelData.sampleAt(win.selected(mini.modelData)).total.pssTotalKb) : "—"
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    MemoryChart {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        controls: false
                                        legend: false
                                        compact: true
                                        reports: [mini.modelData]
                                        selectedIndex: win.selected(mini.modelData)
                                        tooltipAlpha: win.tipAlpha
                                        points: false
                                        onPointSelected: function (point) {
                                            win.selectPoint(mini.modelData, point);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            WCard {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 260
                title: "分类差异"
                padding: 0
                extras: WText {
                    width: Math.max(80, parent.parent.width - 150)
                    text: "相对：" + (win.baseline ? win.label(win.baseline) : "")
                    height: 26
                    color: T.muted
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignRight
                }
                DataTable {
                    objectName: "differenceTable"
                    anchors.fill: parent
                    rows: win.differenceRows
                    columns: win.differenceColumns
                    rowHeight: 58
                }
            }
        }
    }
    Component {
        id: snapshotCompare
        WCard {
            title: "分类差异"
            padding: 0
            extras: WText {
                width: Math.min(450, win.width - 220)
                height: 26
                text: "相对：" + (win.baseline ? win.label(win.baseline) : "")
                color: T.muted
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
            }
            DataTable {
                objectName: "differenceTable"
                anchors.fill: parent
                rows: win.differenceRows
                columns: win.differenceColumns
                rowHeight: 58
            }
        }
    }
}
