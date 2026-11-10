import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Format.js" as F
import "Theme.js" as T

WCard {
    id: card
    required property var report
    required property int ordinal
    required property string reportTitle
    property int selectedIndex: -1
    property bool shown: true
    property bool isBaseline: false
    readonly property color reportColor: backend.comparisonColor(card.ordinal)
    signal baselineRequested()
    property real tooltipAlpha: .8
    property alias chartItem: chart
    signal pointPicked(int index)
    signal visibilityToggled()
    padding: 8
    Rectangle {
        width: parent.width; height: 34; radius: 4
        color: Qt.rgba(card.reportColor.r, card.reportColor.g, card.reportColor.b, .09)
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 6
            WCheck {
                objectName: "reportVisible-" + card.ordinal
                checked: card.shown
                enabled: !card.isBaseline
                Accessible.name: "显示 " + card.reportTitle
                onClicked: card.visibilityToggled()
            }
            Rectangle {
                width: 10; height: 10; radius: 5
                color: backend.comparisonColor(card.ordinal)
            }
            WText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: card.reportTitle
                color: Qt.darker(card.reportColor, 1.25)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                HoverHandler { id: titleHover }
                ToolTip.visible: titleHover.hovered && truncated
                ToolTip.text: text
                ToolTip.delay: 500
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            WTag {
                objectName: "currentBaseline-" + card.ordinal
                visible: card.isBaseline
                text: "当前基准"
                implicitHeight: 28
                implicitWidth: 72
                ink: T.error
                tint: "white"
            }
            WButton {
                objectName: "setBaseline-" + card.ordinal
                visible: !card.isBaseline
                text: "设为基准"
                small: true
                onClicked: card.baselineRequested()
            }
            WButton {
                objectName: "samplePeak-" + card.ordinal
                text: "选中峰值"
                hint: "定位峰值"
                small: true
                visible: card.shown
                enabled: card.report.stats.validCount > 0
                onClicked: {
                    card.pointPicked(card.report.peakIndex("Total"));
                    chart.plotItem.resetView();
                }
            }
            WButton {
                objectName: "expandSample-" + card.ordinal
                visible: card.shown
                iconName: "ExpandOutlined"
                hint: "放大图表并选择采样点"
                small: true
                onClicked: chart.expandChart()
            }
            Item { Layout.fillWidth: true }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: card.shown
            WText { text: "采样点"; font.pixelSize: 12; color: T.muted }
            WField {
                objectName: "sampleIndex-" + card.ordinal
                Layout.preferredWidth: 56
                implicitHeight: 28
                font.pixelSize: 12
                enabled: card.report.stats.validCount > 0
                text: card.selectedIndex < 0 ? "—" : String(card.selectedIndex + 1)
                validator: IntValidator { bottom: 1; top: Math.max(1, card.report.count) }
                onEditingFinished: {
                    if (acceptableInput)
                        card.pointPicked(Number(text) - 1);
                    text = Qt.binding(function () { return card.selectedIndex < 0 ? "—" : String(card.selectedIndex + 1); });
                }
            }
            WText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: card.selectedIndex < 0 ? "—" : F.duration(Number(card.report.sampleAt(card.selectedIndex).timestamp || 0) - Number(card.report.meta.startedAt || 0))
                font.pixelSize: 12; color: T.muted
            }
            WText {
                text: F.validSample(card.report.sampleAt(card.selectedIndex)) ? F.bytes(card.report.sampleAt(card.selectedIndex).total.pssTotalKb) : "—"
                font.pixelSize: 14; font.weight: Font.DemiBold
            }
        }
        MemoryChart {
            id: chart
            visible: card.shown
            Layout.fillWidth: true
            Layout.fillHeight: true
            controls: false
            legend: false
            compact: true
            comparison: true
            expandedTitle: card.reportTitle
            reports: [card.report]
            hiddenReports: card.shown ? [] : [card.report.meta.sessionDir]
            selectedIndex: card.selectedIndex
            tooltipAlpha: card.tooltipAlpha
            points: false
            onPointSelected: function (point) { card.pointPicked(point); }
        }
    }
}
