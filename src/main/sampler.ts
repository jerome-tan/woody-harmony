import { EventEmitter } from 'events'
import type {
  DeviceInfo,
  MemoryCategoryValues,
  ProcessMemorySample,
  SamplerConfig,
  SamplingSessionMeta,
  SamplingStatus
} from '@shared/types'
import { getCurrentTarget, getPidByName, shell } from './hdc'
import { parseProcessMemory } from './hidumper'
import { appendSample, ensureDir, writeMeta, writeRawSample } from './storage'

function zeroCategoryValues(): MemoryCategoryValues {
  return {
    pssTotalKb: 0,
    sharedCleanKb: 0,
    sharedDirtyKb: 0,
    privateCleanKb: 0,
    privateDirtyKb: 0,
    swapTotalKb: 0,
    swapPssTotalKb: 0,
    heapSizeKb: 0,
    heapAllocKb: 0,
    heapFreeKb: 0
  }
}

/** 应用未运行时的占位采样：数据全 0，pid 为空 */
function makeZeroSample(): ProcessMemorySample {
  return {
    timestamp: Date.now(),
    pid: null,
    total: zeroCategoryValues(),
    categories: {},
    nativeHeapDetail: {},
    purgSumKb: 0,
    purgPinKb: 0,
    dmaKb: 0,
    ashmemTotalKb: 0
  }
}

function makeSessionId(bundleName: string): string {
  const d = new Date()
  const pad = (n: number): string => String(n).padStart(2, '0')
  const ts = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  return `${bundleName}-${ts}`
}

class Sampler extends EventEmitter {
  private running = false
  private timer: NodeJS.Timeout | null = null
  private pid: number | null = null
  private config: SamplerConfig | null = null
  private bundleName = ''
  private appLabel = ''
  private sessionDir = ''
  private meta: SamplingSessionMeta | null = null
  private sampleCount = 0
  private consecutiveFailures = 0
  /** 会话开始时刻（用于采样时长上限判定） */
  private startedAtTs = 0
  /** false 为实时查看模式：全程不落盘（无 meta/samples/raw），结束不生成报告 */
  private persist = true

  isRunning(): boolean {
    return this.running
  }

  getMeta(): SamplingSessionMeta | null {
    return this.meta
  }

  /** 当前（或最近一次）会话的落盘目录，无会话时为空串 */
  getSessionDir(): string {
    return this.sessionDir
  }

  private setStatus(state: SamplingStatus['state'], message?: string, autoStopped = false): void {
    const status: SamplingStatus = { state, message }
    if (autoStopped) status.autoStopped = true
    this.emit('status', status)
  }

  async start(
    saveRoot: string,
    config: SamplerConfig,
    bundleName: string,
    appLabel: string,
    device?: DeviceInfo,
    persist = true,
    taskName?: string
  ): Promise<void> {
    if (this.running) throw new Error('已有采样正在进行中，请先停止')
    const target = getCurrentTarget()
    if (!target) throw new Error('尚未选择目标设备')

    this.config = config
    this.bundleName = bundleName
    this.appLabel = appLabel
    this.sampleCount = 0
    this.consecutiveFailures = 0
    this.persist = persist
    this.startedAtTs = Date.now()

    this.setStatus('starting', '正在定位应用进程…')
    try {
      // 应用未启动也允许采集：pid 为空期间记录全 0 占位数据，待应用启动后自动接管为真实采样
      this.pid = await getPidByName(this.bundleName).catch(() => null)

      if (persist) {
        this.sessionDir = `${saveRoot}/${makeSessionId(bundleName)}`
        await ensureDir(this.sessionDir)
        this.meta = {
          id: makeSessionId(bundleName),
          bundleName,
          appLabel,
          device: device ?? {
            targetId: target,
            marketName: '',
            model: '',
            softwareVersion: '',
            apiVersion: '',
            serialNumber: target,
            ramTotalKb: 0,
            screenResolution: ''
          },
          config,
          startedAt: Date.now(),
          sampleCount: 0,
          sessionDir: this.sessionDir,
          taskName: taskName?.trim() || undefined
        }
        await writeMeta(this.sessionDir, this.meta)
      } else {
        // 实时查看模式：不建目录、不写 meta
        this.sessionDir = ''
        this.meta = null
      }
    } catch (err) {
      // 启动失败：复位并广播错误态，避免 UI 卡在「启动中」且停止按钮失效
      this.pid = null
      this.meta = null
      this.setStatus('error', `启动采集失败：${(err as Error).message}`)
      throw err
    }

    this.running = true
    this.setStatus(
      'sampling',
      this.pid != null ? `采样中，pid=${this.pid}` : '应用未运行，记录全 0 数据，等待应用启动…'
    )
    // 立即采集一次，随后按间隔循环
    void this.loop()
  }

  private async loop(): Promise<void> {
    if (!this.running) return
    const cfg = this.config as SamplerConfig
    // 采样时长上限：到期自动结束（避免用户忘记停止，记录文件持续膨胀）
    const maxMs = cfg.maxDurationMs ?? 0
    if (maxMs > 0 && Date.now() - this.startedAtTs >= maxMs) {
      await this.finish(true)
      return
    }
    const tickStart = Date.now()
    try {
      // pid 为空（应用未运行）时每次尝试重新解析，应用一旦启动即接管
      if (this.pid == null) {
        const pid = await getPidByName(this.bundleName).catch(() => null)
        if (pid != null) {
          this.pid = pid
          this.setStatus('sampling', `采样中，pid=${pid}`)
        }
      }
      const sample = this.pid == null ? makeZeroSample() : await this.collectOnce()
      if (this.running) {
        this.sampleCount++
        // 实时查看模式不落盘，仅广播到界面
        if (this.persist) await appendSample(this.sessionDir, sample)
        this.consecutiveFailures = 0
        this.emit('sample', sample)
      }
    } catch (err) {
      // 采样失败：多半是进程退出/重启，重新解析 pid
      const newPid = await getPidByName(this.bundleName).catch(() => null)
      if (newPid == null) {
        // 进程已退出：回到等待模式（记录全 0），不算错误
        this.pid = null
        this.consecutiveFailures = 0
        this.setStatus('sampling', '应用未运行，记录全 0 数据，等待应用启动…')
      } else if (newPid !== this.pid) {
        this.pid = newPid
        this.consecutiveFailures = 0
        this.setStatus('sampling', `进程 pid 变化为 ${newPid}`)
      } else {
        this.consecutiveFailures++
        if (this.consecutiveFailures >= 5) {
          this.setStatus('error', `采样连续失败：${(err as Error).message}`)
          await this.finish()
          return
        }
      }
    }
    if (this.running) {
      // 以本次 tick 起点对齐间隔，避免 hidumper 执行耗时叠加导致实际周期变大
      const delay = Math.max(0, cfg.intervalMs - (Date.now() - tickStart))
      this.timer = setTimeout(() => void this.loop(), delay)
    }
  }

  private async collectOnce(): Promise<ProcessMemorySample> {
    if (!this.pid) throw new Error('pid 为空')
    const cfg = this.config as SamplerConfig
    const args = ['hidumper', '--mem', String(this.pid)]
    if (cfg.showAshmem) args.push('--show-ashmem')
    if (cfg.showDmabuf) args.push('--show-dmabuf')
    if (cfg.showGpumem) args.push('--show-gpumem')
    const raw = await shell(args.join(' '), { timeout: 30000 })
    const timestamp = Date.now()
    // 保留本次 hidumper 原始输出（raw/<bundleName>-<时间戳>.txt），便于核查解析结果；
    // 实时查看模式不落盘。写文件不阻塞采样节奏（fire-and-forget），失败忽略。
    if (this.persist) {
      void writeRawSample(this.sessionDir, this.bundleName, timestamp, raw).catch(() => undefined)
    }

    const parsed = parseProcessMemory(raw)
    const sample: ProcessMemorySample = {
      timestamp,
      pid: this.pid,
      total: parsed.total,
      categories: parsed.categories,
      nativeHeapDetail: parsed.nativeHeapDetail,
      purgSumKb: parsed.purgSumKb,
      purgPinKb: parsed.purgPinKb,
      dmaKb: parsed.dmaKb,
      ashmemTotalKb: parsed.ashmemTotalKb
    }
    return sample
  }

  async stop(): Promise<SamplingSessionMeta | null> {
    if (!this.running) return this.meta
    this.setStatus('stopping', '正在停止…')
    return this.finish()
  }

  private async finish(autoStopped = false): Promise<SamplingSessionMeta | null> {
    this.running = false
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (this.meta) {
      this.meta.endedAt = Date.now()
      this.meta.sampleCount = this.sampleCount
      try {
        await writeMeta(this.sessionDir, this.meta)
      } catch {
        // ignore
      }
    }
    this.setStatus(
      'idle',
      autoStopped ? '已达采样时长上限，采样自动结束' : '已停止',
      autoStopped
    )
    return this.meta
  }

  /**
   * 同步运行中会话的任务名称（记录列表里重命名时调用）。
   * 否则 stop() 会用内存中的旧 meta 覆盖磁盘上已更新的名称。
   */
  updateTaskName(dir: string, taskName: string): void {
    if (this.meta && this.sessionDir === dir) {
      const value = taskName.trim()
      if (value) this.meta.taskName = value
    }
  }
}

export const sampler = new Sampler()