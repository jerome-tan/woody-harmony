import "Theme.js" as T
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "Format.js" as F

ColumnLayout {
    id: root
    objectName: "reportsPage"
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
            text: "报告库"
            font.pixelSize: 20
            font.bold: true
        }
        Item {
            Layout.fillWidth: true
        }
        WButton {
            text: "恢复默认布局"
            onClicked: table.resetLayout()
        }
        WButton {
            text: "导入报告"
            onClicked: importDialog.open()
        }
        WButton {
            hint: "刷新报告"
            iconName: "ReloadOutlined"
            onClicked: backend.refreshRecords()
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width < 760 ? 1 : 2
        columnSpacing: 8
        rowSpacing: 8
        RowLayout {
            spacing: 8
            Repeater {
                model: [
                    {
                        key: "all",
                        label: "全部"
                    },
                    {
                        key: "trend",
                        label: "内存录制"
                    },
                    {
                        key: "snapshot",
                        label: "内存快照"
                    }
                ]
                WButton {
                    required property var modelData
                    objectName: "reportFilter-" + modelData.key
                    iconName: modelData.key === "trend" ? "LineChartOutlined" : modelData.key === "snapshot" ? "CameraOutlined" : ""
                    text: modelData.label + " (" + backend.records.filter(function (r) {
                        return modelData.key === "all" || (r.type || "trend") === modelData.key;
                    }).length + ")"
                    tone: root.filter === modelData.key ? "primary" : "default"
                    onClicked: root.filter = modelData.key
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            WField {
                id: search
                objectName: "reportSearch"
                Layout.minimumWidth: 0
                Layout.fillWidth: true
                placeholderText: "搜索报告、应用或设备"
            }
            WButton {
                id: columnsButton
                objectName: "columnsButton"
                text: "显示列"
                small: true
                onClicked: columnsPopup.open()
                Popup {
                    id: columnsPopup
                    objectName: "columnsPopup"
                    y: columnsButton.height + 4
                    x: columnsButton.width - width
                    width: 200
                    padding: 12
                    focus: true
                    background: Rectangle {
                        color: "white"
                        radius: 6
                        border.color: T.border
                    }
                    Column {
                        spacing: 8
                        Repeater {
                            model: table.layoutColumns
                            WCheck {
                                required property var modelData
                                objectName: "column-" + modelData.key
                                text: modelData.title
                                checked: !modelData.hidden
                                enabled: !modelData.locked
                                onClicked: table.toggleColumn(modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "white"
        radius: 8
        border.color: T.border
        DataTable {
            id: table
            objectName: "reportsTable"
            anchors.fill: parent
            rows: root.filtered
            selectable: true
            numberedSelection: true
            selected: root.selected
            editableColumns: true
            preferenceKey: "reports.columns.v1"
            sortKey: "startedAt"
            descending: true
            emptyText: "暂无报告，完成采集后会显示在这里"
            columns: [
                {
                    key: "taskName",
                    title: "报告名称",
                    width: 240,
                    locked: true,
                    link: true,
                    format: function (v, r) {
                        return F.title(r);
                    }
                },
                {
                    key: "type",
                    title: "类型",
                    width: 110,
                    locked: true,
                    icon: function (v) {
                        return v === "snapshot" ? "CameraOutlined" : "LineChartOutlined";
                    },
                    format: function (v) {
                        return v === "snapshot" ? "内存快照" : "内存录制";
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
                    hidden: true,
                    title: "版本 (API)",
                    width: 140,
                    format: function (v, r) {
                        var d = r.device || {};
                        return (d.softwareVersion || "—") + (d.apiVersion ? " (" + d.apiVersion + ")" : "");
                    }
                },
                {
                    key: "device_sn",
                    hidden: true,
                    title: "序列号",
                    width: 190,
                    format: function (v, r) {
                        return (r.device || {}).serialNumber || (r.device || {}).targetId || "—";
                    }
                },
                {
                    key: "actions",
                    title: "操作",
                    lockedRight: true,
                    locked: true,
                    width: 64,
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
    Rectangle {
        visible: root.selected.length > 0
        Layout.fillWidth: true
        implicitHeight: 64
        radius: 6
        color: T.chrome
        border.color: T.border
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            WText {
                text: "已选 " + root.selected.length + " 份报告"
                font.weight: Font.DemiBold
            }
            WText {
                Layout.fillWidth: true
                text: root.mixed ? "请选择同类型报告进行对比" : root.selected.length > 4 ? "最多对比 4 份报告" : root.selected.length < 2 ? "至少选择 2 份报告" : ""
                color: T.positive
                font.pixelSize: 12
            }
            WButton {
                text: "清除选择"
                small: true
                onClicked: root.selected = []
            }
            WButton {
                text: "删除"
                small: true
                tone: "danger"
                onClicked: root.confirmDelete(root.selected)
            }
            WButton {
                objectName: "compareReportsButton"
                text: "对比报告"
                tone: "primary"
                enabled: root.selected.length >= 2 && root.selected.length <= 4 && !root.mixed
                onClicked: backend.openCompare(root.selected)
            }
        }
    }
    FolderDialog {
        id: importDialog
        title: "选择历史报告目录（包含 meta.json）"
        onAccepted: backend.openReport(backend.fromFileUrl(selectedFolder))
    }
    WDialog {
        id: removeDialog
        objectName: "removeDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 440
        modal: true
        title: "删除报告"
        acceptText: "删除报告"
        acceptTone: "danger"
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
