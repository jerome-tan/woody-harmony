// 内存分类的单行数值（对应 hidumper --mem pid 输出的 10 列）
export interface MemoryCategoryValues {
  pssTotalKb: number
  sharedCleanKb: number
  sharedDirtyKb: number
  privateCleanKb: number
  privateDirtyKb: number
  swapTotalKb: number
  swapPssTotalKb: number
  heapSizeKb: number
  heapAllocKb: number
  heapFreeKb: number
}

export interface DeviceInfo {
  targetId: string
  /** 型号名称，如 HUAWEI Mate 60 Pro（const.product.name） */
  marketName: string
  /** 型号代码，如 ALN-AL80（const.product.model） */
  model: string
  /** 软件版本，如 HarmonyOS 6.1.1.120 */
  softwareVersion: string
  /** API 版本，如 18 */
  apiVersion: string
  /** 序列号（hdc 目标标识） */
  serialNumber: string
  /** 运行内存总量 */
  ramTotalKb: number
  /** 屏幕分辨率，如 1260 × 2720 */
  screenResolution: string
}

export interface DeviceSummary {
  targetId: string
  status: string
}

export interface AppInfo {
  bundleName: string
  label: string
  /** 运行中进程的主 PID；未运行为 null */
  pid: number | null
}

export interface SamplerConfig {
  // 采样间隔（毫秒）
  intervalMs: number
  // 是否打印 ashmem 明细（--show-ashmem）
  showAshmem: boolean
  // 是否打印 DMA 明细（--show-dmabuf）
  showDmabuf: boolean
  // 是否打印 GPU 内存明细（--show-gpumem）
  showGpumem: boolean
  /** 采样时长上限（毫秒），到期自动结束并落盘；0/缺省 = 不限 */
  maxDurationMs?: number
}

export interface ProcessMemorySample {
  timestamp: number
  /** 采样时刻的进程 PID；应用未运行时的占位采样为 null（数据全 0） */
  pid: number | null
  total: MemoryCategoryValues
  categories: Record<string, MemoryCategoryValues>
  nativeHeapDetail: Record<string, MemoryCategoryValues>
  purgSumKb: number
  purgPinKb: number
  dmaKb: number
  ashmemTotalKb: number
}

/** 报告类型：趋势采样会话 / 单次内存快照（历史会话文件无此字段，视为 trend） */
export type ReportType = 'trend' | 'snapshot'

export interface SamplingSessionMeta {
  id: string
  /** 缺省为趋势采样会话 */
  type?: ReportType
  bundleName: string
  appLabel: string
  device: DeviceInfo
  config: SamplerConfig
  startedAt: number
  endedAt?: number
  sampleCount: number
  /** 会话落盘目录（meta.json / samples.jsonl 所在目录） */
  sessionDir?: string
  /** 任务名称：峰值采样表单必填（默认 Task-yyyyMMdd-HHmmss），快照无此字段 */
  taskName?: string
}

/** ashmem 明细条目（--show-ashmem）：每条匿名共享内存块 */
export interface AshmemEntry {
  /** 块名称（去掉 dev/ashmem/ 前缀），如 Create PixelMap */
  name: string
  fd: number
  virtualBytes: number
  physicalBytes: number
}

/** DMA buffer 明细条目（--show-dmabuf）：每个 ION/DMA buffer */
export interface DmabufEntry {
  /** 对象类型名（leak_type 列），如 xcomponent-s-RenderXComponent_WIID_MainWindow */
  name: string
  fd: number
  ino: number
  sizeBytes: number
}

/** GPU 内存的一个 Channel（--show-gpumem） */
export interface GpuChannel {
  name: string
  totalBytes: number
}

/** GPU 内存明细 */
export interface GpuDetail {
  channels: GpuChannel[]
  totalUsedBytes: number
  totalAllocatedBytes: number
}

/** 单次内存快照：hidumper --mem <pid> 的一次性采集解析结果，落盘为 snapshot.json */
export interface MemorySnapshot {
  capturedAt: number
  pid: number
  total: MemoryCategoryValues
  categories: Record<string, MemoryCategoryValues>
  nativeHeapDetail: Record<string, MemoryCategoryValues>
  purgSumKb: number
  purgPinKb: number
  dmaKb: number
  ashmemTotalKb: number
  /** ashmem 明细（采集时勾选 --show-ashmem 才有） */
  ashmemDetail?: AshmemEntry[]
  /** DMA buffer 明细（采集时勾选 --show-dmabuf 才有） */
  dmabufDetail?: DmabufEntry[]
  /** GPU 内存明细（采集时勾选 --show-gpumem 才有） */
  gpuDetail?: GpuDetail
}

export type SamplingState = 'idle' | 'starting' | 'sampling' | 'stopping' | 'error'

export interface SamplingStatus {
  state: SamplingState
  message?: string
  /** 因达到采样时长上限而自动结束（区别于用户手动停止） */
  autoStopped?: boolean
}

export interface LoadedSession {
  meta: SamplingSessionMeta
  samples: ProcessMemorySample[]
}

/** 「关于」弹窗信息：版本 + 构建期固化的提交/系统信息 + 运行时组件版本 */
export interface AboutInfo {
  version: string
  /** 构建时最新 git commit（无 git 仓库时为空串） */
  commit: string
  /** 该 commit 的提交时间（YYYY-MM-DD HH:mm） */
  commitDate: string
  electron: string
  node: string
  v8: string
  /** 构建机系统（如 Darwin arm64 25.6.0） */
  os: string
}

/** 快照采集选项 */
export interface SnapshotOptions {
  /** 采集 smaps 逐 VMA 明细（较慢，落盘为 .smaps.txt 原文） */
  includeSmaps?: boolean
  /** 采集 ashmem 明细（--show-ashmem） */
  showAshmem?: boolean
  /** 采集 DMA buffer 明细（--show-dmabuf） */
  showDmabuf?: boolean
  /** 采集 GPU 内存明细（--show-gpumem） */
  showGpumem?: boolean
}

// preload 暴露给渲染进程的 API
export interface IpcApi {
  /** Actual host platform, supplied by preload rather than inferred from the user agent. */
  readonly platform: string
  /** Open the application menu for the calling window; resolves when the menu closes. */
  showWindowMenu(x: number, y: number): Promise<void>
  getHdcPath(): Promise<string>
  setHdcPath(path: string): Promise<void>
  /** 采集报告输出目录：custom 为自定义值（空串=默认），defaultDir 为默认目录 */
  getSessionsDir(): Promise<{ custom: string; defaultDir: string }>
  /** 弹出目录选择框，返回所选目录；取消返回 null（仅选择，不保存） */
  chooseSessionsDir(): Promise<string | null>
  /** 保存自定义输出目录；传空串恢复默认 */
  setSessionsDir(dir: string): Promise<void>
  listDevices(): Promise<DeviceSummary[]>
  setTarget(targetId: string): Promise<void>
  getDeviceInfo(): Promise<DeviceInfo | null>
  listApps(): Promise<AppInfo[]>
  startSampling(
    config: SamplerConfig,
    bundleName: string,
    appLabel: string,
    /** 是否落盘；false 为实时查看模式（不写 meta/samples/raw，结束不生成报告） */
    persist?: boolean,
    /** 任务名称（峰值采样） */
    taskName?: string
  ): Promise<void>
  stopSampling(): Promise<SamplingSessionMeta | null>
  onSample(cb: (s: ProcessMemorySample) => void): () => void
  onSamplingStatus(cb: (s: SamplingStatus) => void): () => void
  /** 拍摄一次内存快照：按包名定位进程，执行 hidumper --mem 并落盘，返回完整数据 */
  takeSnapshot(
    bundleName: string,
    appLabel: string,
    taskName?: string,
    options?: SnapshotOptions
  ): Promise<{ meta: SamplingSessionMeta; snapshot: MemorySnapshot }>
  /** 按目录加载已保存的内存快照（snapshot.json） */
  loadSnapshot(dir: string): Promise<MemorySnapshot | null>
  openSession(): Promise<LoadedSession | null>
  /** 列出全部历史采样记录（按开始时间倒序） */
  listSessions(): Promise<SamplingSessionMeta[]>
  /** 按目录加载指定采样记录 */
  openSessionDir(dir: string): Promise<LoadedSession | null>
  /** 删除指定采样记录目录 */
  deleteSession(dir: string): Promise<void>
  /** 编辑某条采样记录的任务名称（回写 meta.json） */
  renameSession(dir: string, taskName: string): Promise<void>
  /** 当前（或最近一次）会话的落盘目录 */
  getSessionDir(): Promise<string>
  /** 用系统文件管理器打开指定目录 */
  revealPath(path: string): Promise<void>
  /** 打开单份报告查看窗口（独立 BrowserWindow，可同时打开多份） */
  openReportWindow(dir: string): Promise<void>
  /** 打开报告对比窗口（独立 BrowserWindow，加载同一渲染入口的对比视图） */
  openCompareWindow(dirs: string[]): Promise<void>
  /** 菜单「关于」点击事件（携带版本与构建信息） */
  onShowAbout(cb: (info: AboutInfo) => void): () => void
}
