import { useCallback, useEffect, useRef, useState } from 'react'
import { Badge, Layout, Modal, Tag } from 'antd'
import { version as APP_VERSION } from '../../../package.json'
import {
  AppstoreOutlined,
  FileTextOutlined,
  HomeOutlined,
  SettingOutlined
} from '@ant-design/icons'
import type {
  AboutInfo,
  AppInfo,
  DeviceInfo,
  DeviceSummary,
  ProcessMemorySample,
  SamplerConfig,
  SamplingSessionMeta,
  SamplingStatus,
  SnapshotOptions
} from '@shared/types'
import AppLogo from './components/AppLogo'
import type { PageKey, PageProps } from './pages/types'
import type { ToolTargetState } from './components/TargetPicker'
import HomePage from './pages/HomePage'
import ToolsPage from './pages/ToolsPage'
import PeakPage from './pages/PeakPage'
import LivePage from './pages/LivePage'
import WatchPage from './pages/WatchPage'
import SnapPage from './pages/SnapPage'
import ReportsPage from './pages/ReportsPage'
import SettingsPage from './pages/SettingsPage'
import { DEFAULT_CONFIG } from './constants'
import { formatDeviceLabel } from './utils'
import { notify } from './notify'

const { Sider, Content } = Layout

// 无设备时的探测间隔退避表（毫秒）：启动初期较密，之后逐步拉长
const DEVICE_BACKOFF_MS = [2500, 5000, 10000, 30000]
// 已连接后的保活探测间隔（仅检测是否断开）
const DEVICE_KEEPALIVE_MS = 8000

const NAV_ITEMS: Array<{ key: PageKey; icon: React.ReactNode; label: string }> = [
  { key: 'home', icon: <HomeOutlined />, label: '首页' },
  { key: 'tools', icon: <AppstoreOutlined />, label: '工具集' },
  { key: 'reports', icon: <FileTextOutlined />, label: '查看报告' },
  { key: 'settings', icon: <SettingOutlined />, label: '设置' }
]

export default function App(): JSX.Element {
  const [page, setPage] = useState<PageKey>('home')
  // 「关于」弹窗（菜单触发，数据来自主进程）
  const [aboutInfo, setAboutInfo] = useState<AboutInfo | null>(null)
  useEffect(() => window.api.onShowAbout(setAboutInfo), [])

  // 设置
  const [hdcPath, setHdcPath] = useState('')
  const [sessionsDir, setSessionsDir] = useState('')
  const [defaultSessionsDir, setDefaultSessionsDir] = useState('')

  // 设备上下文（全局轮询）
  const [devices, setDevices] = useState<DeviceSummary[]>([])
  const [currentTarget, setCurrentTarget] = useState<string | null>(null)
  const [deviceInfo, setDeviceInfo] = useState<DeviceInfo | null>(null)
  const [deviceLoading, setDeviceLoading] = useState(false)

  // 采样状态
  const [status, setStatus] = useState<SamplingStatus>({ state: 'idle' })
  const [samples, setSamples] = useState<ProcessMemorySample[]>([])
  const [liveBundle, setLiveBundle] = useState('')
  const [liveStartedAt, setLiveStartedAt] = useState<number | null>(null)
  const [sessionDir, setSessionDir] = useState('')
  const [snapshotting, setSnapshotting] = useState(false)
  /** 本次采样会话的时长上限（毫秒，0=不限），用于实时页展示预计结束时间 */
  const [liveMaxDurationMs, setLiveMaxDurationMs] = useState(0)
  /** 当前进行中的会话属于哪个工具（决定顶栏状态芯片跳转与停止行为） */
  const [liveTool, setLiveTool] = useState<'peak' | 'watch'>('peak')

  // 报告
  const [records, setRecords] = useState<SamplingSessionMeta[]>([])
  const [recordsLoading, setRecordsLoading] = useState(false)

  const sampling =
    status.state === 'starting' || status.state === 'sampling' || status.state === 'stopping'

  const go = useCallback((p: PageKey) => setPage(p), [])

  // ── 设备轮询 ──
  const currentTargetRef = useRef<string | null>(null)
  useEffect(() => {
    currentTargetRef.current = currentTarget
  }, [currentTarget])

  const clearDevice = useCallback(() => {
    setDevices([])
    setCurrentTarget(null)
    currentTargetRef.current = null
    setDeviceInfo(null)
  }, [])

  const connectTo = useCallback(async (targetId: string) => {
    setCurrentTarget(targetId)
    currentTargetRef.current = targetId
    try {
      await window.api.setTarget(targetId)
      setDeviceInfo(await window.api.getDeviceInfo())
    } catch (e) {
      notify.error('连接设备失败', e)
    }
  }, [])

  const refreshDevices = useCallback(async () => {
    setDeviceLoading(true)
    try {
      const list = await window.api.listDevices()
      setDevices(list)
      const cur = currentTargetRef.current
      if (list.length === 0) {
        clearDevice()
      } else if (!cur || !list.some((d) => d.targetId === cur)) {
        await connectTo(list[0].targetId)
      } else {
        setDeviceInfo(await window.api.getDeviceInfo())
      }
    } catch (e) {
      notify.error('刷新设备失败', e)
    } finally {
      setDeviceLoading(false)
    }
  }, [clearDevice, connectTo])

  useEffect(() => {
    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | null = null
    let attempt = 0
    const tick = async (): Promise<void> => {
      if (cancelled) return
      let list: DeviceSummary[] = []
      try {
        list = await window.api.listDevices()
      } catch {
        list = []
      }
      if (cancelled) return
      let delay: number
      if (list.length === 0) {
        clearDevice()
        delay = DEVICE_BACKOFF_MS[Math.min(attempt, DEVICE_BACKOFF_MS.length - 1)]
        attempt++
      } else {
        attempt = 0
        setDevices(list)
        const cur = currentTargetRef.current
        const stillThere = cur != null && list.some((d) => d.targetId === cur)
        if (!stillThere) {
          await connectTo(list[0].targetId)
          if (cancelled) return
        }
        delay = DEVICE_KEEPALIVE_MS
      }
      if (!cancelled) timer = setTimeout(() => void tick(), delay)
    }
    void tick()
    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
    }
  }, [clearDevice, connectTo])

  // ── 采样事件 ──
  useEffect(() => {
    const offStatus = window.api.onSamplingStatus(setStatus)
    const offSample = window.api.onSample((s) => setSamples((prev) => [...prev, s]))
    return () => {
      offStatus()
      offSample()
    }
  }, [])

  // ── 设置加载 ──
  useEffect(() => {
    window.api.getHdcPath().then(setHdcPath).catch(() => {})
    window.api
      .getSessionsDir()
      .then((r) => {
        setSessionsDir(r.custom)
        setDefaultSessionsDir(r.defaultDir)
      })
      .catch(() => {})
  }, [])

  // ── 报告列表 ──
  const refreshRecords = useCallback(async () => {
    setRecordsLoading(true)
    try {
      setRecords(await window.api.listSessions())
    } catch (e) {
      notify.error('获取报告列表失败', e)
    } finally {
      setRecordsLoading(false)
    }
  }, [])

  useEffect(() => {
    void refreshRecords()
  }, [refreshRecords])

  // 采样时长到期自动结束：提示并（仅当停留在实时页时）弹出报告窗口、跳回报告列表
  const liveToolRef = useRef(liveTool)
  const sessionDirRef = useRef(sessionDir)
  const pageRef = useRef(page)
  useEffect(() => {
    liveToolRef.current = liveTool
  }, [liveTool])
  useEffect(() => {
    sessionDirRef.current = sessionDir
  }, [sessionDir])
  useEffect(() => {
    pageRef.current = page
  }, [page])
  useEffect(() => {
    if (status.state !== 'idle' || !status.autoStopped || liveToolRef.current !== 'peak') return
    notify.success('已达采样时长上限，采样自动结束')
    void refreshRecords()
    const dir = sessionDirRef.current
    if (pageRef.current === 'live' && dir) {
      setPage('reports')
      window.api.openReportWindow(dir).catch(() => {})
    }
  }, [status, refreshRecords])

  const saveTaskName = useCallback(async (dir: string, taskName: string) => {
    const name = taskName.trim()
    if (!dir || !name) return
    try {
      await window.api.renameSession(dir, name)
      setRecords((prev) => prev.map((r) => (r.sessionDir === dir ? { ...r, taskName: name } : r)))
    } catch (e) {
      notify.error('保存任务名称失败', e)
    }
  }, [])

  // ── 峰值采样流程：配置 → 实时；结束 → 报告页 ──
  const onStartPeak = useCallback(
    async (target: ToolTargetState, config: SamplerConfig, taskName: string) => {
      if (!target.app) return
      setSamples([])
      setLiveBundle(target.app.bundleName)
      setLiveStartedAt(null)
      setSessionDir('')
      setLiveTool('peak')
      setLiveMaxDurationMs(config.maxDurationMs ?? 0)
      try {
        await window.api.startSampling(
          config,
          target.app.bundleName,
          target.app.bundleName,
          true,
          taskName
        )
        setLiveStartedAt(Date.now())
        setSessionDir(await window.api.getSessionDir())
        setPage('live')
        void refreshRecords()
      } catch (e) {
        notify.error('启动采样失败', e)
      }
    },
    [refreshRecords]
  )

  const stopPeak = useCallback(async () => {
    try {
      const meta = await window.api.stopSampling()
      void refreshRecords()
      if (meta?.sessionDir) {
        window.api.openReportWindow(meta.sessionDir).catch(() => {})
        notify.success('采样已结束，报告已生成')
      }
      setPage('reports')
    } catch (e) {
      notify.error('结束采样失败', e)
    }
  }, [refreshRecords])

  // ── 实时内存查看：不落盘，结束后回到配置页，不生成报告 ──
  const onStartWatch = useCallback(async (target: ToolTargetState, intervalMs: number) => {
    if (!target.app) return
    setSamples([])
    setLiveBundle(target.app.bundleName)
    setLiveStartedAt(null)
    setSessionDir('')
    setLiveTool('watch')
    try {
      await window.api.startSampling(
        // persist=false：不写 meta/samples/raw；maxDurationMs=0：查看不设时长上限
        { ...DEFAULT_CONFIG, intervalMs, maxDurationMs: 0 },
        target.app.bundleName,
        target.app.bundleName,
        false
      )
      setLiveStartedAt(Date.now())
      setPage('watch')
    } catch (e) {
      notify.error('启动实时查看失败', e)
    }
  }, [])

  const stopWatch = useCallback(async () => {
    try {
      await window.api.stopSampling()
      notify.success('已结束实时查看（数据未落盘）')
      setPage('watch')
    } catch (e) {
      notify.error('结束查看失败', e)
    }
  }, [])

  // ── 内存快照流程：配置 → 抓取中 → 弹出报告窗口 ──
  const onStartSnap = useCallback(
    async (target: ToolTargetState, taskName: string, options: SnapshotOptions) => {
      if (!target.app) return
      setSnapshotting(true)
      try {
        const { meta } = await window.api.takeSnapshot(
          target.app.bundleName,
          target.app.bundleName,
          taskName,
          options
        )
        if (meta.sessionDir) window.api.openReportWindow(meta.sessionDir).catch(() => {})
        notify.success('内存快照已保存')
        void refreshRecords()
      } catch (e) {
        notify.error('抓取内存快照失败', e)
      } finally {
        setSnapshotting(false)
      }
    },
    [refreshRecords]
  )

  const saveHdcPath = useCallback(async (path: string) => {
    try {
      await window.api.setHdcPath(path)
      setHdcPath(path)
    } catch (e) {
      notify.error('保存 hdc 路径失败', e)
      throw e
    }
  }, [])

  const saveSessionsDir = useCallback(
    async (dir: string) => {
      try {
        await window.api.setSessionsDir(dir)
        setSessionsDir(dir)
        void refreshRecords()
      } catch (e) {
        notify.error('保存输出目录失败', e)
        throw e
      }
    },
    [refreshRecords]
  )

  // 共享页面 props
  const pageProps: PageProps = {
    go,
    devices,
    currentTarget,
    deviceInfo,
    deviceLoading,
    onRefreshDevices: refreshDevices,
    onSelectDevice: (id) => void connectTo(id),
    sampling,
    status,
    onStartPeak: (t, c, n) => void onStartPeak(t, c, n),
    onStartSnap: (t, n, s) => void onStartSnap(t, n, s),
    snapshotting,
    refreshRecordsTick: 0,
    onSaveTaskName: saveTaskName
  }

  // 顶栏设备芯片：统一「型号[序列号] 版本(API)」格式
  const deviceChip = currentTarget ? (
    <Tag
      color="success"
      title={deviceInfo ? formatDeviceLabel(deviceInfo) : currentTarget}
      style={{
        marginInlineEnd: 0,
        maxWidth: 420,
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
        WebkitAppRegion: 'no-drag'
      } as React.CSSProperties}
    >
      ● {deviceInfo ? formatDeviceLabel(deviceInfo) : currentTarget}
    </Tag>
  ) : (
    <Tag style={{ marginInlineEnd: 0, WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
      ○ 未连接设备
    </Tag>
  )

  return (
    <Layout style={{ height: '100vh' }}>
      {/* 顶栏：窗口拖拽区 + 全局状态 */}
      <div
        style={
          {
            height: 46,
            flex: '0 0 auto',
            display: 'flex',
            alignItems: 'center',
            padding: '0 14px 0 86px',
            background: '#fff',
            borderBottom: '1px solid #f0f0f0',
            WebkitAppRegion: 'drag'
          } as React.CSSProperties
        }
      >
        <span style={{ flex: 1 }} />
        {sampling && (
          <Tag
            color={liveTool === 'watch' ? 'success' : 'processing'}
            style={{ marginInlineEnd: 8, cursor: 'pointer', WebkitAppRegion: 'no-drag' } as React.CSSProperties}
            onClick={() => setPage(liveTool === 'watch' ? 'watch' : 'live')}
            title={liveTool === 'watch' ? '点击回到实时查看页' : '点击回到实时采样页'}
          >
            <Badge status="processing" /> {liveTool === 'watch' ? '查看中' : '采样中'} · {samples.length} 点
          </Tag>
        )}
        {deviceChip}
      </div>

      <Layout>
        {/* 左侧主导航 */}
        <Sider
          width={172}
          theme="light"
          style={{
            flex: '0 0 172px',
            borderRight: '1px solid #f0f0f0',
            padding: '14px 10px',
            display: 'flex',
            flexDirection: 'column'
          }}
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 9,
              padding: '2px 8px 14px',
              borderBottom: '1px solid #f0f0f0',
              marginBottom: 10
            }}
          >
            {/* 应用 Logo（与 build/icon.svg 同稿） */}
            <AppLogo size={38} radius={10} />
            <div style={{ lineHeight: 1.3, minWidth: 0 }}>
              <div style={{ fontSize: 15, fontWeight: 600 }}>Woody</div>
              <div style={{ fontSize: 11, color: '#8c8c8c' }}>v{APP_VERSION}</div>
            </div>
          </div>
          {NAV_ITEMS.map((item) => {
            const active =
              page === item.key ||
              (item.key === 'tools' &&
                (page === 'peak' || page === 'snap' || page === 'live' || page === 'watch'))
            return (
              <div
                key={item.key}
                onClick={() => setPage(item.key)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  height: 40,
                  padding: '0 12px',
                  borderRadius: 8,
                  color: active ? '#1677ff' : 'rgba(0,0,0,.65)',
                  background: active ? '#e6f4ff' : 'transparent',
                  fontWeight: active ? 600 : 400,
                  fontSize: 13.5,
                  cursor: 'pointer',
                  marginBottom: 2
                }}
              >
                <span style={{ width: 18, textAlign: 'center', fontSize: 15 }}>{item.icon}</span>
                {item.label}
                {item.key === 'reports' && records.length > 0 && (
                  <span
                    style={{
                      marginLeft: 'auto',
                      fontSize: 11,
                      minWidth: 18,
                      height: 18,
                      lineHeight: '18px',
                      textAlign: 'center',
                      padding: '0 5px',
                      borderRadius: 9,
                      background: active ? '#fff' : '#f0f0f0',
                      color: active ? '#1677ff' : '#8c8c8c'
                    }}
                  >
                    {records.length}
                  </span>
                )}
              </div>
            )
          })}
          <div style={{ flex: 1 }} />
        </Sider>

        {/* 主区：单页路由（flex 列布局，报告/实时页可用 flex:1 自适应撑满高度） */}
        <Content
          style={{
            overflow: 'auto',
            padding: '20px 24px 32px',
            minHeight: 0,
            display: 'flex',
            flexDirection: 'column'
          }}
        >
          {page === 'home' && <HomePage {...pageProps} />}
          {page === 'tools' && <ToolsPage {...pageProps} />}
          {page === 'peak' && <PeakPage {...pageProps} />}
          {page === 'live' && (
            <LivePage
              {...pageProps}
              samples={samples}
              bundleName={liveBundle}
              startedAt={liveStartedAt}
              sessionDir={sessionDir}
              maxDurationMs={liveMaxDurationMs}
              onStop={() => void stopPeak()}
            />
          )}
          {page === 'watch' && (
            <WatchPage
              {...pageProps}
              watching={sampling && liveTool === 'watch'}
              samples={samples}
              bundleName={liveBundle}
              startedAt={liveStartedAt}
              onStartWatch={(t, ms) => void onStartWatch(t, ms)}
              onStopWatch={() => void stopWatch()}
            />
          )}
          {page === 'snap' && <SnapPage {...pageProps} />}
          {page === 'reports' && (
            <ReportsPage
              {...pageProps}
              records={records}
              loading={recordsLoading}
              lockedDir={sampling ? sessionDir : null}
              refreshRecords={refreshRecords}
            />
          )}
          {page === 'settings' && (
            <SettingsPage
              {...pageProps}
              hdcPath={hdcPath}
              sessionsDir={sessionsDir}
              defaultSessionsDir={defaultSessionsDir}
              onSaveHdcPath={saveHdcPath}
              onSaveSessionsDir={saveSessionsDir}
            />
          )}
        </Content>
      </Layout>

      {/* 关于弹窗（macOS 菜单「关于 Woody」触发，自绘以自定义内容顺序） */}
      <Modal
        open={!!aboutInfo}
        footer={null}
        onCancel={() => setAboutInfo(null)}
        width={340}
        centered
      >
        <div style={{ padding: '8px 0 2px' }}>
          <div style={{ textAlign: 'center' }}>
            <div style={{ display: 'flex', justifyContent: 'center' }}>
              <AppLogo size={64} radius={14} />
            </div>
            <div style={{ fontSize: 17, fontWeight: 600, marginTop: 10 }}>Woody</div>
            <div style={{ fontSize: 12.5, color: '#595959', marginTop: 4 }}>
              鸿蒙（HarmonyOS）开发者工具
            </div>
          </div>
          {aboutInfo && (
            <div
              style={{
                marginTop: 14,
                paddingTop: 12,
                borderTop: '1px solid #f0f0f0',
                fontSize: 12,
                lineHeight: 2
              }}
            >
              {(
                [
                  ['版本', `v${aboutInfo.version}`],
                  ['提交', aboutInfo.commit],
                  ['日期', aboutInfo.commitDate],
                  ['Electron', aboutInfo.electron],
                  ['Node.js', aboutInfo.node],
                  ['V8', aboutInfo.v8],
                  ['OS', aboutInfo.os]
                ] as Array<[string, string]>
              ).map(([k, v]) => (
                <div key={k} style={{ display: 'flex', gap: 8 }}>
                  <span style={{ width: 72, flex: '0 0 auto', textAlign: 'right', color: '#8c8c8c' }}>
                    {k}:
                  </span>
                  <span style={{ color: '#262626', fontVariantNumeric: 'tabular-nums', wordBreak: 'break-all' }}>
                    {v}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </Modal>
    </Layout>
  )
}
