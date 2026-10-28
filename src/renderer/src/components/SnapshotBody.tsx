import { Card, Col, Row, Statistic, Table, Tabs, Tag, Typography } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import * as echarts from 'echarts'
import { useEffect, useMemo, useRef } from 'react'
import type { MemorySnapshot } from '@shared/types'
import { colorOf } from '../constants'
import { tooltipPosition } from '../chartTooltip'
import { formatBytes, kbToMb } from '../utils'

interface Props {
  snapshot: MemorySnapshot
}

interface CategoryRow {
  key: string
  name: string
  pss: number
  privateDirty: number
  privateClean: number
  sharedDirty: number
  sharedClean: number
  swap: number
  heap: string
  isTotal?: boolean
}

function toRow(name: string, v: MemorySnapshot['total'], isTotal = false): CategoryRow {
  return {
    key: name,
    name,
    pss: kbToMb(v.pssTotalKb),
    privateDirty: kbToMb(v.privateDirtyKb),
    privateClean: kbToMb(v.privateCleanKb),
    sharedDirty: kbToMb(v.sharedDirtyKb),
    sharedClean: kbToMb(v.sharedCleanKb),
    swap: kbToMb(v.swapPssTotalKb),
    heap: v.heapSizeKb > 0 ? `${formatBytes(v.heapAllocKb)} / ${formatBytes(v.heapSizeKb)}` : '-',
    isTotal
  }
}

const numCol = (
  title: string,
  dataIndex: keyof Pick<
    CategoryRow,
    'pss' | 'privateDirty' | 'privateClean' | 'sharedDirty' | 'sharedClean' | 'swap'
  >
): NonNullable<ColumnsType<CategoryRow>[number]> => ({
  title,
  dataIndex,
  width: 92,
  align: 'right',
  sorter: (a, b) => (a[dataIndex] as number) - (b[dataIndex] as number),
  render: (v: number) => v.toFixed(2)
})

const COLUMNS: ColumnsType<CategoryRow> = [
  {
    title: '分类',
    dataIndex: 'name',
    width: 150,
    render: (v: string, r) => (
      <span style={{ fontWeight: r.isTotal ? 600 : 400, fontFamily: 'monospace' }}>{v}</span>
    )
  },
  { ...numCol('Pss (MB)', 'pss'), defaultSortOrder: 'descend' },
  numCol('私有脏 (MB)', 'privateDirty'),
  numCol('私有净 (MB)', 'privateClean'),
  numCol('共享脏 (MB)', 'sharedDirty'),
  numCol('共享净 (MB)', 'sharedClean'),
  numCol('Swap (MB)', 'swap'),
  { title: 'Heap 已用/容量', dataIndex: 'heap', width: 150, align: 'right' }
]

/** 快照报告主体：概览指标 + 分类 Pss 构成（左侧饼图 + 右侧条形图）+ 附加指标 + 全量明细表 */
export default function SnapshotBody({ snapshot }: Props): JSX.Element {
  const pieRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<HTMLDivElement>(null)

  const t = snapshot.total
  const stats = [
    { label: 'Total Pss', value: formatBytes(t.pssTotalKb), color: '#1677ff' },
    { label: 'Private Dirty', value: formatBytes(t.privateDirtyKb), color: undefined },
    { label: 'Swap Pss', value: formatBytes(t.swapPssTotalKb), color: undefined },
    {
      label: 'Heap 已用/容量',
      value: `${formatBytes(t.heapAllocKb)} / ${formatBytes(t.heapSizeKb)}`,
      color: undefined
    }
  ]

  // 条形图：按 Pss 降序，零值分类不展示
  const barRows = useMemo(
    () =>
      Object.entries(snapshot.categories)
        .map(([name, v]) => ({ name, mb: kbToMb(v.pssTotalKb) }))
        .filter((r) => r.mb > 0.01)
        .sort((a, b) => b.mb - a.mb),
    [snapshot]
  )

  // 明细表：Total 置顶，其后为各分类与 native heap 细分
  const tableRows = useMemo(() => {
    const rows: CategoryRow[] = [toRow('Total', t, true)]
    for (const [name, v] of Object.entries(snapshot.categories)) rows.push(toRow(name, v))
    for (const [name, v] of Object.entries(snapshot.nativeHeapDetail)) {
      rows.push(toRow(`↳ ${name}`, v))
    }
    return rows
  }, [snapshot, t])

  const chartHeight = Math.min(340, Math.max(180, barRows.length * 22 + 40))

  useEffect(() => {
    if (!chartRef.current || !pieRef.current) return
    const barChart = echarts.init(chartRef.current)
    const pieChart = echarts.init(pieRef.current)
    const observer = new ResizeObserver(() => {
      barChart.resize()
      pieChart.resize()
    })
    observer.observe(chartRef.current)

    // 左侧饼图：分类 Pss 占比构成（颜色与条形图一一对应）
    const sumMb = barRows.reduce((s, r) => s + r.mb, 0)
    // 占比 <2% 的微小切片：连标签带引线整体隐藏（悬停 tooltip 有明细），
    // 否则会有一簇空引线缠绕在饼图边缘
    const pieData = barRows.map((r, i) => {
      const show = sumMb > 0 && (r.mb / sumMb) * 100 >= 2
      return {
        name: r.name,
        value: r.mb,
        itemStyle: { color: colorOf(r.name, i) },
        label: { show },
        labelLine: { show }
      }
    })
    pieChart.setOption({
      title: {
        text: 'Total Pss',
        subtext: formatBytes(snapshot.total.pssTotalKb),
        left: 'center',
        top: '40%',
        textStyle: { fontSize: 11, color: '#8c8c8c', fontWeight: 400 },
        subtextStyle: { fontSize: 13, color: '#262626', fontWeight: 600 }
      },
      tooltip: {
        trigger: 'item',
        appendToBody: true,
        position: tooltipPosition,
        formatter: (p: { name?: string; value?: number; percent?: number }) =>
          `${p.name}<br/>Pss：${Number(p.value).toFixed(2)} MB · ${p.percent?.toFixed(1)}%`
      },
      series: [
        {
          type: 'pie',
          // 半径收窄一点，给四周放射的标签留出余量
          radius: ['40%', '58%'],
          center: ['50%', '50%'],
          data: pieData,
          // 两行富文本标签（名称 / 数值·百分比），沿切片角度放射到饼图四周（顶部切片在上、底部在下）
          label: {
            lineHeight: 14,
            rich: {
              n: { fontSize: 11, color: '#262626' },
              v: { fontSize: 10, color: '#8c8c8c', padding: [1, 0, 0, 0] }
            },
            formatter: (p: { name?: string; value?: number; percent?: number }) => {
              const mb = Number(p.value)
              const mbText = mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)
              return `{n|${p.name}}\n{v|${mbText} MB · ${p.percent?.toFixed(1)}%}`
            }
          },
          // 引线要足够长：两行标签以引线末端垂直居中，太短会压到饼环
          labelLine: { length: 14, length2: 12 }
        }
      ]
    })

    barChart.setOption({
      grid: { left: 8, right: 56, top: 8, bottom: 24, containLabel: true },
      xAxis: { type: 'value', name: 'Pss (MB)', nameTextStyle: { fontSize: 11 }, axisLabel: { fontSize: 11 } },
      yAxis: {
        type: 'category',
        inverse: true,
        data: barRows.map((r) => r.name),
        axisLabel: { fontSize: 11 }
      },
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        formatter: (params: unknown) => {
          const arr = Array.isArray(params) ? params : [params]
          const p = arr[0] as { name?: string; value?: number } | undefined
          return p ? `${p.name}<br/>Pss：${Number(p.value).toFixed(2)} MB` : ''
        }
      },
      series: [
        {
          type: 'bar',
          barMaxWidth: 18,
          data: barRows.map((r, i) => ({
            value: r.mb,
            itemStyle: { color: colorOf(r.name, i) }
          })),
          label: {
            show: true,
            position: 'right',
            fontSize: 11,
            formatter: (p: { value?: unknown }) => `${Number(p.value).toFixed(2)}`
          }
        }
      ]
    })
    return () => {
      observer.disconnect()
      barChart.dispose()
      pieChart.dispose()
    }
  }, [barRows, snapshot])

  const extras: Array<[string, number]> = [
    ['PurgSum', snapshot.purgSumKb],
    ['PurgPin', snapshot.purgPinKb],
    ['Dma', snapshot.dmaKb],
    ['Total Ashmem', snapshot.ashmemTotalKb]
  ]

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <Row gutter={[12, 12]}>
        {stats.map((s) => (
          <Col xs={12} md={6} key={s.label}>
            <Card size="small">
              <Statistic
                title={s.label}
                value={s.value}
                valueStyle={s.color ? { color: s.color } : undefined}
              />
            </Card>
          </Col>
        ))}
      </Row>
      <Card size="small" title="分类占用（Pss）">
        <div style={{ display: 'flex', gap: 8, alignItems: 'stretch' }}>
          <div ref={pieRef} style={{ flex: '0 0 440px', height: chartHeight }} />
          <div ref={chartRef} style={{ flex: 1, minWidth: 0, height: chartHeight }} />
        </div>
        <div style={{ marginTop: 8 }}>
          {extras
            .filter(([, v]) => v > 0)
            .map(([k, v]) => (
              <Tag key={k}>{`${k}: ${formatBytes(v)}`}</Tag>
            ))}
        </div>
      </Card>
      <Card size="small" title="分类明细表" styles={{ body: { padding: 0 } }}>
        <Table<CategoryRow>
          size="small"
          columns={COLUMNS}
          dataSource={tableRows}
          pagination={false}
          scroll={{ x: 'max-content' }}
        />
      </Card>
      <DetailSections snapshot={snapshot} />
    </div>
  )
}

/* ─── 段明细：ashmem / dmabuf / gpumem（采集时勾选 --show-* 才有数据） ─── */

function bytesToText(bytes: number): string {
  return formatBytes(bytes / 1024)
}

function DetailSections({ snapshot }: Props): JSX.Element | null {
  const { ashmemDetail, dmabufDetail, gpuDetail } = snapshot
  // 三个字段都不存在 = 采集时未开启任何明细，不渲染本卡片（历史快照兼容）
  if (!ashmemDetail && !dmabufDetail && !gpuDetail) return null

  const ashmemTotal = (ashmemDetail ?? []).reduce((s, e) => s + e.physicalBytes, 0)
  const dmabufTotal = (dmabufDetail ?? []).reduce((s, e) => s + e.sizeBytes, 0)

  const items: NonNullable<React.ComponentProps<typeof Tabs>['items']> = []

  if (ashmemDetail) {
    items.push({
      key: 'ashmem',
      label: `ashmem（${ashmemDetail.length} 条 · ${bytesToText(ashmemTotal)}）`,
      children: (
        <Table
          size="small"
          pagination={false}
          locale={{ emptyText: '该进程无 ashmem 内存块' }}
          dataSource={ashmemDetail.map((e, i) => ({ ...e, key: i }))}
          columns={[
            { title: '名称', dataIndex: 'name', ellipsis: true },
            { title: 'FD', dataIndex: 'fd', width: 70, align: 'right' },
            {
              title: '虚拟大小',
              dataIndex: 'virtualBytes',
              width: 110,
              align: 'right',
              sorter: (a, b) => a.virtualBytes - b.virtualBytes,
              render: bytesToText
            },
            {
              title: '物理大小',
              dataIndex: 'physicalBytes',
              width: 110,
              align: 'right',
              sorter: (a, b) => a.physicalBytes - b.physicalBytes,
              defaultSortOrder: 'descend',
              render: (v: number) => <b>{bytesToText(v)}</b>
            }
          ]}
        />
      )
    })
  }

  if (dmabufDetail) {
    items.push({
      key: 'dmabuf',
      label: `dmabuf（${dmabufDetail.length} 条 · ${bytesToText(dmabufTotal)}）`,
      children: (
        <Table
          size="small"
          pagination={false}
          locale={{ emptyText: '该进程无 DMA buffer' }}
          dataSource={dmabufDetail.map((e, i) => ({ ...e, key: i }))}
          columns={[
            {
              title: '对象类型',
              dataIndex: 'name',
              ellipsis: true,
              render: (v: string) => <Typography.Text ellipsis={{ tooltip: v }} style={{ maxWidth: 420 }}>{v}</Typography.Text>
            },
            { title: 'FD', dataIndex: 'fd', width: 70, align: 'right' },
            { title: 'ino', dataIndex: 'ino', width: 80, align: 'right' },
            {
              title: '大小',
              dataIndex: 'sizeBytes',
              width: 110,
              align: 'right',
              sorter: (a, b) => a.sizeBytes - b.sizeBytes,
              defaultSortOrder: 'descend',
              render: (v: number) => <b>{bytesToText(v)}</b>
            }
          ]}
        />
      )
    })
  }

  if (gpuDetail) {
    items.push({
      key: 'gpumem',
      label: `gpumem（${gpuDetail.channels.length} 个通道 · ${bytesToText(gpuDetail.totalUsedBytes)}）`,
      children: (
        <>
          <Table
            size="small"
            pagination={false}
            locale={{ emptyText: '无 GPU 内存通道数据' }}
            dataSource={gpuDetail.channels.map((c) => ({ ...c, key: c.name }))}
            columns={[
              { title: 'Channel', dataIndex: 'name', ellipsis: true },
              {
                title: '内存',
                dataIndex: 'totalBytes',
                width: 130,
                align: 'right',
                sorter: (a, b) => a.totalBytes - b.totalBytes,
                defaultSortOrder: 'descend',
                render: (v: number) => <b>{bytesToText(v)}</b>
              }
            ]}
          />
          <div style={{ padding: '8px 12px', borderTop: '1px solid #f0f0f0', fontSize: 12, color: '#8c8c8c' }}>
            Total used: {bytesToText(gpuDetail.totalUsedBytes)} · Total allocated: {bytesToText(gpuDetail.totalAllocatedBytes)}
            （桶级分布见 raw 原文）
          </div>
        </>
      )
    })
  }

  return (
    <Card size="small" title="内存明细" styles={{ body: { padding: '0 12px 8px' } }}>
      <Tabs size="small" items={items} />
    </Card>
  )
}
