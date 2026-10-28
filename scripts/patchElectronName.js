/**
 * 开发模式下修正 macOS 菜单栏 / 关于面板显示的应用名与图标。
 * macOS 从应用包 Info.plist 的 CFBundleName / CFBundleDisplayName 读取菜单栏名称、
 * 关于面板图标取自应用包的 electron.icns，运行时 app.setName() 均无法改变；
 * 开发模式跑的是 node_modules 里的 Electron.app，因此直接改写其 Info.plist 并替换图标。
 * 仅影响本地开发环境，重新安装 electron 后需重新执行（已挂到 postinstall 与 dev 脚本）。
 * 打包产物由 electron-builder 依据 productName 与 build/icon.icns 生成，不受影响。
 *
 * 注意：新版 macOS 对带有 com.apple.provenance 的 .app 包有「App 管理」写保护，
 * 直接改写会 EPERM，此时回退为「移走原包 → 拷贝出无保护副本 → 打补丁 → 放回原位」。
 */
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const APP_NAME = 'Woody'

// CI 只构建安装包，跳过开发环境专用的 Electron.app 修改与 LaunchServices 注册。
if (process.platform !== 'darwin' || process.env.CI) process.exit(0)

const distDir = path.join(__dirname, '..', 'node_modules', 'electron', 'dist')
const appDir = path.join(distDir, 'Electron.app')
const plistPath = path.join(appDir, 'Contents', 'Info.plist')
if (!fs.existsSync(plistPath)) process.exit(0)

// 关于面板 / Finder 显示的图标（dev 下默认是 Electron 自带的 electron.icns）
const iconSrc = path.join(__dirname, '..', 'build', 'icon.icns')
const patchIcon = (appDirPath) => {
  const dst = path.join(appDirPath, 'Contents', 'Resources', 'electron.icns')
  if (!fs.existsSync(iconSrc) || !fs.existsSync(dst)) return false
  fs.copyFileSync(iconSrc, dst)
  return true
}

const patch = (file) => {
  const content = fs.readFileSync(file, 'utf8')
  const replaceEntry = (xml, key) =>
    xml.replace(new RegExp(`(<key>${key}</key>\\s*<string>)[^<]*(</string>)`), `$1${APP_NAME}$2`)
  const next = replaceEntry(replaceEntry(content, 'CFBundleName'), 'CFBundleDisplayName')
  if (next === content) return false
  fs.writeFileSync(file, next)
  return true
}

const report = (renamed, iconPatched, suffix = '') => {
  const parts = [renamed && `菜单栏应用名已改为「${APP_NAME}」`, iconPatched && '图标已替换'].filter(Boolean)
  if (parts.length) console.log(`[patch] Electron.app ${parts.join('，')}${suffix}`)
}

// 刷新 LaunchServices 注册缓存，否则 Dock 悬停 tooltip / Finder 仍显示旧名（Electron）
const refreshLaunchServices = () => {
  spawnSync(
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
    ['-f', appDir]
  )
}

try {
  const renamed = patch(plistPath)
  const iconPatched = patchIcon(appDir)
  report(renamed, iconPatched)
  if (renamed || iconPatched) refreshLaunchServices()
  process.exit(0)
} catch {
  // 落入 macOS App 管理写保护，走迂回方案
}

const backupDir = path.join(distDir, '.Electron.app.orig')
const stagedDir = path.join(distDir, '.Electron.app.staged')
try {
  fs.rmSync(backupDir, { recursive: true, force: true })
  fs.rmSync(stagedDir, { recursive: true, force: true })
  fs.renameSync(appDir, backupDir)
  fs.cpSync(backupDir, stagedDir, { recursive: true }) // 副本不带 provenance，可写
  const renamed = patch(path.join(stagedDir, 'Contents', 'Info.plist'))
  const iconPatched = patchIcon(stagedDir)
  fs.renameSync(stagedDir, appDir)
  fs.rmSync(backupDir, { recursive: true, force: true })
  report(renamed, iconPatched, '（迂回方案）')
  refreshLaunchServices()
} catch (err) {
  // 失败不阻塞 dev 启动，仅提示手动处理方式
  console.warn(`[patch] 修改 Electron.app 应用名/图标失败：${err.message}`)
  console.warn('[patch] 可在 系统设置 → 隐私与安全性 → App 管理 中授权终端后，重新执行 node scripts/patchElectronName.js')
  for (const dir of [stagedDir, backupDir]) {
    if (fs.existsSync(dir) && !fs.existsSync(appDir)) fs.renameSync(dir, appDir)
  }
}
