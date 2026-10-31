import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F

WindowBase {
    id: win
    objectName: "compareWindow"
    width: 1440
    height: 873
    property var reports: []
    property var ordered: reports.slice()
    property var picked: ({})
    property int tab: 0
    property string metric: "Total"
    property string alignment: "start"
    property real tipAlpha: .8
    property real split: Number(backend.uiPreference("compare.split.v1", 55))
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
                title: "分类 / 指标",
                width: 140,
                bold: true
            }
        ];
        ordered.forEach(function (r, i) {
            result.push({
                key: "v" + i,
                title: win.label(r) + (i === 0 ? "（基准）" : ""),
                width: 190,
                align: "right",
                color: function (v, row) {
                    if (i === 0)
                        return "#262626";
                    var diff = row["d" + i];
                    return diff > 512 ? "#ff4d4f" : diff < -512 ? "#389e0d" : "#262626";
                },
                format: function (v, row) {
                    return v === null ? "—" : F.mb(v) + " MB" + (i > 0 && row["d" + i] !== null ? " (" + F.delta(row["d" + i]) + ")" : "");
                }
            });
        });
        return result;
    }
    readonly property var differenceRows: buildDifferences()
    transientParent: null
    caption: "对比 " + ordered.length + " 份报告"
    badge: snapshots ? "📷 内存快照对比" : "📈 持续采样对比"
    captionNote: "独立窗口 · 关闭后不影响原报告"
    function label(r) {
        var t = F.title(r.meta), dupes = reports.filter(function (o) {
            return F.title(o.meta) === t;
        });
        return dupes.length > 1 ? t + " (" + (dupes.indexOf(r) + 1) + ")" : t;
    }
    function color(r) {
        return F.comparisonColors[reports.indexOf(r) % 4];
    }
    function selected(r) {
        var key = r.meta.sessionDir;
        return picked[key] === undefined ? r.peakIndex("Total") : picked[key];
    }
    function selectPoint(r, index) {
        var next = Object.assign({}, picked);
        next[r.meta.sessionDir] = index;
        picked = next;
    }
    function move(from, to) {
        var next = ordered.slice();
        next.splice(to, 0, next.splice(from, 1)[0]);
        ordered = next;
    }
    function buildDifferences() {
        var values = ordered.map(function (r) {
            return snapshots ? r.snapshot : r.sampleAt(selected(r));
        });
        var names = ["Total"];
        values.forEach(function (s) {
            Object.keys(s.categories || {}).forEach(function (k) {
                if (names.indexOf(k) < 0)
                    names.push(k);
            });
        });
        var result = names.map(function (name) {
            var row = {
                name: name,
                fixed: name === "Total",
                maxDiff: 0
            };
            values.forEach(function (s, i) {
                var v = name === "Total" ? (s.total ? s.total.pssTotalKb : null) : (s.categories && s.categories[name] ? s.categories[name].pssTotalKb : (snapshots ? 0 : null));
                row["v" + i] = v;
                var base = row.v0;
                row["d" + i] = v === null || base === null ? null : v - base;
                if (i > 0)
                    row.maxDiff = Math.max(row.maxDiff, Math.abs(row["d" + i] || 0));
            });
            return row;
        });
        result.sort(function (a, b) {
            if (a.name === "Total")
                return -1;
            if (b.name === "Total")
                return 1;
            return b.maxDiff - a.maxDiff;
        });
        return result;
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
        anchors.margins: 12
        spacing: 12
        Flow {
            id: order
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 8
            WText {
                height: 28
                text: "对比顺序（首个为基准，拖拽调整）："
                font.pixelSize: 12
                color: "#8c8c8c"
            }
            Repeater {
                id: chips
                model: win.ordered
                Rectangle {
                    id: chip
                    required property var modelData
                    required property int index
                    width: Math.min(500, chipText.implicitWidth + (index === 0 ? 82 : 42))
                    height: 28
                    radius: 6
                    color: index === 0 ? "#f0f7ff" : "white"
                    border.color: index === 0 ? "#91caff" : "#e5e5e5"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6
                        WText {
                            text: "⠿"
                            color: "#bfbfbf"
                            font.pixelSize: 12
                        }
                        Rectangle {
                            width: 9
                            height: 9
                            radius: 2
                            color: win.color(chip.modelData)
                        }
                        WText {
                            id: chipText
                            Layout.fillWidth: true
                            text: win.label(chip.modelData)
                            font.pixelSize: 12
                            font.bold: true
                        }
                        WTag {
                            visible: chip.index === 0
                            text: "基准"
                            implicitHeight: 20
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.OpenHandCursor
                        onReleased: function (mouse) {
                            var p = mapToItem(order, mouse.x, mouse.y);
                            var nearest = chip.index, dist = Infinity;
                            for (var i = 0; i < chips.count; ++i) {
                                var item = chips.itemAt(i), center = item.mapToItem(order, item.width / 2, item.height / 2), d = Math.hypot(center.x - p.x, center.y - p.y);
                                if (d < dist) {
                                    dist = d;
                                    nearest = i;
                                }
                            }
                            win.move(chip.index, nearest);
                        }
                    }
                }
            }
        }
        Row {
            visible: !win.snapshots
            spacing: 14
            height: 38
            WButton {
                text: "📈 趋势叠加对比"
                tone: win.tab === 0 ? "primary" : "default"
                onClicked: win.tab = 0
            }
            WButton {
                text: "🎯 采样点对比"
                tone: win.tab === 1 ? "primary" : "default"
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
        id: opacityControl
        Row {
            spacing: 6
            Slider {
                width: 76
                height: 26
                from: .3
                to: 1
                value: win.tipAlpha
                onMoved: win.tipAlpha = value
            }
            WText {
                text: "透明度"
                height: 26
                font.pixelSize: 12
                color: "#8c8c8c"
            }
        }
    }
    Component {
        id: overlayCompare
        ScrollView {
            id: overlayScroll
            clip: true
            Column {
                width: overlayScroll.availableWidth
                spacing: 14
                WCard {
                    width: parent.width
                    height: 400
                    title: "指标趋势叠加"
                    padding: 8
                    extras: [
                        Row {
                            spacing: 10
                            Loader {
                                sourceComponent: opacityControl
                            }
                            WText {
                                text: "对比指标"
                                height: 26
                                font.pixelSize: 12
                                color: "#8c8c8c"
                            }
                            WCombo {
                                width: 170
                                height: 26
                                model: win.metricOptions.map(function (m) {
                                    return m === "Total" ? "Total Pss" : m;
                                })
                                currentIndex: win.metricOptions.indexOf(win.metric)
                                onActivated: win.metric = win.metricOptions[currentIndex]
                            }
                            WText {
                                text: "时间对齐"
                                height: 26
                                font.pixelSize: 12
                                color: "#8c8c8c"
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
                                    tone: win.alignment === modelData.key ? "primary" : "default"
                                    onClicked: win.alignment = modelData.key
                                }
                            }
                        }
                    ]
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4
                        Flow {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            spacing: 8
                            Repeater {
                                model: win.ordered
                                Row {
                                    required property var modelData
                                    spacing: 5
                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: win.color(modelData)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    WText {
                                        text: win.label(modelData)
                                        width: Math.min(350, implicitWidth)
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                        MemoryChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            controls: false
                            legend: false
                            reports: win.ordered
                            metric: win.metric
                            alignment: win.alignment
                            tooltipAlpha: win.tipAlpha
                            points: false
                        }
                    }
                }
                WCard {
                    width: parent.width
                    height: 44 + 38 + 42 * win.ordered.length + 12
                    title: "关键指标差异（Total Pss）"
                    padding: 0
                    DataTable {
                        anchors.fill: parent
                        rows: win.ordered.map(function (r, i) {
                            return Object.assign({
                                name: win.label(r),
                                startedAt: r.meta.startedAt,
                                count: r.count,
                                peakDiff: r.stats.peak - win.ordered[0].stats.peak,
                                index: i
                            }, r.stats);
                        })
                        columns: [
                            {
                                key: "name",
                                title: "报告",
                                width: 340,
                                bold: true
                            },
                            {
                                key: "startedAt",
                                title: "采样时间",
                                width: 175,
                                format: F.date
                            },
                            {
                                key: "peak",
                                title: "峰值 Pss",
                                width: 120,
                                align: "right",
                                format: F.bytes,
                                color: function () {
                                    return "#ff4d4f";
                                }
                            },
                            {
                                key: "avg",
                                title: "均值",
                                width: 110,
                                align: "right",
                                format: F.bytes
                            },
                            {
                                key: "last",
                                title: "结束值",
                                width: 110,
                                align: "right",
                                format: F.bytes
                            },
                            {
                                key: "growth",
                                title: "增长幅度",
                                width: 120,
                                align: "right",
                                format: F.delta,
                                color: function (v) {
                                    return v > 0 ? "#ff4d4f" : "#389e0d";
                                }
                            },
                            {
                                key: "durationMs",
                                title: "时长",
                                width: 100,
                                format: F.duration
                            },
                            {
                                key: "count",
                                title: "采样点数",
                                width: 100
                            },
                            {
                                key: "peakDiff",
                                title: "峰值差异",
                                width: 130,
                                align: "right",
                                format: function (v, r) {
                                    return r.index === 0 ? "基准" : F.delta(v);
                                },
                                color: function (v) {
                                    return v > 512 ? "#ff4d4f" : v < -512 ? "#389e0d" : "#262626";
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
        Item {
            id: splitArea
            WCard {
                id: miniCard
                x: 0
                y: 0
                width: Math.max(300, (parent.width - 10) * win.split / 100)
                height: parent.height
                title: "各报告完整趋势（点击小图选取对比点）"
                padding: 10
                extras: Loader {
                    sourceComponent: opacityControl
                }
                ScrollView {
                    id: miniScroll
                    anchors.fill: parent
                    clip: true
                    Column {
                        width: miniScroll.availableWidth
                        spacing: 10
                        Repeater {
                            model: win.ordered
                            WCard {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: Math.max(180, (miniCard.body.height - 10 * (win.ordered.length - 1)) / win.ordered.length)
                                padding: 6
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: 9
                                            height: 9
                                            radius: 2
                                            color: win.color(modelData)
                                        }
                                        WText {
                                            Layout.fillWidth: true
                                            text: win.label(modelData)
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                        WTag {
                                            visible: index === 0
                                            text: "基准"
                                        }
                                        WButton {
                                            text: "选峰值"
                                            small: true
                                            onClicked: win.selectPoint(modelData, modelData.peakIndex("Total"))
                                        }
                                    }
                                    WText {
                                        Layout.fillWidth: true
                                        text: "选中 #" + (win.selected(modelData) + 1) + " · " + F.date(modelData.sampleAt(win.selected(modelData)).timestamp) + " · " + F.bytes((modelData.sampleAt(win.selected(modelData)).total || {}).pssTotalKb)
                                        font.pixelSize: 11
                                        color: "#8c8c8c"
                                    }
                                    MemoryChart {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        controls: false
                                        legend: false
                                        compact: true
                                        reports: [modelData]
                                        selectedIndex: win.selected(modelData)
                                        tooltipAlpha: win.tipAlpha
                                        points: false
                                        onPointSelected: function (point) {
                                            win.selectPoint(modelData, point);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                x: miniCard.width + 2
                y: 0
                width: 6
                height: parent.height
                radius: 3
                color: resizeHover.hovered ? "#91caff" : "#e5e5e5"
                HoverHandler {
                    id: resizeHover
                    cursorShape: Qt.SplitHCursor
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SplitHCursor
                    onPositionChanged: function (mouse) {
                        if (pressed) {
                            var p = mapToItem(splitArea, mouse.x, 0);
                            win.split = Math.max(30, Math.min(75, p.x / (splitArea.width - 10) * 100));
                        }
                    }
                    onReleased: backend.setUiPreference("compare.split.v1", win.split)
                }
            }
            WCard {
                x: miniCard.width + 10
                y: 0
                width: parent.width - x
                height: parent.height
                title: "选中采样点 · 分类差异（MB）"
                padding: 0
                DataTable {
                    anchors.fill: parent
                    rows: win.differenceRows
                    columns: win.differenceColumns
                }
            }
        }
    }
    Component {
        id: snapshotCompare
        WCard {
            title: "内存快照分类差异（MB）"
            padding: 0
            DataTable {
                anchors.fill: parent
                rows: win.differenceRows
                columns: win.differenceColumns
            }
        }
    }
}
