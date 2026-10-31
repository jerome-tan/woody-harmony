// Loads the unchanged production Electron entry point; only device discovery is mocked.
const fs = require('node:fs')
const path = require('node:path')
const { app, BrowserWindow, ipcMain } = require('electron')
const config = JSON.parse(fs.readFileSync(process.env.WOODY_PERF_CONFIG, 'utf8'))
const output = config.output
const profile = path.join(output, 'profile')
fs.mkdirSync(profile, { recursive: true })
for (const name of ['userData', 'sessionData']) app.setPath(name, profile)
fs.writeFileSync(path.join(profile, 'settings.json'), JSON.stringify({ hdcPath: '', sessionsDir: config.fixtures }))
const windows = []
app.on('browser-window-created', (_event, win) => {
  windows.push(win)
  if (windows.length === 1) {
    for (const [channel, value] of Object.entries({ 'hdc:getPath': 'benchmark (offline)', 'device:list': [], 'device:info': null })) {
      ipcMain.removeHandler(channel)
      ipcMain.handle(channel, () => value)
    }
  }
})
const wait = ms => new Promise(resolve => setTimeout(resolve, ms))
const evaluate = (win, expression) => win.webContents.executeJavaScript(expression, true)
async function until(condition) {
  const end = Date.now() + 20000
  while (Date.now() < end) { if (await condition()) return; await wait(20) }
  throw new Error('Electron benchmark ready condition timed out')
}
function mark(phase) { fs.writeFileSync(path.join(output, 'phase.json'), JSON.stringify({ phase, timestamp: Date.now() })) }
require(path.join(__dirname, '../../out/main/index.js'))
app.whenReady().then(async () => {
  const main = windows[0]
  await until(() => !main.webContents.isLoadingMainFrame() && evaluate(main, '!!document.querySelector(".window-titlebar__title")'))
  await evaluate(main, 'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
  fs.writeFileSync(path.join(output, 'ready'), 'ready\n')
  await wait(1000)
  mark('idle'); await wait(3000)
  if (config.mode === 'report') {
    mark('loading')
    await evaluate(main, `window.api.openReportWindow(${JSON.stringify(path.join(config.fixtures, 'benchmark-3600'))})`)
    await until(() => windows.length > 1)
    const report = windows[1]
    await until(() => !report.webContents.isLoadingMainFrame() && evaluate(report, '!!document.querySelector("[_echarts_instance_]")'))
    await wait(2000)
    mark('report-idle'); await wait(3000)
    const rect = await evaluate(report, 'document.querySelector("[_echarts_instance_]").getBoundingClientRect().toJSON()')
    // Match the Qt harness: hover at 40 Hz, alternate wheel direction every 2 s, wheel at 10 Hz.
    mark('interaction')
    const lags = []
    let ticks = 0, previous = performance.now()
    const started = previous
    await new Promise(resolve => {
      const timer = setInterval(() => {
        const now = performance.now()
        lags.push(Math.max(0, now - previous - 25)); previous = now
        const x = Math.round(rect.x + 80 + (rect.width - 110) * (.5 + .4 * Math.sin(ticks * .07)))
        report.webContents.sendInputEvent({ type: 'mouseMove', x, y: Math.round(rect.y + rect.height * .45) })
        if (ticks % 4 === 0) report.webContents.sendInputEvent({ type: 'mouseWheel', x: Math.round(rect.x + rect.width * .55), y: Math.round(rect.y + rect.height * .5), deltaY: Math.floor(ticks / 80) % 2 ? 80 : -80, canScroll: true })
        ++ticks
        if (now - started >= 10000) { clearInterval(timer); resolve() }
      }, 25)
    })
    lags.sort((a, b) => a - b)
    fs.writeFileSync(path.join(output, 'interaction.json'), JSON.stringify({ inputTicks: ticks, elapsedMs: performance.now() - started, mainProcessTimerLagP95Ms: lags[Math.floor((lags.length - 1) * .95)] }, null, 2))
  }
  mark('done'); app.quit()
}).catch(error => { console.error(error); app.exit(2) })
