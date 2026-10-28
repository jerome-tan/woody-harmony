import { useEffect, useRef, useState } from 'react'
import { Button, Empty, Input, List, Popover, Tag } from 'antd'
import { DownOutlined, ReloadOutlined } from '@ant-design/icons'
import type { AppInfo } from '@shared/types'

interface Props {
  apps: AppInfo[]
  selectedBundle: string | null
  loading: boolean
  disabled?: boolean
  onRefresh: () => void
  onSelect: (app: AppInfo) => void
}

/** 目标应用选择器：点击弹出搜索框 + 限高应用列表（默认选中当前活跃进程由父级决定） */
export default function AppSelector({
  apps,
  selectedBundle,
  loading,
  disabled,
  onRefresh,
  onSelect
}: Props): JSX.Element {
  const [open, setOpen] = useState(false)
  const [keyword, setKeyword] = useState('')

  // 选中项 DOM 引用：展开列表后滚动到可视区域
  const selectedItemRef = useRef<HTMLDivElement>(null)

  // 每次展开列表时自动刷新一次应用状态
  const handleOpenChange = (next: boolean): void => {
    setOpen(next)
    if (next) onRefresh()
  }

  const kw = keyword.toLowerCase()
  const filtered = apps.filter(
    (a) => a.bundleName.toLowerCase().includes(kw) || a.label.toLowerCase().includes(kw)
  )

  // 打开列表后把选中项滚动到可视区中间（apps 刷新后会重新定位）
  useEffect(() => {
    if (!open) return
    const timer = window.setTimeout(() => {
      selectedItemRef.current?.scrollIntoView({ block: 'center' })
    }, 0)
    return () => window.clearTimeout(timer)
  }, [open, apps])

  // 触发按钮内容：运行中的已选应用在包名后展示 PID
  const selectedApp = selectedBundle
    ? (apps.find((a) => a.bundleName === selectedBundle) ?? null)
    : null
  const triggerText = selectedApp
    ? selectedApp.pid != null
      ? `${selectedApp.bundleName}（${selectedApp.pid}）`
      : selectedApp.bundleName
    : (selectedBundle ?? '请选择应用')
  const triggerLabel = (
    <>
      {selectedApp?.bundleName ?? selectedBundle ?? '请选择应用'}
      {selectedApp?.pid != null && <span style={{ color: '#52c41a' }}>（{selectedApp.pid}）</span>}
    </>
  )

  const content = (
    <div style={{ width: 340 }}>
      <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
        <Input.Search
          placeholder="搜索应用包名"
          allowClear
          value={keyword}
          onChange={(e) => setKeyword(e.target.value)}
        />
        <Button
          icon={<ReloadOutlined />}
          loading={loading}
          disabled={disabled}
          onClick={onRefresh}
        />
      </div>
      {/* 限高，避免列表过长 */}
      <div style={{ maxHeight: 280, overflow: 'auto' }}>
        {filtered.length === 0 ? (
          <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="暂无应用" />
        ) : (
          <List
            size="small"
            dataSource={filtered}
            renderItem={(app) => {
              const selected = selectedBundle === app.bundleName
              return (
                <List.Item
                  onClick={() => {
                    onSelect(app)
                    setOpen(false)
                  }}
                  style={{
                    cursor: 'pointer',
                    padding: '6px 8px',
                    borderRadius: 4,
                    background: selected ? '#e6f4ff' : 'transparent'
                  }}
                >
                  <div
                    ref={selected ? selectedItemRef : undefined}
                    title={app.bundleName}
                    style={{
                      flex: 1,
                      minWidth: 0,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                      fontWeight: selected ? 600 : 400
                    }}
                  >
                    {app.bundleName}
                    {app.pid != null && (
                      <span style={{ color: '#52c41a' }}>（{app.pid}）</span>
                    )}
                  </div>
                  {selected && <Tag color="blue">已选</Tag>}
                </List.Item>
              )
            }}
          />
        )}
      </div>
    </div>
  )

  return (
    <Popover
      open={open}
      onOpenChange={handleOpenChange}
      trigger="click"
      placement="bottomLeft"
      title="选择目标应用"
      content={content}
    >
      <Button disabled={disabled} style={{ width: '100%' }}>
        <span style={{ display: 'flex', alignItems: 'center', width: '100%' }}>
          <span
            style={{
              flex: 1,
              minWidth: 0,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              textAlign: 'left'
            }}
            title={triggerText}
          >
            {triggerLabel}
          </span>
          <DownOutlined style={{ marginLeft: 6, fontSize: 10, flex: '0 0 auto' }} />
        </span>
      </Button>
    </Popover>
  )
}
