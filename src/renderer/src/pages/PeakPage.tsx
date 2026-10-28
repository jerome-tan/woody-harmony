import { useState } from 'react'
import { Alert, Button, Card, Checkbox, Input, InputNumber, Select, Steps, Typography } from 'antd'
import { PlayCircleOutlined } from '@ant-design/icons'
import type { SamplerConfig } from '@shared/types'
import type { PageProps } from './types'
import { DEFAULT_CONFIG } from '../constants'
import TargetPicker, { type ToolTargetState } from '../components/TargetPicker'
import FormLabel from '../components/FormLabel'

/** 默认任务名：Task-yyyyMMdd-HHmmss */
function defaultTaskName(): string {
  const d = new Date()
  const p = (n: number): string => String(n).padStart(2, '0')
  return `Task-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}

const ADVANCED_OPTIONS: Array<{ key: keyof SamplerConfig; label: string }> = [
  { key: 'showAshmem', label: 'ashmem 明细' },
  { key: 'showDmabuf', label: 'dmabuf 明细' },
  { key: 'showGpumem', label: 'gpumem 明细' }
]

const rowStyle: React.CSSProperties = { display: 'flex', alignItems: 'flex-start', gap: 12 }

/** 峰值内存采样 · 配置页：横向标签 + 控件，单列居中表单 */
export default function PeakPage(props: PageProps): JSX.Element {
  const [taskName, setTaskName] = useState(defaultTaskName)
  const [target, setTarget] = useState<ToolTargetState>({
    deviceId: props.currentTarget,
    app: null
  })
  const [config, setConfig] = useState<SamplerConfig>({ ...DEFAULT_CONFIG })

  const intervalInvalid = config.intervalMs < 200
  const canStart = !props.sampling && !!target.app && !!taskName.trim() && !intervalInvalid

  return (
    <div>
      <a onClick={() => props.go('tools')} style={{ fontSize: 12.5 }}>
        ‹ 返回工具集
      </a>
      {/* 居中定宽容器：页面自适应但不把表单拉得过宽 */}
      <div style={{ display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: '100%', maxWidth: 720 }}>
          <Steps
            size="small"
            current={0}
            items={[{ title: '配置参数' }, { title: '实时采样' }, { title: '采样报告' }]}
            style={{ margin: '14px 0 18px' }}
          />
          <Card title="📈 持续内存采样">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              {/* 任务名称 */}
              <div style={rowStyle}>
                <FormLabel text="任务名称" required />
                <Input
                  style={{ flex: 1 }}
                  value={taskName}
                  onChange={(e) => setTaskName(e.target.value)}
                  placeholder="Task-YYYYMMDD-HHmmss"
                  maxLength={80}
                  status={!taskName.trim() ? 'error' : ''}
                  disabled={props.sampling}
                />
              </div>
              {/* 目标设备 / 目标应用（TargetPicker 内部已是横向行，标签宽度一致） */}
              <TargetPicker
                value={target}
                onChange={setTarget}
                devices={props.devices}
                currentTarget={props.currentTarget}
                deviceInfo={props.deviceInfo}
                deviceLoading={props.deviceLoading}
                onRefreshDevices={props.onRefreshDevices}
                onSelectDevice={props.onSelectDevice}
                notRunningHint="应用未运行，您可以开始采样后，再手动运行该应用。"
                disabled={props.sampling}
              />
              {/* 采样间隔 */}
              <div style={rowStyle}>
                <FormLabel text="采样间隔" required />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <InputNumber
                      style={{ width: 150 }}
                      min={200}
                      step={100}
                      addonAfter="毫秒"
                      value={config.intervalMs}
                      onChange={(v) => setConfig({ ...config, intervalMs: Number(v) || 0 })}
                      status={intervalInvalid ? 'error' : ''}
                      disabled={props.sampling}
                    />
                    {/* 典型间隔快捷选择 */}
                    {[200, 500, 1000, 2000].map((ms) => (
                      <Button
                        key={ms}
                        size="small"
                        type={config.intervalMs === ms ? 'primary' : 'default'}
                        disabled={props.sampling}
                        onClick={() => setConfig({ ...config, intervalMs: ms })}
                      >
                        {ms}ms
                      </Button>
                    ))}
                  </div>
                  {intervalInvalid && (
                    <Typography.Text type="danger" style={{ fontSize: 11.5, display: 'block', marginTop: 4 }}>
                      采样间隔不能低于 200ms（hidumper 单次执行约 100ms，过小会导致采样堆积）
                    </Typography.Text>
                  )}
                </div>
              </div>
              {/* 采样时长：到期自动结束，避免忘记停止导致记录文件膨胀 */}
              <div style={rowStyle}>
                <FormLabel text="采样时长" required />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Select
                    style={{ width: 260 }}
                    value={config.maxDurationMs ?? 0}
                    onChange={(v) => setConfig({ ...config, maxDurationMs: v })}
                    disabled={props.sampling}
                    options={[
                      { value: 5 * 60 * 1000, label: '5 分钟' },
                      { value: 10 * 60 * 1000, label: '10 分钟（默认）' },
                      { value: 30 * 60 * 1000, label: '30 分钟' },
                      { value: 60 * 60 * 1000, label: '1 小时' },
                      { value: 2 * 60 * 60 * 1000, label: '2 小时' },
                      { value: 0, label: '不限（不推荐，文件会持续增大）' }
                    ]}
                  />
                </div>
              </div>
              {/* 高级选项：双列网格，勾选框左对齐 */}
              <div style={rowStyle}>
                <FormLabel text="高级选项" />
                <div
                  style={{
                    flex: 1,
                    minWidth: 0,
                    display: 'grid',
                    gridTemplateColumns: '1fr 1fr',
                    gap: '6px 16px',
                    paddingTop: 4
                  }}
                >
                  {ADVANCED_OPTIONS.map((opt) => (
                    <Checkbox
                      key={opt.key}
                      checked={Boolean(config[opt.key])}
                      onChange={(e) => setConfig({ ...config, [opt.key]: e.target.checked })}
                      disabled={props.sampling}
                    >
                      {opt.label}
                    </Checkbox>
                  ))}
                </div>
              </div>
              {props.sampling && (
                <Alert type="warning" showIcon message="已有采样任务进行中，请先在实时页结束当前采样" />
              )}
              <Button
                type="primary"
                size="large"
                icon={<PlayCircleOutlined />}
                disabled={!canStart}
                onClick={() =>
                  target.app && props.onStartPeak(target, config, taskName.trim())
                }
                block
              >
                开始采样
              </Button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
