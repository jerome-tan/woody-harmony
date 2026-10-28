import type { SamplerConfig } from '@shared/types'

export const DEFAULT_CONFIG: SamplerConfig = {
  intervalMs: 1000,
  showAshmem: false,
  showDmabuf: false,
  showGpumem: false,
  // 默认 30 分钟自动结束，避免忘记停止导致记录文件持续膨胀；可改为 0 表示不限
  maxDurationMs: 10 * 60 * 1000
}

// 固定颜色映射，保证不同分类颜色稳定且相互之间对比度高
export const CATEGORY_COLORS: Record<string, string> = {
  Total: '#e6194b', // 红
  GL: '#911eb4', // 紫
  Graph: '#4363d8', // 蓝
  'ark ts heap': '#f58231', // 橙
  'native heap': '#3cb44b', // 绿
  stack: '#46f0f0', // 青
  '.so': '#ffe119', // 黄
  '.hap': '#9a6324', // 棕
  'AnonPage other': '#f032e6', // 品红
  'FilePage other': '#808080', // 灰
  dev: '#000000', // 黑
  '.db': '#008080', // 蓝绿
  '.ttf': '#bcf60c', // 黄绿
  guard: '#000075' // 藏青
}

const FALLBACK_COLORS = [
  '#e6194b',
  '#3cb44b',
  '#ffe119',
  '#4363d8',
  '#f58231',
  '#911eb4',
  '#46f0f0',
  '#f032e6',
  '#bcf60c',
  '#9a6324',
  '#008080',
  '#808080',
  '#000075',
  '#000000'
]

export function colorOf(category: string, index: number): string {
  return CATEGORY_COLORS[category] || FALLBACK_COLORS[index % FALLBACK_COLORS.length]
}

// 默认展示的分类顺序（Total 放最前，线最粗最醒目）
export const DEFAULT_CATEGORIES = [
  'Total',
  'GL',
  'Graph',
  'ark ts heap',
  'native heap',
  'stack',
  '.so',
  '.hap',
  'AnonPage other',
  'FilePage other',
  'dev',
  '.db',
  '.ttf',
  'guard'
]