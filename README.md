# Woody

鸿蒙开发调试工具，基于 Electron，支持 macOS / Windows。通过设备 hdc 接口执行 `hidumper` 采集内存数据：实时趋势、内存快照、持续采样与多报告对比；日志、Trace 等更多调试能力持续扩展中。

## 功能特性

- 展示设备信息：型号名称、型号代码、软件版本、序列号、运行内存、屏幕分辨率；侧栏宽度可拖拽调节
- 查看并选择已连接鸿蒙设备（手机、平板、2in1 等）上的应用列表
- 开始采集前弹出配置：hidumper 采样间隔、是否采集 smaps / ashmem / DMA / GPU 明细、Ability 名称、是否自动启动
- 应用未运行时通过 hdc `aa start` 自动拉起
- 按指定间隔通过 `hidumper --mem pid` 采样，数据落盘保留
- 实时显示内存总量及细分（GL / Graph / ark ts heap / native heap / .so / stack 等）多色趋势线
- 停止后展示完整周期趋势，鼠标悬停显示竖虚线与各分类具体数值，支持缩放
- 打开历史采样目录回看趋势图

## 技术栈

Electron 31 · electron-vite · React 18 · TypeScript · Ant Design 5 · ECharts 5

## 环境要求

- Node.js 20+ 与 npm
- 本机可用的 hdc（DevEco Studio 或 HarmonyOS / OpenHarmony SDK 自带）。工具会自动在常见 SDK 路径、环境变量与 PATH 中查找，也可在右上角「设置」中手动配置 hdc 路径
- 鸿蒙设备已开启开发者模式 / USB 调试并连接

## 目录结构

```
src/
├── main/            # 主进程
│   ├── hdc.ts       # hdc 定位与命令封装
│   ├── hidumper.ts  # hidumper 输出解析
│   ├── sampler.ts   # 采样引擎
│   ├── storage.ts   # JSONL 落盘 / 历史加载
│   ├── ipc.ts       # IPC handlers
│   └── index.ts     # 窗口入口
├── preload/         # contextBridge 桥接
├── shared/          # 主/渲染进程共享类型
└── renderer/        # React UI（设备面板 / 应用列表 / 配置弹窗 / 趋势图）
```

## 安装

```bash
npm install
```

## 开发运行

```bash
npm run dev
```

## 编译与打包

| 命令 | 说明 |
| --- | --- |
| `npm run typecheck` | TypeScript 类型检查 |
| `npm run build` | 编译主进程 / 预加载 / 渲染进程到 `out/` |
| `npm run build:unpack` | 打包为未压缩的应用目录（`dist/`） |
| `npm run build:mac` | 打包 macOS DMG（生成于 `dist/`） |
| `npm run build:win` | 打包 Windows NSIS 安装包（建议在 Windows 上执行） |

## 使用说明

1. 启动后自动检测并选中设备，或在「目标设备」下拉框中选择；如 hdc 未自动定位，在右上角「设置」中填写 hdc 路径后保存。
2. 在应用列表点击「刷新」，选中目标应用。
3. 点击「开始采集」，在弹窗中配置采样间隔、是否采集 smaps / ashmem / DMA / GPU 明细、Ability 名称、是否自动启动。
4. 采样过程中实时查看趋势图；点击「停止采集」后展示完整周期趋势。
5. 鼠标在图表上移动时显示竖虚线与各分类数值。
6. 点击「打开历史」选择之前保存的采样目录即可回看。

## 数据保存

每次采样的数据保存在 `~/.woody/reports/<bundleName>-<时间戳>/` 目录下（可在设置页自定义）：

- `meta.json`：会话元信息（设备、应用、配置、起止时间、采样点数）
- `samples.jsonl`：每个采样点一行 JSON

## 注意事项

- `hidumper --mem-smaps` 仅 **debug 版应用** 支持；采集到的 smaps 原始文本保存于样本的 `smapsRaw` 字段，趋势图仍基于 `--mem` 的分类汇总。
- macOS 未配置 Apple Developer ID 证书时，`electron-builder` 会跳过签名；本项目已通过 `afterPack` 钩子对产物做 **ad-hoc 签名**，使签名完整有效。`dmg` 安装后首次打开会提示「无法验证开发者」，用户需在 系统设置 → 隐私与安全性 中点「仍要打开」（或右键 → 打开）。要彻底消除提示，需 Apple Developer ID 证书 + 公证（$99/年）。

## 常见问题

### macOS 提示「已阻止恶意软件并移到废纸篓，未打开 Electron.app」

macOS Gatekeeper 会拦截签名失效的 Electron 二进制（`npm install` 解压会破坏官方签名，且文件带 `com.apple.quarantine` 隔离属性），随后 `npm run dev` 会报 `spawn .../Electron.app/.../Electron ENOENT`。

修复（重新下载二进制 + ad-hoc 重签名 + 移除隔离属性）：

```bash
node node_modules/electron/install.js
codesign --force --deep --sign - node_modules/electron/dist/Electron.app
xattr -cr node_modules/electron/dist/Electron.app
```

执行后再运行 `npm run dev` 即可。若重装依赖或删除 `node_modules/electron/dist` 后再次遇到，重复上述命令。

### dmg 安装后提示「已阻止恶意软件」/「无法验证开发者」

这是 macOS 的 **Gatekeeper** 安全机制，涉及两个概念：

- **代码签名**：用证书证明「应用来自谁、未被篡改」。
- **公证（Notarization）**：Apple 扫描应用确认无恶意内容后盖章。
- **Gatekeeper**：运行时校验签名与公证。

拦截行为分两种，取决于签名是否**完整**：

| 状态 | 表现 | 能否绕过 |
| --- | --- | --- |
| 签名**损坏**（`codesign --verify` 失败） | 「已阻止恶意软件」并直接移到废纸篓 | 不能点允许 |
| 签名**完整**但非 Apple 证书（ad-hoc/自签名） | 「无法验证开发者」 | 可右键 → 打开，或 系统设置 → 隐私与安全性 → 仍要打开 |

本项目通过 `afterPack` 钩子对产物做 ad-hoc 签名，保证签名完整，因此属于第二种，可手动放行。

临时放行（本机一次性）：

```bash
xattr -cr "/Applications/HarmonyOS Memory Tools.app"
```

或右键点击应用 → 打开 → 点「打开」。

彻底消除提示（他人机器无感安装）：需注册 [Apple Developer Program](https://developer.apple.com/programs/)（$99/年），配置 Developer ID Application 证书 + 公证，再填写 `electron-builder.yml` 的 `mac.identity` 与 `mac.notarize` 相关配置。
