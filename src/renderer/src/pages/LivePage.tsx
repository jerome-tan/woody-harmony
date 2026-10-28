import { Button, Card, Col, Row, Statistic, Tag, Typography } from 'antd'
import { FolderOpenOutlined, StopOutlined } from '@ant-design/icons'
import { useMemo } from 'react'
import type { ProcessMemorySample, SamplingStatus } from '@shared/types'
import type { PageProps } from './types'
import { DEFAULT_CATEGORIES } from '../constants'
import { formatBytes, formatDuration } from '../utils'
import MemoryChart from '../components/MemoryChart'

interface Props extends PageProps {
  samples: ProcessMemorySample[]
  bundleName: string
  startedAt: number | null
  sessionDir: string
  /** 采样时长上限（毫秒，0=不限）；>0 时横幅展示预计自动结束时间 */
  maxDurationMs?: number
  /** 实时查看变体：数据不落盘，结束不生成报告 */
  watch?: boolean
  onStop: () => void
}

/** 实时采样页：状态横幅 + 实时统计 + 实时趋势图；watch 变体为不落盘的实时查看 */
export default function LivePage(props: Props): JSX.Element {
  const { samples, status, watch = false } = props

  const categories = useMemo(() => {
    const present = new Set<string>()
    for (const s of samples) {
      for (const k of Object.keys(s.categories)) present.add(k)
    }
    const ordered = DEFAULT_CATEGORIES.filter((c) => c === 'Total' || present.has(c))
    const extraKeys = [...present].filter((c) => !DEFAULT_CATEGORIES.includes(c))
    return [...ordered, ...extraKeys]
  }, [samples])

  const last = samples[samples.length - 1]
  const first = samples[0]
  const currentKb = last?.total.pssTotalKb ?? 0
  const growthKb = last && first ? last.total.pssTotalKb - first.total.pssTotalKb : 0
  const elapsedMs = last && props.startedAt ? last.timestamp - props.startedAt : 0
  const pid = last?.pid ?? null

  const stateColor: Record<SamplingStatus['state'], string> = {
    idle: 'default',
    starting: 'processing',
    sampling: 'success',
    stopping: 'warning',
    error: 'error'
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, flex: 1, minHeight: 0 }}>
      {/* 状态横幅 */}
      <Card
        size="small"
        style={{ background: 'linear-gradient(90deg,#f0f7ff,#fff)', borderColor: '#91caff' }}
        styles={{ body: { display: 'flex', alignItems: 'center', gap: 14 } }}
      >
        <span
          style={{
            width: 38,
            height: 38,
            borderRadius: 10,
            background: watch ? '#52c41a' : '#1677ff',
            color: '#fff',
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 17,
            flex: '0 0 auto'
          }}
        >
          {watch ? '📡' : '📈'}
        </span>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontWeight: 600, fontSize: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
            {props.bundleName}
            <Tag color={watch ? 'processing' : stateColor[status.state]} style={{ marginInlineEnd: 0 }}>
              {watch
                ? '查看中 · 不落盘'
                : status.state === 'sampling'
                  ? '采样中'
                  : status.state === 'starting'
                    ? '启动中'
                    : status.state === 'stopping'
                      ? '停止中'
                      : status.state === 'idle'
                        ? '已结束'
                        : status.state}
            </Tag>
          </div>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            {props.startedAt ? `${new Date(props.startedAt).toLocaleTimeString()} 开始` : ''}
            {status.message ? ` · ${status.message}` : ''}
            {watch
              ? ' · 数据仅保留在内存中，结束后不生成报告'
              : props.maxDurationMs
                ? ` · 预计 ${new Date((props.startedAt ?? Date.now()) + props.maxDurationMs).toLocaleTimeString()} 自动结束`
                : ''}
          </Typography.Text>
        </div>
        {!watch && (
          <Button
            icon={<FolderOpenOutlined />}
            disabled={!props.sessionDir}
            onClick={() => void window.api.revealPath(props.sessionDir)}
          >
            采集目录
          </Button>
        )}
        <Button danger icon={<StopOutlined />} disabled={!props.sampling} onClick={props.onStop}>
          {watch ? '结束查看' : '结束采样'}
        </Button>
      </Card>

      {/* 实时统计 */}
      <Row gutter={[12, 12]}>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="当前 Total Pss"
              value={formatBytes(currentKb)}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="Private Dirty" value={formatBytes(last?.total.privateDirtyKb ?? 0)} />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="采样点数"
              value={samples.length}
              suffix={pid != null ? `· PID ${pid}` : ''}
            />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="已采样时长"
              value={formatDuration(elapsedMs)}
              suffix={
                <span style={{ fontSize: 12, color: growthKb > 0 ? '#ff4d4f' : '#389e0d' }}>
                  {growthKb !== 0 ? `${growthKb > 0 ? '+' : '-'}${formatBytes(Math.abs(growthKb))}` : ''}
                </span>
              }
            />
          </Card>
        </Col>
      </Row>

      {/* 实时趋势图：卡片高度撑满剩余空间 */}
      <Card
        size="small"
        style={{ flex: 1, minHeight: 0 }}
        styles={{ body: { height: '100%', padding: 8 } }}
      >
        <MemoryChart
          samples={samples}
          categories={categories}
          title={watch ? '实时内存' : '实时趋势'}
          live
        />
      </Card>
    </div>
  )
}
