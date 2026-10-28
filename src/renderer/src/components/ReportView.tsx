import { useState } from 'react'
import { Button, Descriptions, Modal, Tag, Typography } from 'antd'
import { FolderOpenOutlined, InfoCircleOutlined } from '@ant-design/icons'
import type { MemorySnapshot, ProcessMemorySample, SamplingSessionMeta } from '@shared/types'
import { formatBytes, formatDuration } from '../utils'
import SnapshotBody from './SnapshotBody'
import TrendBody from './TrendBody'

/** 一份完整报告的数据包（meta + 趋势样本或快照数据） */
export interface ReportData {
  meta: SamplingSessionMeta
  samples?: ProcessMemorySample[]
  snapshot?: MemorySnapshot
}

interface Props {
  report: ReportData
  /** 编辑任务名称（回写 meta.json） */
  onSaveTaskName: (dir: string, taskName: string) => Promise<void>
}

function fmtTime(ts: number): string {
  const d = new Date(ts)
  const p = (n: number): string => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

/** 报告详情页：头部（包名/类型/操作）+ 环境信息网格 + 趋势或快照内容 */
export default function ReportView({ report, onSaveTaskName }: Props): JSX.Element {
  const { meta } = report
  const isSnap = meta.type === 'snapshot'
  const dir = meta.sessionDir ?? ''
  const [envOpen, setEnvOpen] = useState(false)

  const end = meta.endedAt ?? meta.startedAt
  const pid =
    isSnap
      ? (report.snapshot?.pid ?? '-')
      : ([...(report.samples ?? [])].reverse().find((s) => s.pid != null)?.pid ?? '-')

  // 设备三项拆开显示，避免一长串换行错乱
  const sysVer = meta.device.softwareVersion
    ? meta.device.apiVersion
      ? `${meta.device.softwareVersion}（API ${meta.device.apiVersion}）`
      : meta.device.softwareVersion
    : meta.device.apiVersion
      ? `API ${meta.device.apiVersion}`
      : '-'
  const deviceName = meta.device.marketName || meta.device.model || '-'
  const sn = meta.device.serialNumber || meta.device.targetId || '-'
  // 完整采集命令（与主进程 sampler 一致）：趋势含可选维度参数，勾选 smaps 时另有 mem-smaps 命令
  const collectCmd = isSnap
    ? `hidumper --mem ${pid}`
    : [
        `hidumper --mem ${pid}`,
        meta.config.showAshmem && '--show-ashmem',
        meta.config.showDmabuf && '--show-dmabuf',
        meta.config.showGpumem && '--show-gpumem'
      ]
        .filter(Boolean)
        .join(' ')

  // [标签, 值, 跨列数]
  const envItems: Array<[string, string, number?]> = isSnap
    ? [
        ['任务名称', meta.taskName || '-'],
        ['快照时间', fmtTime(report.snapshot?.capturedAt ?? meta.startedAt)],
        ['采集命令', collectCmd],
        ['PID', String(pid)],
        ['设备', deviceName],
        ['系统版本', sysVer],
        ['序列号', sn],
        ['运行内存', meta.device.ramTotalKb ? formatBytes(meta.device.ramTotalKb) : '-'],
        ['屏幕分辨率', meta.device.screenResolution || '-']
      ]
    : [
        ['任务名称', meta.taskName || '-'],
        ['起始时间', fmtTime(meta.startedAt)],
        ['采集命令', collectCmd],
        ['时长', formatDuration(end - meta.startedAt)],
        ['采样点数', `${meta.sampleCount} 点`],
        ['采样间隔', meta.config.intervalMs ? `${meta.config.intervalMs / 1000} 秒` : '-'],
        ['PID', String(pid)],
        ['设备', deviceName],
        ['系统版本', sysVer],
        ['序列号', sn],
        ['运行内存', meta.device.ramTotalKb ? formatBytes(meta.device.ramTotalKb) : '-'],
        ['屏幕分辨率', meta.device.screenResolution || '-']
      ]

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, flex: 1, minHeight: 0 }}>
      {/* 头部 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <span
          style={{
            width: 36,
            height: 36,
            borderRadius: 10,
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 17,
            flex: '0 0 auto',
            background: isSnap ? '#fffbe6' : '#e6f4ff'
          }}
        >
          {isSnap ? '📷' : '📈'}
        </span>
        <div style={{ minWidth: 0 }}>
          <Typography.Title
            level={4}
            style={{ margin: 0, wordBreak: 'break-all' }}
            editable={{ tooltip: '编辑任务名称', onChange: (v) => void onSaveTaskName(dir, v) }}
          >
            {meta.taskName || meta.bundleName}
          </Typography.Title>
          {meta.taskName && (
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              {meta.bundleName}
            </Typography.Text>
          )}
        </div>
        <Tag color={isSnap ? 'gold' : 'blue'}>{isSnap ? '内存快照' : '持续采样'}</Tag>
        <span style={{ flex: 1 }} />
        <Button
          size="small"
          icon={<InfoCircleOutlined />}
          onClick={() => setEnvOpen(true)}
        >
          环境信息
        </Button>
        <Button
          size="small"
          icon={<FolderOpenOutlined />}
          disabled={!dir}
          onClick={() => void window.api.revealPath(dir)}
        >
          打开目录
        </Button>
      </div>

      {/* 环境信息（弹窗，不再常驻页面） */}
      <Modal
        title="环境信息"
        open={envOpen}
        footer={null}
        onCancel={() => setEnvOpen(false)}
        width={620}
      >
        <Descriptions
          size="small"
          column={1}
          colon={false}
          styles={{ label: { width: 92, color: '#8c8c8c' }, content: { color: 'rgba(0,0,0,0.88)' } }}
          items={envItems.map(([k, v, span]) => ({
            key: k,
            label: k,
            children: v,
            span: span ?? 1
          }))}
        />
      </Modal>

      {/* 内容 */}
      {isSnap
        ? report.snapshot && <SnapshotBody snapshot={report.snapshot} />
        : <TrendBody samples={report.samples ?? []} />}
    </div>
  )
}
