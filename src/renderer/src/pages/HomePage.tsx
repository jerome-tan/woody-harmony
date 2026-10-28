import { Card, Tag, Typography } from 'antd'
import { RightOutlined } from '@ant-design/icons'
import type { PageProps } from './types'
import { TOOLS } from '../tools'

/** 首页：工具简介 + 常用工具卡片 */
export default function HomePage({ go }: PageProps): JSX.Element {
  return (
    <div style={{ maxWidth: 1080 }}>
      {/* 简介 Hero */}
      <div
        style={{
          borderRadius: 14,
          padding: '30px 34px',
          color: '#fff',
          background: 'linear-gradient(115deg,#0b3d91 0%,#1677ff 55%,#4da3ff 100%)',
          marginBottom: 20,
          position: 'relative',
          overflow: 'hidden'
        }}
      >
        <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: 0.3 }}>Woody</div>
        <div style={{ fontSize: 13, opacity: 0.92, lineHeight: 1.9, maxWidth: 620, marginTop: 10 }}>
          面向 HarmonyOS 设备的开发调试工具箱：通过 hdc 执行 hidumper
          持续采集进程内存、一键抓取瞬时内存快照，生成可视化报告并支持同类型报告横向对比；
          日志、Trace 等更多调试能力持续扩展中。
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
          {['📡 实时内存', '📷 内存快照', '📈 持续内存采样', '⇄ 报告对比'].map((t) => (
            <span
              key={t}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                height: 24,
                padding: '0 11px',
                borderRadius: 12,
                background: 'rgba(255,255,255,.16)',
                border: '1px solid rgba(255,255,255,.28)',
                fontSize: 11.5
              }}
            >
              {t}
            </span>
          ))}
        </div>
      </div>

      <Typography.Title level={5} style={{ marginTop: 0 }}>
        常用工具
      </Typography.Title>
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
