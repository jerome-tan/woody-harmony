/**
 * 生成 macOS 图标 build/icon.icns：
 * 用项目内 Electron 把 build/icon.svg 渲染为 iconset 各尺寸 PNG（透明背景），
 * 再由 macOS 自带 iconutil 打包为 icns。logo 变更后执行 `node scripts/buildIcons.js`。
 */
const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..')
const electron = path.join(root, 'node_modules', '.bin', 'electron')
const svg2png = path.join(root, 'scripts', 'svg2png.js')
const svg = path.join(root, 'build', 'icon.svg')
const iconsetDir = path.join(root, 'build', 'icon.iconset')

const SIZES = [
  ['icon_16x16.png', 16],
  ['icon_16x16@2x.png', 32],
  ['icon_32x32.png', 32],
  ['icon_32x32@2x.png', 64],
  ['icon_128x128.png', 128],
  ['icon_128x128@2x.png', 256],
  ['icon_256x256.png', 256],
  ['icon_256x256@2x.png', 512],
  ['icon_512x512.png', 512],
  ['icon_512x512@2x.png', 1024]
]

fs.rmSync(iconsetDir, { recursive: true, force: true })
fs.mkdirSync(iconsetDir, { recursive: true })
for (const [name, size] of SIZES) {
  const out = path.join(iconsetDir, name)
  const r = spawnSync(electron, [svg2png, svg, out, String(size)], { stdio: 'inherit' })
  if (r.status !== 0) process.exit(r.status ?? 1)
}
const r = spawnSync('iconutil', ['-c', 'icns', iconsetDir, '-o', path.join(root, 'build', 'icon.icns')], {
  stdio: 'inherit'
})
if (r.status !== 0) process.exit(r.status ?? 1)
fs.rmSync(iconsetDir, { recursive: true, force: true })
console.log('[icons] build/icon.icns 已生成')
