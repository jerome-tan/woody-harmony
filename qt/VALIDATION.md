# Qt 6.12.0 迁移验证

验证日期：2026-10-31。分支：`codex/qt-6.12.0`。原生实现为 C++20 + Qt Quick；图表由 Qt 原生绘制，不依赖 WebEngine、Qt Charts、Qt Graphs 或 Node.js。

本报告区分功能回归、部署验证和性能测量。自动化通过不等于所有硬件、系统版本和实际设备场景均已验证。

## 来源与复现

- Electron 参考代码：`4e562bb913a31239bed89b137eaf6877330cce30`；本分支保留的 `src/` 与该提交一致。运行时 Electron 44.4.4。
- Electron 包体积：[原版 Actions 41014290111](https://github.com/jerome-tan/woody-harmony/actions/runs/41014290111)。读取各 Artifact ZIP 中程序文件的大小，不计 GitHub 外层 ZIP。
- Qt 跨平台验证：[Actions 41161710090](https://github.com/jerome-tan/woody-harmony/actions/runs/41161710090)，代码提交 `393ba6b7c0fa3ca6a5ab07561f40cca3730e75c2`。
- 本机 macOS 测量：Apple M5、32 GiB、macOS 26.6.2、arm64；本机受测安装包提交 `91fd861`。另保留 `430dff4` 的较早一批数据观察波动；两者应用业务代码一致，期间改动为测试工具和 CI。最终 `393ba6b` 另修正 Windows 顶栏选项，macOS 窗口选项不变。
- 复现命令见 [构建与测量说明](README.md)。持久化的测量摘要位于 [validation/](validation/)；完整逐次采样、测试日志和截图在 Actions 的 `woody-qt-evidence-*` 中，保留 14 天。

## 包体积

单位均为十进制 MB，即字节数除以 1,000,000。展开大小统计普通文件，不计符号链接、目录及文件系统开销。Qt 包包含所需动态库、QML、插件和许可文件，不要求用户安装 Qt。

| 产物 | Electron | Qt | 减少 |
| --- | ---: | ---: | ---: |
| Windows x64 安装 EXE | 114.92 MB | 18.63 MB | 83.8% |
| Windows x64 ZIP | 153.73 MB | 29.09 MB | 81.1% |
| macOS arm64 DMG | 117.82 MB | 32.24 MB | 72.6% |
| macOS arm64 ZIP | 124.68 MB | 28.93 MB | 76.8% |
| macOS Intel DMG | 122.31 MB | 35.81 MB | 70.7% |
| macOS Intel ZIP | 130.10 MB | 31.78 MB | 75.6% |

Qt 展开大小：Windows x64 **78.02 MB**；macOS arm64 **81.52 MB**；macOS Intel **85.70 MB**。

本机 M5 构建的 DMG 为 **32.06 MB**、ZIP 为 **29.85 MB**，展开 **81.09 MB**；与 CI 的编译器、SDK 和压缩环境不同，因此字节数不完全相同。各自的精确字节数及 SHA-256 独立保存。

macOS 包按 arm64 / x86_64 分开裁剪架构。Windows ZIP 是完整程序目录，解压即可运行；同时保留 NSIS 安装版。Qt 运行库为动态链接，未对 SDK 库做功能裁剪。

## 性能

两版使用同一份 3,600 个样本、13 个分类的历史报告。每种运行时分别启动主窗口和报告场景各三次；报告交互持续 10 秒，发送 400 次鼠标移动、100 次滚轮输入。统计整个应用进程树，包括 Electron 的渲染、GPU 等子进程。

下表取各轮阶段平均值的中位数；启动取每种运行时六次启动的中位数。启动为文件缓存未清空的进程启动，约 50 ms 采样间隔，不是磁盘冷启动。CPU 100% 表示一个逻辑核心。

### Apple M5 本机

| 指标 | Electron | Qt |
| --- | ---: | ---: |
| 启动到主窗口就绪 | 544 ms | 362 ms |
| 主窗口静置 RSS | 543.98 MB | 194.33 MB |
| 报告静置 RSS | 921.44 MB | 286.39 MB |
| 图表交互 RSS | 1,090.20 MB | 310.45 MB |
| 主窗口静置 CPU | 2.18% | 1.16% |
| 报告静置 CPU | 0.30% | 2.06% |
| 图表交互 CPU | 59.95% | 52.67% |

本批图表交互 RSS 下降约 72%，CPU 下降约 12%。较早一批同负载的交互 RSS 为 1,067.77 / 310.97 MB，CPU 为 64.14% / 51.58%，改善方向一致。

启动波动较大：最终一批为 544 / 362 ms，较早一批为 417 / 442 ms，因此不能据此声称 macOS 启动稳定变快。报告静置 CPU 也更高，不能声称 Qt 在每个场景都更快或更省电。就绪信号分别为 Qt 首次 `frameSwapped` 和 Electron 页面加载后的双 `requestAnimationFrame`，不是输入到显示延迟测量。

### GitHub 托管 runner

同一平台的两种运行时在同一任务中交替测量。以下均为该任务的三轮结果，不能拿不同平台行直接比较硬件性能。

| 平台 / 运行时 | 启动 | 报告静置 RSS | 交互 RSS | 报告静置 CPU | 交互 CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Windows x64 / electron | 548 ms | 573.06 MB | 737.03 MB | 0.00% | 130.01% |
| Windows x64 / qt | 268 ms | 202.72 MB | 215.48 MB | 0.00% | 92.69% |
| macOS arm64 / electron | 1143 ms | 779.20 MB | 958.24 MB | 1.51% | 124.06% |
| macOS arm64 / qt | 1029 ms | 235.24 MB | 253.83 MB | 0.62% | 45.19% |
| macOS Intel / electron | 2148 ms | 652.10 MB | 814.31 MB | 0.50% | 135.08% |
| macOS Intel / qt | 1243 ms | 188.48 MB | 205.24 MB | 0.51% | 83.56% |

Windows 交互阶段私有工作集中位数为 **304.82 MB → 173.36 MB**，约减少 43%；这项与 RSS 分开列示，不把共享页重复统计产生的差额视为物理内存节省。

RSS 对共享内存页可能重复计数，不能把差值直接当作系统物理内存节省值。Windows 另记录私有工作集 USS；macOS 不在计时期间遍历 Mach VM 页面，以免测量本身阻塞。Qt GUI 线程与 Electron 主进程的定时器延迟只作诊断，不可互相比作帧率或输入到显示延迟。云端 runner 的硬件、GPU 和调度情况不同，不能与本机数据横向比较。

## 功能与部署回归

以下是迁移范围；具体自动化覆盖以测试结果中的逐项记录为准。

| 范围 | 迁移内容 |
| --- | --- |
| 数据兼容 | 原有报告目录、`meta.json`、`samples.jsonl`、快照格式和设置迁移；报告重命名、搜索、删除及目录操作 |
| 采集 | 设备/应用查询、应用未启动零值占位、PID 变化、周期采样、实时查看不落盘、自动结束、取消及退出时完成报告 |
| 快照 | 内存分类、十列内存数值、native heap、ashmem / DMA / GPU 明细及 smaps 原文 |
| 图表 | 精确样本、悬浮框及透明度、曲线/采样点开关、滚轮缩放/平移、范围选择、实时跟随、图表展开与 Escape 还原 |
| 多报告 | 独立窗口、2～4 份同类对比、开始/峰值/结束对齐、指标切换、稳定颜色、隐藏序列、采样点选取及快照差异 |
| 表格 | 排序、调整列宽、列顺序、固定列及设置持久化 |
| 平台窗口 | 单行顶栏、macOS 原生菜单/系统按钮、Windows 应用菜单/原生系统按钮、当前窗口最小化/关闭/退出快捷键 |
| 部署 | 打包后移走构建 SDK 再运行验证，排除 SDK DLL/插件兜底；macOS 分架构部署和签名检查；Windows 中文/空格路径 ZIP 启动、安装启动、卸载且保留非程序用户文件 |

`CoreTest` 与 `BackendTest` 覆盖解析、存储和 hdc 生命周期。UI 回归使用实际 Qt 鼠标、滚轮和键盘事件：构建目录含模拟 hdc 的场景 48 步，部署后场景 44 步。测试结果和截图逐项留档。macOS 另人工检查原生菜单、系统按钮和正常退出。

最终运行三个平台全部成功：每个平台两套后端测试及 48 步构建目录 UI 回归通过；macOS 两种架构各通过 44 步部署回归，Windows ZIP 与安装版各通过 44 步回归，安装/卸载检查也通过。汇总见 [ci-checks.json](validation/ci-checks.json)。

本地重复测试曾发现悬浮框进入/退出断言偶发失败；测试工具只注入了 Qt 事件，未同步系统游标。界面回归现在同步两者，完整回归和连续五轮定向复测均通过。性能模式保持这一功能关闭，与 Electron 的注入输入方式一致。

Windows 额外保存桌面上的完整窗口截图，因为 Qt 的客户端截图不包含平台顶栏叠加层。根据 [Qt 6.12 Windows 后端](https://github.com/qt/qtbase/blob/v6.12.0/src/plugins/platforms/windows/qwindowswindow.cpp) 的 `updateCustomTitlebar()`，使用 `CustomizeWindowHint`，显式保留最小化、最大化、关闭按钮，并省略 `WindowTitleHint`，避免平台标题文字/图标与 QML 顶栏重叠。窗口标题本身仍保留，供任务栏与辅助功能使用。

已核对修正后的 [Windows 主窗口](validation/screenshots/windows-main.png) 与 [报告窗口](validation/screenshots/windows-report.png)。截图使用模拟设备和固定报告数据，包含客户端截图中缺失的平台按钮层；runner 桌面分辨率限制了底部显示范围。

## 尚未证明的范围

- 本次没有连接可用的 HarmonyOS 设备，`hdc list targets` 返回 `[Empty]`。采集流程使用可控制的模拟 hdc 验证；真实设备、不同 hidumper 输出版本、USB 断连及设备权限仍需要真机验收。
- 已按原版页面、布局、配色、报告结构和交互迁移，并以截图和交互回归核对。Qt 与浏览器的文字、图标和曲线抗锯齿存在渲染差异，不宣称逐像素完全一致。
- Qt 6.12 SDK 的系统基线为 macOS 14.4+、Windows 10 1809+ / 11 x64。CI 验证 macOS 15 两种架构及 Windows Server 2022，未覆盖每个最低版本和显卡组合。
- 性能结果来自固定历史报告负载；不代表实时设备采集、长时间运行、最大规模报告、耗电量或峰值 GPU 内存的结果。
- macOS 使用 ad-hoc 签名，未做 Developer ID 公证；Windows 未配置代码签名。本分支产物在 Actions 下载，未覆盖或重新发布原有 v0.1.0 Release。
