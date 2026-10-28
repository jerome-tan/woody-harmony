// 打包后对 macOS 产物做 ad-hoc 重签名。
//
// 背景：npm 解压 electron 会破坏官方签名，electron-builder 无 Developer ID 证书时会跳过签名，
// 导致产物签名「损坏」，被 Gatekeeper 判为「恶意软件」并直接移入废纸篓。
// 这里重新做 ad-hoc 签名，使签名「完整有效」，Gatekeeper 会降级为「无法验证开发者」，
// 用户即可在 系统设置 → 隐私与安全性 中点「仍要打开」，或右键「打开」运行。
const { execFileSync } = require('child_process')
const path = require('path')

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'darwin') return

  const appName = context.packager.appInfo.productFilename
  const appPath = path.join(context.appOutDir, `${appName}.app`)

  console.log(`  • ad-hoc 重签名: ${appPath}`)

  try {
    execFileSync('xattr', ['-cr', appPath], { stdio: 'inherit' })
  } catch {
    // 无扩展属性时报错，可忽略
  }

  // 递归签名嵌套的 Helper.app 与 Framework，并移除时间戳依赖
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', appPath], { stdio: 'inherit' })

  // 校验签名完整性，失败会抛错并中断打包
  execFileSync('codesign', ['--verify', '--deep', '--strict', appPath], { stdio: 'inherit' })
  console.log('  • ad-hoc 签名完成（签名完整有效）')
}
