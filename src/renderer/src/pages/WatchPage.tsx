import { Alert, Button, Card, InputNumber, Typography } from 'antd'
import { RadarChartOutlined } from '@ant-design/icons'
import { useState } from 'react'
import type { ProcessMemorySample } from '@shared/types'
import type { PageProps } from './types'
import { DEFAULT_CONFIG } from '../constants'
import TargetPicker, { type ToolTargetState } from '../components/TargetPicker'
import FormLabel from '../components/FormLabel'
import LivePage from './LivePage'

interface Props extends PageProps {
  /** 当前进行中的会话是否为实时查看模式 */
  watching: boolean
  samples: ProcessMemorySample[]
  bundleName: string
  startedAt: number | null
  onStartWatch: (target: ToolTargetState, intervalMs: number) => void
  onStopWatch: () => void
}

/** 实时内存查看：与趋势图相同的实时界面，但数据不落盘（不建目录/不写文件/不生成报告） */
export default function WatchPage(props: Props): JSX.Element {
  const [target, setTarget] = useState<ToolTargetState>({
    deviceId: props.currentTarget,
    app: null
  })
  const [intervalMs, setIntervalMs] = useState(DEFAULT_CONFIG.intervalMs)

  // 查看进行中：复用实时页（watch 变体）
  if (props.watching) {
    return (
      <LivePage
        {...props}
        samples={props.samples}
        bundleName={props.bundleName}
        startedAt={props.startedAt}
        sessionDir=""
        watch
        onStop={props.onStopWatch}
      />
    )
  }

  return (
    <div>
      <a onClick={() => props.go('tools')} style={{ fontSize: 12.5 }}>
        ‹ 返回工具集
      </a>
      {/* 居中定宽容器，与峰值采样/快照配置页一致 */}
      <div style={{ display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: '100%', maxWidth: 720 }}>
          <Card style={{ marginTop: 14 }} title="📡 实时内存">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                仅用于查看实时内存：数据不落盘、不写入本地文件、不产生测试报告
              </Typography.Text>
              <TargetPicker
                value={target}
                onChange={setTarget}
                devices={props.devices}
                currentTarget={props.currentTarget}
                deviceInfo={props.deviceInfo}
                deviceLoading={props.deviceLoading}
                onRefreshDevices={props.onRefreshDevices}
                onSelectDevice={props.onSelectDevice}
                notRunningHint="应用未运行，您可以开始查看后，再手动运行该应用。"
                disabled={props.sampling}
              />
              {/* 采样间隔 */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <FormLabel text="采样间隔" />
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                  <InputNumber
                    style={{ width: 150 }}
                    min={200}
                    step={100}
                    addonAfter="毫秒"
                    value={intervalMs}
                    onChange={(v) => setIntervalMs(Number(v) || DEFAULT_CONFIG.intervalMs)}
                    disabled={props.sampling}
                  />
                  {/* 典型间隔快捷选择 */}
                  {[200, 500, 1000, 2000].map((ms) => (
                    <Button
                      key={ms}
                      size="small"
                      type={intervalMs === ms ? 'primary' : 'default'}
                      disabled={props.sampling}
                      onClick={() => setIntervalMs(ms)}
                    >
                      {ms}ms
                    </Button>
                  ))}
                </div>
              </div>
              {props.sampling && (
                <Alert
                  type="warning"
                  showIcon
                  message="已有采样任务进行中，请先在对应页面结束当前任务"
                />
              )}
              <Button
                type="primary"
                size="large"
                icon={<RadarChartOutlined />}
                disabled={props.sampling || !target.app}
                onClick={() => target.app && props.onStartWatch(target, intervalMs)}
                style={{ background: '#52c41a', borderColor: '#52c41a' }}
                block
              >
                开始查看
              </Button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
