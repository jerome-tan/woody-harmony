import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ScrollView {
    id: root
    property bool toolsOnly: false
    signal navigate(string page)
    clip: true
    readonly property var tools: [
        {
            route: "watch",
            icon: "📡",
            color: "#52c41a",
            name: "实时内存",
            tag: "实时查看 · 不落盘",
            desc: "对应 DevEco Profiler 的实时监控（Realtime Monitor）：以实时图表观察进程内存的瞬时变化，数据仅保留在内存中——不写盘、不生成报告，适合随手的临时观察。"
        },
        {
            route: "snap",
            icon: "📷",
            color: "#faad14",
            name: "内存快照",
            tag: "单次采集 · 快照报告",
            desc: "对应 DevEco Profiler 的 Snapshot：对目标进程执行一次 hidumper --mem，定格当前时刻的完整内存构成（分类 Pss、私有脏、Swap、Heap 明细等），适合抓取异常现场、对比前后差异。"
        },
        {
            route: "peak",
            icon: "📈",
            color: "#1677ff",
            name: "持续内存采样",
            tag: "周期采集 · 趋势报告",
            desc: "按固定间隔执行 hidumper --mem 持续录制（对应 DevEco Allocation 的 Memory 泳道语义），追踪内存随时间的变化曲线，定位峰值与疑似泄漏点，结束后自动生成趋势报告。"
        }
    ]
    Column {
        width: root.availableWidth
        spacing: 22
        Rectangle {
            visible: !root.toolsOnly
            width: parent.width
            height: 184
            radius: 14
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: "#0b3d91"
                }
                GradientStop {
                    position: .55
                    color: "#1677ff"
                }
                GradientStop {
                    position: 1
                    color: "#4da3ff"
                }
            }
            Column {
                x: 34
                y: 30
                width: parent.width - 68
                spacing: 12
                WText {
                    text: "Woody"
                    font.pixelSize: 22
                    font.bold: true
                    color: "white"
                }
                WText {
                    width: parent.width
                    text: "HarmonyOS 设备内存分析工具 · 连接设备、采集数据、定位内存问题"
                    font.pixelSize: 13
                    color: "#d6e9ff"
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: ["设备连接", "实时内存", "快照分析", "采样对比"]
                        Rectangle {
                            required property string modelData
                            width: tagLabel.implicitWidth + 20
                            height: 27
                            radius: 14
                            color: "#33ffffff"
                            WText {
                                id: tagLabel
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 12
                                color: "white"
                            }
                        }
                    }
                }
            }
        }
        WText {
            text: root.toolsOnly ? "工具集" : "内存分析工具"
            font.pixelSize: 20
            font.bold: true
        }
        GridLayout {
            width: parent.width
            columns: Math.max(1, Math.floor((width + 16) / 326))
            columnSpacing: 16
            rowSpacing: 16
            Repeater {
                model: root.tools
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 310
                    Layout.preferredHeight: 256
                    radius: 8
                    color: "white"
                    border.color: toolHover.hovered ? modelData.color : "#f0f0f0"
                    HoverHandler {
                        id: toolHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.navigate(modelData.route)
                    }
                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 12
                        Row {
                            spacing: 12
                            Rectangle {
                                property color accent: modelData.color
                                width: 42
                                height: 42
                                radius: 10
                                color: Qt.rgba(accent.r, accent.g, accent.b, .12)
                                WText {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.pixelSize: 24
                                }
                            }
                            WText {
                                text: modelData.name
                                height: 42
                                font.pixelSize: 17
                                font.bold: true
                            }
                        }
                        WTag {
                            text: modelData.tag
                            ink: modelData.color
                            tint: "#fafafa"
                        }
                        WText {
                            width: parent.width
                            text: modelData.desc
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                            lineHeight: 1.55
                            font.pixelSize: 12
                            color: "#8c8c8c"
                        }
                    }
                }
            }
        }
        WText {
            visible: !root.toolsOnly
            width: parent.width
            text: "通过 hdc 连接 HarmonyOS 设备，使用 hidumper 获取系统内存数据。"
            color: "#8c8c8c"
            font.pixelSize: 12
        }
    }
}
