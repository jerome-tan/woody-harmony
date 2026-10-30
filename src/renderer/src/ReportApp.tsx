import { Card, Empty, Tag } from 'antd'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ReportData } from './components/ReportView'
import ReportView from './components/ReportView'
import WindowTitleBar from './components/WindowTitleBar'
import { notify } from './notify'

/** 单报告查看窗口入口（独立 BrowserWindow）：经 query 传入会话目录，自行加载数据 */
export default function ReportApp(): JSX.Element {
  const [report, setReport] = useState<ReportData | null>(null)
  const [error, setError] = useState('')

  const dir = useMemo(
    () => new URLSearchParams(window.location.search).get('dir') ?? '',
    []
  )

  useEffect(() => {
    void (async () => {
      try {
        if (!dir) throw new Error('缺少报告目录参数')
        const session = await window.api.openSessionDir(dir)
        if (!session) throw new Error('无法读取报告数据')
        if (session.meta.type === 'snapshot') {
          const snapshot = await window.api.loadSnapshot(dir)
          if (!snapshot) throw new Error('快照数据缺失或已损坏')
          setReport({ meta: session.meta, snapshot })
        } else {
          setReport({ meta: session.meta, samples: session.samples })
        }
      } catch (e) {
        setError((e as Error).message)
      }
    })()
  }, [dir])

  // 窗口标题随任务名称（多窗口并排时便于区分）
  useEffect(() => {
    if (report) document.title = `${report.meta.taskName || report.meta.bundleName} - Woody`
  }, [report])

  // 编辑任务名称：直接回写 meta.json（主窗口报告列表下次刷新时同步）
  const saveTaskName = useCallback(async (d: string, taskName: string) => {
    const name = taskName.trim()
    if (!d || !name) return
    try {
      await window.api.renameSession(d, name)
      setReport((prev) => (prev ? { ...prev, meta: { ...prev.meta, taskName: name } } : prev))
    } catch (e) {
      notify.error('保存任务名称失败', e)
    }
  }, [])

  const isSnap = report?.meta.type === 'snapshot'

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: '#f3f5f9' }}>
      <WindowTitleBar
        title={report ? report.meta.taskName || report.meta.bundleName : '加载中…'}
        badge={report ? <Tag color={isSnap ? 'gold' : 'blue'}>{isSnap ? '📷 内存快照' : '📈 持续采样'}</Tag> : undefined}
        description="独立窗口 · 关闭后不影响原报告"
      />
      <div
        style={{
          flex: 1,
          minHeight: 0,
          overflow: 'hidden',
          padding: '12px 16px 16px',
          display: 'flex',
          flexDirection: 'column'
        }}
      >
        {error ? (
          <Card>
            <Empty description={`加载报告失败：${error}`} />
          </Card>
        ) : !report ? (
          <Card>
            <Empty description="正在加载报告…" />
          </Card>
        ) : (
          <ReportView report={report} onSaveTaskName={saveTaskName} />
        )}
      </div>
    </div>
  )
}
