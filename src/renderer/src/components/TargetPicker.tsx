import { Button, Select, Typography } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import { useCallback, useEffect, useRef, useState } from 'react'
import type { AppInfo, DeviceInfo, DeviceSummary } from '@shared/types'
import { formatDeviceLabel } from '../utils'
import AppSelector from './AppSelector'
import FormLabel from './FormLabel'
import { notify } from '../notify'

/** 配置页选择的目标：设备 + 应用（PID 展示由 AppSelector 内部处理） */
export interface ToolTargetState {
  deviceId: string | null
  app: AppInfo | null
}

interface Props {
  value: ToolTargetState
  onChange: (next: ToolTargetState) => void
  devices: DeviceSummary[]
  currentTarget: string | null
  deviceInfo: DeviceInfo | null
  deviceLoading: boolean
  onRefreshDevices: () => void
  onSelectDevice: (targetId: string) => void
  disabled?: boolean
  /** 目标应用未运行时的红色提示文案（不传则不提示，由调用方自行处理） */
  notRunningHint?: string
}

/** 工具配置页通用：目标设备 + 目标应用选择（应用列表随设备联动） */
export default function TargetPicker({
  value,
  onChange,
  devices,
  currentTarget,
  deviceInfo,
  deviceLoading,
  onRefreshDevices,
  onSelectDevice,
  disabled,
  notRunningHint
}: Props): JSX.Element {
  const [apps, setApps] = useState<AppInfo[]>([])
  const [appsLoading, setAppsLoading] = useState(false)

  const deviceId = value.deviceId ?? currentTarget

  // 轮询期间访问最新 value/onChange 的 ref（避免轮询闭包捕获旧值）
  const valueRef = useRef(value)
  valueRef.current = value
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

  // 每 1.5s 静默刷新应用列表：应用的运行状态（PID）随启停变化，
  // 关闭应用后选择器应及时从「运行中 (pid)」变为「未运行」提示
  useEffect(() => {
    if (!deviceId) return
    const timer = setInterval(() => {
      void (async () => {
        try {
          const list = await window.api.listApps()
          setApps(list)
          // 同步选中应用的最新状态（pid 变化或应用消失）
          const cur = valueRef.current.app
          if (cur) {
            const latest = list.find((a) => a.bundleName === cur.bundleName) ?? null
            if ((latest?.pid ?? null) !== (cur.pid ?? null)) {
              onChangeRef.current({ ...valueRef.current, app: latest })
            }
          }
        } catch {
          /* 设备断开等异常静默，下个周期重试 */
        }
      })()
    }, 1500)
    return () => clearInterval(timer)
  }, [deviceId])

  const refreshApps = useCallback(async () => {
    if (!deviceId) return
    setAppsLoading(true)
    try {
      setApps(await window.api.listApps())
    } catch (e) {
      notify.error('获取应用列表失败', e)
    } finally {
      setAppsLoading(false)
    }
  }, [deviceId])

  // 设备切换后拉取应用列表，并默认选中运行中的应用
  useEffect(() => {
    if (!deviceId) {
      setApps([])
      return
    }
    void (async () => {
      setAppsLoading(true)
      try {
        const list = await window.api.listApps()
        setApps(list)
        if (!value.app || !list.some((a) => a.bundleName === value.app!.bundleName)) {
          onChange({ ...value, app: list.find((a) => a.pid != null) ?? null })
        }
      } catch (e) {
        notify.error('获取应用列表失败', e)
      } finally {
        setAppsLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [deviceId])

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <FormLabel text="目标设备" required />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', gap: 6 }}>
            <Select
              style={{ flex: 1, minWidth: 0 }}
              value={deviceId ?? undefined}
              popupMatchSelectWidth={false}
              styles={{ popup: { root: { minWidth: 560 } } }}
              placeholder={devices.length ? '请选择设备' : '未检测到设备'}
              // 设备显示统一为「型号[序列号] 版本(API)」；仅当前已连接设备能拿到完整信息，其余先显示序列号
              options={devices.map((d) => ({
                value: d.targetId,
                label:
                  d.targetId === currentTarget && deviceInfo
                    ? formatDeviceLabel(deviceInfo)
                    : d.targetId
              }))}
              onChange={(id) => {
                onSelectDevice(id)
                onChange({ deviceId: id, app: null })
              }}
              notFoundContent="未检测到设备"
              disabled={disabled}
            />
            <Button
              icon={<ReloadOutlined />}
              loading={deviceLoading}
              disabled={disabled}
              onClick={onRefreshDevices}
              title="刷新设备"
            />
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <FormLabel text="目标应用" required />
        <div style={{ flex: 1, minWidth: 0 }}>
          <AppSelector
            apps={apps}
            selectedBundle={value.app?.bundleName ?? null}
            loading={appsLoading}
            disabled={disabled || !deviceId}
            onRefresh={refreshApps}
            onSelect={(app) => onChange({ ...value, app })}
          />
          {value.app && value.app.pid == null && notRunningHint && (
            <Typography.Text type="danger" style={{ fontSize: 11.5, display: 'block', marginTop: 4 }}>
              {notRunningHint}
            </Typography.Text>
          )}
        </div>
      </div>
    </div>
  )
}
