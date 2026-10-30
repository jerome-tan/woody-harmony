import { useCallback, useEffect, useRef, useState } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import { MenuOutlined } from '@ant-design/icons'
import { TITLE_BAR_HEIGHT } from '@shared/windowChrome'
import { notify } from '../notify'
import './WindowTitleBar.css'

interface ControlsOverlay extends EventTarget {
  readonly visible: boolean
}

const overlay = (navigator as Navigator & { windowControlsOverlay?: ControlsOverlay }).windowControlsOverlay
const isMac = window.api.platform === 'darwin'

interface Props {
  title: string
  badge?: ReactNode
  description?: string
  actions?: ReactNode
}

export default function WindowTitleBar({ title, badge, description, actions }: Props): JSX.Element {
  const [overlayVisible, setOverlayVisible] = useState(overlay?.visible ?? false)
  const [menuOpen, setMenuOpen] = useState(false)
  const menuButton = useRef<HTMLButtonElement>(null)
  const opening = useRef(false)

  useEffect(() => {
    const update = (): void => setOverlayVisible(overlay?.visible ?? false)
    overlay?.addEventListener('geometrychange', update)
    update()
    return () => overlay?.removeEventListener('geometrychange', update)
  }, [])

  const openMenu = useCallback(() => {
    if (!menuButton.current || opening.current) return
    const rect = menuButton.current.getBoundingClientRect()
    opening.current = true
    setMenuOpen(true)
    void window.api.showWindowMenu(rect.left, rect.bottom)
      .catch((error) => notify.error('无法打开应用菜单', error))
      .finally(() => {
        opening.current = false
        setMenuOpen(false)
      })
  }, [])

  useEffect(() => {
    if (isMac) return
    let altOnly = false
    const keyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Alt') {
        if (!event.repeat) altOnly = !event.ctrlKey && !event.shiftKey && !event.metaKey
      } else {
        altOnly = false
        if (event.key === 'F10' && !event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
          event.preventDefault()
          openMenu()
        }
      }
    }
    const keyUp = (event: KeyboardEvent): void => {
      if (event.key === 'Alt' && altOnly) {
        event.preventDefault()
        altOnly = false
        openMenu()
      }
    }
    const blur = (): void => { altOnly = false }
    window.addEventListener('keydown', keyDown)
    window.addEventListener('keyup', keyUp)
    window.addEventListener('blur', blur)
    return () => {
      window.removeEventListener('keydown', keyDown)
      window.removeEventListener('keyup', keyUp)
      window.removeEventListener('blur', blur)
    }
  }, [openMenu])

  return (
    <header
      className="window-titlebar"
      data-platform={isMac ? 'mac' : 'windows'}
      data-overlay={overlay ? (overlayVisible ? 'visible' : 'hidden') : 'unavailable'}
      style={{ '--titlebar-height': `${TITLE_BAR_HEIGHT}px` } as CSSProperties}
    >
      <div className="window-titlebar__safe-area">
        {!isMac && (
          <button
            ref={menuButton}
            type="button"
            className="window-titlebar__menu"
            aria-label="应用菜单"
            aria-haspopup="menu"
            aria-expanded={menuOpen}
            title="应用菜单（Alt / F10）"
            onMouseDown={(event) => event.preventDefault()}
            onClick={openMenu}
          >
            <MenuOutlined />
          </button>
        )}
        <div className="window-titlebar__content">
          {badge && <span className="window-titlebar__badge">{badge}</span>}
          <b className="window-titlebar__title" title={title}>{title}</b>
          {description && <span className="window-titlebar__description">{description}</span>}
        </div>
        {actions && <div className="window-titlebar__actions">{actions}</div>}
      </div>
    </header>
  )
}
