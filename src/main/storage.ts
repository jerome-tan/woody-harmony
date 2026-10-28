import { promises as fs } from 'fs'
import { join } from 'path'
import type { MemorySnapshot, ProcessMemorySample, SamplingSessionMeta } from '@shared/types'

export async function ensureDir(dir: string): Promise<void> {
  await fs.mkdir(dir, { recursive: true })
}

export async function writeMeta(dir: string, meta: SamplingSessionMeta): Promise<void> {
  await ensureDir(dir)
  await fs.writeFile(join(dir, 'meta.json'), JSON.stringify(meta, null, 2), 'utf8')
}

/** 更新指定会话的任务名称（回写 meta.json 的 taskName 字段） */
export async function updateSessionTaskName(dir: string, taskName: string): Promise<void> {
  const value = taskName.trim()
  if (!value) throw new Error('任务名称不能为空')
  const { meta } = await loadSession(dir)
  meta.taskName = value
  await writeMeta(dir, meta)
}

export async function appendSample(dir: string, sample: ProcessMemorySample): Promise<void> {
  await fs.appendFile(join(dir, 'samples.jsonl'), JSON.stringify(sample) + '\n', 'utf8')
}

/** 原始输出文件名：<yyyyMMdd>-<HHmmss>.<SSS>-<bundleName>.txt（毫秒保证同秒唯一，时间戳在前便于排序） */
function rawFileName(bundleName: string, timestamp: number): string {
  const d = new Date(timestamp)
  const pad = (n: number, w = 2): string => String(n).padStart(w, '0')
  const date = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`
  const time = `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  return `${date}-${time}.${pad(d.getMilliseconds(), 3)}-${bundleName}.txt`
}

/** 保存某采样点的 hidumper 原始输出：raw/<bundleName>-<时间戳>.txt */
export async function writeRawSample(
  dir: string,
  bundleName: string,
  timestamp: number,
  raw: string
): Promise<void> {
  const rawDir = join(dir, 'raw')
  await ensureDir(rawDir)
  await fs.writeFile(join(rawDir, rawFileName(bundleName, timestamp)), raw, 'utf8')
}

/** 写入内存快照（snapshot.json） */
export async function writeSnapshot(dir: string, snapshot: MemorySnapshot): Promise<void> {
  await ensureDir(dir)
  await fs.writeFile(join(dir, 'snapshot.json'), JSON.stringify(snapshot, null, 2), 'utf8')
}

/** 写入快照的 smaps 逐 VMA 明细原文：<同名>.smaps.txt */
export async function writeSnapshotSmaps(
  dir: string,
  bundleName: string,
  capturedAt: number,
  raw: string
): Promise<void> {
  await ensureDir(dir)
  await fs.writeFile(
    join(dir, rawFileName(bundleName, capturedAt).replace(/\.txt$/, '.smaps.txt')),
    raw,
    'utf8'
  )
}

/** 写入快照的 hidumper 原始输出：<bundleName>-<时间戳>.txt */
export async function writeSnapshotRaw(
  dir: string,
  bundleName: string,
  capturedAt: number,
  raw: string
): Promise<void> {
  await ensureDir(dir)
  await fs.writeFile(join(dir, rawFileName(bundleName, capturedAt)), raw, 'utf8')
}

/** 读取内存快照；文件缺失或损坏时返回 null */
export async function loadSnapshot(dir: string): Promise<MemorySnapshot | null> {
  try {
    const raw = await fs.readFile(join(dir, 'snapshot.json'), 'utf8')
    return JSON.parse(raw) as MemorySnapshot
  } catch {
    return null
  }
}

export interface LoadedSession {
  meta: SamplingSessionMeta
  samples: ProcessMemorySample[]
}

export async function loadSession(dir: string): Promise<LoadedSession> {
  // 友好报错：目录不存在 / 不是报告目录时给出可操作提示，而不是抛 ENOENT 原文
  try {
    await fs.access(dir)
  } catch {
    throw new Error('所选目录不存在或不可访问')
  }
  const metaPath = join(dir, 'meta.json')
  try {
    await fs.access(metaPath)
  } catch {
    throw new Error('所选目录不是有效的报告目录（缺少 meta.json），请选择单个报告目录，而不是输出根目录')
  }
  const metaRaw = await fs.readFile(metaPath, 'utf8')
  let meta: SamplingSessionMeta
  try {
    meta = JSON.parse(metaRaw) as SamplingSessionMeta
  } catch {
    throw new Error('报告的 meta.json 已损坏（不是合法 JSON）')
  }
  let samples: ProcessMemorySample[] = []
  try {
    const raw = await fs.readFile(join(dir, 'samples.jsonl'), 'utf8')
    samples = raw
      .split(/\r?\n/)
      .filter((l) => l.trim())
      .map((l) => JSON.parse(l) as ProcessMemorySample)
  } catch {
    samples = []
  }
  // sessionDir 以实际读取路径为准：历史 meta 里记录的可能是迁移前的旧绝对路径（如默认输出目录变更后）
  meta.sessionDir = dir
  return { meta, samples }
}

/** 扫描采样根目录，列出全部历史记录（按开始时间倒序）；跳过损坏目录 */
export async function listSessions(root: string): Promise<SamplingSessionMeta[]> {
  let entries: import('fs').Dirent[]
  try {
    entries = await fs.readdir(root, { withFileTypes: true })
  } catch {
    return []
  }
  const metas: SamplingSessionMeta[] = []
  for (const entry of entries) {
    if (!entry.isDirectory()) continue
    const dir = join(root, entry.name)
    try {
      const raw = await fs.readFile(join(dir, 'meta.json'), 'utf8')
      const meta = JSON.parse(raw) as SamplingSessionMeta
      meta.sessionDir = dir
      metas.push(meta)
    } catch {
      // 无 meta.json 或解析失败的目录直接跳过
    }
  }
  metas.sort((a, b) => b.startedAt - a.startedAt)
  return metas
}

/** 删除指定采样记录目录（含全部采样文件） */
export async function deleteSession(dir: string): Promise<void> {
  await fs.rm(dir, { recursive: true, force: true })
}
