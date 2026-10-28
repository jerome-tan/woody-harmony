import { execFile } from 'child_process'
import { promisify } from 'util'
import { existsSync, readdirSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'
import type { AppInfo, DeviceSummary } from '@shared/types'

const execFileAsync = promisify(execFile)

const isWin = process.platform === 'win32'
const HDC_BIN = isWin ? 'hdc.exe' : 'hdc'
const HDC_STD_BIN = isWin ? 'hdc_std.exe' : 'hdc_std'

let hdcPath = ''
let currentTarget: string | null = null

function listSubdirs(dir: string): string[] {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => join(dir, d.name))
  } catch {
    return []
  }
}

/** 版本目录按数字降序排列，优先使用新版 SDK */
function sortVersionDirsDesc(dirs: string[]): string[] {
  return dirs.sort((a, b) => {
    const na = parseFloat(a.split(/[\\/]/).pop() || '0') || 0
    const nb = parseFloat(b.split(/[\\/]/).pop() || '0') || 0
    return nb - na
  })
}

function candidatePaths(): string[] {
  const home = homedir()
  const list: string[] = []
  if (isWin) {
    // DevEco Studio 默认 SDK：~/AppData/Local/OpenHarmony/Sdk/<版本>/toolchains/hdc.exe
    for (const root of [
      join(home, 'AppData', 'Local', 'OpenHarmony', 'Sdk'),
      join(home, 'AppData', 'Local', 'Huawei', 'Sdk')
    ]) {
      for (const v of sortVersionDirsDesc(listSubdirs(root))) {
        list.push(join(v, 'toolchains', HDC_BIN))
      }
      list.push(join(root, 'toolchains', HDC_BIN), join(root, HDC_BIN))
    }
    list.push('C:\\Program Files\\Huawei\\Sdk\\toolchains\\' + HDC_BIN)
  } else {
    // DevEco Studio 默认 SDK：~/Library/OpenHarmony/Sdk/<版本>/toolchains/hdc
    for (const root of [
      join(home, 'Library', 'OpenHarmony', 'Sdk'),
      join(home, 'Library', 'Huawei', 'Sdk')
    ]) {
      for (const v of sortVersionDirsDesc(listSubdirs(root))) {
        list.push(join(v, 'toolchains', HDC_BIN))
      }
      list.push(join(root, 'toolchains', HDC_BIN), join(root, HDC_BIN))
    }
    // DevEco Studio 应用包内 SDK：/Applications/DevEco-Studio*.app/Contents/sdk/*/openharmony/toolchains/hdc
    for (const app of listSubdirs('/Applications').filter((p) => /deveco-studio/i.test(p))) {
      for (const sdkDir of listSubdirs(join(app, 'Contents', 'sdk'))) {
        list.push(join(sdkDir, 'openharmony', 'toolchains', HDC_BIN))
      }
    }
    // 官方命令行工具包解压目录（command-line-tools-*）
    for (const base of [home, join(home, 'Tools')]) {
      for (const dir of listSubdirs(base).filter((p) => /command-line-tools/i.test(p))) {
        for (const sdkDir of listSubdirs(join(dir, 'sdk'))) {
          list.push(join(sdkDir, 'openharmony', 'toolchains', HDC_BIN))
        }
      }
    }
    list.push(
      join(home, '.local', 'bin', HDC_BIN),
      '/usr/local/bin/' + HDC_BIN,
      join(home, 'Library', 'OpenHarmony', 'Sdk', 'toolchains', HDC_STD_BIN)
    )
  }
  return list
}

export function setHdcPath(p: string): void {
  hdcPath = p
}

export function getCurrentTarget(): string | null {
  return currentTarget
}

export function setCurrentTarget(t: string | null): void {
  currentTarget = t
}

async function resolveHdcPath(): Promise<string> {
  if (hdcPath && existsSync(hdcPath)) return hdcPath
  // 支持通过 HDC_PATH 环境变量显式指定
  const envPath = process.env.HDC_PATH
  if (envPath && existsSync(envPath)) {
    hdcPath = envPath
    return envPath
  }
  for (const c of candidatePaths()) {
    if (existsSync(c)) {
      hdcPath = c
      return c
    }
  }
  // GUI 应用不继承 shell 配置文件中的 PATH，主动查询登录 shell 里的 hdc
  const fromShell = await resolveFromLoginShell()
  if (fromShell) {
    hdcPath = fromShell
    return fromShell
  }
  // 依赖 PATH 环境变量中的命令名（Windows GUI 应用可继承系统/用户 PATH；
  // macOS 从终端启动 dev 时也可继承）
  return HDC_BIN
}

/**
 * 通过非交互登录 shell 解析用户环境中的 hdc。
 * macOS 上双击启动的 GUI 应用不加载 ~/.zprofile / ~/.zshenv 中的 PATH，
 * 这里用 zsh -lc 还原：.zshenv（任何 zsh 调用都会读）与 .zprofile 均会被加载。
 * 刻意不用 -i（交互模式才读 ~/.zshrc）：交互式初始化可能 source 重量级脚本，
 * 耗时长且不可靠。
 */
async function resolveFromLoginShell(): Promise<string | null> {
  if (isWin) return null
  const shellBin = process.env.SHELL || '/bin/zsh'
  try {
    const { stdout } = await execFileAsync(shellBin, ['-lc', 'which hdc'], {
      timeout: 3000,
      encoding: 'utf8'
    })
    // shell 启动脚本可能输出其他内容，取最后一个形如绝对路径的行
    const lines = stdout.split(/\r?\n/).map((l) => l.trim())
    const hit = [...lines].reverse().find((l) => l.startsWith('/') && l.endsWith(`/${HDC_BIN}`))
    if (hit && existsSync(hit)) return hit
  } catch {
    // shell 解析失败不影响后续兜底
  }
  return null
}

/** 当前生效的 hdc 路径（含自动探测结果） */
export async function resolveHdcPathPublic(): Promise<string> {
  return resolveHdcPath()
}

interface RunOptions {
  useTarget?: boolean
  timeout?: number
}

export async function runHdc(args: string[], opts: RunOptions = {}): Promise<string> {
  const { useTarget = true, timeout = 20000 } = opts
  const bin = await resolveHdcPath()
  const fullArgs: string[] = []
  if (useTarget && currentTarget) {
    fullArgs.push('-t', currentTarget)
  }
  fullArgs.push(...args)
  try {
    const { stdout } = await execFileAsync(bin, fullArgs, {
      timeout,
      maxBuffer: 32 * 1024 * 1024,
      encoding: 'utf8'
    })
    return stdout
  } catch (err) {
    const e = err as { stderr?: string; message?: string; code?: string }
    if (e?.code === 'ENOENT') {
      throw new Error(
        `未找到 hdc 可执行文件（已尝试自动探测常见安装目录）。` +
          `请在左侧「hdc 路径」输入框中手动指定 hdc 的完整路径，例如 DevEco Studio 自带：\n` +
          (isWin
            ? `C:\\Users\\<用户名>\\AppData\\Local\\OpenHarmony\\Sdk\\<版本>\\toolchains\\hdc.exe`
            : `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`)
      )
    }
    throw new Error(`hdc ${args.join(' ')} 执行失败: ${e?.stderr || e?.message || '未知错误'}`)
  }
}

export async function shell(cmd: string, opts: RunOptions = {}): Promise<string> {
  return runHdc(['shell', cmd], opts)
}

export async function listDevices(): Promise<DeviceSummary[]> {
  const out = await runHdc(['list targets'], { useTarget: false })
  return out
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && l !== '[Empty]')
    .map((l) => {
      const parts = l.split(/\s+/)
      return { targetId: parts[0], status: parts[1] || 'connected' }
    })
}

async function getParam(name: string): Promise<string> {
  try {
    const out = (await shell(`param get ${name}`, { timeout: 10000 })).trim()
    // 参数不存在/无权限时输出形如 Get parameter "xxx" fail! errNum is:106!
    return out.includes('fail!') ? '' : out
  } catch {
    return ''
  }
}

export interface DeviceProps {
  marketName: string
  model: string
  softwareVersion: string
  apiVersion: string
}

export async function getDeviceProps(): Promise<DeviceProps> {
  const marketName = await getParam('const.product.name')
  const model = (await getParam('const.product.model')) || (await getParam('const.ohos.model'))
  // 发行版名称（HarmonyOS）+ 构建号（OpenHarmony-6.1.1.120 中的 6.1.1.120）
  const distName = (await getParam('const.product.os.dist.name')) || 'HarmonyOS'
  const fullname = await getParam('const.ohos.fullname')
  const distVersion = await getParam('const.product.os.dist.version')
  const build = fullname.includes('-') ? fullname.split('-').pop()!.trim() : distVersion
  // API 版本（如 18），不同版本参数名不一，逐个兜底
  const apiVersion =
    (await getParam('const.ohos.apiversion')) || (await getParam('const.product.os.dist.apiversion'))
  return {
    marketName: marketName || '未知',
    model: model || '未知',
    softwareVersion: build ? `${distName} ${build}` : distName,
    apiVersion
  }
}

/** 主屏渲染分辨率，如 1260 × 2720；获取失败返回空串 */
export async function getScreenResolution(): Promise<string> {
  try {
    const out = await shell('hidumper -s RenderService -a screen', { timeout: 15000 })
    const m = out.match(/render resolution=(\d+)\s*x\s*(\d+)/)
    return m ? `${m[1]} × ${m[2]}` : ''
  } catch {
    return ''
  }
}

export async function listApps(): Promise<AppInfo[]> {
  const out = await shell('bm dump -a', { timeout: 40000 })
  const seen = new Map<string, AppInfo>()
  const add = (bundleName: string): void => {
    if (!seen.has(bundleName)) {
      seen.set(bundleName, {
        bundleName,
        label: bundleName.split('.').pop() || bundleName,
        pid: null
      })
    }
  }
  // 格式一：键值对（部分系统版本输出 "bundleName": "com.xxx"）
  const kvRe = /bundleName["']?\s*[:=]\s*["']?([A-Za-z0-9_.]+)["']?/g
  let m: RegExpExecArray | null
  while ((m = kvRe.exec(out))) add(m[1])
  // 格式二：纯包名列表（OpenHarmony 6.x：ID: <userId>: 下每行一个包名）
  for (const line of out.split(/\r?\n/)) {
    const lm = line.match(/^\s*([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)\s*$/)
    if (lm) add(lm[1])
  }
  // 关联运行中进程的 PID（应用主进程名 = 包名，多进程为 包名:子进程名）
  try {
    const ps = await shell('ps -ef', { timeout: 15000 })
    for (const line of ps.split(/\r?\n/)) {
      const tokens = line.trim().split(/\s+/)
      // ps -ef 列：UID PID PPID C STIME TTY TIME CMD...
      if (tokens.length < 8 || !/^\d+$/.test(tokens[1])) continue
      const cmd = tokens[7]
      const base = cmd.includes(':') ? cmd.slice(0, cmd.indexOf(':')) : cmd
      const app = seen.get(base)
      if (app && app.pid == null) {
        app.pid = parseInt(tokens[1], 10)
      }
    }
  } catch {
    // ps 不可用时全部按未运行处理
  }
  const apps = Array.from(seen.values())
  // 运行中的应用排在前面，组内保持设备返回顺序（sort 稳定）
  apps.sort((a, b) => Number(b.pid != null) - Number(a.pid != null))
  return apps
}

export async function getPidByName(name: string): Promise<number | null> {
  try {
    const out = await shell(`pidof ${name}`)
    const m = out.match(/\d+/)
    if (m) return parseInt(m[0], 10)
  } catch {
    // pidof 不可用时回退到 ps -ef
  }
  try {
    const ps = await shell('ps -ef')
    for (const line of ps.split(/\r?\n/)) {
      if (line.includes(name)) {
        const tokens = line.trim().split(/\s+/)
        if (tokens.length >= 2 && /^\d+$/.test(tokens[1])) {
          return parseInt(tokens[1], 10)
        }
      }
    }
  } catch {
    // ignore
  }
  return null
}
