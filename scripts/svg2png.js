/**
 * SVG → 透明背景 PNG 转换（利用项目内 Electron 离屏渲染，避免 qlmanage 垫白底）。
 * 用法：node_modules/.bin/electron scripts/svg2png.js <in.svg> <out.png> [size]
 */
const { app, BrowserWindow } = require('electron')
const fs = require('fs')

const [, , svgPath, pngPath, sizeStr] = process.argv
if (!svgPath || !pngPath) {
  console.error('usage: electron scripts/svg2png.js <in.svg> <out.png> [size]')
  process.exit(1)
}
const size = Number(sizeStr || 1024)

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: size,
    height: size,
    show: false,
    frame: false,
    transparent: true,
    webPreferences: { offscreen: true }
  })
  try {
    const svg = fs.readFileSync(svgPath, 'utf8')
    const sized = svg.replace('<svg ', `<svg width="${size}" height="${size}" `)
    await win.loadURL(
      'data:text/html;charset=utf-8,' +
        encodeURIComponent(`<body style="margin:0;background:transparent">${sized}</body>`)
    )
    const img = await win.webContents.capturePage()
    fs.writeFileSync(pngPath, img.toPNG())
    console.log(`[svg2png] ${pngPath} (${size}x${size})`)
  } finally {
    win.destroy()
    app.quit()
  }
})
