import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Woody.Native
import "Format.js" as F

Column {
    id: root
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
    spacing: 14
    StatCards {
        width: parent.width
        height: 90
        values: [
            {
                label: "Total Pss",
                value: F.bytes(root.total.pssTotalKb),
                color: "#1677ff"
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
        width: parent.width
        height: Math.min(340, Math.max(180, Object.keys(root.snapshot.categories || {}).length * 22 + 40)) + 96
        title: "分类占用（Pss）"
        Row {
            width: parent.width
            height: parent.height - 26
            spacing: 8
            SnapshotPlot {
                id: pie
                width: Math.min(440, parent.width * .46)
                height: parent.height
                snapshot: root.snapshot
                mode: "pie"
            }
            SnapshotPlot {
                id: bar
                width: parent.width - pie.width - 8
                height: parent.height
                snapshot: root.snapshot
                mode: "bar"
            }
        }
        Row {
            anchors.bottom: parent.bottom
            spacing: 6
            Repeater {
                model: [
                    {
                        name: "PurgSum",
                        value: root.snapshot.purgSumKb
                    },
                    {
                        name: "PurgPin",
                        value: root.snapshot.purgPinKb
                    },
                    {
                        name: "Dma",
                        value: root.snapshot.dmaKb
                    },
                    {
                        name: "Total Ashmem",
                        value: root.snapshot.ashmemTotalKb
                    }
                ]
                WTag {
                    required property var modelData
                    visible: modelData.value > 0
                    text: modelData.name + ": " + F.bytes(modelData.value)
                    ink: "#595959"
                    tint: "#fafafa"
                }
            }
        }
        ChartTip {
            source: pie
            data: pie.tooltip
            alpha: 1
        }
        ChartTip {
            source: bar
            data: bar.tooltip
            alpha: 1
        }
    }
    WCard {
        width: parent.width
        height: 44 + Math.min(720, 38 + root.rows.length * 42 + 12)
        title: "分类明细表"
        padding: 0
        DataTable {
            anchors.fill: parent
            rows: root.rows
            sortKey: "pssTotalKb"
            descending: true
            columns: [
                {
                    key: "name",
                    title: "分类",
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
        visible: root.detailTabs.length > 0
        width: parent.width
        height: 420
        title: "段明细"
        padding: 10
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            Row {
                spacing: 4
                Repeater {
                    model: root.detailTabs
                    WButton {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        tone: root.detailIndex === index ? "primary" : "default"
                        onClicked: root.detailIndex = index
                    }
                }
            }
            DataTable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                property string kind: root.detailTabs.length ? root.detailTabs[Math.min(root.detailIndex, root.detailTabs.length - 1)].key : ""
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
                color: "#8c8c8c"
            }
        }
    }
}
