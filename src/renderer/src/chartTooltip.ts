import type { ProcessMemorySample } from '@shared/types'

/**
 * tooltip 定位。
 *
 * 注意坐标系陷阱：ECharts 传给 position 回调的 point 是「图表容器内坐标」
 * （实测：鼠标在视口 y≈700 时 point[1] 只有 142），而回调返回值会被
 * ECharts 加上容器偏移后渲染。因此必须先在「视口坐标系」里完成所有
 * 越界/遮挡判断（用全局追踪的 clientX/clientY），最后换算回容器坐标系返回。
 *
 * 垂直方向优先显示在鼠标上方——鼠标位于屏幕下半区时，下方/居中显示会让
 * tooltip 底部被悬浮的 macOS Dock（或任务栏）遮挡。
 */

// 全局追踪鼠标视口坐标（passive，无性能影响）
let lastClientX = 0
let lastClientY = 0
if (typeof window !== 'undefined') {
  window.addEventListener(
    'mousemove',
    (e) => {
      lastClientX = e.clientX
      lastClientY = e.clientY
    },
    { passive: true }
  )
}

export function tooltipPosition(
  point: number[],
  _params: unknown,
  dom: unknown,
  _rect: unknown,
  size?: { contentSize: [number, number]; viewSize: [number, number] }
): number[] {
  const vw = window.innerWidth
  const vh = window.innerHeight
  let cw = 0
  let ch = 0
  if (size?.contentSize) {
    ;[cw, ch] = size.contentSize
  }
  if ((!cw || !ch) && dom) {
    const el = (Array.isArray(dom) ? dom[0] : dom) as HTMLElement | undefined
    cw = el?.offsetWidth || cw
    ch = el?.offsetHeight || ch
  }
  // 双路都读不到（理论兜底）：按常见尺寸估算
  if (!cw) cw = 320
  if (!ch) ch = 240

  // 容器在视口系中的偏移 = 鼠标视口坐标 - 鼠标容器内坐标
  const containerLeft = lastClientX - point[0]
  const containerTop = lastClientY - point[1]

  // 以下均在视口坐标系计算
  let vx = lastClientX + 12
  if (vx + cw > vw - 8) vx = Math.max(8, lastClientX - cw - 12)
  // 垂直：优先鼠标上方；上方放不下才放下方
  let vy = lastClientY - ch - 12
  if (vy < 8) {
    vy = Math.min(lastClientY + 12, vh - ch - 8)
    if (vy < 8) vy = 8
  }

  // 换算回 ECharts 期望的容器坐标系
  return [vx - containerLeft, vy - containerTop]
}

/** ECharts axis tooltip 参数（仅取本函数需要的字段） */
interface AxisTipParam {
  dataIndex: number
  seriesName: string
  color?: string
  marker?: string
}

/**
 * 采样点 tooltip 的 HTML：报告页趋势图与对比窗口小图共用同一格式。
 * Total 置顶（黑色加粗 + GB 换算），其余分类按内存降序，右侧占比与条形。
 */
export function formatSampleTooltip(params: unknown, samples: ProcessMemorySample[]): string {
  const arr: AxisTipParam[] = Array.isArray(params) ? params : [params]
  if (arr.length === 0) return ''
  const idx = arr[0]?.dataIndex
  const sample = samples[idx ?? -1]
  if (!sample) return ''
  const t0 = samples[0]?.timestamp ?? 0
  const totalKb = sample.total.pssTotalKb

  // Total 置顶，其余按内存降序：大项在上，重点一眼可见
  const rows = arr
    .map((p) => ({
      p,
      kb:
        p.seriesName === 'Total'
          ? sample.total.pssTotalKb
          : (sample.categories[p.seriesName]?.pssTotalKb ?? 0)
    }))
    .sort((a, b) => {
      const aTotal = a.p.seriesName === 'Total'
      const bTotal = b.p.seriesName === 'Total'
      if (aTotal !== bTotal) return aTotal ? -1 : 1
      return b.kb - a.kb
    })

  const num = 'font-variant-numeric:tabular-nums;white-space:nowrap'
  const line = (r: { p: AxisTipParam; kb: number }): string => {
    const name = r.p.seriesName
    const isTotal = name === 'Total'
    const mb = r.kb / 1024
    const pct = totalKb > 0 ? (r.kb / totalKb) * 100 : 0
    const weight = isTotal ? 'font-weight:600' : ''
    const color = String(r.p.color ?? '#999')
    const nameCell =
      `<span style="display:flex;align-items:center;gap:4px;white-space:nowrap;max-width:130px;overflow:hidden;text-overflow:ellipsis;${weight}">` +
      `${r.p.marker ?? ''} ${name}</span>`
    // Total 的 GB 换算用绝对定位挂在数值后面，不参与布局，
    // 避免撑宽占比列、导致其他行的 MB 值与百分比之间出现空隙
    const valueCell = isTotal
      ? `<span style="text-align:right;${num};${weight}"><span style="position:relative;display:inline-block">${mb.toFixed(1)} MB` +
        `<span style="position:absolute;left:100%;top:0;margin-left:4px">（${(mb / 1024).toFixed(2)} GB）</span></span></span>`
      : `<span style="text-align:right;${num}">${mb.toFixed(1)} MB</span>`
    const pctCell = isTotal
      ? '<span></span>'
      : `<span style="text-align:right;color:#999;${num}">${pct.toFixed(1)}%</span>`
    const barCell = isTotal
      ? '<span></span>'
      : `<span style="display:block;height:4px;width:48px;background:#f0f0f0;border-radius:2px;overflow:hidden">` +
        `<span style="display:block;height:100%;width:${Math.min(100, pct).toFixed(1)}%;background:${color}"></span></span>`
    return nameCell + valueCell + pctCell + barCell
  }

  const absTime = new Date(sample.timestamp).toLocaleTimeString()
  const header =
    `<div style="font-size:12px;color:#666;margin-bottom:5px;text-align:center">` +
    `相对 ${((sample.timestamp - t0) / 1000).toFixed(1)}s · ${absTime}</div>`
  const body =
    `<div style="max-height:60vh;overflow-y:auto">` +
    `<div style="display:grid;grid-template-columns:auto minmax(56px,auto) auto auto;` +
    `column-gap:8px;row-gap:3px;align-items:center;font-size:12px">` +
    rows.map(line).join('') +
    '</div></div>'
  return header + body
}
