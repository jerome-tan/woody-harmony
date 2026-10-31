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
    property bool smooth: false
    property bool points: true
    property bool maximized: false
    signal pointSelected(int index)
    signal restoreRequested
    title: controls ? "内存趋势" : ""
    padding: compact ? 4 : 8
    extras: [
        Row {
            visible: chart.controls
            spacing: 10
            Row {
                spacing: 6
                Slider {
                    width: 76
                    height: 26
                    from: .3
                    to: 1
                    value: chart.tooltipAlpha
                    onMoved: chart.tooltipAlpha = value
                }
                WText {
                    text: "透明度"
                    height: 26
                    font.pixelSize: 12
                    color: "#8c8c8c"
                }
            }
            WSwitch {
                text: "显示采样点"
                checked: chart.points
                onClicked: chart.points = checked
            }
            WSwitch {
                text: "平滑曲线"
                checked: chart.smooth
                onClicked: chart.smooth = checked
            }
            WButton {
                text: chart.live && !plot.following ? "跟随最新" : "重置视图"
                small: true
                onClicked: plot.resetView()
            }
            WButton {
                text: chart.maximized ? "↙" : "⛶"
                small: true
                hint: chart.maximized ? "还原" : "最大化图表"
                onClicked: chart.maximized ? chart.restoreRequested() : expanded.open()
            }
        }
    ]
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
            onPointSelected: function (index) {
                chart.pointSelected(index);
            }
        }
        Rectangle {
            visible: chart.legend && chart.reports.length === 1
            width: 1
            Layout.fillHeight: true
            color: "#f0f0f0"
        }
        ScrollView {
            visible: chart.legend && chart.reports.length === 1
            Layout.preferredWidth: 178
            Layout.fillHeight: true
            clip: true
            Column {
                width: 178
                spacing: 3
                leftPadding: 10
                topPadding: 4
                WText {
                    text: "内存分类"
                    color: "#8c8c8c"
                    font.pixelSize: 12
                    height: 25
                }
                Repeater {
                    model: chart.reports.length ? chart.reports[0].categories : []
                    Row {
                        required property string modelData
                        required property int index
                        height: 24
                        spacing: 6
                        WCheck {
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
                            width: 9
                            height: 9
                            radius: 2
                            color: backend.colorOf(modelData, index)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        WText {
                            width: 126
                            text: modelData
                            font.pixelSize: 12
                            height: 24
                            HoverHandler {
                                onHoveredChanged: plot.highlight = hovered ? parent.text : ""
                            }
                        }
                    }
                }
            }
        }
    }
    ChartTip {
        data: plot.tooltip
        source: plot
        alpha: chart.tooltipAlpha
    }
    Popup {
        id: expanded
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
        Loader {
            anchors.fill: parent
            active: expanded.opened
            source: active ? Qt.resolvedUrl("MemoryChart.qml") : ""
            onLoaded: {
                item.reports = Qt.binding(function () { return chart.reports; });
                item.live = Qt.binding(function () { return chart.live; });
                item.metric = chart.metric;
                item.alignment = chart.alignment;
                item.legend = chart.legend;
                item.maximized = true;
                item.tooltipAlpha = chart.tooltipAlpha;
                item.selectedIndex = Qt.binding(function () { return chart.selectedIndex; });
                item.restoreRequested.connect(function () { expanded.close(); });
                item.pointSelected.connect(function (index) { chart.pointSelected(index); });
            }
        }
    }
}
