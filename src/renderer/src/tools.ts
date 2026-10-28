import type { PageKey } from './pages/types'

/** 工具注册表：新增工具只需在此登记一条元数据 */
export interface ToolDef {
  /** 路由：点击卡片跳转的页面 */
  route: PageKey
  icon: string
  /** 图标底色（antd 主题色系） */
  color: string
  name: string
  tag: string
  desc: string
}

export const TOOLS: ToolDef[] = [
  {
    route: 'watch',
    icon: '📡',
    color: '#52c41a',
    name: '实时内存',
    tag: '实时查看 · 不落盘',
    desc: '对应 DevEco Profiler 的实时监控（Realtime Monitor）：以实时图表观察进程内存的瞬时变化，数据仅保留在内存中——不写盘、不生成报告，适合随手的临时观察。'
  },
  {
    route: 'snap',
    icon: '📷',
    color: '#faad14',
    name: '内存快照',
    tag: '单次采集 · 快照报告',
    desc: '对应 DevEco Profiler 的 Snapshot：对目标进程执行一次 hidumper --mem，定格当前时刻的完整内存构成（分类 Pss、私有脏、Swap、Heap 明细等），适合抓取异常现场、对比前后差异。'
  },
  {
    route: 'peak',
    icon: '📈',
    color: '#1677ff',
    name: '持续内存采样',
    tag: '周期采集 · 趋势报告',
    desc: '按固定间隔执行 hidumper --mem 持续录制（对应 DevEco Allocation 的 Memory 泳道语义），追踪内存随时间的变化曲线，定位峰值与疑似泄漏点，结束后自动生成趋势报告。'
  }
]
