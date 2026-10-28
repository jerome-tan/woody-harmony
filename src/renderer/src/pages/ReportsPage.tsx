import {
  Alert,
  Button,
  Card,
  Checkbox,
  Empty,
  Input,
  Modal,
  Popconfirm,
  Segmented,
  Table,
  Tag,
  Typography
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  DeleteOutlined,
  EditOutlined,
  FolderOpenOutlined,
  ReloadOutlined,
  UndoOutlined,
  SwapOutlined
} from '@ant-design/icons'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { SamplingSessionMeta } from '@shared/types'
import type { PageProps } from './types'
import { formatDuration } from '../utils'
import { notify } from '../notify'
import ResizableHeaderCell from '../components/ResizableHeaderCell'

/** 列标识 */
type ColKey =
  | 'type'
  | 'task'
  | 'app'
  | 'start'
  | 'duration'
  | 'device_name'
  | 'device_ver'
  | 'device_sn'
  | 'actions'
/** 各列默认宽度（应用列较窄） */
const COL_DEFAULTS: Record<ColKey, number> = {
  type: 96,
  task: 240,
  app: 180,
  start: 175,
  duration: 100,
  device_name: 260,
  device_ver: 140,
  device_sn: 190,
  actions: 84
}

/** 列标题（用于计算最小宽度：不缩到比标题文字还窄） */
const COL_TITLES: Record<ColKey, string> = {
  type: '任务类型',
  task: '任务名称',
  app: '应用',
  start: '开始时间',
  duration: '持续时长',
  device_name: '设备名称',
  device_ver: '系统版本',
  device_sn: '序列号',
  actions: '操作'
}

/** 列最小宽度 = 标题文本 + 内边距 + 排序图标（如有）+ 拖拽把手余量 */
function colMinWidth(key: ColKey): number {
  const sortable = key !== 'actions'
  return COL_TITLES[key].length * 15 + 32 + (sortable ? 24 : 0) + 10
}
const COL_ORDER_DEFAULT: ColKey[] = [
  'type',
  'task',
  'app',
  'start',
  'duration',
  'device_name',
  'device_ver',
  'device_sn',
  'actions'
]
/** 不支持拖拽调整顺序的列（任务类型 / 任务名称固定在前） */
const COL_FIXED_ORDER = new Set<ColKey>(['type', 'task'])
const COL_STORE_KEY = 'reports.columns.v1'

/** 从 localStorage 恢复列布局；损坏或与当前列定义不一致时回退默认 */
function loadColLayout(): { order: ColKey[]; widths: Record<ColKey, number> } {
  try {
    const raw = localStorage.getItem(COL_STORE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as { order?: string[]; widths?: Record<string, number> }
      const keys = new Set<string>(COL_ORDER_DEFAULT)
      const order: ColKey[] =
        Array.isArray(parsed.order) &&
        parsed.order.length === COL_ORDER_DEFAULT.length &&
        parsed.order.every((k) => keys.has(k))
          ? (parsed.order as ColKey[])
          : [...COL_ORDER_DEFAULT]
      const widths = { ...COL_DEFAULTS }
      for (const k of COL_ORDER_DEFAULT) {
        const w = parsed.widths?.[k]
        if (typeof w === 'number' && w >= 56) widths[k] = w
      }
      return { order, widths }
    }
  } catch {
    // ignore
  }
  return { order: [...COL_ORDER_DEFAULT], widths: { ...COL_DEFAULTS } }
}

/** 持续时长（毫秒）；快照无时长，排序时排最前（-1） */
function durationOf(r: SamplingSessionMeta): number {
  return r.type === 'snapshot' ? -1 : (r.endedAt ?? r.startedAt) - r.startedAt
}

function fmtTime(ts: number): string {
  const d = new Date(ts)
  const p = (n: number): string => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}


interface Props extends PageProps {
  records: SamplingSessionMeta[]
  loading: boolean
  lockedDir: string | null
  refreshRecords: () => Promise<void>
}

/** 测试报告：列表管理（筛选/搜索/多选删除/同类型对比） */
export default function ReportsPage(props: Props): JSX.Element {
  const { records, loading, lockedDir } = props
  const [filter, setFilter] = useState<'all' | 'trend' | 'snapshot'>('all')
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<Set<string>>(new Set())

  // 列表变化时清理失效选择
  useEffect(() => {
    setSelected((prev) => {
      const dirs = new Set(records.map((r) => r.sessionDir ?? ''))
      const next = new Set([...prev].filter((d) => dirs.has(d)))
      return next.size === prev.size ? prev : next
    })
  }, [records])

  const filtered = useMemo(() => {
    const kw = query.trim().toLowerCase()
    return records.filter((r) => {
      if (filter !== 'all' && (r.type ?? 'trend') !== filter) return false
      if (kw) {
        const hay = `${r.bundleName} ${r.taskName ?? ''} ${r.device.marketName} ${r.device.serialNumber}`.toLowerCase()
        if (!hay.includes(kw)) return false
      }
      return true
    })
  }, [records, filter, query])

  const selectedRecords = useMemo(
    () => records.filter((r) => r.sessionDir && selected.has(r.sessionDir)),
    [records, selected]
  )
  const selectedTypes = useMemo(
    () => new Set(selectedRecords.map((r) => r.type ?? 'trend')),
    [selectedRecords]
  )
  const compareOk =
    selectedRecords.length >= 2 && selectedRecords.length <= 4 && selectedTypes.size === 1

  // 打开报告：独立窗口展示（可同时打开多份），数据由报告窗口自行加载
  const openRecord = useCallback((record: SamplingSessionMeta) => {
    const dir = record.sessionDir
    if (!dir) return
    window.api.openReportWindow(dir).catch((e) => notify.error('打开报告失败', e))
  }, [])

  const openHistory = useCallback(async () => {
    try {
      // 先经主进程校验目录合法性（无效目录会抛出分级错误），再开独立窗口
      const loaded = await window.api.openSession()
      const dir = loaded?.meta.sessionDir
      if (!dir) return
      await window.api.openReportWindow(dir)
    } catch (e) {
      notify.error('打开历史记录失败', e)
    }
  }, [])

  const deleteDirs = useCallback(
    async (dirs: string[]) => {
      const locked = dirs.filter((d) => d === lockedDir)
      const targets = dirs.filter((d) => d !== lockedDir)
      if (locked.length > 0) {
        notify.error('删除失败', new Error('包含正在采样中的记录，请先停止采样'))
      }
      try {
        for (const dir of targets) {
          await window.api.deleteSession(dir)
        }
        if (targets.length > 0) notify.success(`已删除 ${targets.length} 份报告`)
        setSelected(new Set())
        await props.refreshRecords()
      } catch (e) {
        notify.error('删除报告失败', e)
      }
    },
    [lockedDir, props]
  )

  const confirmDelete = useCallback(
    (dirs: string[], title: string) => {
      Modal.confirm({
        title,
        content: '将永久删除对应目录（含 hidumper 原文），删除后不可恢复。',
        okText: '删除',
        okButtonProps: { danger: true },
        cancelText: '取消',
        onOk: () => deleteDirs(dirs)
      })
    },
    [deleteDirs]
  )

  // 列布局（宽度 / 顺序）持久化
  const [colLayout, setColLayout] = useState(loadColLayout)
  useEffect(() => {
    localStorage.setItem(COL_STORE_KEY, JSON.stringify(colLayout))
  }, [colLayout])

  const handleColResize = (key: string, width: number): void => {
    setColLayout((p) => ({ ...p, widths: { ...p.widths, [key as ColKey]: width } }))
  }

  const handleColReorder = (from: string, to: string): void => {
    setColLayout((p) => {
      const order = [...p.order]
      const fi = order.indexOf(from as ColKey)
      const ti = order.indexOf(to as ColKey)
      if (fi < 0 || ti < 0) return p
      order.splice(fi, 1)
      order.splice(ti, 0, from as ColKey)
      return { ...p, order }
    })
  }

  // 列定义：全部单元格默认黑色、统一字号；任务类型（标签）与任务名称（链接）保留特殊样式
  const baseColumns: ColumnsType<SamplingSessionMeta> = [
    {
      key: 'type',
      title: '任务类型',
      sorter: (a, b) => (a.type ?? 'trend').localeCompare(b.type ?? 'trend'),
      render: (_, r) =>
        r.type === 'snapshot' ? <Tag color="gold">📷 快照</Tag> : <Tag color="blue">📈 持续</Tag>
    },
    {
      key: 'task',
      title: '任务名称',
      sorter: (a, b) => (a.taskName || a.bundleName).localeCompare(b.taskName || b.bundleName),
      render: (_, r) => (
        <div style={{ minWidth: 0 }}>
          {/* 点击名称 = 查看报告；铅笔图标 = 编辑任务名称 */}
          <Typography.Text
            editable={{
              icon: <EditOutlined style={{ fontSize: 11, color: '#8c8c8c' }} />,
              tooltip: '编辑任务名称',
              // children 是 <a> 元素，editable 无法提取文本，需显式给初始值
              text: r.taskName || r.bundleName,
              onChange: (v) => void props.onSaveTaskName(r.sessionDir ?? '', v)
            }}
            style={{ display: 'flex', alignItems: 'center', gap: 2, minWidth: 0 }}
          >
            <a
              onClick={() => void openRecord(r)}
              title={r.taskName || r.bundleName}
              style={{
                fontWeight: 600,
                display: 'inline-block',
                maxWidth: '100%',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                verticalAlign: 'bottom'
              }}
            >
              {r.taskName || r.bundleName}
            </a>
          </Typography.Text>
        </div>
      )
    },
    {
      key: 'app',
      title: '应用',
      dataIndex: 'bundleName',
      ellipsis: true,
      sorter: (a, b) => a.bundleName.localeCompare(b.bundleName),
      render: (v: string) => <Typography.Text ellipsis={{ tooltip: v }}>{v}</Typography.Text>
    },
    {
      key: 'start',
      title: '开始时间',
      dataIndex: 'startedAt',
      ellipsis: true,
      sorter: (a, b) => a.startedAt - b.startedAt,
      render: (v: number) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{fmtTime(v)}</span>
    },
    {
      key: 'duration',
      title: '持续时长',
      ellipsis: true,
      sorter: (a, b) => durationOf(a) - durationOf(b),
      render: (_, r) =>
        r.type === 'snapshot' ? (
          <span>-</span>
        ) : (
          <span style={{ fontVariantNumeric: 'tabular-nums' }}>
            {formatDuration(durationOf(r))}
          </span>
        )
    },
    {
      key: 'device_name',
      title: '设备名称',
      ellipsis: true,
      sorter: (a, b) =>
        (a.device.marketName || a.device.model || '').localeCompare(
          b.device.marketName || b.device.model || ''
        ),
      render: (_, r) => r.device.marketName || r.device.model || '-'
    },
    {
      key: 'device_ver',
      title: '系统版本',
      ellipsis: true,
      sorter: (a, b) => (a.device.softwareVersion || '').localeCompare(b.device.softwareVersion || ''),
      render: (_, r) =>
        ((r.device.softwareVersion || '').replace(/^HarmonyOS\s*/i, '') || '-') +
        (r.device.apiVersion ? `(${r.device.apiVersion})` : '')
    },
    {
      key: 'device_sn',
      title: '序列号',
      ellipsis: true,
      sorter: (a, b) =>
        (a.device.serialNumber || a.device.targetId || '').localeCompare(
          b.device.serialNumber || b.device.targetId || ''
        ),
      render: (_, r) => r.device.serialNumber || r.device.targetId || '-'
    },
    {
      // 操作：仅保留打开目录 / 删除图标（查看通过点击任务名称完成）
      key: 'actions',
      title: '操作',
      render: (_, r) => {
        const dir = r.sessionDir ?? ''
        const locked = !!lockedDir && dir === lockedDir
        return (
          <span style={{ display: 'inline-flex', gap: 0 }}>
            <Button
              size="small"
              type="text"
              icon={<FolderOpenOutlined />}
              title="打开目录"
              disabled={!dir}
              onClick={() => void window.api.revealPath(dir)}
            />
            <Popconfirm
              title="删除该报告？"
              description="含 hidumper 原文，删除后不可恢复"
              okText="删除"
              okButtonProps={{ danger: true }}
              cancelText="取消"
              onConfirm={() => void deleteDirs([dir])}
            >
              <Button
                size="small"
                type="text"
                danger
                icon={<DeleteOutlined />}
                disabled={!dir || locked}
                title={locked ? '正在采样中，无法删除' : '删除'}
              />
            </Popconfirm>
          </span>
        )
      }
    }
  ]

  // 按持久化的顺序/宽度组装，并注入表头单元格行为（调宽 + 列序拖拽）
  const columns: ColumnsType<SamplingSessionMeta> = colLayout.order
    .map((k) => {
      const col = baseColumns.find((c) => (c as { key?: string }).key === k)
      if (!col) return null
      return {
        ...col,
        width: colLayout.widths[k],
        onHeaderCell: () =>
          ({
            colKey: k,
            colResizable: true,
            colDraggable: !COL_FIXED_ORDER.has(k),
            colMinWidth: colMinWidth(k),
            onColResize: handleColResize,
            onColReorder: handleColReorder
          }) as unknown as React.HTMLAttributes<HTMLTableCellElement>
      }
    })
    .filter((c): c is NonNullable<typeof c> => c !== null)

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 10, marginBottom: 14 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          查看报告
        </Typography.Title>
        <Typography.Text type="secondary" style={{ fontSize: 12.5, paddingBottom: 2 }}>
          共 {records.length} 份 · 点击任务名称查看报告 · 勾选同类型报告可对比
        </Typography.Text>
        <span style={{ flex: 1 }} />
        <Button
          size="small"
          icon={<UndoOutlined />}
          title="恢复默认列宽与列顺序"
          onClick={() =>
            setColLayout({ order: [...COL_ORDER_DEFAULT], widths: { ...COL_DEFAULTS } })
          }
        >
          恢复默认布局
        </Button>
        <Button size="small" icon={<FolderOpenOutlined />} onClick={() => void openHistory()}>
          导入历史目录
        </Button>
        <Button size="small" icon={<ReloadOutlined />} loading={loading} onClick={() => void props.refreshRecords()}>
          刷新
        </Button>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 12 }}>
        <Segmented
          value={filter}
          onChange={(v) => setFilter(v as typeof filter)}
          options={[
            { label: `全部 ${records.length}`, value: 'all' },
            { label: `📈 持续采样 ${records.filter((r) => r.type !== 'snapshot').length}`, value: 'trend' },
            { label: `📷 内存快照 ${records.filter((r) => r.type === 'snapshot').length}`, value: 'snapshot' }
          ]}
        />
        <Input.Search
          style={{ width: 240 }}
          placeholder="搜索包名 / 备注 / 设备…"
          allowClear
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      {/* 强制表格总宽 = 列宽之和：fixed 布局下不会因容器更宽而把多余空间摊给其他列 */}
      <style>{`.reports-table .ant-table-content table { width: ${COL_ORDER_DEFAULT.reduce((sum, k) => sum + colLayout.widths[k], 0) + 56}px !important; min-width: 0 !important; }`}</style>
      <Table<SamplingSessionMeta>
        className="reports-table"
        size="middle"
        tableLayout="fixed"
        components={{ header: { cell: ResizableHeaderCell } }}
        rowKey={(r) => r.sessionDir ?? r.id}
        columns={columns}
        dataSource={filtered}
        loading={loading}
        locale={{ emptyText: <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="暂无报告" /> }}
        rowSelection={{
          columnWidth: 56,
          selectedRowKeys: [...selected],
          getCheckboxProps: (r) => ({ disabled: r.sessionDir === lockedDir }),
          onChange: (keys) => setSelected(new Set(keys.map(String)))
        }}
        pagination={false}
        scroll={{ x: COL_ORDER_DEFAULT.reduce((sum, k) => sum + colLayout.widths[k], 0) + 56 }}
      />

      {/* 对比提示条 */}
      {selectedRecords.length > 0 && (
        <Alert
          style={{ marginTop: 12 }}
          type={compareOk ? 'info' : 'warning'}
          showIcon
          message={
            selectedRecords.length < 2
              ? '再勾选 1~3 份同类型报告即可对比（持续采样 ↔ 持续采样，快照 ↔ 快照）'
              : selectedTypes.size > 1
                ? '所选报告类型不一致：持续采样与内存快照不可互相对比，请仅勾选同类型报告'
                : selectedRecords.length > 4
                  ? '一次最多对比 4 份报告，请减少勾选'
                  : `已选 ${selectedRecords.length} 份${selectedTypes.has('snapshot') ? '内存快照' : '持续采样'}报告，可以对比`
          }
          action={
            <Button
              size="small"
              type="primary"
              icon={<SwapOutlined />}
              disabled={!compareOk}
              onClick={() => {
                const dirs = selectedRecords.map((r) => r.sessionDir!).filter(Boolean)
                void window.api.openCompareWindow(dirs).catch((e) => notify.error('打开对比窗口失败', e))
              }}
            >
              对比已选报告
            </Button>
          }
        />
      )}

      {/* 底部批量操作 */}
      <Card size="small" style={{ marginTop: 12 }} styles={{ body: { display: 'flex', alignItems: 'center', gap: 10 } }}>
        <Typography.Text type="secondary" style={{ fontSize: 12.5 }}>
          已选 <b>{selectedRecords.length}</b> 份
        </Typography.Text>
        <Checkbox
          checked={filtered.length > 0 && filtered.every((r) => r.sessionDir && selected.has(r.sessionDir))}
          indeterminate={selected.size > 0 && !filtered.every((r) => r.sessionDir && selected.has(r.sessionDir))}
          onChange={(e) => {
            if (e.target.checked) {
              setSelected(new Set(filtered.map((r) => r.sessionDir!).filter(Boolean)))
            } else {
              setSelected(new Set())
            }
          }}
        >
          全选当前列表
        </Checkbox>
        <Button size="small" disabled={selected.size === 0} onClick={() => setSelected(new Set())}>
          清空选择
        </Button>
        <span style={{ flex: 1 }} />
        <Button
          size="small"
          danger
          icon={<DeleteOutlined />}
          disabled={selectedRecords.length === 0}
          onClick={() =>
            confirmDelete(
              selectedRecords.map((r) => r.sessionDir!).filter(Boolean),
              `确认删除所选 ${selectedRecords.length} 份报告？`
            )
          }
        >
          删除所选
        </Button>
      </Card>
    </div>
  )
}
