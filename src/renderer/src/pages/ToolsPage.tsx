import { Card, Tag, Typography } from 'antd'
import { RightOutlined } from '@ant-design/icons'
import type { PageProps } from './types'
import { TOOLS } from '../tools'

/** 工具集：全部工具卡片（新增工具只需在 tools.ts 注册） */
export default function ToolsPage({ go }: PageProps): JSX.Element {
  return (
    <div style={{ maxWidth: 1080 }}>
      <div style={{ marginBottom: 16 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          工具集
        </Typography.Title>
        <Typography.Text type="secondary" style={{ fontSize: 12.5 }}>
          全部内存分析工具（后续将持续扩充）
        </Typography.Text>
      </div>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill,minmax(310px,1fr))',
          gap: 16
        }}
      >
        {TOOLS.map((t) => (
          <Card
            key={t.route}
            hoverable
            onClick={() => go(t.route)}
            styles={{ body: { display: 'flex', flexDirection: 'column', gap: 10, minHeight: 158 } }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
              <span
                style={{
                  width: 42,
                  height: 42,
                  borderRadius: 10,
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 20,
                  color: '#fff',
                  background: t.color,
                  flex: '0 0 auto'
                }}
              >
                {t.icon}
              </span>
              <div>
                <div style={{ fontSize: 15.5, fontWeight: 600 }}>{t.name}</div>
                <Tag style={{ marginTop: 3 }} color={t.route === 'peak' ? 'blue' : 'gold'}>
                  {t.tag}
                </Tag>
              </div>
            </div>
            <Typography.Text type="secondary" style={{ fontSize: 12.5, lineHeight: 1.8, flex: 1 }}>
              {t.desc}
            </Typography.Text>
            <div style={{ color: '#1677ff', fontSize: 12.5, textAlign: 'right' }}>
              进入使用 <RightOutlined style={{ fontSize: 11 }} />
            </div>
          </Card>
        ))}
      </div>
    </div>
  )
}
