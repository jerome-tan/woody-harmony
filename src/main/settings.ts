import { promises as fs } from 'fs'
import { join } from 'path'

const SETTINGS_FILE = 'settings.json'

export interface AppSettings {
  hdcPath: string
  /** 自定义采集报告输出目录；空串表示使用默认目录（userData/sessions） */
  sessionsDir: string
}

const DEFAULTS: AppSettings = { hdcPath: '', sessionsDir: '' }

export async function loadSettings(userDataDir: string): Promise<AppSettings> {
  const file = join(userDataDir, SETTINGS_FILE)
  try {
    const raw = await fs.readFile(file, 'utf8')
    return { ...DEFAULTS, ...JSON.parse(raw) }
  } catch {
    return { ...DEFAULTS }
  }
}

export async function saveSettings(userDataDir: string, settings: AppSettings): Promise<void> {
  const file = join(userDataDir, SETTINGS_FILE)
  await fs.writeFile(file, JSON.stringify(settings, null, 2), 'utf8')
}
