import { Modal } from 'antd'
import { useEffect, useState } from 'react'
import type { AboutInfo } from '@shared/types'
import AppLogo from './AppLogo'

/** Each window handles its own native menu's About action. */
export default function AboutDialog(): JSX.Element {
  const [aboutInfo, setAboutInfo] = useState<AboutInfo | null>(null)
  useEffect(() => window.api.onShowAbout(setAboutInfo), [])

  return (
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
  )
}
