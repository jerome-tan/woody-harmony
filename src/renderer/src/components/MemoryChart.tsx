import { useEffect, useMemo, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import * as echarts from 'echarts'
import type { EChartsOption } from 'echarts'
import { Button, Checkbox, Slider, Switch } from 'antd'
import { FullscreenExitOutlined, FullscreenOutlined } from '@ant-design/icons'
import type { ProcessMemorySample } from '@shared/types'
import { colorOf } from '../constants'
import { formatSampleTooltip, tooltipPosition } from '../chartTooltip'
import { formatBytes, kbToMb } from '../utils'

interface Props {
  samples: ProcessMemorySample[]
  categories: string[]
  /** 图表标题（显示在标题栏左侧，最大化浮层中保留） */
  title?: string
  /** 采集进行中：30s 滑动窗口自动左移；否则默认铺满全程 */
  live?: boolean
}

/** 一屏展示的时间跨度（秒），超出后整体左移（滑动窗口） */
const WINDOW_SEC = 30

/** 可视窗口的最小时间跨度（秒）：防止无限放大导致窗口小于采样间隔、趋势线消失 */
const MIN_VALUE_SPAN = 2

/** 判定「窗口右缘已贴近数据末尾」的容差（秒） */
const FOLLOW_TOLERANCE = 1

/**
 * x 轴基础配置。nameLocation 用 'middle' 让轴标题居中显示，
 * 避免默认 'end' 位置被右缘裁切（只能看到「相」字）。
 */
const X_AXIS_BASE = {
  type: 'value' as const,
  name: '相对时间 (s)',
  nameLocation: 'middle' as const,
  nameGap: 26,
  nameTextStyle: { fontSize: 11 },
  axisLabel: { fontSize: 11, formatter: (v: number) => `${Math.round(v)}` }
}

function catValuePss(s: ProcessMemorySample, category: string): number {
  if (category === 'Total') return s.total.pssTotalKb
  return s.categories[category]?.pssTotalKb ?? 0
}

/** 图表标题栏控制项的 pill 样式：浅灰底圆角容器，把「文字 + 控件」圈成一组 */
const pillStyle: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
  fontSize: 12,
  color: '#666',
  background: '#f5f5f5',
  borderRadius: 6,
  padding: '3px 10px'
}

export default function MemoryChart({
  samples,
  categories,
  title,
  live = false
}: Props): JSX.Element {
  const containerRef = useRef<HTMLDivElement>(null)
  // 图表+分类侧栏的外层容器：横向滚轮平移需在此捕获阶段拦截，先于 ECharts 的缩放监听
  const wrapRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<echarts.ECharts | null>(null)

  // 用户是否手动缩放过（缩放后停止自动跟随最新）
  const manualRef = useRef(false)
  const [manual, setManual] = useState(false)
  // 程序写入窗口期间为 true，用于在 datazoom 事件中屏蔽程序写
  const applyingRef = useRef(false)
  // 最近一次由程序写入的窗口，兜底区分「用户缩放」与「自动滑动」
  const appliedRef = useRef({ start: 0, end: WINDOW_SEC })
  // 会话标识（首帧时间戳），换会话时重置缩放状态
  const sessionKeyRef = useRef(0)

  // 供 tooltip 回调读取最新数据（避免 setOption 合并更新时闭包拿到旧值）
  const samplesRef = useRef(samples)
  samplesRef.current = samples

  // 分类勾选（未勾选的从 series 中移除）
  const [hidden, setHidden] = useState<Set<string>>(new Set())
  // 悬浮框背景透明度（0.3 ~ 1，默认近乎不透明；tooltip 会遮挡曲线时用户可调低）
  const [tipOpacity, setTipOpacity] = useState(0.8)
 // 是否平滑曲线：默认关闭，直接显示折线
  const [smooth, setSmooth] = useState(false)
  // 是否在 Total 线上标记每个采样点（默认开）
  const [showPoints, setShowPoints] = useState(true)
  // 最大化（全屏浮层，Esc 或按钮还原）
  const [maximized, setMaximized] = useState(false)

  // Esc 退出最大化
  useEffect(() => {
    if (!maximized) return
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') setMaximized(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [maximized])
  const visibleCategories = useMemo(
    () => categories.filter((c) => !hidden.has(c)),
    [categories, hidden]
  )

  const toggleCategory = (category: string, checked: boolean): void => {
    setHidden((prev) => {
      const next = new Set(prev)
      if (checked) next.delete(category)
      else next.add(category)
      return next
    })
  }

  const followLatest = (): void => {
    manualRef.current = false
    setManual(false)
  }

  useEffect(() => {
    if (!containerRef.current) return
    const chart = echarts.init(containerRef.current)
    chartRef.current = chart
    // 监听容器自身尺寸变化：窗口缩放、侧栏拖拽、卡片 flex 高度变化都能自适应
    const observer = new ResizeObserver(() => chart.resize())
    observer.observe(containerRef.current)
    return () => {
      observer.disconnect()
      chart.dispose()
      chartRef.current = null
    }
  }, [])

  // 新会话（首帧时间戳变化）时重置缩放状态，回到自动窗口
  useEffect(() => {
    const key = samples[0]?.timestamp ?? 0
    if (key !== sessionKeyRef.current) {
      sessionKeyRef.current = key
      manualRef.current = false
      setManual(false)
    }
  }, [samples])

  // 用户通过 dataZoom（滚轮/拖拽/拖滚动条）改变窗口后，停止自动跟随；
  // 缩放到完整范围（或窗口覆盖全程）时视为回到自动跟随
  useEffect(() => {
    const chart = chartRef.current
    if (!chart) return
    const handler = (): void => {
      if (applyingRef.current) return
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const dz = (chart.getOption() as any).dataZoom?.[0]
      if (!dz) return
      const start = Number(dz.startValue)
      const end = Number(dz.endValue)
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return
      const applied = appliedRef.current
      if (Math.abs(start - applied.start) < 0.2 && Math.abs(end - applied.end) < 0.2) return
      // 缩到/拖到完整范围：视为回到自动跟随
      if (Number(dz.start) <= 0.5 && Number(dz.end) >= 99.5) {
        if (manualRef.current) {
          manualRef.current = false
          setManual(false)
        }
        return
      }
      const prevSpan = applied.end - applied.start
      // 跨度基本不变 = 平移；平移回数据末尾时恢复自动跟随，否则进入手动态（视图保持不动）
      const isPan = Math.abs(end - start - prevSpan) < 0.05
      appliedRef.current = { start, end }
      const list = samplesRef.current
      const elapsed =
        list.length > 0 ? (list[list.length - 1].timestamp - list[0].timestamp) / 1000 : 0
      if (isPan && end >= elapsed - FOLLOW_TOLERANCE) {
        if (manualRef.current) {
          manualRef.current = false
          setManual(false)
        }
        return
      }
      if (!manualRef.current) {
        manualRef.current = true
        setManual(true)
      }
    }
    chart.on('datazoom', handler)
    return () => {
      chart.off('datazoom', handler)
    }
  }, [])

  // 触摸板/滚轮手势统一在父级捕获阶段处理：
  // 1. 横向滑动 = 平移：必须拦截并 stopPropagation，否则 zrender 的 getWheelDeltaMayPolyfill
  //    在 deltaY=0（纯横向）时回退用 deltaX 换算缩放，横向滑动会被当成缩放；
  // 2. 纵向滚轮继续放大且已达最小跨度时直接吞掉事件：ECharts 的跨度钳制（sliderMove）
  //    会保留以鼠标为锚点重算的左缘、把右缘顶出（end=start+minSpan），导致窗口随放大漂移。
  useEffect(() => {
    const wrap = wrapRef.current
    const chart = chartRef.current
    if (!wrap || !chart) return
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const currentSpan = (): number | null => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const dz = (chart.getOption() as any).dataZoom?.[0]
      if (!dz) return null
      const start = Number(dz.startValue)
      const end = Number(dz.endValue)
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null
      return end - start
    }
    const swallow = (e: WheelEvent): void => {
      e.preventDefault()
      e.stopPropagation()
    }
    const onWheel = (e: WheelEvent): void => {
      if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) {
        // 纵向（滚轮/捏合）缩放：已达最小跨度后继续放大 → 吞掉，保持不动
        if (e.deltaY < 0) {
          const span = currentSpan()
          if (span != null && span <= MIN_VALUE_SPAN + 1e-3) swallow(e)
        }
        return
      }
      // 横向滑动 = 平移
      swallow(e)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const dz = (chart.getOption() as any).dataZoom?.[0]
      if (!dz) return
      const start = Number(dz.startValue)
      const end = Number(dz.endValue)
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return
      const span = end - start
      const list = samplesRef.current
      if (list.length === 0) return
      const domainMax = Math.max((list[list.length - 1].timestamp - list[0].timestamp) / 1000, 1)
      // 位移量与图表像素宽成正比：滑过整个图表宽 ≈ 平移一个窗口
      const shift = (e.deltaX / Math.max(wrap.clientWidth, 1)) * span
      let ns = start + shift
      if (ns < 0) ns = 0
      if (ns + span > domainMax) ns = domainMax - span
      if (ns === start) return
      applyingRef.current = true
      chart.dispatchAction({ type: 'dataZoom', startValue: ns, endValue: ns + span })
      applyingRef.current = false
      appliedRef.current = { start: ns, end: ns + span }
      // 平移到数据末尾：恢复自动跟随；平移到历史段：进入手动态，视图不再随新采样移动
      if (ns + span >= domainMax - FOLLOW_TOLERANCE) {
        if (manualRef.current) {
          manualRef.current = false
          setManual(false)
        }
      } else if (!manualRef.current) {
        manualRef.current = true
        setManual(true)
      }
    }
    wrap.addEventListener('wheel', onWheel, { passive: false, capture: true })
    return () => wrap.removeEventListener('wheel', onWheel, true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const option = useMemo<EChartsOption>(() => {
    const t0 = samples[0]?.timestamp ?? 0
    const relSec = (s: ProcessMemorySample): number => (s.timestamp - t0) / 1000
    const elapsed =
      samples.length > 0 ? (samples[samples.length - 1].timestamp - t0) / 1000 : 0

    const series = visibleCategories.map((category) => {
      const ci = categories.indexOf(category)
      const isTotal = category === 'Total'
      return {
        name: category,
        type: 'line' as const,
        smooth,
        // Total 线可按开关标记采样点：圆点略粗于线宽（线 2.5px → 点 5px），白边保证密集时可分辨；
        // 其余分类始终不画点
        showSymbol: isTotal ? showPoints : false,
        symbol: 'circle',
        symbolSize: 5,
        // 不做 lttb 抽稀：抽稀点在缩放小窗口内过于稀疏，导致窗口边缘线条「断开」；
        // 1s 间隔下数据量有限（1 小时仅 3600 点/系列），全量绘制即可，边缘由画布裁剪
        clip: true,
        data: samples.map((s) => [relSec(s), kbToMb(catValuePss(s, category))] as [number, number]),
        lineStyle: { width: isTotal ? 2.5 : 1.5 },
        itemStyle:
          isTotal && showPoints
            ? { color: colorOf(category, ci), borderColor: '#fff', borderWidth: 1 }
            : { color: colorOf(category, ci) },
        emphasis: { focus: 'series' as const }
      }
    })

    // 停止后：找出 Total 的最高采样点，单独标记并显示峰值内存。
    // markPoint 使用精确坐标，不受 lttb 降采样影响。
    const peakPoint =
      !live && samples.length > 0
        ? samples.reduce<{ x: number; kb: number } | null>((acc, s) => {
            const kb = s.total.pssTotalKb
            return !acc || kb > acc.kb ? { x: relSec(s), kb } : acc
          }, null)
        : null
    if (peakPoint) {
      const total = series.find((s) => s.name === 'Total')
      if (total) {
        Object.assign(total, {
          markPoint: {
            symbol: 'circle',
            symbolSize: 9,
            itemStyle: {
              color: colorOf('Total', categories.indexOf('Total')),
              borderColor: '#fff',
              borderWidth: 1.5
            },
            label: {
              show: true,
              position: 'top',
              distance: 8,
              formatter: (): string => `峰值 ${formatBytes(peakPoint.kb)}`,
              fontSize: 11,
              color: '#333',
              backgroundColor: 'rgba(255,255,255,0.85)',
              borderColor: 'rgba(0,0,0,0.12)',
              borderWidth: 1,
              borderRadius: 3,
              padding: [2, 6]
            },
            data: [{ coord: [peakPoint.x, kbToMb(peakPoint.kb)], name: '峰值' }]
          }
        })
      }
    }

    return {
      color: visibleCategories.map((c) => colorOf(c, categories.indexOf(c))),
      animation: false,
      tooltip: {
        trigger: 'axis',
        // 渲染到 body 下，避免分类较多时 tooltip 被图表容器裁剪
        appendToBody: true,
        // 钳制在视口内，避免内容超出屏幕边界
        position: tooltipPosition,
        backgroundColor: `rgba(255,255,255,${tipOpacity})`,
        axisPointer: {
          type: 'line',
          lineStyle: { type: 'dashed', color: '#999' }
        },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        formatter: (params: any) => formatSampleTooltip(params, samplesRef.current)
      },
      grid: { left: 64, right: 24, top: 44, bottom: 84 },
      // 报告/停止后：x 轴范围精确固定到数据末尾，消除刻度取整造成的右侧留白；
      // 随 option 原子写入（不依赖二次 setOption 补写）。实时模式用自动刻度（min/max 置 null，
      // 防止从报告切回时配置合并保留旧的固定范围；ECharts 运行时默认即 null，类型定义未包含故断言）。
      xAxis: (
        live
          ? { ...X_AXIS_BASE, min: null, max: null }
          : { ...X_AXIS_BASE, min: 0, max: Math.max(elapsed, 1) }
      ) as EChartsOption['xAxis'],
      yAxis: {
        type: 'value',
        name: '内存',
        scale: true,
        axisLabel: {
          fontSize: 11,
          formatter: (v: number) => formatBytes(v * 1024)
        },
        splitLine: { lineStyle: { type: 'dashed', color: '#eee' } }
      },
      // 注意：不在此处设置 min/max/startValue/endValue——domain 每秒变化时
      // merge 更新会让 ECharts 内部 dataZoom 状态漂移（窗口卡住、缩略图与主图脱节）。
      // 窗口统一由下方 effect 通过 dispatchAction 命令式写入。
      dataZoom: [
        {
          type: 'inside',
          xAxisIndex: 0,
          // 不过滤数据点：默认 filter 会丢弃窗口外的点，导致线条只从窗口内第一个点开始画、
          // 两侧到窗口边缘之间空白；none 只改可视范围，线段在边缘处被画布裁剪、保持连续
          filterMode: 'none',
          // 放开 ECharts 默认 5%~95% 的 span 钳制：滚轮缩到最小时不再被内部校正改写窗口
          minSpan: 0.5,
          maxSpan: 100,
          // 值域最小跨度：防止无限放大导致可视窗口小于采样间隔、趋势线消失
          minValueSpan: MIN_VALUE_SPAN
        },
        {
          type: 'slider',
          xAxisIndex: 0,
          height: 44,
          bottom: 14,
          filterMode: 'none',
          minSpan: 0.5,
          maxSpan: 100,
          minValueSpan: MIN_VALUE_SPAN,
          labelFormatter: (v: number) => `${Math.round(v)}s`,
          textStyle: { fontSize: 11 }
        }
      ],
      series
    }
  }, [samples, categories, visibleCategories, smooth, showPoints, live, tipOpacity])

  // 应用 option：仅整体替换 series，其余组件合并更新，避免每秒重建坐标系造成的卡顿
  useEffect(() => {
    const chart = chartRef.current
    if (!chart) return
    applyingRef.current = true
    chart.setOption(option, { replaceMerge: ['series'] })
    // 非实时场景下清掉可能残留的 tooltip（series 替换后旧 tooltip 会变成残影）
    if (!live) chart.dispatchAction({ type: 'hideTip' })
    applyingRef.current = false
  }, [option, live])

  // 窗口控制：命令式写入可视窗口（百分比，与 ECharts span 检查同域）。
  // 跟随开关（manualRef）统一由 datazoom / 触摸板平移处理器管理：
  // - 未缩放/未平移：实时模式滑动跟随最新，报告页铺满全程
  // - 手动查看（缩放或平移历史段）：视图保持不动，采样继续，直到用户平移回数据末尾
  //   或缩放到完整范围才恢复跟随
  useEffect(() => {
    const chart = chartRef.current
    if (!chart || samples.length === 0) return
    const t0 = samples[0].timestamp
    const elapsed = (samples[samples.length - 1].timestamp - t0) / 1000

    if (!manualRef.current) {
      const cur = appliedRef.current
      const start = live ? Math.max(0, elapsed - WINDOW_SEC) : 0
      const end = live ? Math.max(WINDOW_SEC, elapsed) : Math.max(elapsed, 1)
      if (Math.abs(start - cur.start) > 0.05 || Math.abs(end - cur.end) > 0.05) {
        appliedRef.current = { start, end }
        const span = Math.max(elapsed, 1)
        applyingRef.current = true
        chart.dispatchAction({
          type: 'dataZoom',
          start: (start / span) * 100,
          end: (end / span) * 100
        })
        applyingRef.current = false
      }
    }
  }, [samples, live, manual])

  return (
    <div
      style={
        maximized
          ? {
              position: 'fixed',
              // 不覆盖应用顶部标题栏（46px，含红绿灯按钮），避免最大化时误点关闭窗口
              top: 46,
              left: 0,
              right: 0,
              bottom: 0,
              zIndex: 1000,
              background: '#fff',
              display: 'flex',
              flexDirection: 'column'
            }
          : { display: 'flex', flexDirection: 'column', width: '100%', height: '100%' }
      }
    >
      {/* 标题栏：最大化浮层中同样保留 */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '5px 10px',
          borderBottom: '1px solid #f0f0f0',
          flex: '0 0 auto'
        }}
      >
        {title && <span style={{ fontWeight: 600, fontSize: 13 }}>{title}</span>}
        <span style={{ flex: 1 }} />
        {/* 控制项统一包成 pill（浅灰底圆角），保证控件与文字说明的分组一目了然 */}
        <span style={pillStyle}>
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
        <span style={pillStyle}>
          <Switch size="small" checked={showPoints} onChange={setShowPoints} />
          显示采样点
        </span>
        <span style={pillStyle}>
          <Switch size="small" checked={smooth} onChange={setSmooth} />
          平滑曲线
        </span>
        <Button type="link" size="small" disabled={!manual} onClick={followLatest}>
          重置视图
        </Button>
        <Button
          type="text"
          size="small"
          icon={maximized ? <FullscreenExitOutlined /> : <FullscreenOutlined />}
          title={maximized ? '还原（Esc）' : '最大化展示'}
          onClick={() => setMaximized((v) => !v)}
        />
      </div>
      <div
        ref={wrapRef}
        style={{ display: 'flex', gap: 10, flex: 1, minHeight: 0, padding: maximized ? 12 : 0 }}
      >
        <div ref={containerRef} style={{ flex: 1, minWidth: 0, height: '100%' }} />
        <div
          style={{
            flex: '0 0 190px',
            width: 190,
            height: '100%',
            display: 'flex',
            flexDirection: 'column',
            borderLeft: '1px solid #f0f0f0',
            paddingLeft: 10
          }}
        >
          <div style={{ marginBottom: 6 }}>
            <span style={{ fontSize: 12, color: '#666' }}>内存分类</span>
          </div>
          <div style={{ flex: 1, minHeight: 0, overflow: 'auto' }}>
            {categories.map((category) => {
              const ci = categories.indexOf(category)
              return (
                <div
                  key={category}
                  style={{ marginBottom: 2 }}
                  // 悬停分类行 = 高亮图中对应曲线（其余变淡，与悬停图例/曲线效果一致）
                  onMouseEnter={() => {
                    if (hidden.has(category)) return
                    chartRef.current?.dispatchAction({ type: 'highlight', seriesName: category })
                  }}
                  onMouseLeave={() => {
                    chartRef.current?.dispatchAction({ type: 'downplay', seriesName: category })
                  }}
                >
                  <Checkbox
                    checked={!hidden.has(category)}
                    onChange={(e) => toggleCategory(category, e.target.checked)}
                  >
                    <span
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 5,
                        fontSize: 12
                      }}
                    >
                      <span
                        style={{
                          width: 10,
                          height: 10,
                          borderRadius: 2,
                          background: colorOf(category, ci),
                          border: '1px solid rgba(0,0,0,0.15)',
                          flex: '0 0 auto'
                        }}
                      />
                      <span>{category}</span>
                    </span>
                  </Checkbox>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}
