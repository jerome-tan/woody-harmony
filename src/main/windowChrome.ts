import { app, BrowserWindow, ipcMain, Menu } from 'electron'
import type { BrowserWindowConstructorOptions, MenuItemConstructorOptions } from 'electron'
import type { AboutInfo } from '@shared/types'
import { TITLE_BAR_HEIGHT } from '@shared/windowChrome'

/** macOS keeps its traffic lights; Windows uses native caption buttons in our title bar. */
export function windowChromeOptions(): BrowserWindowConstructorOptions {
  return process.platform === 'darwin'
    ? { titleBarStyle: 'hiddenInset', titleBarOverlay: true }
    : {
        titleBarStyle: 'hidden',
        titleBarOverlay: { color: '#ffffff', symbolColor: '#595959', height: TITLE_BAR_HEIGHT }
      }
}

export function configureWindowChrome(win: BrowserWindow): void {
  if (process.platform === 'darwin') return
  // A null menu also prevents Alt from revealing an extra native menu row.
  win.setMenu(null)
  win.webContents.on('before-input-event', (event, input) => {
    if (input.type !== 'keyDown' || !input.control || input.alt || input.meta || input.shift) return
    const key = input.key.toLowerCase()
    if (!['w', 'm', 'q'].includes(key)) return
    event.preventDefault()
    if (key === 'w') win.close()
    else if (key === 'm') win.minimize()
    else app.quit()
  })
}

export function setupApplicationMenu(aboutInfo: AboutInfo): void {
  const about: MenuItemConstructorOptions = {
    label: '关于 Woody',
    click: (_item, win) => {
      const target = win ? BrowserWindow.fromId(win.id) : BrowserWindow.getFocusedWindow()
      target?.webContents.send('app:about', aboutInfo)
    }
  }
  const common: MenuItemConstructorOptions[] = [
    {
      label: '编辑',
      submenu: [
        { role: 'undo', label: '撤销' },
        { role: 'redo', label: '重做' },
        { type: 'separator' },
        { role: 'cut', label: '剪切' },
        { role: 'copy', label: '拷贝' },
        { role: 'paste', label: '粘贴' },
        { role: 'selectAll', label: '全选' }
      ]
    },
    {
      label: '窗口',
      submenu: [
        { role: 'minimize', label: '最小化' },
        { role: 'zoom', label: process.platform === 'darwin' ? '缩放' : '最大化 / 还原' },
        { type: 'separator' },
        { role: 'close', label: '关闭窗口' }
      ]
    }
  ]

  if (process.platform === 'darwin') {
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      {
        label: 'Woody',
        submenu: [
          about,
          { type: 'separator' },
          { role: 'services', label: '服务' },
          { type: 'separator' },
          { role: 'hide', label: '隐藏 Woody' },
          { role: 'hideOthers', label: '隐藏其他' },
          { role: 'unhide', label: '全部显示' },
          { type: 'separator' },
          { role: 'quit', label: '退出 Woody' }
        ]
      },
      ...common
    ]))
  } else {
    Menu.setApplicationMenu(null)
  }

  ipcMain.handle('window:show-menu', (event, x: number, y: number) => {
    if (process.platform === 'darwin' || !Number.isFinite(x) || !Number.isFinite(y)) return
    const win = BrowserWindow.fromWebContents(event.sender)
    if (!win || win.isDestroyed()) return
    const menu = Menu.buildFromTemplate([
      ...common,
      { type: 'separator' },
      about,
      { role: 'quit', label: '退出 Woody' }
    ])
    const zoom = event.sender.getZoomFactor()
    const bounds = win.getContentBounds()
    return new Promise<void>((resolve) => {
      const done = (): void => {
        win.removeListener('closed', done)
        resolve()
      }
      win.once('closed', done)
      menu.popup({
        window: win,
        x: Math.max(0, Math.min(Math.round(x * zoom), bounds.width - 1)),
        y: Math.max(0, Math.min(Math.round(y * zoom), bounds.height - 1)),
        callback: done
      })
    })
  })
}
