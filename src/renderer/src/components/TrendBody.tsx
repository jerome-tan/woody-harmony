import { Card, Col, Empty, Row, Statistic } from 'antd'
import { useMemo } from 'react'
import type { ProcessMemorySample } from '@shared/types'
import { DEFAULT_CATEGORIES } from '../constants'
import { formatBytes } from '../utils'
import MemoryChart from './MemoryChart'

interface Props {
  samples: ProcessMemorySample[]
}

/** 趋势报告主体：峰值/均值/结束值/增长幅度概览 + 全程趋势图 */
export default function TrendBody({ samples }: Props): JSX.Element {
  const categories = useMemo(() => {
    const present = new Set<string>()
    for (const s of samples) {
      for (const k of Object.keys(s.categories)) present.add(k)
    }
    const ordered = DEFAULT_CATEGORIES.filter((c) => c === 'Total' || present.has(c))
    const extraKeys = [...present].filter((c) => !DEFAULT_CATEGORIES.includes(c))
    return [...ordered, ...extraKeys]
  }, [samples])

  const stats = useMemo(() => {
    if (samples.length === 0) return null
    const totals = samples.map((s) => s.total.pssTotalKb)
    const peak = Math.max(...totals)
    const first = totals[0]
    const last = totals[totals.length - 1]
    const avg = Math.round(totals.reduce((a, b) => a + b, 0) / totals.length)
    return { peak, first, last, avg, growth: last - first }
  }, [samples])

  if (samples.length === 0) {
    return (
      <Card>
        <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="该报告没有样本数据" />
      </Card>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, flex: 1, minHeight: 0 }}>
      <Row gutter={[12, 12]} style={{ flex: '0 0 auto' }}>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="峰值 Total Pss"
              value={formatBytes(stats!.peak)}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="均值" value={formatBytes(stats!.avg)} />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="结束值" value={formatBytes(stats!.last)} />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="增长幅度（起始 → 结束）"
              value={`${stats!.growth >= 0 ? '+' : ''}${formatBytes(Math.abs(stats!.growth))}`}
              valueStyle={{ color: stats!.growth > 0 ? '#ff4d4f' : '#389e0d' }}
            />
          </Card>
        </Col>
      </Row>
      {/* 图表卡片：撑满剩余高度（随窗口缩放自适应），保留最小高度防止过度压缩 */}
      <Card
        size="small"
        style={{ flex: 1, minHeight: 380 }}
        styles={{ body: { height: '100%', padding: 8 } }}
      >
        <MemoryChart samples={samples} categories={categories} title="内存趋势" />
      </Card>
    </div>
  )
}
