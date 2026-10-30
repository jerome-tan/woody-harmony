// Runs the built app on the host OS. Device discovery is mocked; window chrome,
// preload, report storage, renderer layout and menus use the production code.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

if (!process.versions.electron) {
  const { spawnSync } = require('node:child_process')
  const env = { ...process.env }
  delete env.ELECTRON_RUN_AS_NODE
  delete env.ELECTRON_RENDERER_URL
  const child = spawnSync(require('electron'), [__filename], { env, stdio: 'inherit', timeout: 120000 })
  if (child.error) console.error(child.error)
  process.exit(child.status ?? 1)
}

const { app, BrowserWindow, Menu, desktopCapturer, ipcMain } = require('electron')
const output = process.env.WOODY_CHROME_QA_DIR || fs.mkdtempSync(path.join(os.tmpdir(), 'woody-chrome-'))
const evidence = path.join(output, 'evidence')
for (const dir of ['profile', 'appdata', 'logs', 'reports', 'evidence']) fs.mkdirSync(path.join(output, dir), { recursive: true })
app.setPath('userData', path.join(output, 'profile'))
app.setPath('sessionData', path.join(output, 'profile'))
app.setPath('appData', path.join(output, 'appdata'))
app.setPath('logs', path.join(output, 'logs'))
fs.writeFileSync(path.join(output, 'profile/settings.json'), JSON.stringify({ hdcPath: '', sessionsDir: path.join(output, 'reports') }))

const windows = []
const errors = []
const checks = []
const device = { targetId: 'QA', marketName: 'Woody QA 设备', model: 'QA', softwareVersion: '6.0', apiVersion: '24', serialNumber: 'QA', ramTotalKb: 8388608, screenResolution: '1920x1080' }
app.on('browser-window-created', (_event, win) => {
  windows.push(win)
  win.webContents.on('render-process-gone', (_e, details) => errors.push(`Renderer exited: ${details.reason}`))
  win.webContents.on('console-message', (event) => {
    if (event.level === 'error') errors.push(event.message)
  })
  if (windows.length === 1) {
    const handlers = {
      'hdc:getPath': () => 'QA (no device commands)',
      'device:list': () => [],
      'device:info': () => null
    }
    for (const [channel, handler] of Object.entries(handlers)) {
      ipcMain.removeHandler(channel)
      ipcMain.handle(channel, handler)
    }
  }
})

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms))
async function until(check, label, timeout = 15000) {
  const end = Date.now() + timeout
  while (Date.now() < end) {
    if (await check()) return
    await delay(80)
  }
  throw new Error(`Timed out: ${label}`)
}
const evaluate = (win, expression) => win.webContents.executeJavaScript(expression, true)
async function ready(win) {
  await until(() => !win.webContents.isLoadingMainFrame() && evaluate(win, "!!document.querySelector('.window-titlebar__title')"), 'title bar ready')
}
async function screenshot(win, name) {
  fs.writeFileSync(path.join(evidence, `${name}.png`), (await win.capturePage()).toPNG())
}
async function checkLayout(win, name) {
  await ready(win)
  await until(() => evaluate(win, 'navigator.windowControlsOverlay?.visible'), 'native window controls overlay')
  const layout = await evaluate(win, `(() => {
    const header = document.querySelector('.window-titlebar')
    const safe = document.querySelector('.window-titlebar__safe-area').getBoundingClientRect()
    const title = document.querySelector('.window-titlebar__title')
    return {
      platform: window.api.platform, viewport: innerWidth,
      header: header.getBoundingClientRect().toJSON(), safe: safe.toJSON(),
      overlay: navigator.windowControlsOverlay.getTitlebarAreaRect().toJSON(),
      menu: !!document.querySelector('.window-titlebar__menu'),
      titleWidth: title.clientWidth, titleScrollWidth: title.scrollWidth,
      horizontalOverflow: document.documentElement.scrollWidth > innerWidth,
      descriptionVisible: getComputedStyle(document.querySelector('.window-titlebar__description') || title).display !== 'none'
    }
  })()`)
  assert.equal(layout.platform, process.platform)
  assert.equal(layout.header.y, 0)
  assert.equal(layout.header.height, 46)
  assert.equal(layout.menu, process.platform !== 'darwin')
  assert(layout.titleWidth > 0)
  assert(layout.safe.left >= layout.overlay.x - 1)
  assert(layout.safe.right <= layout.overlay.x + layout.overlay.width + 1)
  if (process.platform === 'win32') {
    assert.equal(win.isMenuBarVisible(), false)
    assert.equal(layout.overlay.x, 0)
    assert(layout.overlay.width < layout.viewport, 'Native caption buttons must reserve the right edge')
  } else assert(layout.overlay.x > 0, 'macOS must reserve its traffic lights')
  checks.push({ name, ...layout })
  await screenshot(win, name)
  return layout
}
function reportFixture(name) {
  const dir = path.join(output, 'reports', name)
  fs.mkdirSync(dir, { recursive: true })
  const values = { pssTotalKb: 1024, sharedCleanKb: 0, sharedDirtyKb: 0, privateCleanKb: 512, privateDirtyKb: 512, swapTotalKb: 0, swapPssTotalKb: 0, heapSizeKb: 1024, heapAllocKb: 512, heapFreeKb: 512 }
  const startedAt = 1700000000000
  const samples = [0, 1, 2].map(i => ({ timestamp: startedAt + i * 1000, pid: 1234, total: values, categories: { GL: values }, nativeHeapDetail: {}, purgSumKb: 0, purgPinKb: 0, dmaKb: 0, ashmemTotalKb: 0 }))
  const meta = { id: name, taskName: `${name} · ${'用于验证窄窗口标题截断'.repeat(5)}`, type: 'trend', bundleName: 'com.example.qa', appLabel: 'QA', device, config: { intervalMs: 1000, showAshmem: false, showDmabuf: false, showGpumem: false }, startedAt, endedAt: startedAt + 2000, sampleCount: 3, sessionDir: dir }
  fs.writeFileSync(path.join(dir, 'meta.json'), JSON.stringify(meta))
  fs.writeFileSync(path.join(dir, 'samples.jsonl'), samples.map(s => JSON.stringify(s)).join('\n') + '\n')
  return dir
}
const dirs = [reportFixture('QA-A'), reportFixture('QA-B')]
require(path.join(__dirname, '../out/main/index.js'))

app.whenReady().then(async () => {
  const main = windows[0]
  await ready(main)
  await checkLayout(main, 'main')
  await evaluate(main, `window.api.openReportWindow(${JSON.stringify(dirs[0])})`)
  const report = windows[1]
  await ready(report)
  await until(() => evaluate(report, "document.querySelector('.window-titlebar__title').textContent.startsWith('QA-A')"), 'report loaded')
  await checkLayout(report, 'report')
  await evaluate(main, `window.api.openCompareWindow(${JSON.stringify(dirs)})`)
  const compare = windows[2]
  await ready(compare)
  await until(() => evaluate(compare, "document.querySelectorAll('canvas').length > 0"), 'comparison chart loaded')
  await checkLayout(compare, 'compare')

  if (process.platform === 'win32') {
    // capturePage omits OS caption buttons; keep a native-window image as well.
    const sources = await desktopCapturer.getSources({ types: ['window'], thumbnailSize: { width: 1600, height: 1000 } })
    const source = sources.find(item => item.id === compare.getMediaSourceId())
    if (source && !source.thumbnail.isEmpty()) fs.writeFileSync(path.join(evidence, 'compare-native.png'), source.thumbnail.toPNG())
    compare.maximize()
    await until(() => compare.isMaximized(), 'window maximized')
    await delay(200)
    await checkLayout(compare, 'compare-maximized')
    compare.unmaximize()
    await until(() => !compare.isMaximized(), 'window restored')
  }

  for (const [win, name] of [[report, 'report-narrow'], [compare, 'compare-narrow']]) {
    win.setSize(640, 680)
    await until(() => evaluate(win, 'innerWidth <= 640'), 'narrow window resized')
    await delay(200)
    const layout = await checkLayout(win, name)
    assert.equal(layout.descriptionVisible, false)
    if (win === report) assert(layout.titleScrollWidth > layout.titleWidth, 'Long report title must ellipsize')
  }

  // Exercise the native menu on the active child window, including its About dialog.
  let menu
  if (process.platform === 'darwin') {
    const globalMenu = Menu.getApplicationMenu()
    assert.deepEqual(globalMenu.items.map(item => item.label), ['Woody', '编辑', '窗口'])
    menu = globalMenu.items[0].submenu
  } else {
    assert.equal(Menu.getApplicationMenu(), null)
    const popup = Menu.prototype.popup
    let popups = 0
    Menu.prototype.popup = function(options) {
      assert.equal(options.window.id, report.id)
      menu = this
      popups++
      popup.call(this, options)
      setTimeout(() => this.closePopup(options.window), 250)
    }
    report.focus()
    await evaluate(report, "document.querySelector('.window-titlebar__menu').click()")
    await until(() => popups === 1, 'menu click routed to report window')
    await until(() => evaluate(report, "document.querySelector('.window-titlebar__menu').getAttribute('aria-expanded') === 'false'"), 'menu closed')
    report.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'F10' })
    report.webContents.sendInputEvent({ type: 'keyUp', keyCode: 'F10' })
    await until(() => popups === 2, 'F10 opens compact menu')
    await until(() => evaluate(report, "document.querySelector('.window-titlebar__menu').getAttribute('aria-expanded') === 'false'"), 'keyboard menu closed')
    assert.deepEqual(menu.items.filter(item => item.submenu).map(item => item.label), ['编辑', '窗口'])
    Menu.prototype.popup = popup
  }
  const about = menu.items.find(item => item.label === '关于 Woody')
  about.click(about, report, {})
  await until(() => evaluate(report, "!!document.querySelector('[role=dialog]')"), 'About shown in originating report window')
  assert.equal(await evaluate(main, "!!document.querySelector('[role=dialog]')"), false)
  await screenshot(report, 'about-report')
  await evaluate(report, "document.querySelector('.ant-modal-close').click()")
  if (process.platform === 'win32') {
    report.focus()
    report.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'm', modifiers: ['control'] })
    report.webContents.sendInputEvent({ type: 'keyUp', keyCode: 'm', modifiers: ['control'] })
    await until(() => report.isMinimized(), 'Ctrl+M minimizes current window')
    assert.equal(main.isMinimized(), false)
    report.restore()
    report.focus()
    await until(() => !report.isMinimized() && report.isFocused(), 'report restored and focused')
    report.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'w', modifiers: ['control'] })
    await until(() => report.isDestroyed(), 'Ctrl+W closes current report')
    assert(!main.isDestroyed() && !compare.isDestroyed())
  } else report.close()
  assert.deepEqual(errors, [])
  fs.writeFileSync(path.join(evidence, 'result.json'), JSON.stringify({ platform: process.platform, checks, errors, menus: 'pass', childWindowShortcuts: process.platform === 'win32' ? 'pass' : 'native macOS menu retained' }, null, 2))
  console.log(`Window chrome checks passed (${process.platform}). Evidence: ${evidence}`)
  app.exit(0)
}).catch(async error => {
  console.error(error)
  fs.writeFileSync(path.join(evidence, 'failure.txt'), `${error.stack}\n${errors.join('\n')}`)
  for (const win of BrowserWindow.getAllWindows()) await screenshot(win, `failure-${win.id}`).catch(() => {})
  app.exit(1)
})
