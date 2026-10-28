import type { DeviceInfo } from '@shared/types'

/** 默认任务名：Task-yyyyMMdd-HHmmss（如 Task-20261001-112233） */
export function defaultTaskName(): string {
  const d = new Date()
  const p = (n: number): string => String(n).padStart(2, '0')
  return `Task-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}

export function kbToMb(kb: number): number {
  return Math.round((kb / 1024) * 100) / 100
}

/**
 * 设备统一显示格式（对齐 DevEco Testing / DevEco Studio 设备列表）：
 * 「型号名称[序列号] 软件版本(API版本)」，如 HUAWEI MateBook Fold | ULTIMATE DESIGN[45Nxxx] 7.0.0(26)
 */
export function formatDeviceLabel(
  d?: Partial<DeviceInfo> | null,
  fallbackId = ''
): string {
  const name = d?.marketName || d?.model || ''
  const sn = d?.serialNumber || d?.targetId || fallbackId
  const ver = (d?.softwareVersion || '').replace(/^HarmonyOS\s*/i, '')
  const api = d?.apiVersion || ''
  const head = name ? (sn ? `${name}[${sn}]` : name) : sn
  const tail = ver ? (api ? `${ver}(${api})` : ver) : api
  return [head, tail].filter(Boolean).join(' ') || '未知设备'
}

export function formatBytes(kb: number): string {
  if (kb >= 1024 * 1024) {
    return (kb / 1024 / 1024).toFixed(2) + ' GB'
  }
  if (kb >= 1024) {
    return (kb / 1024).toFixed(1) + ' MB'
  }
  return Math.round(kb) + ' kB'
}

export function formatDuration(ms: number): string {
  const s = Math.round(ms / 1000)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  const rest = s % 60
  return `${m}m${rest}s`
}