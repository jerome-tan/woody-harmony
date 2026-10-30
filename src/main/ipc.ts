import { app, BrowserWindow, dialog, ipcMain, shell as electronShell } from 'electron'
import { promises as fsp } from 'fs'
import { homedir } from 'os'
import { dirname, join } from 'path'
import { configureWindowChrome, windowChromeOptions } from './windowChrome'
import {
  getCurrentTarget,
  getDeviceProps,
  getPidByName,
  getScreenResolution,
  listApps,
  listDevices,
  resolveHdcPathPublic,
  setCurrentTarget,
  setHdcPath,
  shell
} from './hdc'
import { parseMemoryDetails, parseProcessMemory, parseProcMeminfo, parseSystemMemory } from './hidumper'
import { sampler } from './sampler'
import {
  deleteSession,
  listSessions,
  loadSession,
  loadSnapshot,
  updateSessionTaskName,
  writeMeta,
  writeSnapshot,
  writeSnapshotRaw,
  writeSnapshotSmaps
} from './storage'
import { loadSettings, saveSettings } from './settings'
import type { AppSettings } from './settings'
import type {
  DeviceInfo,
  MemorySnapshot,
  ProcessMemorySample,
  SamplerConfig,
  SamplingSessionMeta,
  SamplingStatus,
  SnapshotOptions
} from '@shared/types'

function broadcast(channel: string, payload: unknown): void {
  for (const win of BrowserWindow.getAllWindows()) {
    win.webContents.send(channel, payload)
  }
}

// 最近一次成功采集的设备信息，供采样会话写入 meta（避免采样启动时重复采集）
let cachedDeviceInfo: DeviceInfo | null = null

async function buildDeviceInfo(): Promise<DeviceInfo | null> {
  const targetId = getCurrentTarget()
  if (!targetId) return null
  const { marketName, model, softwareVersion, apiVersion } = await getDeviceProps()
  // 优先读 /proc/meminfo（瞬时返回）；全量 hidumper --mem 需遍历所有进程（26s+），仅作兜底
  let ramTotalKb = 0
  try {
    const meminfo = await shell('cat /proc/meminfo', { timeout: 10000 })
    ramTotalKb = parseProcMeminfo(meminfo).ramTotalKb
    if (!ramTotalKb) throw new Error('meminfo 解析为空')
  } catch {
    ramTotalKb = parseSystemMemory(await shell('hidumper --mem', { timeout: 90000 })).ramTotalKb
  }
  const screenResolution = await getScreenResolution()
  return {
    targetId,
    marketName,
    model,
    softwareVersion,
    apiVersion,
    serialNumber: targetId,
    ramTotalKb,
    screenResolution
  }
}

/** 快照目录名：<bundleName>-snapshot-<yyyyMMdd-HHmmss>，与采样会话目录同风格 */
function makeSnapshotDirName(bundleName: string): string {
  const d = new Date()
  const pad = (n: number): string => String(n).padStart(2, '0')
  const ts = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  return `${bundleName}-snapshot-${ts}`
}

async function pathExists(p: string): Promise<boolean> {
  try {
    await fsp.access(p)
    return true
  } catch {
    return false
  }
}

/**
 * 历史版本默认输出目录（<userData>/sessions，含各历史应用名）整体迁移到 ~/.woody/reports。
 * 仅当目标目录不存在时迁移；失败不阻塞启动。
 */
async function migrateLegacySessionsDir(target: string): Promise<void> {
  if (await pathExists(target)) return
  const appData = app.getPath('appData')
  for (const legacy of ['Woody', '啄木鸟', '鸿蒙内存采样工具', 'HarmonyOS Memory Tools']) {
    const dir = join(appData, legacy, 'sessions')
    if (!(await pathExists(dir))) continue
    try {
      await fsp.mkdir(dirname(target), { recursive: true })
      await fsp.rename(dir, target)
    } catch {
      /* 迁移失败不阻塞启动，设置页可手动指定旧目录 */
    }
    return
  }
}

export function registerIpc(): void {
  const userDataDir = app.getPath('userData')
  /** 默认输出根目录：~/.woody/reports（用户 HOME 下可见、便于备份；曾位于 userData/sessions） */
  const defaultSessionsRoot = join(homedir(), '.woody', 'reports')
  // 内存中的完整设置（saveSettings 整文件覆盖，避免字段互冲）
  const settings: AppSettings = { hdcPath: '', sessionsDir: '' }
  // 「打开历史」对话框上次选中目录的父目录（本次运行内记忆）
  let lastSessionOpenParent = ''

  /** 当前生效的采集报告输出根目录：自定义优先，否则默认 ~/.woody/reports */
  const getSessionsRoot = (): string => settings.sessionsDir || defaultSessionsRoot

  void loadSettings(userDataDir).then(async (s) => {
    Object.assign(settings, s)
    if (settings.hdcPath) setHdcPath(settings.hdcPath)
    // 用户未自定义输出目录时，把历史默认目录里的报告迁到新位置
    if (!settings.sessionsDir) await migrateLegacySessionsDir(defaultSessionsRoot)
  })

  sampler.on('sample', (s: ProcessMemorySample) => broadcast('sampling:sample', s))
  sampler.on('status', (s: SamplingStatus) => broadcast('sampling:status', s))

  ipcMain.handle('hdc:getPath', () => resolveHdcPathPublic())
  ipcMain.handle('hdc:setPath', async (_e, p: string) => {
    setHdcPath(p)
    settings.hdcPath = p
    await saveSettings(userDataDir, settings)
  })

  // 采集报告输出目录：查询 / 弹框选择 / 保存（空串恢复默认）
  ipcMain.handle('settings:getSessionsDir', () => ({
    custom: settings.sessionsDir,
    defaultDir: defaultSessionsRoot
  }))
  ipcMain.handle('settings:chooseSessionsDir', async () => {
    const res = await dialog.showOpenDialog({
      title: '选择采集报告输出目录',
      defaultPath: getSessionsRoot(),
      properties: ['openDirectory', 'createDirectory']
    })
    return res.canceled || res.filePaths.length === 0 ? null : res.filePaths[0]
  })
  ipcMain.handle('settings:setSessionsDir', async (_e, dir: string) => {
    settings.sessionsDir = (dir || '').trim()
    await saveSettings(userDataDir, settings)
  })

  ipcMain.handle('device:list', () => listDevices())
  ipcMain.handle('device:setTarget', (_e, targetId: string) => {
    if (getCurrentTarget() !== (targetId || null)) cachedDeviceInfo = null
    setCurrentTarget(targetId || null)
  })
  ipcMain.handle('device:info', async () => {
    if (!getCurrentTarget()) {
      cachedDeviceInfo = null
      return null
    }
    try {
      cachedDeviceInfo = await buildDeviceInfo()
      return cachedDeviceInfo
    } catch (err) {
      throw new Error(`获取设备信息失败：${(err as Error).message}`)
    }
  })

  ipcMain.handle('app:list', async () => {
    if (!getCurrentTarget()) throw new Error('请先选择目标设备')
    return listApps()
  })

  ipcMain.handle(
    'sampling:start',
    (_e, config: SamplerConfig, bundleName: string, appLabel: string, persist?: boolean, taskName?: string) => {
      // 采样会话写入真实设备信息；优先用缓存，缺失时即时采集（失败则回退占位）
      const devicePromise: Promise<DeviceInfo | undefined> = cachedDeviceInfo
        ? Promise.resolve(cachedDeviceInfo)
        : buildDeviceInfo().catch(() => null).then((d) => d ?? undefined)
      return devicePromise.then((device) =>
        sampler.start(getSessionsRoot(), config, bundleName, appLabel, device, persist, taskName)
      )
    }
  )
  ipcMain.handle('sampling:stop', () => sampler.stop())

  // 内存快照：一次性 hidumper --mem，落盘为独立快照目录（meta.json type=snapshot + snapshot.json）
  ipcMain.handle('snapshot:take', async (_e, bundleName: string, appLabel: string, taskName?: string, options?: SnapshotOptions) => {
    const target = getCurrentTarget()
    if (!target) throw new Error('尚未选择目标设备')
    const pid = await getPidByName(bundleName).catch(() => null)
    if (pid == null) throw new Error(`应用 ${bundleName} 未在运行，无法拍摄快照`)
    // --show-* 明细参数附加在 --mem 输出末尾（ashmem/dmabuf 明细、GPU 分桶），由 parseMemoryDetails 解析
    const flags = [
      options?.showAshmem && '--show-ashmem',
      options?.showDmabuf && '--show-dmabuf',
      options?.showGpumem && '--show-gpumem'
    ].filter(Boolean)
    const raw = await shell(`hidumper --mem ${pid}${flags.length ? ' ' + flags.join(' ') : ''}`, { timeout: 30000 })
    const details = parseMemoryDetails(raw)
    const snapshot: MemorySnapshot = { capturedAt: Date.now(), pid, ...parseProcessMemory(raw) }
    if (options?.showAshmem) snapshot.ashmemDetail = details.ashmem
    if (options?.showDmabuf) snapshot.dmabufDetail = details.dmabuf
    if (options?.showGpumem && details.gpu) snapshot.gpuDetail = details.gpu

    // 与采样会话同级的快照目录，复用记录列表/删除/备注链路
    const dirName = makeSnapshotDirName(bundleName)
    const dir = join(getSessionsRoot(), dirName)
    const device: DeviceInfo = cachedDeviceInfo ??
      (await buildDeviceInfo().catch(() => null)) ?? {
        targetId: target,
        marketName: '',
        model: '',
        softwareVersion: '',
        apiVersion: '',
        serialNumber: target,
        ramTotalKb: 0,
        screenResolution: ''
      }
    const meta: SamplingSessionMeta = {
      id: dirName,
      type: 'snapshot',
      bundleName,
      appLabel,
      device,
      // 快照无采样配置，仅占位以满足 meta 结构
      config: {
        intervalMs: 0,
        showAshmem: false,
        showDmabuf: false,
        showGpumem: false
      },
      startedAt: snapshot.capturedAt,
      endedAt: snapshot.capturedAt,
      sampleCount: 1,
      sessionDir: dir,
      taskName: taskName?.trim() || undefined
    }
    await writeMeta(dir, meta)
    await writeSnapshot(dir, snapshot)
    // 保留 hidumper 原始输出全文，便于核对解析结果
    await writeSnapshotRaw(dir, bundleName, snapshot.capturedAt, raw)
    // 勾选 smaps 时追加采集逐 VMA 明细（较慢），落盘为 <同名>.smaps.txt
    if (options?.includeSmaps) {
      const smapsRaw = await shell(`hidumper --mem-smaps ${pid}`, { timeout: 60000 }).catch(() => null)
      if (smapsRaw != null) await writeSnapshotSmaps(dir, bundleName, snapshot.capturedAt, smapsRaw)
    }
    return { meta, snapshot }
  })

  ipcMain.handle('snapshot:load', (_e, dir: string) => (dir ? loadSnapshot(dir) : null))

  ipcMain.handle('session:open', async () => {
    const res = await dialog.showOpenDialog({
      title: '选择已保存的采样目录',
      // 默认定位到上一次打开历史时的父目录；首次则为当前输出根目录
      defaultPath: lastSessionOpenParent || getSessionsRoot(),
      properties: ['openDirectory']
    })
    if (res.canceled || res.filePaths.length === 0) return null
    const dir = res.filePaths[0]
    lastSessionOpenParent = dirname(dir)
    const session = await loadSession(dir)
    if (session && !session.meta.sessionDir) session.meta.sessionDir = dir
    return session
  })

  ipcMain.handle('session:list', () => listSessions(getSessionsRoot()))

  ipcMain.handle('session:openDir', async (_e, dir: string) => {
    if (!dir) return null
    const session = await loadSession(dir)
    if (session && !session.meta.sessionDir) session.meta.sessionDir = dir
    return session
  })

  ipcMain.handle('session:delete', async (_e, dir: string) => {
    if (!dir) return
    if (sampler.isRunning() && sampler.getSessionDir() === dir) {
      throw new Error('该记录正在采样中，无法删除')
    }
    await deleteSession(dir)
  })

  ipcMain.handle('session:rename', async (_e, dir: string, taskName: string) => {
    if (!dir) return
    await updateSessionTaskName(dir, taskName)
    // 若改的是正在采样中的会话，同步内存态，避免停止时被旧 meta 覆盖
    sampler.updateTaskName(dir, taskName)
  })

  ipcMain.handle('session:getDir', () => sampler.getSessionDir())
  ipcMain.handle('shell:revealPath', async (_e, dir: string) => {
    if (!dir) throw new Error('暂无可打开的目录')
    const err = await electronShell.openPath(dir)
    if (err) throw new Error(err)
  })

  // 单报告查看窗口：每份报告一个独立 BrowserWindow，可同时打开多份（经 query 传入会话目录）
  ipcMain.handle('report:open', (_e, dir: string) => {
    if (typeof dir !== 'string' || !dir) return
    const win = new BrowserWindow({
      width: 1280,
      height: 840,
      // minWidth 需 ≤ 半屏宽度（1280 宽屏 Mac 为 640），否则 macOS 分屏平铺时窗口超出半屏互相重叠
      minWidth: 640,
      minHeight: 600,
      title: '报告 - Woody',
      ...windowChromeOptions(),
      webPreferences: {
        preload: join(__dirname, '../preload/index.js'),
        sandbox: false,
        contextIsolation: true,
        nodeIntegration: false
      }
    })
    configureWindowChrome(win)
    if (process.env['ELECTRON_RENDERER_URL']) {
      void win.loadURL(
        `${process.env['ELECTRON_RENDERER_URL']}?mode=report&dir=${encodeURIComponent(dir)}`
      )
    } else {
      void win.loadFile(join(__dirname, '../renderer/index.html'), {
        query: { mode: 'report', dir }
      })
    }
  })

  // 报告对比窗口：独立 BrowserWindow，加载同一渲染入口，经 query 传入对比的会话目录
  ipcMain.handle('compare:open', (_e, dirs: string[]) => {
    const valid = (Array.isArray(dirs) ? dirs : []).filter((d) => typeof d === 'string' && d)
    if (valid.length < 2) return
    const query = `mode=compare&dirs=${encodeURIComponent(valid.join('|'))}`
    const win = new BrowserWindow({
      width: 1440,
      height: 900,
      // minWidth 需 ≤ 半屏宽度（1280 宽屏 Mac 为 640），否则 macOS 分屏平铺时窗口超出半屏互相重叠
      minWidth: 640,
      minHeight: 620,
      title: '报告对比 - Woody',
      ...windowChromeOptions(),
      webPreferences: {
        preload: join(__dirname, '../preload/index.js'),
        sandbox: false,
        contextIsolation: true,
        nodeIntegration: false
      }
    })
    configureWindowChrome(win)
    if (process.env['ELECTRON_RENDERER_URL']) {
      void win.loadURL(`${process.env['ELECTRON_RENDERER_URL']}?${query}`)
    } else {
      void win.loadFile(join(__dirname, '../renderer/index.html'), {
        query: { mode: 'compare', dirs: valid.join('|') }
      })
    }
  })
}
