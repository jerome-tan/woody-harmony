import { Button, Card, Input, Space, Typography } from 'antd'
import { useEffect, useState } from 'react'
import type { PageProps } from './types'
import { notify } from '../notify'

interface Props extends PageProps {
  hdcPath: string
  sessionsDir: string
  defaultSessionsDir: string
  onSaveHdcPath: (path: string) => Promise<void>
  onSaveSessionsDir: (dir: string) => Promise<void>
}

/** 设置页（右侧区域内页面）：报告默认路径 + hdc 路径 */
export default function SettingsPage(props: Props): JSX.Element {
  const [path, setPath] = useState(props.hdcPath)
  const [dir, setDir] = useState(props.sessionsDir)

  useEffect(() => setPath(props.hdcPath), [props.hdcPath])
  useEffect(() => setDir(props.sessionsDir), [props.sessionsDir])

  const chooseDir = async (): Promise<void> => {
    try {
      const picked = await window.api.chooseSessionsDir()
      if (picked) setDir(picked)
    } catch {
      // 取消或失败均保持原值
    }
  }

  const save = async (): Promise<void> => {
    try {
      if (path.trim() !== props.hdcPath) await props.onSaveHdcPath(path.trim())
      if (dir.trim() !== props.sessionsDir) await props.onSaveSessionsDir(dir.trim())
      notify.success('设置已保存')
    } catch {
      // 各保存函数内部已提示
    }
  }

  return (
    <div style={{ maxWidth: 640 }}>
      <Typography.Title level={4} style={{ marginTop: 0 }}>
        设置
      </Typography.Title>
      <Card title="存储与工具链">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div>
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              报告默认存储路径
            </Typography.Text>
            <Space.Compact style={{ width: '100%', marginTop: 4 }}>
              <Input value={dir} placeholder={props.defaultSessionsDir} readOnly />
              <Button onClick={() => void chooseDir()}>选择…</Button>
              <Button disabled={!dir} onClick={() => setDir('')}>
                恢复默认
              </Button>
            </Space.Compact>
            <Typography.Text type="secondary" style={{ fontSize: 11.5, display: 'block', marginTop: 4 }}>
              留空则使用默认路径；目录变更后报告列表自动按新路径重新扫描。
            </Typography.Text>
          </div>
          <div>
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              hdc 可执行文件路径
            </Typography.Text>
            <Input
              style={{ marginTop: 4 }}
              value={path}
              placeholder="留空则自动查找（PATH / 常见安装目录）"
              onChange={(e) => setPath(e.target.value)}
            />
            <Typography.Text type="secondary" style={{ fontSize: 11.5, display: 'block', marginTop: 4 }}>
              hdc 来自 HarmonyOS SDK / DevEco Studio，用于与设备通信执行 hidumper。
            </Typography.Text>
          </div>
          <div>
            <Button type="primary" onClick={() => void save()}>
              保存设置
            </Button>
          </div>
        </div>
      </Card>
    </div>
  )
}
