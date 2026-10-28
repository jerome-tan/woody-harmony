/**
 * 构建信息生成：把当前 git 最新提交与构建机系统信息固化到 src/main/buildInfo.ts，
 * 供「关于」弹窗展示。无 git 仓库（如源码包）时提交字段留空。
 * 已挂到 dev / build / postinstall 脚本，无需手动执行。
 */
const { execSync } = require('child_process')
const os = require('os')
const fs = require('fs')
const path = require('path')

let commit = ''
let commitDate = ''
try {
  commit = execSync('git rev-parse --short HEAD', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim()
  const iso = execSync('git log -1 --format=%cI', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim()
  const d = new Date(iso)
  const pad = (n) => String(n).padStart(2, '0')
  commitDate = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
} catch {
  /* 无 git 仓库时留空 */
}

const buildOs = `${os.type()} ${os.arch()} ${os.release()}`

const content = `// 构建期由 scripts/genBuildInfo.js 生成，请勿手改（已加入 .gitignore）
export const GIT_COMMIT = ${JSON.stringify(commit)}
export const GIT_COMMIT_DATE = ${JSON.stringify(commitDate)}
export const BUILD_OS = ${JSON.stringify(buildOs)}
`
fs.writeFileSync(path.join(__dirname, '..', 'src', 'main', 'buildInfo.ts'), content)
console.log(`[buildInfo] commit=${commit || '(空)'} date=${commitDate || '(空)'} os=${buildOs}`)
