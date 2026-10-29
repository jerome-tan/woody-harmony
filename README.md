# Woody

[![Build and Release](https://github.com/jerome-tan/woody-harmony/actions/workflows/build.yml/badge.svg)](https://github.com/jerome-tan/woody-harmony/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/jerome-tan/woody-harmony)](https://github.com/jerome-tan/woody-harmony/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

鸿蒙开发调试桌面工具，支持 macOS / Windows。通过 hdc 执行 `hidumper`，提供实时内存趋势、单次快照、持续采样和多报告对比。

## 下载

正式版本在 [Releases](https://github.com/jerome-tan/woody-harmony/releases/latest) 下载；最新开发构建可在 [Actions](https://github.com/jerome-tan/woody-harmony/actions/workflows/build.yml) 的 Artifacts 中下载。构建同时提供安装包和免安装包，免安装包会随后续正式版本发布：

| 平台 | 安装包 | 免安装包 |
| --- | --- | --- |
| macOS Apple Silicon（M 系列） | `Woody-<版本>-mac-arm64.dmg` | `Woody-<版本>-mac-arm64-portable.zip` |
| macOS Intel | `Woody-<版本>-mac-x64.dmg` | `Woody-<版本>-mac-x64-portable.zip` |
| Windows x64 | `Woody-<版本>-win-x64-setup.exe` | `Woody-<版本>-win-x64-portable.exe` |

Windows 免安装版双击 `portable.exe` 运行，无需安装或管理员权限；启动时会解压到临时目录，退出后清理临时程序文件。macOS 免安装版解压 ZIP 后直接打开 `Woody.app`，也可自行移动到常用目录。

免安装版与安装版使用相同的设置和报告保存位置，报告默认仍在用户主目录的 `.woody/reports/`，可在「设置」中更改。程序所在目录不会自动成为数据目录；hdc 仍需按下文配置。

每个正式版本附带 `SHA256SUMS.txt`，覆盖该版本发布的所有安装包和免安装包。macOS 应用使用 ad-hoc 签名，未配置 Apple Developer ID 签名与公证；Windows 程序未配置代码签名，首次运行可能出现系统安全提示。

## 功能

- **设备与应用**：自动探测 hdc，选择设备，查看型号、系统/API 版本、内存、分辨率与应用运行状态。
- **实时内存**：查看 Total PSS 和 GL、Graph、ArkTS heap、native heap 等分类趋势，支持缩放、平移、自动跟随；不落盘、不生成报告。
- **持续采样**：配置采样间隔与时长，默认每秒采样、10 分钟自动结束；保存结构化样本和 hidumper 原文。
- **内存快照**：定格当前进程内存构成，可附加 ashmem、DMA、GPU 明细，以及单独采集 smaps 原文。
- **报告管理**：加载历史、搜索筛选、重命名、删除、打开目录，并在独立窗口查看报告。
- **报告对比**：选择 2～4 份同类型报告，按开始、峰值或结束对齐趋势，也可比较选定采样点和快照分类差异。

## 使用要求

- 本机有可用的 hdc（DevEco Studio 或 HarmonyOS / OpenHarmony SDK 自带）。Woody 会在常见 SDK 目录、`HDC_PATH` 和 PATH 中查找，也可在「设置」中手动指定路径。
- 鸿蒙设备已开启开发者模式 / USB 调试，并完成连接授权。
- smaps 和部分资源明细是否可用，取决于系统版本、应用构建类型及设备权限。

## 使用流程

1. 启动后确认顶部设备信息；必要时在「设置」中配置 hdc 路径。
2. 在「工具集」选择实时内存、持续内存采样或内存快照。
3. 选择目标设备和应用，配置参数并开始采集。
4. 持续采样结束或快照完成后，查看生成的报告；在「查看报告」中选择同类型报告进行对比。

实时查看和持续采样允许在应用尚未启动时开始：此时记录 `pid: null` 的零值占位样本，待手动启动应用后自动采集。Woody 不会自动启动应用。内存快照要求目标应用正在运行。

## 数据保存

默认保存到用户主目录下的 `.woody/reports/`，可在「设置」中修改输出目录。

| 类型 | 内容 |
| --- | --- |
| 持续采样 | `meta.json`、`samples.jsonl`、`raw/` 下每次采集的原始文本 |
| 内存快照 | `meta.json`、`snapshot.json`、hidumper 原始文本；勾选 smaps 后另存 `.smaps.txt` |
| 实时查看 | 仅保留在内存中，不生成文件 |

## 开发

技术栈：Electron 44 · electron-vite · React 18 · TypeScript · Ant Design 5 · ECharts 5。

需要 Node.js **22.12.0 或更高版本**，推荐 Node.js 24（与 GitHub Actions 一致）。

```bash
npm ci
npm run dev
```

```text
src/
├── main/            # hdc、hidumper 解析、采样引擎、存储、IPC、窗口管理
├── preload/         # contextBridge 暴露类型化 window.api
├── shared/          # 主进程与界面的共享类型
└── renderer/src/
    ├── pages/       # 首页、工具流程、报告列表、设置
    ├── components/  # 选择器、趋势图、快照与报告组件
    ├── App.tsx      # 主窗口状态与流程
    ├── ReportApp.tsx
    └── CompareApp.tsx
```

| 命令 | 用途 |
| --- | --- |
| `npm run typecheck` | 主进程与界面的 TypeScript 检查 |
| `npm run build` | 编译到 `out/` |
| `npm run build:unpack` | 生成未压缩应用目录 |
| `npm run build:mac -- --arm64` | macOS Apple Silicon DMG + 免安装 ZIP |
| `npm run build:mac -- --x64` | macOS Intel DMG + 免安装 ZIP |
| `npm run build:win -- --x64` | Windows x64 NSIS 安装包 + Portable EXE |

安装包输出到 `dist/`。macOS 包在 macOS 上构建，Windows 包在 Windows 上构建。打包命令默认不上传任何文件。

前端的 React、Ant Design、ECharts 等依赖由 Vite 打包，放在 `devDependencies`，避免再把完整 `node_modules` 重复装入安装包。以后若主进程或 preload 使用未被打包的运行时依赖，仍需放入 `dependencies`。生产前端启用代码压缩，并自动附带 `THIRD_PARTY_LICENSES.txt`；Electron 运行时、语言资源与功能组件保持完整。DMG 使用 UDBZ 压缩以减少下载体积，挂载和复制时会比默认格式稍慢。

## GitHub Actions 与版本发布

[Build and Release](.github/workflows/build.yml) 在以下场景自动执行三平台构建：

- 推送到 `main`、提交面向 `main` 的 Pull Request，或手动运行工作流：检查类型、编译、打包，验证每个平台的安装包与免安装包均已生成，并在构建摘要显示文件大小；产物保存在 Actions Artifacts 中 14 天。
- 推送 `v*` 标签：额外校验标签与 `package.json` 版本一致；全部构建成功后，汇总 6 个包、生成 SHA-256 校验文件并发布 GitHub Release。

发布任务使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需额外配置个人访问令牌。普通构建只有仓库读取权限，发布任务单独申请 `contents: write`。

后续发布示例（工作区需干净）：

1. 如需自定义说明，先提交 `.github/release-notes/v0.1.1.md`；没有对应文件时自动生成说明。
2. 更新版本并推送：

   ```bash
   npm version 0.1.1
   git push origin main
   git push origin v0.1.1
   ```

如果构建或上传失败，修复后可重跑工作流；未完成的 Release 保持草稿状态。已正式发布的版本不会被工作流覆盖，应使用新版本号发布后续改动。

## macOS 开发环境故障

开发脚本会修改本地 `node_modules/electron/dist/Electron.app` 的名称和图标。如开发运行遭系统拦截，可重新下载并对本机开发副本签名：

```bash
node node_modules/electron/install.js
node scripts/patchElectronName.js
codesign --force --deep --sign - node_modules/electron/dist/Electron.app
xattr -cr node_modules/electron/dist/Electron.app
npm run dev
```

此操作针对本地开发副本；发布包的 ad-hoc 签名由 `scripts/afterPack.js` 完成。

## 许可证

[MIT](LICENSE)
