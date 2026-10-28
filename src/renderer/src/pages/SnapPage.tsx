import { useState } from 'react'
import { Alert, Button, Card, Checkbox, Input, Spin, Steps, Typography } from 'antd'
import { CameraOutlined, LoadingOutlined } from '@ant-design/icons'
import type { SnapshotOptions } from '@shared/types'
import type { PageProps } from './types'
import { defaultTaskName } from '../utils'
import TargetPicker, { type ToolTargetState } from '../components/TargetPicker'
import FormLabel from '../components/FormLabel'

const rowStyle: React.CSSProperties = { display: 'flex', alignItems: 'flex-start', gap: 12 }

/** 快照可选的明细采集项（附加在 hidumper --mem 输出末尾，报告页「内存明细」区展示） */
const DETAIL_OPTIONS: Array<{ key: keyof SnapshotOptions; label: string }> = [
  { key: 'showAshmem', label: 'ashmem 明细' },
  { key: 'showDmabuf', label: 'dmabuf 明细' },
  { key: 'showGpumem', label: 'gpumem 明细' },
  { key: 'includeSmaps', label: '含 smaps 明细（逐 VMA，较慢）' }
]

/** 内存快照抓取 · 配置页；抓取中显示加载页，完成后 App 跳转报告页 */
export default function SnapPage(props: PageProps): JSX.Element {
  const [taskName, setTaskName] = useState(defaultTaskName)
  const [options, setOptions] = useState<SnapshotOptions>({})
  const [target, setTarget] = useState<ToolTargetState>({
    deviceId: props.currentTarget,
    app: null
  })

  // 抓取中页
  if (props.snapshotting) {
    return (
      <div style={{ maxWidth: 620, margin: '80px auto 0' }}>
        <Card>
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 14,
              padding: '40px 0',
              color: 'rgba(0,0,0,.65)'
            }}
          >
            <Spin indicator={<LoadingOutlined style={{ fontSize: 34 }} spin />} />
            <div style={{ fontSize: 15, fontWeight: 600 }}>正在抓取内存快照…</div>
            <Typography.Text type="secondary" style={{ textAlign: 'center', lineHeight: 1.9 }}>
              正在对 <b>{target.app?.bundleName ?? '目标应用'}</b> 执行
              <br />
              <code style={{ background: '#f5f5f5', padding: '2px 6px', borderRadius: 4 }}>
                hidumper --mem {target.app?.pid ?? '<pid>'}
              </code>
              （单次采集，约 1~3 秒）
            </Typography.Text>
          </div>
        </Card>
      </div>
    )
  }

  const canGrab = !!target.app && target.app.pid != null && !!taskName.trim()

  return (
    <div>
      <a onClick={() => props.go('tools')} style={{ fontSize: 12.5 }}>
        ‹ 返回工具集
      </a>
      <div style={{ display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: '100%', maxWidth: 720 }}>
          <Steps
            size="small"
            current={0}
            items={[{ title: '配置参数' }, { title: '抓取快照' }, { title: '快照报告' }]}
            style={{ margin: '14px 0 18px' }}
          />
          <Card title="📷 内存快照">
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
                />
              </div>
              <TargetPicker
                value={target}
                onChange={setTarget}
                devices={props.devices}
                currentTarget={props.currentTarget}
                deviceInfo={props.deviceInfo}
                deviceLoading={props.deviceLoading}
                onRefreshDevices={props.onRefreshDevices}
                onSelectDevice={props.onSelectDevice}
              />
              {target.app && target.app.pid == null && (
                <Alert
                  type="warning"
                  showIcon
                  message={`应用 ${target.app.bundleName} 当前未在运行，无法抓取快照`}
                />
              )}
              {/* 高级选项：双列网格 */}
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
                  {DETAIL_OPTIONS.map((opt) => (
                    <Checkbox
                      key={opt.key}
                      checked={Boolean(options[opt.key])}
                      onChange={(e) => setOptions({ ...options, [opt.key]: e.target.checked })}
                    >
                      {opt.label}
                    </Checkbox>
                  ))}
                </div>
              </div>
              <Button
                size="large"
                icon={<CameraOutlined />}
                disabled={!canGrab}
                onClick={() => target.app && props.onStartSnap(target, taskName.trim(), options)}
                style={{ background: '#faad14', borderColor: '#faad14', color: '#fff' }}
                block
              >
                开始抓取
              </Button>
              <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                一次性执行 hidumper --mem，落盘为独立目录：snapshot.json（结构化）+ hidumper 原文 + meta.json
              </Typography.Text>
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
