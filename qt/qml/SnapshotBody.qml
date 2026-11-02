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
    property string chartMode: "bar"
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
        Layout.fillWidth: true
        Layout.preferredHeight: 280
        Layout.minimumHeight: 260
        title: "内存构成"
        extras: Row {
            spacing: 4
            WButton {
                objectName: "barChartButton"
                text: "条形图"
                small: true
                tone: root.chartMode === "bar" ? "selected" : "default"
                onClicked: root.chartMode = "bar"
            }
            WButton {
                objectName: "pieChartButton"
                text: "环形图"
                small: true
                tone: root.chartMode === "pie" ? "selected" : "default"
                onClicked: root.chartMode = "pie"
            }
        }
        RowLayout {
            anchors.fill: parent
            spacing: 24
            SnapshotPlot {
                id: composition
                objectName: "snapshotPlot"
                Layout.fillWidth: true
                Layout.fillHeight: true
                snapshot: root.snapshot
                mode: root.chartMode
            }
            Column {
                visible: root.width >= 800
                Layout.preferredWidth: 200
                spacing: 18
                Repeater {
                    model: [
                        {
                            name: "Dma",
                            value: root.snapshot.dmaKb
                        },
                        {
                            name: "Ashmem",
                            value: root.snapshot.ashmemTotalKb
                        },
                        {
                            name: "PurgSum",
                            value: root.snapshot.purgSumKb
                        },
                        {
                            name: "PurgPin",
                            value: root.snapshot.purgPinKb
                        }
                    ]
                    RowLayout {
                        required property var modelData
                        width: parent.width
                        WText {
                            text: modelData.name
                            color: T.muted
                            Layout.fillWidth: true
                        }
                        WText {
                            text: modelData.value === undefined ? "—" : F.bytes(modelData.value)
                        }
                    }
                }
            }
        }
        ChartTip {
            source: composition
            data: composition.tooltip
            alpha: 1
        }
    }
    Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: 8
        visible: root.width < 800
        Repeater {
            model: [
                {
                    name: "Dma",
                    value: root.snapshot.dmaKb
                },
                {
                    name: "Ashmem",
                    value: root.snapshot.ashmemTotalKb
                },
                {
                    name: "PurgSum",
                    value: root.snapshot.purgSumKb
                },
                {
                    name: "PurgPin",
                    value: root.snapshot.purgPinKb
                }
            ]
            WTag {
                required property var modelData
                text: modelData.name + "  " + (modelData.value === undefined ? "—" : F.bytes(modelData.value))
            }
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
        Layout.fillHeight: true
        Layout.minimumHeight: 180
        title: ""
        padding: 0
        DataTable {
            anchors.fill: parent
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
        Layout.fillHeight: true
        Layout.minimumHeight: 180
        title: ""
        padding: 10
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            DataTable {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
