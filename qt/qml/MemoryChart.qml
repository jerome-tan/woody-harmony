import "Theme.js" as T
import "Format.js" as F
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Woody.Native

WCard {
    id: chart
    objectName: "memoryChart"
    Layout.minimumHeight: compact ? 80 : 180
    property var reports: []
    property bool live: false
    property bool compact: false
    property bool controls: true
    property bool legend: true
    property string metric: "Total"
    property string alignment: "start"
    property int selectedIndex: -1
    property real tooltipAlpha: .8
    property var hidden: []
    property var hiddenReports: []
    property bool smooth: false
    property bool points: false
    readonly property bool narrow: width < 820
    readonly property bool hasCategories: legend && reports.length === 1
    property alias plotItem: plot
    property bool maximized: false
    function openDisplayOptions(button) {
        displayOptions.parent = button;
        displayOptions.open();
    }
    function expandChart() {
        expanded.open();
    }
    signal pointSelected(int index)
    signal restoreRequested
    title: controls ? "内存趋势" : ""
    padding: compact ? 4 : 8
    extras: Row {
        visible: chart.controls
        spacing: 8
        WButton {
            id: categoriesButton
            objectName: "categoriesButton"
            visible: chart.hasCategories && chart.narrow
            text: "分类 (" + (chart.reports.length ? chart.reports[0].categories.length : 0) + ")"
            small: true
            onClicked: categoriesPopup.open()
        }
        WButton {
            id: displayButton
            objectName: "displayOptionsButton"
            text: "显示选项"
            small: true
            onClicked: displayOptions.open()
        }
        WButton {
            visible: !chart.narrow || chart.live
            text: chart.live && !plot.following ? "跟随最新" : "重置视图"
            small: true
            onClicked: plot.resetView()
        }
        WButton {
            objectName: "maximizeChart"
            iconName: chart.maximized ? "CompressOutlined" : "ExpandOutlined"
            small: true
            hint: chart.maximized ? "还原图表" : "展开图表"
            onClicked: chart.maximized ? chart.restoreRequested() : expanded.open()
        }
    }
    Popup {
        id: displayOptions
        objectName: "displayOptions"
        margins: 8
        parent: displayButton
        x: Math.min(0, parent.width - width)
        y: parent.height + 5
        width: 260
        padding: 16
        focus: true
        background: Rectangle {
            color: "white"
            border.color: T.border
            radius: 6
        }
        Column {
            width: parent.width
            spacing: 14
            WSwitch {
                objectName: "pointsSwitch"
                text: "采样点"
                checked: chart.points
                onClicked: chart.points = checked
            }
            WSwitch {
                objectName: "smoothSwitch"
                text: "平滑曲线"
                checked: chart.smooth
                onClicked: chart.smooth = checked
            }
            Rectangle {
                width: parent.width
                height: 1
                color: T.border
            }
            RowLayout {
                width: parent.width
                WText {
                    text: "悬浮框透明度"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                WText {
                    text: Math.round(chart.tooltipAlpha * 100) + "%"
                    font.pixelSize: 12
                    color: T.muted
                }
            }
            WSlider {
                objectName: "tooltipOpacity"
                width: parent.width
                from: .3
                to: 1
                value: chart.tooltipAlpha
                onMoved: chart.tooltipAlpha = value
            }
            WButton {
                visible: chart.narrow
                width: parent.width
                small: true
                text: "重置视图"
                onClicked: {
                    plot.resetView();
                    displayOptions.close();
                }
            }
        }
    }
    Component {
        id: categoryList
        ScrollView {
            id: categoryScroll
            clip: true
            Column {
                width: categoryScroll.availableWidth
                spacing: 6
                WText {
                    text: "内存分类"
                    color: T.muted
                    font.pixelSize: 12
                    height: 28
                }
                Repeater {
                    model: chart.reports.length ? chart.reports[0].categories : []
                    RowLayout {
                        id: categoryRow
                        required property string modelData
                        required property int index
                        readonly property var sample: chart.reports.length && chart.reports[0].stats.currentValid ? chart.reports[0].sampleAt(chart.reports[0].count - 1) : ({})
                        readonly property var value: modelData === "Total" ? (sample.total || {}).pssTotalKb : ((sample.categories || {})[modelData] || {}).pssTotalKb
                        width: parent.width
                        spacing: 8
                        WCheck {
                            objectName: "category-" + modelData
                            Accessible.name: modelData
                            checked: chart.hidden.indexOf(modelData) < 0
                            onClicked: {
                                var a = chart.hidden.slice(), i = a.indexOf(modelData);
                                if (i < 0)
                                    a.push(modelData);
                                else
                                    a.splice(i, 1);
                                chart.hidden = a;
                            }
                        }
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: backend.colorOf(modelData, index)
                        }
                        WText {
                            Layout.fillWidth: true
                            text: F.categoryName(modelData)
                            font.pixelSize: 12
                            HoverHandler {
                                onHoveredChanged: plot.highlight = hovered ? categoryRow.modelData : ""
                            }
                        }
                        WText {
                            Layout.preferredWidth: 64
                            text: categoryRow.value === undefined ? "—" : F.bytes(categoryRow.value)
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
    Popup {
        id: categoriesPopup
        objectName: "categoriesPopup"
        margins: 8
        parent: categoriesButton
        x: Math.min(0, categoriesButton.width - width)
        y: categoriesButton.height + 5
        width: 220
        height: Math.min(360, chart.height - 8)
        padding: 14
        focus: true
        background: Rectangle {
            color: "white"
            border.color: T.border
            radius: 6
        }
        Loader {
            anchors.fill: parent
            sourceComponent: categoryList
        }
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        MemoryPlot {
            id: plot
            objectName: "memoryPlot"
            Layout.fillWidth: true
            Layout.fillHeight: true
            reports: chart.reports
            live: chart.live
            compact: chart.compact
            metric: chart.metric
            alignment: chart.alignment
            selectedIndex: chart.selectedIndex
            smooth: chart.smooth
            points: chart.points
            hiddenCategories: chart.hidden
            hiddenReports: chart.hiddenReports
            // Move the cursor in the scene graph without repainting/uploading the chart texture.
            Column {
                visible: plot.hoverX >= 0
                x: plot.hoverX
                y: 30
                spacing: 3
                Repeater {
                    model: Math.max(0, Math.floor((plot.height - (chart.compact ? 92 : 114)) / 6))
                    Rectangle {
                        width: 1
                        height: 3
                        color: T.muted
                    }
                }
            }
            onPointSelected: function (index) {
                chart.pointSelected(index);
            }
        }
        Rectangle {
            visible: chart.hasCategories && !chart.narrow
            width: 1
            Layout.fillHeight: true
            color: T.border
        }
        Loader {
            visible: chart.hasCategories && !chart.narrow
            active: visible
            Layout.preferredWidth: 230
            Layout.fillHeight: true
            Layout.leftMargin: visible ? 12 : 0
            sourceComponent: categoryList
        }
    }

    ChartTip {
        objectName: "chartTip"
        data: plot.tooltip
        source: expanded.opened ? null : plot
        alpha: chart.tooltipAlpha
    }
    Popup {
        id: expanded
        objectName: "expandedChart"
        popupType: Popup.Item
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: parent ? parent.width - 20 : 800
        height: parent ? parent.height - 20 : 600
        modal: true
        focus: true
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            color: "white"
            radius: 8
        }
        onOpened: contentItem.forceActiveFocus()
        onAboutToHide: {
            if (!expandedLoader.item)
                return;
            chart.hidden = expandedLoader.item.hidden;
            chart.points = expandedLoader.item.points;
            chart.smooth = expandedLoader.item.smooth;
            chart.tooltipAlpha = expandedLoader.item.tooltipAlpha;
            if (expandedLoader.item.plotItem.following)
                plot.resetView();
            else
                plot.setRange(expandedLoader.item.plotItem.rangeStart, expandedLoader.item.plotItem.rangeEnd);
        }
        contentItem: Item {
            focus: true
            Keys.onEscapePressed: function (event) {
                expanded.close();
                event.accepted = true;
            }
            Loader {
                id: expandedLoader
                anchors.fill: parent
                active: expanded.opened
                source: active ? Qt.resolvedUrl("MemoryChart.qml") : ""
                onLoaded: {
                    item.reports = Qt.binding(function () {
                        return chart.reports;
                    });
                    item.live = Qt.binding(function () {
                        return chart.live;
                    });
                    item.metric = chart.metric;
                    item.alignment = chart.alignment;
                    item.legend = chart.legend;
                    item.hidden = chart.hidden;
                    item.hiddenReports = chart.hiddenReports;
                    item.points = chart.points;
                    item.smooth = chart.smooth;
                    item.maximized = true;
                    item.tooltipAlpha = chart.tooltipAlpha;
                    item.selectedIndex = Qt.binding(function () {
                        return chart.selectedIndex;
                    });
                    if (!plot.following)
                        item.plotItem.setRange(plot.rangeStart, plot.rangeEnd);
                    item.restoreRequested.connect(function () {
                        expanded.close();
                    });
                    item.pointSelected.connect(function (index) {
                        chart.pointSelected(index);
                    });
                }
            }
        }
    }
}
