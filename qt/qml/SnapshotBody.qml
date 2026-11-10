import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Woody.Native
import "Format.js" as F

ColumnLayout {
    id: root
    objectName: "snapshotBody"
    property var snapshot: ({})
    readonly property var total: snapshot.total || {}
    readonly property var rows: F.categoryRows(snapshot)
    readonly property var detailTabs: {
        var tabs = [];
        if (snapshot.ashmemDetail)
            tabs.push({
                key: "ashmem",
                label: "ashmem（" + snapshot.ashmemDetail.length + " 条 · " + F.bytes(snapshot.ashmemDetail.reduce(function (s, r) {
                    return s + r.physicalBytes;
                }, 0) / 1024) + "）"
            });
        if (snapshot.dmabufDetail)
            tabs.push({
                key: "dmabuf",
                label: "dmabuf（" + snapshot.dmabufDetail.length + " 条 · " + F.bytes(snapshot.dmabufDetail.reduce(function (s, r) {
                    return s + r.sizeBytes;
                }, 0) / 1024) + "）"
            });
        if (snapshot.gpuDetail)
            tabs.push({
                key: "gpu",
                label: "gpumem"
            });
        return tabs;
    }
    property int detailIndex: 0
    property string chartMode: "pie"
    readonly property bool sideBySide: width >= 1000
    spacing: 14
    StatCards {
        width: parent.width
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        values: [
            {
                label: "Total Pss",
                value: F.bytes(root.total.pssTotalKb),
                color: T.accent
            },
            {
                label: "Private Dirty",
                value: F.bytes(root.total.privateDirtyKb)
            },
            {
                label: "Swap Pss",
                value: F.bytes(root.total.swapPssTotalKb)
            },
            {
                label: "Heap 已用/容量",
                value: F.bytes(root.total.heapAllocKb) + " / " + F.bytes(root.total.heapSizeKb)
            }
        ]
    }
    WCard {
        objectName: "snapshotComposition"
        Layout.fillWidth: true
        Layout.preferredHeight: 350 + (root.sideBySide ? 0 : 40)
        title: "内存构成"
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            RowLayout {
                objectName: "snapshotChartTabs"
                visible: !root.sideBySide
                Layout.fillWidth: true
                spacing: 4
                WButton {
                    objectName: "pieChartButton"
                    text: "环形图"
                    small: true
                    tone: root.chartMode === "pie" ? "selected" : "default"
                    onClicked: root.chartMode = "pie"
                }
                WButton {
                    objectName: "barChartButton"
                    text: "条形图"
                    small: true
                    tone: root.chartMode === "bar" ? "selected" : "default"
                    onClicked: root.chartMode = "bar"
                }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                SnapshotPlot {
                    id: donut
                    objectName: "snapshotDonutPlot"
                    visible: root.sideBySide || root.chartMode === "pie"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    snapshot: root.snapshot
                    mode: "pie"
                }
                Rectangle {
                    visible: root.sideBySide
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: T.border
                }
                SnapshotPlot {
                    id: bars
                    objectName: "snapshotBarPlot"
                    visible: root.sideBySide || root.chartMode === "bar"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    snapshot: root.snapshot
                    mode: "bar"
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: 8
                Repeater {
                    model: [
                        { name: "Dma", value: root.snapshot.dmaKb },
                        { name: "Ashmem", value: root.snapshot.ashmemTotalKb },
                        { name: "PurgSum", value: root.snapshot.purgSumKb },
                        { name: "PurgPin", value: root.snapshot.purgPinKb }
                    ]
                    WTag {
                        required property var modelData
                        text: modelData.name + "  " + (modelData.value === undefined ? "—" : F.bytes(modelData.value))
                        ink: T.muted
                        tint: T.chrome
                    }
                }
            }
        }
        ChartTip {
            source: donut
            data: donut.visible ? donut.tooltip : ({})
            alpha: 1
        }
        ChartTip {
            source: bars
            data: bars.visible ? bars.tooltip : ({})
            alpha: 1
        }
    }
    Row {
        Layout.fillWidth: true
        spacing: 20
        WTab {
            text: "分类明细"
            selected: root.detailIndex === 0
            onClicked: root.detailIndex = 0
        }
        Repeater {
            model: root.detailTabs
            WTab {
                required property var modelData
                required property int index
                objectName: "detailTab-" + modelData.key
                text: modelData.label
                selected: root.detailIndex === index + 1
                onClicked: root.detailIndex = index + 1
            }
        }
    }
    WCard {
        width: parent.width
        visible: root.detailIndex === 0
        Layout.fillWidth: true
        Layout.preferredHeight: categoryTable.implicitHeight
        title: ""
        padding: 0
        DataTable {
            id: categoryTable
            objectName: "snapshotCategoryTable"
            anchors.fill: parent
            expandVertically: true
            rows: root.rows
            rowHeight: 36
            fillColumns: true
            sortKey: "pssTotalKb"
            descending: true
            columns: [
                {
                    key: "name",
                    locked: true,
                    title: "分类",
                    format: F.categoryName,
                    width: 170
                },
                {
                    key: "pssTotalKb",
                    title: "Pss (MB)",
                    width: 100,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "privateDirtyKb",
                    title: "私有脏 (MB)",
                    width: 112,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "privateCleanKb",
                    title: "私有净 (MB)",
                    width: 112,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "sharedDirtyKb",
                    title: "共享脏 (MB)",
                    width: 112,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "sharedCleanKb",
                    title: "共享净 (MB)",
                    width: 112,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "swapPssTotalKb",
                    title: "Swap (MB)",
                    width: 105,
                    align: "right",
                    format: F.mb
                },
                {
                    key: "heapAllocKb",
                    title: "Heap 已用/容量",
                    width: 180,
                    align: "right",
                    format: function (v, r) {
                        return r.heapSizeKb > 0 ? F.bytes(v) + " / " + F.bytes(r.heapSizeKb) : "—";
                    }
                }
            ]
        }
    }
    WCard {
        visible: root.detailIndex > 0 && root.detailTabs.length > 0
        width: parent.width
        Layout.fillWidth: true
        Layout.preferredHeight: detailContent.implicitHeight + 20
        title: ""
        padding: 10
        ColumnLayout {
            id: detailContent
            anchors.fill: parent
            spacing: 8
            DataTable {
                objectName: "snapshotDetailTable"
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                expandVertically: true
                property string kind: root.detailTabs.length ? root.detailTabs[Math.max(0, Math.min(root.detailIndex - 1, root.detailTabs.length - 1))].key : ""
                rows: kind === "ashmem" ? root.snapshot.ashmemDetail || [] : kind === "dmabuf" ? root.snapshot.dmabufDetail || [] : root.snapshot.gpuDetail ? root.snapshot.gpuDetail.channels || [] : []
                emptyText: "该进程无相关内存块"
                columns: kind === "ashmem" ? [
                    {
                        key: "name",
                        title: "名称",
                        width: 420
                    },
                    {
                        key: "fd",
                        title: "FD",
                        width: 90
                    },
                    {
                        key: "virtualBytes",
                        title: "虚拟大小",
                        width: 160,
                        align: "right",
                        format: function (v) {
                            return F.bytes(v / 1024);
                        }
                    },
                    {
                        key: "physicalBytes",
                        title: "物理大小",
                        width: 160,
                        align: "right",
                        format: function (v) {
                            return F.bytes(v / 1024);
                        }
                    }
                ] : kind === "dmabuf" ? [
                    {
                        key: "name",
                        title: "名称",
                        width: 420
                    },
                    {
                        key: "fd",
                        title: "FD",
                        width: 90
                    },
                    {
                        key: "ino",
                        title: "Inode",
                        width: 160
                    },
                    {
                        key: "sizeBytes",
                        title: "大小",
                        width: 160,
                        align: "right",
                        format: function (v) {
                            return F.bytes(v / 1024);
                        }
                    }
                ] : [
                    {
                        key: "name",
                        title: "通道",
                        width: 420
                    },
                    {
                        key: "totalBytes",
                        title: "大小",
                        width: 200,
                        align: "right",
                        format: function (v) {
                            return F.bytes(v / 1024);
                        }
                    }
                ]
            }
            WText {
                visible: !!root.snapshot.gpuDetail
                text: root.snapshot.gpuDetail ? "GPU 已用：" + F.bytes(root.snapshot.gpuDetail.totalUsedBytes / 1024) + " · 已分配：" + F.bytes(root.snapshot.gpuDetail.totalAllocatedBytes / 1024) : ""
                font.pixelSize: 12
                color: T.muted
            }
        }
    }
}
