import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "Format.js" as F

ColumnLayout {
    id: root
    property string filter: "all"
    property var selected: []
    property var toDelete: []
    readonly property var selectedRecords: backend.records.filter(function (r) {
        return root.selected.indexOf(r.sessionDir) >= 0;
    })
    readonly property bool mixed: selectedRecords.some(function (r) {
        return (r.type || "trend") !== (root.selectedRecords[0].type || "trend");
    })
    readonly property var filtered: backend.records.filter(function (r) {
        var q = search.text.toLowerCase();
        return (root.filter === "all" || (r.type || "trend") === root.filter) && [r.bundleName, r.taskName, (r.device || {}).marketName, (r.device || {}).serialNumber].some(function (s) {
            return String(s || "").toLowerCase().indexOf(q) >= 0;
        });
    }).map(function (r) {
        var d = r.device || {};
        return Object.assign({}, r, {
            taskName: F.title(r),
            duration: r.type === "snapshot" ? 0 : (r.endedAt || Date.now()) - r.startedAt,
            device_name: d.marketName || d.model || "",
            device_ver: (d.softwareVersion || "") + " " + (d.apiVersion || ""),
            device_sn: d.serialNumber || d.targetId || ""
        });
    })
    spacing: 14
    function confirmDelete(dirs) {
        toDelete = dirs;
        removeDialog.open();
    }
    RowLayout {
        Layout.fillWidth: true
        WText {
            text: "查看报告"
            font.pixelSize: 20
            font.bold: true
        }
        WTag {
            text: String(backend.records.length)
            ink: "#595959"
            tint: "#fafafa"
        }
        Item {
            Layout.fillWidth: true
        }
        WButton {
            text: "恢复默认布局"
            small: true
            onClicked: table.resetLayout()
        }
        WButton {
            text: "导入历史目录"
            onClicked: importDialog.open()
        }
        WButton {
            text: "↻ 刷新"
            onClicked: backend.refreshRecords()
        }
    }
    WText {
        Layout.fillWidth: true
        text: "点击任务名称打开独立报告窗口；选择 2～4 份同类型报告进行对比。"
        font.pixelSize: 12
        color: "#8c8c8c"
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                {
                    key: "all",
                    label: "全部"
                },
                {
                    key: "trend",
                    label: "持续采样"
                },
                {
                    key: "snapshot",
                    label: "内存快照"
                }
            ]
            WButton {
                required property var modelData
                text: modelData.label + " (" + backend.records.filter(function (r) {
                    return modelData.key === "all" || (r.type || "trend") === modelData.key;
                }).length + ")"
                tone: root.filter === modelData.key ? "primary" : "default"
                onClicked: root.filter = modelData.key
            }
        }
        WField {
            id: search
            Layout.fillWidth: true
            placeholderText: "搜索任务、应用、设备或序列号"
        }
        WButton {
            text: "对比 " + root.selected.length + " 份报告"
            tone: "primary"
            enabled: root.selected.length >= 2 && root.selected.length <= 4 && !root.mixed
            onClicked: backend.openCompare(root.selected)
        }
    }
    WText {
        visible: root.mixed || root.selected.length > 4
        text: root.mixed ? "持续采样与内存快照不可互相对比" : "最多选择 4 份报告"
        color: "#fa8c16"
        font.pixelSize: 12
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "white"
        radius: 8
        border.color: "#f0f0f0"
        DataTable {
            id: table
            anchors.fill: parent
            rows: root.filtered
            selectable: true
            selected: root.selected
            editableColumns: true
            preferenceKey: "reports.columns.v1"
            sortKey: "startedAt"
            descending: true
            emptyText: "暂无报告，先开始一次持续采样或拍摄内存快照"
            columns: [
                {
                    key: "type",
                    title: "类型",
                    width: 110,
                    locked: true,
                    format: function (v) {
                        return v === "snapshot" ? "📷 内存快照" : "📈 持续采样";
                    }
                },
                {
                    key: "taskName",
                    title: "任务名称",
                    width: 240,
                    locked: true,
                    link: true,
                    rename: true,
                    format: function (v, r) {
                        return F.title(r);
                    }
                },
                {
                    key: "bundleName",
                    title: "应用",
                    width: 180
                },
                {
                    key: "startedAt",
                    title: "采样时间",
                    width: 175,
                    format: F.date
                },
                {
                    key: "duration",
                    title: "时长",
                    width: 100,
                    format: function (v, r) {
                        return r.type === "snapshot" ? "—" : F.duration((r.endedAt || Date.now()) - r.startedAt);
                    }
                },
                {
                    key: "device_name",
                    title: "设备型号",
                    width: 260,
                    format: function (v, r) {
                        return (r.device || {}).marketName || (r.device || {}).model || "—";
                    }
                },
                {
                    key: "device_ver",
                    title: "版本 (API)",
                    width: 140,
                    format: function (v, r) {
                        var d = r.device || {};
                        return (d.softwareVersion || "—") + (d.apiVersion ? " (" + d.apiVersion + ")" : "");
                    }
                },
                {
                    key: "device_sn",
                    title: "序列号",
                    width: 190,
                    format: function (v, r) {
                        return (r.device || {}).serialNumber || (r.device || {}).targetId || "—";
                    }
                },
                {
                    key: "actions",
                    title: "操作",
                    width: 90,
                    sortable: false
                }
            ]
            onSelectionChangedByUser: function (keys) {
                root.selected = keys;
            }
            onCellClicked: function (row, key) {
                backend.openReport(row.sessionDir);
            }
            onAction: function (row, name) {
                if (name === "folder")
                    backend.revealPath(row.sessionDir);
                else if (name === "rename")
                    root.Window.window.rename(row.sessionDir, F.title(row));
                else
                    root.confirmDelete([row.sessionDir]);
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        WText {
            text: "已选 " + root.selected.length + " 项"
            font.pixelSize: 12
            color: "#8c8c8c"
        }
        WButton {
            text: "全选"
            small: true
            onClicked: root.selected = root.filtered.map(function (r) {
                return r.sessionDir;
            })
        }
        WButton {
            text: "清空选择"
            small: true
            enabled: root.selected.length > 0
            onClicked: root.selected = []
        }
        Item {
            Layout.fillWidth: true
        }
        WButton {
            text: "删除所选报告"
            tone: "danger"
            enabled: root.selected.length > 0
            onClicked: root.confirmDelete(root.selected)
        }
    }
    FolderDialog {
        id: importDialog
        title: "选择历史报告目录（包含 meta.json）"
        onAccepted: backend.openReport(backend.fromFileUrl(selectedFolder))
    }
    Dialog {
        id: removeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 440
        modal: true
        title: "删除报告"
        standardButtons: Dialog.Ok | Dialog.Cancel
        WText {
            width: parent.width
            text: "确定删除这 " + root.toDelete.length + " 份报告及其原始采集文件？此操作无法撤销。"
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        onAccepted: {
            backend.deleteReports(root.toDelete);
            root.selected = root.selected.filter(function (p) {
                return root.toDelete.indexOf(p) < 0;
            });
        }
    }
}
