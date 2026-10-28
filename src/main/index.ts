import { app, BrowserWindow, Menu, nativeImage } from 'electron'
import type { MenuItemConstructorOptions } from 'electron'
import { existsSync, renameSync } from 'fs'
import { join } from 'path'
import { BUILD_OS, GIT_COMMIT, GIT_COMMIT_DATE } from './buildInfo'
import { registerIpc } from './ipc'
import type { AboutInfo } from '@shared/types'

/** 应用显示名：菜单栏 / 窗口标题 / 关于面板，同时决定 userData 目录名（与 electron-builder productName 一致） */
const APP_NAME = 'Woody'

/**
 * 旧版本数据目录迁移：历史版本曾用「鸿蒙内存采样工具」（旧 dev 名）、
 * 「HarmonyOS Memory Tools」（旧打包 productName）与「啄木鸟」（曾用中文名）作为应用名，
 * 其 userData 目录中的历史报告与设置迁移到当前目录；已有新目录或迁移失败时不阻塞启动。
 */
function migrateLegacyUserData(): void {
  const userDataDir = app.getPath('userData')
  if (existsSync(userDataDir)) return
  const appData = app.getPath('appData')
  for (const legacy of ['啄木鸟', '鸿蒙内存采样工具', 'HarmonyOS Memory Tools']) {
    const dir = join(appData, legacy)
    if (!existsSync(dir)) continue
    try {
      renameSync(dir, userDataDir)
    } catch {
      /* 迁移失败不阻塞启动，设置页可手动指定旧目录 */
    }
    return
  }
}

/** 「关于」弹窗信息：版本 + 构建信息（提交/日期/系统）+ 运行时组件版本，菜单点击时发给渲染层 */
type AboutPayload = AboutInfo

/** 定制中文精简菜单：应用菜单（macOS）+ 编辑 + 窗口，替换 Electron 默认英文菜单 */
function setupMenu(aboutInfo: AboutPayload): void {
  const template: MenuItemConstructorOptions[] = []
  if (process.platform === 'darwin') {
    template.push({
      label: APP_NAME,
      submenu: [
        {
          label: `关于 ${APP_NAME}`,
          click: () => BrowserWindow.getAllWindows()[0]?.webContents.send('app:about', aboutInfo)
        },
        { type: 'separator' },
        { role: 'services', label: '服务' },
        { type: 'separator' },
        { role: 'hide', label: `隐藏 ${APP_NAME}` },
        { role: 'hideOthers', label: '隐藏其他' },
        { role: 'unhide', label: '全部显示' },
        { type: 'separator' },
        { role: 'quit', label: `退出 ${APP_NAME}` }
      ]
    })
  }
  template.push({
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
  })
  template.push({
    label: '窗口',
    submenu: [
      { role: 'minimize', label: '最小化' },
      { role: 'zoom', label: '缩放' },
      { type: 'separator' },
      { role: 'close', label: '关闭窗口' }
    ]
  })
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

function createWindow(): void {
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 1024,
    minHeight: 680,
    title: APP_NAME,
    // 隐藏原生标题栏，保留左上角红绿灯按钮，窗口顶部由渲染层自绘（含拖拽区）
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  // 主窗口关闭 = 退出整个应用：报告/对比等子窗口一并级联关闭
  //（不用 parent 属性实现——Electron 会按父窗口居中子窗口，父窗口贴顶时子窗口被顶到菜单栏下）
  win.on('close', () => {
    for (const w of BrowserWindow.getAllWindows()) {
      if (w !== win && !w.isDestroyed()) w.close()
    }
  })

  if (process.env['ELECTRON_RENDERER_URL']) {
    void win.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    void win.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

app.whenReady().then(() => {
  app.setName(APP_NAME)
  migrateLegacyUserData()
  // dev 模式下 Dock 默认是 Electron 图标，替换为应用图标（打包产物由 electron-builder 生成 icns/ico）
  if (process.platform === 'darwin' && !app.isPackaged) {
    const icon = nativeImage.createFromPath(join(__dirname, '../../build/icon.png'))
    if (!icon.isEmpty()) app.dock?.setIcon(icon)
  }
  // 「关于」弹窗信息：应用版本 + 构建期固化的提交与系统信息（scripts/genBuildInfo.js 生成）+ 运行时组件版本
  setupMenu({
    version: app.getVersion(),
    commit: GIT_COMMIT,
    commitDate: GIT_COMMIT_DATE,
    electron: process.versions.electron,
    node: process.versions.node,
    v8: process.versions.v8,
    os: BUILD_OS
  })
  registerIpc()
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
