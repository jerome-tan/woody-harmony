import type { AshmemEntry, DmabufEntry, GpuChannel, GpuDetail, MemoryCategoryValues } from '@shared/types'

export interface ParsedProcessMemory {
  total: MemoryCategoryValues
  categories: Record<string, MemoryCategoryValues>
  nativeHeapDetail: Record<string, MemoryCategoryValues>
  purgSumKb: number
  purgPinKb: number
  dmaKb: number
  ashmemTotalKb: number
}

export interface SystemMemoryInfo {
  ramTotalKb: number
  ramFreeKb: number
  ramUsedKb: number
}

function zeroValues(): MemoryCategoryValues {
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

function parseValues(numeric: string[]): MemoryCategoryValues {
  return {
    pssTotalKb: Number(numeric[0]),
    sharedCleanKb: Number(numeric[1]),
    sharedDirtyKb: Number(numeric[2]),
    privateCleanKb: Number(numeric[3]),
    privateDirtyKb: Number(numeric[4]),
    swapTotalKb: Number(numeric[5]),
    swapPssTotalKb: Number(numeric[6]),
    heapSizeKb: Number(numeric[7]),
    heapAllocKb: Number(numeric[8]),
    heapFreeKb: Number(numeric[9])
  }
}

const NATIVE_HEAP_DETAIL_KEYS = new Set(['jemalloc meta', 'jemalloc heap', 'brk heap', 'musl heap'])

function isNativeHeapDetail(name: string): boolean {
  return (
    NATIVE_HEAP_DETAIL_KEYS.has(name) ||
    name.startsWith('jemalloc') ||
    name.includes('brk heap') ||
    name.includes('musl heap')
  )
}

export function parseProcessMemory(raw: string): ParsedProcessMemory {
  const result: ParsedProcessMemory = {
    total: zeroValues(),
    categories: {},
    nativeHeapDetail: {},
    purgSumKb: 0,
    purgPinKb: 0,
    dmaKb: 0,
    ashmemTotalKb: 0
  }

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed) continue

    // 分类行：以 10 个数字列结尾
    const tokens = trimmed.split(/\s+/)
    if (tokens.length >= 10) {
      const numeric = tokens.slice(-10)
      if (numeric.every((t) => /^\d+$/.test(t))) {
        const name = tokens.slice(0, -10).join(' ')
        const values = parseValues(numeric)
        if (name === 'Total') {
          result.total = values
        } else if (isNativeHeapDetail(name)) {
          result.nativeHeapDetail[name] = values
        } else {
          result.categories[name] = values
        }
      }
    }

    // key: value kB 形式的附加段
    const kv = trimmed.match(/^(PurgSum|PurgPin|Dma|Total Ashmem)\s*:\s*(\d+)\s*kB/i)
    if (kv) {
      const key = kv[1].toLowerCase()
      const value = Number(kv[2])
      if (key === 'purgsum') result.purgSumKb = value
      else if (key === 'purgpin') result.purgPinKb = value
      else if (key === 'dma') result.dmaKb = value
      else if (key === 'total ashmem') result.ashmemTotalKb = value
    }
  }

  return result
}

export function parseSystemMemory(raw: string): SystemMemoryInfo {
  const total = raw.match(/Total RAM\s*:\s*(\d+)\s*kB/)
  const free = raw.match(/Free RAM\s*:\s*(\d+)\s*kB/)
  const used = raw.match(/Used RAM\s*:\s*(\d+)\s*kB/)
  return {
    ramTotalKb: total ? Number(total[1]) : 0,
    ramFreeKb: free ? Number(free[1]) : 0,
    ramUsedKb: used ? Number(used[1]) : 0
  }
}

/**
 * 解析 /proc/meminfo。空闲口径与 hidumper 的 Free RAM（cached + free）保持一致。
 * 全量 hidumper --mem 需遍历系统所有进程（实测 26s+），meminfo 可瞬时返回。
 */
export function parseProcMeminfo(raw: string): SystemMemoryInfo {
  const get = (key: string): number => {
    const m = raw.match(new RegExp(`^${key}:\\s*(\\d+)\\s*kB`, 'm'))
    return m ? Number(m[1]) : 0
  }
  const total = get('MemTotal')
  const free = get('MemFree') + get('Cached')
  return {
    ramTotalKb: total,
    ramFreeKb: free,
    ramUsedKb: Math.max(total - free, 0)
  }
}

/* ─── 明细段解析（--show-ashmem / --show-dmabuf / --show-gpumem 追加输出） ─── */

export interface ParsedMemoryDetails {
  ashmem: AshmemEntry[]
  dmabuf: DmabufEntry[]
  gpu: GpuDetail | null
}

/** 段头位置（Purgeable:/DMA:/Ashmem:/GPU: 均为行首单独一行） */
function sectionIndex(lines: string[], name: string): number {
  return lines.findIndex((l) => l.trim() === `${name}:`)
}

/**
 * 解析 --show-* 明细段。未带参数时对应段只有汇总行（如 `Total Ashmem:0 kB`），明细数组为空。
 * 段顺序固定为 DMA → Ashmem → GPU（hidumper 输出约定）。
 */
export function parseMemoryDetails(raw: string): ParsedMemoryDetails {
  const lines = raw.split('\n')
  const idxDma = sectionIndex(lines, 'DMA')
  const idxAsh = sectionIndex(lines, 'Ashmem')
  const idxGpu = sectionIndex(lines, 'GPU')
  const end = (i: number): number[] => {
    const stops = [idxDma, idxAsh, idxGpu, lines.length].filter((x) => x > i)
    return stops
  }

  // DMA 段：表头行（含 Process 与 size_bytes）之后为数据行，定宽多空格分隔
  const dmabuf: DmabufEntry[] = []
  if (idxDma >= 0) {
    const stop = Math.min(...end(idxDma))
    for (let i = idxDma + 1; i < stop; i++) {
      const parts = lines[i].trim().split(/\s{2,}/)
      // 数据行：≥5 列且 pid/fd 列为纯数字（排除 `Dma:xxx kB` 汇总行与表头行）
      if (parts.length >= 5 && /^\d+$/.test(parts[1] ?? '') && /^\d+$/.test(parts[2] ?? '')) {
        const sizeBytes = Number(parts[3])
        if (!Number.isFinite(sizeBytes)) continue
        dmabuf.push({
          // 最后一列 leak_type 是对象类型名，最有辨识度（如 xcomponent-s-RenderXComponent_*）
          name: parts[parts.length - 1] ?? '',
          fd: Number(parts[2]),
          ino: Number(parts[4]) || 0,
          sizeBytes
        })
      }
    }
    dmabuf.sort((a, b) => b.sizeBytes - a.sizeBytes)
  }

  // Ashmem 段：`Total Ashmem:` 汇总行 → 表头行（tab 分隔）→ 数据行（tab 分隔）
  const ashmem: AshmemEntry[] = []
  if (idxAsh >= 0) {
    const stop = Math.min(...end(idxAsh))
    for (let i = idxAsh + 1; i < stop; i++) {
      const line = lines[i]
      if (!line.includes('\t')) continue
      const parts = line.split('\t')
      // 数据行 9 列：Process_name/Process_ID/Fd/Cnode_idx/Applicant_Pid/Ashmem_name/Virtual_size/Physical_size/magic
      if (parts.length >= 9 && /^\d+$/.test(parts[1]) && /^\d+$/.test(parts[2])) {
        ashmem.push({
          name: (parts[5] ?? '').replace(/^dev\/ashmem\//, ''),
          fd: Number(parts[2]),
          virtualBytes: Number(parts[6]) || 0,
          physicalBytes: Number(parts[7]) || 0
        })
      }
    }
    ashmem.sort((a, b) => b.physicalBytes - a.physicalBytes)
  }

  // GPU 段：Channel 分桶（仅取各 Channel 合计；桶内明细留 raw 原文）
  let gpu: GpuDetail | null = null
  if (idxGpu >= 0) {
    const stop = Math.min(...end(idxGpu))
    const channels: GpuChannel[] = []
    let totalUsedBytes = 0
    let totalAllocatedBytes = 0
    for (let i = idxGpu + 1; i < stop; i++) {
      const line = lines[i]
      const ch = line.match(/^Channel:\s*(.+?)\s*\(Total memory:\s*(\d+)\)\s*$/)
      if (ch) {
        channels.push({ name: ch[1], totalBytes: Number(ch[2]) })
        continue
      }
      const used = line.match(/^Total used memory:\s*(\d+)/)
      if (used) totalUsedBytes = Number(used[1])
      const alloc = line.match(/^Total allocated memory:\s*(\d+)/)
      if (alloc) totalAllocatedBytes = Number(alloc[1])
    }
    channels.sort((a, b) => b.totalBytes - a.totalBytes)
    if (channels.length > 0 || totalUsedBytes > 0) {
      gpu = { channels, totalUsedBytes, totalAllocatedBytes }
    }
  }

  return { ashmem, dmabuf, gpu }
}
