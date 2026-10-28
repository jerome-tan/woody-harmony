import type { ToolTargetState } from '../components/TargetPicker'
import type {
  AppInfo,
  DeviceInfo,
  DeviceSummary,
  SamplerConfig,
  SamplingStatus,
  SnapshotOptions
} from '@shared/types'

/** 页面路由：4 个主导航页 + 工具流程页（报告详情为独立窗口，不占主窗口路由） */
export type PageKey =
  | 'home'
  | 'tools'
  | 'reports'
  | 'settings'
  | 'peak'
  | 'live'
  | 'watch'
  | 'snap'

export interface PageProps {
  go: (page: PageKey) => void
  // 设备上下文（App 全局轮询维护）
  devices: DeviceSummary[]
  currentTarget: string | null
  deviceInfo: DeviceInfo | null
  deviceLoading: boolean
  onRefreshDevices: () => void
  onSelectDevice: (targetId: string) => void
  // 采样状态
  sampling: boolean
  status: SamplingStatus
  /** 启动采样（配置页参数），成功后 App 自动跳转实时页 */
  onStartPeak: (target: ToolTargetState, config: SamplerConfig, taskName: string) => void
  /** 拍摄快照（配置页参数），完成后弹出独立报告窗口；options 为明细采集选项 */
  onStartSnap: (target: ToolTargetState, taskName: string, options: SnapshotOptions) => void
  /** 是否正在执行快照抓取（抓取中页禁用重复点击） */
  snapshotting: boolean
  // 报告
  refreshRecordsTick: number
  /** 编辑任务名称（回写 meta.json） */
  onSaveTaskName: (dir: string, taskName: string) => Promise<void>
}
