import WindowTitleBar from './components/WindowTitleBar'
import { Card, Empty, Segmented, Select, Slider, Table, Tabs, Tag, Typography } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { HolderOutlined } from '@ant-design/icons'
import * as echarts from 'echarts'
import { useEffect, useMemo, useRef, useState } from 'react'
import type { MemorySnapshot, ProcessMemorySample, SamplingSessionMeta } from '@shared/types'
import { colorOf } from './constants'
import { formatSampleTooltip, tooltipPosition } from './chartTooltip'
import { formatBytes, formatDuration, kbToMb } from './utils'

/** 对比窗口入口（独立 BrowserWindow）：经 query 传入会话目录，自行加载数据 */

const CMP_COLORS = ['#1677ff', '#fa8c16', '#52c41a', '#722ed1']

interface CompareItem {
  meta: SamplingSessionMeta
  samples: ProcessMemorySample[]
  snapshot: MemorySnapshot | null
}

function fmtTime(ts: number): string {
  const d = new Date(ts)
  const p = (n: number): string => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

const shortName = (b: string): string => b.split('.').pop() || b

/**
 * 报告标签：优先任务名称（如 Task-20261016-110533），旧报告回退「包名 · 时间」；
 * 重名自动追加序号，保证图例/表头可区分
 */
function labelsOf(items: CompareItem[]): string[] {
  const seen = new Map<string, number>()
  return items.map((it) => {
    const base =
      it.meta.taskName?.trim() ||
      `${shortName(it.meta.bundleName)} · ${fmtTime(it.meta.startedAt).slice(5, 16)}`
    const n = (seen.get(base) ?? 0) + 1
    seen.set(base, n)
    return n > 1 ? `${base}（${n}）` : base
  })
}

const round1 = (v: number): number => Math.round(v * 10) / 10

/** 取样本上某指标的 Pss（KB）；Total 用总计行，分类缺失返回 null */
function metricKb(s: ProcessMemorySample, metric: string): number | null {
  if (metric === 'Total') return s.total.pssTotalKb
  return s.categories[metric]?.pssTotalKb ?? null
}

/* ─── 报告顺序条：首个为基准；拖拽调整顺序（几何判定 + transform 让位，无抖动） ─── */

function OrderBar({
  labels,
  order,
  onChange
}: {
  labels: string[]
  order: number[]
  onChange: (next: number[]) => void
}): JSX.Element {
  const [dragFrom, setDragFrom] = useState<number | null>(null)
  const [overVi, setOverVi] = useState<number | null>(null)
  const [hideVi, setHideVi] = useState<number | null>(null)
  const chipRefs = useRef(new Map<number, HTMLSpanElement>())
  // 拖拽开始时记录：起点视图索引 / 被拖胶囊宽度 / 各胶囊中点 x（拖拽全程不再重测，杜绝抖动回路）
  const dragInfo = useRef<{ from: number; shiftW: number; mids: number[] } | null>(null)

  const reset = (): void => {
    dragInfo.current = null
    setDragFrom(null)
    setOverVi(null)
    setHideVi(null)
  }

  /** 其他胶囊的让位位移：被拖胶囊越过时，中间胶囊向反方向平移一个身位 */
  const shiftOf = (vi: number): string | undefined => {
    const info = dragInfo.current
    if (!info || overVi === null || dragFrom === null || vi === dragFrom) return undefined
    if (overVi > dragFrom && vi > dragFrom && vi <= overVi) return `translateX(${-info.shiftW}px)`
    if (overVi < dragFrom && vi >= overVi && vi < dragFrom) return `translateX(${info.shiftW}px)`
    return undefined
  }

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        flexWrap: 'wrap',
        marginBottom: 10
      }}
      onDragOver={(e) => {
        const info = dragInfo.current
        if (!info) return
        e.preventDefault()
        e.dataTransfer.dropEffect = 'move'
        // 指针 x 与各胶囊中点比较，得出目标位置
        const x = e.clientX
        let idx = info.mids.length - 1
        for (let i = 0; i < info.mids.length; i++) {
          if (x < info.mids[i]) {
            idx = i
            break
          }
        }
        setOverVi(idx)
      }}
      onDrop={(e) => {
        e.preventDefault()
        const info = dragInfo.current
        if (info && overVi !== null && overVi !== info.from) {
          const next = [...order]
          next.splice(info.from, 1)
          next.splice(overVi, 0, order[info.from])
          onChange(next)
        }
        reset()
      }}
    >
      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
        对比顺序（首个为基准，拖拽调整）：
      </Typography.Text>
      {order.map((oi, vi) => (
        <span
          key={oi}
          ref={(el) => {
            if (el) chipRefs.current.set(oi, el)
            else chipRefs.current.delete(oi)
          }}
          draggable
          onDragStart={(e) => {
            e.dataTransfer.setData('text/plain', String(vi))
            e.dataTransfer.effectAllowed = 'move'
            const rects = order.map((k) => chipRefs.current.get(k)?.getBoundingClientRect())
            dragInfo.current = {
              from: vi,
              shiftW: (rects[vi]?.width ?? 0) + 8,
              mids: rects.map((r) => (r ? r.left + r.width / 2 : 0))
            }
            setDragFrom(vi)
            setOverVi(vi)
            // 延迟一帧再隐藏本体：等浏览器完成拖拽残影快照，
            // 否则 dragstart 同步隐藏会让 Chromium 直接取消拖拽
            setTimeout(() => setHideVi(vi), 0)
          }}
          onDragEnd={reset}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 6,
            padding: '3px 10px',
            borderRadius: 6,
            cursor: 'grab',
            fontSize: 12,
            transform: shiftOf(vi),
            transition: dragFrom !== null ? 'transform .18s ease' : undefined,
            // 被拖胶囊本体隐藏（保留占位，不影响让位位移计算），避免与滑入的胶囊文字重叠；
            // 拖动视觉由原生拖拽残影承担
            visibility: hideVi === vi ? 'hidden' : undefined,
            border: `1px solid ${vi === 0 ? '#91caff' : '#e5e6eb'}`,
            background: vi === 0 ? '#f0f7ff' : '#fff'
          }}
        >
          <HolderOutlined style={{ color: '#bbb', fontSize: 11 }} />
          {/* 色块跟随报告（按原始索引取色），调序不换色 */}
          <i
            style={{
              width: 9,
              height: 9,
              borderRadius: 2,
              background: CMP_COLORS[oi % CMP_COLORS.length]
            }}
          />
          <span style={{ fontWeight: vi === 0 ? 600 : 400 }}>{labels[oi]}</span>
          {vi === 0 && (
            <Tag
              color="blue"
              style={{ marginInlineEnd: 0, fontSize: 11, lineHeight: '16px', padding: '0 4px' }}
            >
              基准
            </Tag>
          )}
        </span>
      ))}
    </div>
  )
}

/* ─── 趋势对比：指标叠加图（指标/对齐可选）+ 关键指标差异表 + 各报告完整趋势小图 ─── */

type AlignMode = 'start' | 'peak' | 'end'
const ALIGN_HINT: Record<AlignMode, string> = {
  start: '按开始对齐',
  peak: '按峰值对齐',
  end: '按结束对齐'
}

interface TrendStats {
  peakKb: number
  avgKb: number
  endKb: number
  growthKb: number
  durationMs: number
  count: number
}

function statsOf(it: CompareItem): TrendStats {
  const totals = it.samples.map((s) => s.total.pssTotalKb)
  const peak = totals.length ? Math.max(...totals) : 0
  const end = totals.length ? totals[totals.length - 1] : 0
  const first = totals[0] ?? 0
  const avg = totals.length ? Math.round(totals.reduce((a, b) => a + b, 0) / totals.length) : 0
  return {
    peakKb: peak,
    avgKb: avg,
    endKb: end,
    growthKb: end - first,
    durationMs: (it.meta.endedAt ?? it.meta.startedAt) - it.meta.startedAt,
    count: it.samples.length
  }
}

/** 单份报告的完整趋势小图（Total 加粗 + 全部分类）：标出峰值点，点击拾取对比采样点 */
function MiniTrendChart({
  item,
  pickedTs,
  onPick,
  tipOpacity = 0.8
}: {
  item: CompareItem
  /** 当前选中采样点的时间戳（null = 未选） */
  pickedTs: number | null
  onPick: (sample: ProcessMemorySample) => void
  /** 悬浮框背景透明度（0.3 ~ 1） */
  tipOpacity?: number
}): JSX.Element {
  const ref = useRef<HTMLDivElement>(null)
  const chartRef = useRef<echarts.ECharts | null>(null)
  const onPickRef = useRef(onPick)
  onPickRef.current = onPick

  // 初始化 + 点击拾取：grid 内任意位置点击，吸附到时间最接近的采样点
  useEffect(() => {
    if (!ref.current || item.samples.length === 0) return
    const chart = echarts.init(ref.current)
    chartRef.current = chart
    const observer = new ResizeObserver(() => chart.resize())
    observer.observe(ref.current)
    chart.getZr().on('click', (e) => {
      if (!chart.containPixel('grid', [e.offsetX, e.offsetY])) return
      const x = Number(chart.convertFromPixel({ seriesIndex: 0 }, [e.offsetX, e.offsetY])[0])
      if (!Number.isFinite(x)) return
      const t0 = item.samples[0]?.timestamp ?? item.meta.startedAt
      let best: ProcessMemorySample | null = null
      let bestDist = Infinity
      for (const smp of item.samples) {
        const d = Math.abs((smp.timestamp - t0) / 1000 - x)
        if (d < bestDist) {
          bestDist = d
          best = smp
        }
      }
      if (best) onPickRef.current(best)
    })
    return () => {
      observer.disconnect()
      chart.dispose()
      chartRef.current = null
    }
  }, [item])

  // 数据与标记渲染（选中点变化时仅更新 option）
  useEffect(() => {
    const chart = chartRef.current
    if (!chart || item.samples.length === 0) return
    const t0 = item.samples[0]?.timestamp ?? item.meta.startedAt

    // 分类并集（按首现顺序），颜色与主图 colorOf 规则一致
    const catNames: string[] = []
    const seen = new Set<string>()
    for (const s of item.samples) {
      for (const n of Object.keys(s.categories)) {
        if (!seen.has(n)) {
          seen.add(n)
          catNames.push(n)
        }
      }
    }

    // 峰值采样点（Total Pss 最大）
    let peakIdx = 0
    item.samples.forEach((s, i) => {
      if (s.total.pssTotalKb > item.samples[peakIdx].total.pssTotalKb) peakIdx = i
    })
    const peakKb = item.samples[peakIdx].total.pssTotalKb
    const peakElapsed = round1((item.samples[peakIdx].timestamp - t0) / 1000)
    const pickedElapsed = pickedTs != null ? round1((pickedTs - t0) / 1000) : null

    const option: echarts.EChartsOption = {
      animation: false,
      grid: { left: 56, right: 12, top: 26, bottom: 22 },
      legend: { show: false },
      tooltip: {
        trigger: 'axis',
        // 小图高度有限，tooltip 渲染到 body 避免被容器裁剪；position 钳制在视口内
        appendToBody: true,
        position: tooltipPosition,
        backgroundColor: `rgba(255,255,255,${tipOpacity})`,
        // 与报告页趋势图保持同一 tooltip 格式
        formatter: (params: unknown) => formatSampleTooltip(params, item.samples)
      },
      xAxis: {
        type: 'value',
        axisLabel: { fontSize: 10, formatter: (v: number) => `${Math.round(v)}s` }
      },
      yAxis: {
        type: 'value',
        scale: true,
        axisLabel: { fontSize: 10, formatter: (v: number) => formatBytes(v * 1024) },
        splitLine: { lineStyle: { type: 'dashed', color: '#eee' } }
      },
      series: [
        {
          name: 'Total',
          type: 'line' as const,
          showSymbol: false,
          smooth: true,
          lineStyle: { width: 2.5, color: '#1677ff' },
          itemStyle: { color: '#1677ff' },
          // 直接标出峰值采样点
          markPoint: {
            symbol: 'pin',
            symbolSize: 40,
            itemStyle: { color: '#ff4d4f' },
            label: { show: true, fontSize: 9, color: '#fff', formatter: '峰' },
            data: [{ name: '峰值', coord: [peakElapsed, round1(kbToMb(peakKb))] }]
          },
          // 当前选中的对比采样点（红色虚线竖线）
          markLine:
            pickedElapsed != null
              ? {
                  symbol: 'none',
                  silent: true,
                  lineStyle: { color: '#ff4d4f', type: 'dashed', width: 1.2 },
                  label: {
                    fontSize: 10,
                    color: '#ff4d4f',
                    position: 'insideEndTop',
                    formatter: `${pickedElapsed.toFixed(1)}s`
                  },
                  data: [{ xAxis: pickedElapsed }]
                }
              : undefined,
          data: item.samples.map((s) => [
            round1((s.timestamp - t0) / 1000),
            kbToMb(s.total.pssTotalKb)
          ])
        },
        ...catNames.map((n, i) => ({
          name: n,
          type: 'line' as const,
          showSymbol: false,
          smooth: true,
          lineStyle: { width: 1.2, color: colorOf(n, i) },
          itemStyle: { color: colorOf(n, i) },
          data: item.samples
            .map((s) => {
              const v = s.categories[n]?.pssTotalKb
              return v == null ? null : [round1((s.timestamp - t0) / 1000), kbToMb(v)]
            })
            .filter((d): d is number[] => d !== null)
        }))
      ]
    }
    chart.setOption(option)
  }, [item, pickedTs, tipOpacity])

  return <div ref={ref} style={{ flex: 1, minHeight: 120, cursor: 'crosshair' }} title="点击选取对比采样点" />
}

/** Total Pss 最大的采样点（默认选中峰值） */
function peakSampleOf(it: CompareItem): ProcessMemorySample | null {
  let best: ProcessMemorySample | null = null
  for (const s of it.samples) {
    if (!best || s.total.pssTotalKb > best.total.pssTotalKb) best = s
  }
  return best
}

function TrendCompare({ items }: { items: CompareItem[] }): JSX.Element {
  // 图表 DOM 节点用 state 跟踪：标签页切换时 pane 销毁/重建，
  // 节点变化会触发下方 effect 重新 init，避免切回后图表空白
  const [chartEl, setChartEl] = useState<HTMLDivElement | null>(null)
  const [metric, setMetric] = useState<string>('Total')
  const [align, setAlign] = useState<AlignMode>('start')
  const labels = useMemo(() => labelsOf(items), [items])
  // 各报告当前选中的对比采样点（默认取各自峰值点；按原始索引存储，调序不丢）
  const [picked, setPicked] = useState<(ProcessMemorySample | null)[]>(() =>
    items.map(peakSampleOf)
  )
  // 报告顺序（视图索引 → 原始索引）；首个为基准
  const [order, setOrder] = useState<number[]>(() => items.map((_, i) => i))
  // 悬浮框背景透明度（0.3 ~ 1，两个标签页的图表共用）
  const [tipOpacity, setTipOpacity] = useState(0.8)
  const view = useMemo(() => order.map((i) => items[i]), [items, order])
  const viewLabels = useMemo(() => order.map((i) => labels[i]), [order, labels])
  const viewPicked = useMemo(() => order.map((i) => picked[i]), [order, picked])
  /** 各视图位置对应的报告颜色（跟随报告本身，调序不换色） */
  const viewColors = useMemo(() => order.map((oi) => CMP_COLORS[oi % CMP_COLORS.length]), [order])
  // 标签页 + 采样点对比页的左右分栏比例（持久化）
  const [tab, setTab] = useState<'overlay' | 'picked'>('overlay')
  const [split, setSplit] = useState<number>(() => {
    const v = Number(localStorage.getItem('compare.split.v1'))
    return Number.isFinite(v) && v >= 20 && v <= 80 ? v : 50
  })
  const [splitHover, setSplitHover] = useState(false)
  const splitRef = useRef<HTMLDivElement>(null)

  /** 分隔条拖拽：调整左（小图）/ 右（表格）区域宽度比例 */
  const startSplitDrag = (e: React.MouseEvent): void => {
    e.preventDefault()
    const container = splitRef.current
    if (!container) return
    const rect = container.getBoundingClientRect()
    let pct = split
    const onMove = (ev: MouseEvent): void => {
      pct = Math.min(80, Math.max(20, Math.round(((ev.clientX - rect.left) / rect.width) * 1000) / 10))
      setSplit(pct)
    }
    const onUp = (): void => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
      localStorage.setItem('compare.split.v1', String(pct))
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }

  // 可选对比指标：Total Pss + 所有报告样本的分类并集
  const metricOptions = useMemo(() => {
    const names: string[] = []
    const seen = new Set<string>()
    for (const it of view) {
      for (const s of it.samples) {
        for (const n of Object.keys(s.categories)) {
          if (!seen.has(n)) {
            seen.add(n)
            names.push(n)
          }
        }
      }
    }
    return [
      { value: 'Total', label: 'Total Pss' },
      ...names.map((n) => ({ value: n, label: n }))
    ]
  }, [view])

  /**
   * 各报告的 x 轴偏移（秒）：
   * - start：不偏移（各自从 0 开始）
   * - peak：所选指标的峰值时刻对齐（峰值落在同一 x，比较峰值前后的爬升/回收）
   * - end：曲线末端对齐（比较收尾行为）
   */
  const offsetSec = useMemo(() => {
    if (align === 'start') return view.map(() => 0)
    const els = view.map((it) => {
      const t0 = it.samples[0]?.timestamp ?? it.meta.startedAt
      return it.samples.map((s) => (s.timestamp - t0) / 1000)
    })
    if (align === 'end') {
      const durs = els.map((e) => e[e.length - 1] ?? 0)
      const maxDur = Math.max(...durs, 0)
      return durs.map((d) => maxDur - d)
    }
    const peakAt = view.map((it, i) => {
      let best = -1
      let bestElapsed = 0
      it.samples.forEach((s, j) => {
        const v = metricKb(s, metric) ?? -1
        if (v > best) {
          best = v
          bestElapsed = els[i][j] ?? 0
        }
      })
      return bestElapsed
    })
    const maxPeak = Math.max(...peakAt, 0)
    return peakAt.map((p) => maxPeak - p)
  }, [view, align, metric])

  useEffect(() => {
    if (!chartEl) return
    const chart = echarts.init(chartEl)
    const observer = new ResizeObserver(() => chart.resize())
    observer.observe(chartEl)

    const option: echarts.EChartsOption = {
      animation: false,
      grid: { left: 64, right: 24, top: 46, bottom: 64 },
      legend: { top: 4, textStyle: { fontSize: 12 } },
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        position: tooltipPosition,
        backgroundColor: `rgba(255,255,255,${tipOpacity})`,
        valueFormatter: (v: unknown) => `${Number(v).toFixed(1)} MB`
      },
      dataZoom: [
        { type: 'inside', filterMode: 'none' },
        { type: 'slider', height: 18, bottom: 10, filterMode: 'none' }
      ],
      xAxis: {
        type: 'value',
        name: `相对时间（s · ${ALIGN_HINT[align]}）`,
        nameLocation: 'middle',
        nameGap: 28,
        axisLabel: { fontSize: 11, formatter: (v: number) => `${Math.round(v)}` }
      },
      yAxis: {
        type: 'value',
        name: metric === 'Total' ? 'Total Pss' : metric,
        scale: true,
        axisLabel: { fontSize: 11, formatter: (v: number) => formatBytes(v * 1024) },
        splitLine: { lineStyle: { type: 'dashed', color: '#eee' } }
      },
      series: view.map((it, i) => {
        const t0 = it.samples[0]?.timestamp ?? it.meta.startedAt
        return {
          name: viewLabels[i],
          type: 'line' as const,
          showSymbol: false,
          smooth: true,
          lineStyle: { width: 2, color: viewColors[i] },
          itemStyle: { color: viewColors[i] },
          markPoint: {
            symbolSize: 42,
            label: { fontSize: 10 },
            data: [{ type: 'max' as const, name: '峰值' }]
          },
          data: it.samples
            .map((s) => {
              const v = metricKb(s, metric)
              return v == null
                ? null
                : [round1((s.timestamp - t0) / 1000 + (offsetSec[i] ?? 0)), kbToMb(v)]
            })
            .filter((d): d is number[] => d !== null)
        }
      })
    }
    chart.setOption(option)
    return () => {
      observer.disconnect()
      chart.dispose()
    }
  }, [chartEl, view, viewLabels, viewColors, metric, align, offsetSec, tipOpacity])

  const base = statsOf(view[0])
  const rows = view.map((it, i) => ({ it, i, st: statsOf(it) }))
  const peakMax = Math.max(...rows.map((r) => r.st.peakKb))

  // 悬浮框透明度滑杆（pill 样式与报告页趋势图标题栏一致），两个标签页的图表共用
  const tipSlider = (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        fontSize: 12,
        color: '#666',
        background: '#f5f5f5',
        borderRadius: 6,
        padding: '3px 10px'
      }}
    >
      <Slider
        style={{ width: 72, margin: 0 }}
        min={30}
        max={100}
        value={Math.round(tipOpacity * 100)}
        onChange={(v) => setTipOpacity(v / 100)}
        tooltip={{ formatter: (v) => `悬浮框透明度 ${v ?? 0}%` }}
      />
      透明度
    </span>
  )

  interface DiffRow {
    key: string
    i: number
    label: string
    time: string
    peak: string
    avg: string
    end: string
    growth: string
    duration: string
    count: number
    diffKb: number
  }
  const dataSource: DiffRow[] = rows.map(({ it, i, st }) => ({
    key: it.meta.sessionDir ?? String(i),
    i,
    label: viewLabels[i],
    time: fmtTime(it.meta.startedAt),
    peak: formatBytes(st.peakKb),
    avg: formatBytes(st.avgKb),
    end: formatBytes(st.endKb),
    growth: `${st.growthKb >= 0 ? '+' : '-'}${formatBytes(Math.abs(st.growthKb))}`,
    duration: formatDuration(st.durationMs),
    count: st.count,
    diffKb: st.peakKb - base.peakKb
  }))

  const columns: ColumnsType<DiffRow> = [
    {
      title: '报告',
      render: (_, r) => (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
          <i
            style={{
              width: 11,
              height: 11,
              borderRadius: 3,
              background: viewColors[r.i],
              flex: '0 0 auto'
            }}
          />
          <span>
            <b>{r.label}</b>
          </span>
        </span>
      )
    },
    { title: '采样时间', dataIndex: 'time', width: 165 },
    {
      title: '峰值 Pss',
      dataIndex: 'peak',
      align: 'right',
      width: 110,
      render: (v: string, r) => (
        <b style={{ color: r.peak === formatBytes(peakMax) ? '#ff4d4f' : undefined }}>{v}</b>
      )
    },
    { title: '均值', dataIndex: 'avg', align: 'right', width: 100 },
    { title: '结束值', dataIndex: 'end', align: 'right', width: 100 },
    {
      title: '增长幅度',
      dataIndex: 'growth',
      align: 'right',
      width: 100,
      render: (v: string) => (
        <span style={{ color: v.startsWith('+') ? '#ff4d4f' : '#389e0d' }}>{v}</span>
      )
    },
    { title: '时长', dataIndex: 'duration', align: 'right', width: 90 },
    { title: '点数', dataIndex: 'count', align: 'right', width: 70 },
    {
      title: '峰值差（相对基准）',
      dataIndex: 'diffKb',
      align: 'right',
      width: 150,
      render: (v: number, r) =>
        r.i === 0 ? (
          '基准'
        ) : (
          <span
            style={{ color: v > 512 ? '#ff4d4f' : v < -512 ? '#389e0d' : undefined, fontWeight: 600 }}
          >
            {`${v >= 0 ? '+' : '-'}${formatBytes(Math.abs(v))}`}
          </span>
        )
    }
  ]

  return (
    <>
      {/* Tabs 内容区撑满窗口高度 */}
      <style>{`.compare-tabs{height:100%;display:flex;flex-direction:column}.compare-tabs .ant-tabs-nav{margin-bottom:10px;flex:0 0 auto}.compare-tabs .ant-tabs-content-holder{flex:1;min-height:0}.compare-tabs .ant-tabs-content,.compare-tabs .ant-tabs-tabpane{height:100%}`}</style>
      <OrderBar labels={labels} order={order} onChange={setOrder} />
      <Tabs
        className="compare-tabs"
        activeKey={tab}
        onChange={(k) => setTab(k as 'overlay' | 'picked')}
        destroyInactiveTabPane
        items={[
          {
            key: 'overlay',
            label: '📈 趋势叠加对比',
            children: (
              <div
                style={{
                  height: '100%',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 12,
                  overflow: 'auto'
                }}
              >
                <Card
                  size="small"
                  title="指标趋势叠加"
                  style={{ flex: '0 0 auto' }}
                  extra={
                    <span
                      style={{ display: 'inline-flex', alignItems: 'center', gap: 10, fontWeight: 400 }}
                    >
                      {tipSlider}
                      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                        对比指标
                      </Typography.Text>
                      <Select
                        size="small"
                        style={{ width: 170 }}
                        value={metric}
                        onChange={setMetric}
                        options={metricOptions}
                      />
                      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                        时间对齐
                      </Typography.Text>
                      <Segmented
                        size="small"
                        value={align}
                        onChange={(v) => setAlign(v as AlignMode)}
                        options={[
                          { label: '开始', value: 'start' },
                          { label: '峰值', value: 'peak' },
                          { label: '结束', value: 'end' }
                        ]}
                      />
                    </span>
                  }
                >
                  <div ref={setChartEl} style={{ height: 320 }} />
                </Card>
                <Card
                  size="small"
                  title="关键指标差异（Total Pss）"
                  styles={{ body: { padding: 0 } }}
                  style={{ flex: '0 0 auto' }}
                >
                  <Table<DiffRow>
                    size="small"
                    columns={columns}
                    dataSource={dataSource}
                    pagination={false}
                    scroll={{ x: 'max-content' }}
                  />
                </Card>
              </div>
            )
          },
          {
            key: 'picked',
            label: '🎯 采样点对比',
            children: (
              <div ref={splitRef} style={{ display: 'flex', height: '100%' }}>
                {/* 左：各报告完整趋势小图（内部滚动） */}
                <div
                  style={{
                    width: `${split}%`,
                    minWidth: 0,
                    display: 'flex',
                    flexDirection: 'column',
                    paddingRight: 5
                  }}
                >
                  <Card
                    size="small"
                    title="各报告完整趋势（点击小图选取对比点）"
                    extra={tipSlider}
                    style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}
                    styles={{
                      body: {
                        flex: 1,
                        minHeight: 0,
                        overflow: 'auto',
                        padding: 10,
                        // flex 列容器：小图块按比例分配剩余高度
                        display: 'flex',
                        flexDirection: 'column'
                      }
                    }}
                  >
                    {view.map((it, i) => {
                      const st = statsOf(it)
                      return (
                        <div
                          key={it.meta.sessionDir ?? i}
                          style={{
                            border: '1px solid #f0f0f0',
                            borderRadius: 8,
                            padding: '6px 8px 2px',
                            marginBottom: 10,
                            // 小图块纵向撑满：报告少时图表自适应放大，占满左列可视区
                            flex: '1 1 0',
                            minHeight: 150,
                            display: 'flex',
                            flexDirection: 'column'
                          }}
                        >
                          <div
                            style={{
                              display: 'flex',
                              justifyContent: 'space-between',
                              alignItems: 'center',
                              marginBottom: 2
                            }}
                          >
                            <span style={{ fontWeight: 600, fontSize: 13 }}>
                              <i
                                style={{
                                  display: 'inline-block',
                                  width: 10,
                                  height: 10,
                                  borderRadius: 2,
                                  background: viewColors[i],
                                  marginRight: 6
                                }}
                              />
                              {viewLabels[i]}
                            </span>
                            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                              峰值 {formatBytes(st.peakKb)} · {formatDuration(st.durationMs)}
                            </Typography.Text>
                          </div>
                          <MiniTrendChart
                            item={it}
                            pickedTs={viewPicked[i]?.timestamp ?? null}
                            tipOpacity={tipOpacity}
                            onPick={(sample) =>
                              setPicked((prev) =>
                                prev.map((cur, j) => (j === order[i] ? sample : cur))
                              )
                            }
                          />
                        </div>
                      )
                    })}
                  </Card>
                </div>
                {/* 分隔条：拖拽调整左右宽度 */}
                <div
                  onMouseDown={startSplitDrag}
                  onMouseEnter={() => setSplitHover(true)}
                  onMouseLeave={() => setSplitHover(false)}
                  title="拖拽调整左右宽度"
                  style={{
                    width: 10,
                    flex: '0 0 auto',
                    cursor: 'col-resize',
                    display: 'flex',
                    justifyContent: 'center'
                  }}
                >
                  <div
                    style={{
                      width: 3,
                      borderRadius: 2,
                      background: splitHover ? '#1677ff' : '#e5e6eb'
                    }}
                  />
                </div>
                {/* 右：采样点对比表（内部滚动） */}
                <div
                  style={{
                    flex: 1,
                    minWidth: 0,
                    display: 'flex',
                    flexDirection: 'column',
                    paddingLeft: 5
                  }}
                >
                  <PickedCompareCard items={view} labels={viewLabels} picked={viewPicked} colors={viewColors} />
                </div>
              </div>
            )
          }
        ]}
      />
    </>
  )
}

/* ─── 采样点对比表：行 = Total + 分类，列 = 各报告选中时刻的值 + 差值 ─── */

function PickedCompareCard({
  items,
  labels,
  picked,
  colors
}: {
  items: CompareItem[]
  labels: string[]
  picked: (ProcessMemorySample | null)[]
  /** 各报告颜色（跟随报告本身） */
  colors: string[]
}): JSX.Element {
  interface PickRow {
    key: string
    name: string
    color: string
    valuesMb: (number | null)[]
    maxDiffMb: number
  }

  const rows = useMemo<PickRow[]>(() => {
    // 分类并集（按首现顺序）
    const names: string[] = []
    const seen = new Set<string>()
    for (const it of items) {
      for (const s of it.samples) {
        for (const n of Object.keys(s.categories)) {
          if (!seen.has(n)) {
            seen.add(n)
            names.push(n)
          }
        }
      }
    }
    const all = ['Total', ...names].map((name, ni) => {
      const valuesMb = items.map((_, i) => {
        const smp = picked[i]
        if (!smp) return null
        const kb = metricKb(smp, name)
        return kb == null ? null : round1(kbToMb(kb))
      })
      const nums = valuesMb.filter((v): v is number => v != null)
      return {
        key: name,
        name,
        color: name === 'Total' ? '#1677ff' : colorOf(name, Math.max(0, ni - 1)),
        valuesMb,
        maxDiffMb: nums.length ? round1(Math.max(...nums) - Math.min(...nums)) : 0
      }
    })
    // Total 置顶，其余按最大差异降序
    const [totalRow, ...catRows] = all
    catRows.sort((a, b) => b.maxDiffMb - a.maxDiffMb)
    return [totalRow, ...catRows]
  }, [items, picked])

  /** 选中时刻的列头副标题：相对秒 + 绝对时间 */
  const pickedInfo = (i: number): string => {
    const smp = picked[i]
    if (!smp) return '未选择'
    const t0 = items[i].samples[0]?.timestamp ?? items[i].meta.startedAt
    return `选中 ${((smp.timestamp - t0) / 1000).toFixed(1)}s · ${fmtTime(smp.timestamp).slice(11)}`
  }

  const columns: ColumnsType<PickRow> = [
    {
      title: '指标',
      dataIndex: 'name',
      width: 118,
      render: (v: string, r) => (
        <span>
          <b style={{ color: r.color }}>●</b>{' '}
          <span style={{ fontWeight: v === 'Total' ? 600 : 400 }}>{v}</span>
        </span>
      )
    },
    ...items.map((_, i) => ({
      title: (
        <span style={{ lineHeight: 1.25, display: 'inline-block' }}>
          <i
            style={{
              display: 'inline-block',
              width: 8,
              height: 8,
              borderRadius: 2,
              background: colors[i],
              marginRight: 5
            }}
          />
          {labels[i]}
          <div style={{ fontSize: 10, color: '#8c8c8c', fontWeight: 400 }}>{pickedInfo(i)}</div>
        </span>
      ),
      align: 'right' as const,
      width: 124,
      render: (_: unknown, r: PickRow) => {
        const v = r.valuesMb[i]
        if (v == null) return <span style={{ color: '#bbb' }}>-</span>
        const baseV = r.valuesMb[0]
        const d = i > 0 && baseV != null ? round1(v - baseV) : 0
        return (
          <span style={{ fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>
            {v.toFixed(1)}
            {i > 0 && Math.abs(d) > 0.05 && (
              <span
                style={{
                  marginLeft: 4,
                  fontSize: 10.5,
                  color: d > 0 ? '#ff4d4f' : '#389e0d',
                  fontWeight: 600
                }}
              >
                ({d > 0 ? '+' : ''}
                {d.toFixed(1)})
              </span>
            )}
          </span>
        )
      }
    })),
  ]

  return (
    <Card
      size="small"
      title="采样点对比（点击右侧小图选取采样点，默认峰值 · MB · 红高绿低）"
      style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}
      styles={{ body: { padding: 0, flex: 1, minHeight: 0, overflow: 'auto' } }}
    >
      <style>{`.picked-table .ant-table-thead>tr>th{padding:5px 8px}.picked-table .ant-table-tbody>tr>td{padding:2px 8px}`}</style>
      <Table<PickRow>
        className="picked-table"
        size="small"
        sticky
        columns={columns}
        dataSource={rows}
        pagination={false}
        scroll={{ x: 'max-content' }}
      />
    </Card>
  )
}

/* ─── 快照对比：基准顺序条 + 内存构成差异表（Total 置顶，紧凑样式同采样点对比） ─── */

function SnapshotCompare({ items }: { items: CompareItem[] }): JSX.Element {
  const labels = useMemo(() => labelsOf(items), [items])
  // 报告顺序（首个为基准），与趋势对比同一套交互
  const [order, setOrder] = useState<number[]>(() => items.map((_, i) => i))
  const view = useMemo(() => order.map((i) => items[i]), [items, order])
  const viewLabels = useMemo(() => order.map((i) => labels[i]), [order, labels])
  const viewColors = useMemo(() => order.map((oi) => CMP_COLORS[oi % CMP_COLORS.length]), [order])

  interface SnapDiffRow {
    key: string
    name: string
    color: string
    valuesMb: number[]
    maxDiffMb: number
  }
  const rows = useMemo<SnapDiffRow[]>(() => {
    // 分类并集（按最大差异降序）；Total 置顶
    const names = new Set<string>()
    for (const it of view) {
      for (const n of Object.keys(it.snapshot?.categories ?? {})) names.add(n)
    }
    const catRows = [...names].map((name, ni) => {
      const valuesMb = view.map((it) => kbToMb(it.snapshot?.categories[name]?.pssTotalKb ?? 0))
      return {
        key: name,
        name,
        color: colorOf(name, ni),
        valuesMb,
        maxDiffMb: valuesMb.length ? Math.max(...valuesMb) - Math.min(...valuesMb) : 0
      }
    })
    catRows.sort((a, b) => b.maxDiffMb - a.maxDiffMb)
    const totalValues = view.map((it) => kbToMb(it.snapshot?.total.pssTotalKb ?? 0))
    return [
      {
        key: 'Total',
        name: 'Total',
        color: '#1677ff',
        valuesMb: totalValues,
        maxDiffMb: totalValues.length ? Math.max(...totalValues) - Math.min(...totalValues) : 0
      },
      ...catRows
    ]
  }, [view])

  const columns: ColumnsType<SnapDiffRow> = [
    {
      title: '分类',
      dataIndex: 'name',
      width: 140,
      render: (v: string, r) => (
        <span>
          <b style={{ color: r.color }}>●</b>{' '}
          <span style={{ fontWeight: v === 'Total' ? 600 : 400 }}>{v}</span>
        </span>
      )
    },
    ...view.map((_, i) => ({
      width: 170,
      title: (
        <span
          title={(i === 0 ? '基准 · ' : '') + viewLabels[i]}
          style={{
            display: 'inline-block',
            maxWidth: '100%',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            verticalAlign: 'bottom'
          }}
        >
          <i
            style={{
              display: 'inline-block',
              width: 8,
              height: 8,
              borderRadius: 2,
              background: viewColors[i],
              marginRight: 5
            }}
          />
          {i === 0 ? '基准 · ' : ''}
          {viewLabels[i]}
        </span>
      ),
      align: 'right' as const,
      render: (_: unknown, r: SnapDiffRow) => {
        const v = r.valuesMb[i]
        const d = v - r.valuesMb[0]
        return (
          <span style={{ fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>
            {v.toFixed(1)}
            {i > 0 && Math.abs(d) > 0.05 && (
              <span
                style={{
                  marginLeft: 4,
                  fontSize: 10.5,
                  color: d > 0 ? '#ff4d4f' : '#389e0d',
                  fontWeight: 600
                }}
              >
                ({d > 0 ? '+' : ''}
                {d.toFixed(1)})
              </span>
            )}
          </span>
        )
      }
    }))
  ]

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', gap: 12, minHeight: 0 }}>
      <OrderBar labels={labels} order={order} onChange={setOrder} />
      <Card
        size="small"
        title="内存构成差异（相对基准 · 单位 MB · 红=增长 绿=下降）"
        style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}
        styles={{ body: { padding: 0, flex: 1, minHeight: 0, overflow: 'auto' } }}
      >
        <style>{`
          .picked-table .ant-table-thead>tr>th{padding:5px 8px}
          .picked-table .ant-table-tbody>tr>td{padding:2px 8px}
          /* 表格按列宽自适应，多余空白收拢到右侧（rc-table 默认 width:100% 会均摊拉伸） */
          .snap-diff-table .ant-table table{width:auto !important;min-width:0 !important}
        `}</style>
        <Table<SnapDiffRow>
          className="picked-table snap-diff-table"
          tableLayout="fixed"
          size="small"
          sticky
          columns={columns}
          dataSource={rows}
          pagination={false}
        />
      </Card>
    </div>
  )
}

/* ─── 对比窗口根组件 ─── */

export default function CompareApp(): JSX.Element {
  const [items, setItems] = useState<CompareItem[] | null>(null)
  const [error, setError] = useState('')

  const dirs = useMemo(() => {
    const p = new URLSearchParams(window.location.search)
    return (p.get('dirs') ?? '').split('|').filter(Boolean)
  }, [])

  useEffect(() => {
    void (async () => {
      try {
        const loaded: CompareItem[] = []
        for (const dir of dirs) {
          const session = await window.api.openSessionDir(dir)
          if (!session) throw new Error(`无法读取报告目录：${dir}`)
          const snapshot =
            session.meta.type === 'snapshot' ? await window.api.loadSnapshot(dir) : null
          if (session.meta.type === 'snapshot' && !snapshot) {
            throw new Error(`快照数据缺失或已损坏：${dir}`)
          }
          loaded.push({ meta: session.meta, samples: session.samples, snapshot })
        }
        setItems(loaded)
      } catch (e) {
        setError((e as Error).message)
      }
    })()
  }, [dirs])

  const kinds = useMemo(
    () => (items ? new Set(items.map((it) => it.meta.type ?? 'trend')) : new Set<string>()),
    [items]
  )

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: '#f3f5f9' }}>
      <WindowTitleBar
        title={`对比 ${items?.length ?? dirs.length} 份报告`}
        badge={
          <Tag color={kinds.has('snapshot') ? 'gold' : 'blue'}>
            {kinds.has('snapshot') ? '📷 内存快照对比' : '📈 持续采样对比'}
          </Tag>
        }
        description="独立窗口 · 关闭后不影响原报告"
      />
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', padding: 12 }}>
        {error ? (
          <Card>
            <Empty description={`加载对比数据失败：${error}`} />
          </Card>
        ) : !items ? (
          <Card>
            <Empty description="正在加载对比数据…" />
          </Card>
        ) : kinds.size > 1 ? (
          <Card>
            <Empty description="所选报告类型不一致，无法对比" />
          </Card>
        ) : kinds.has('snapshot') ? (
          <div style={{ height: '100%', overflow: 'auto' }}>
            <SnapshotCompare items={items} />
          </div>
        ) : (
          <TrendCompare items={items} />
        )}
      </div>
    </div>
  )
}
