# Woody Qt R2.1 设计实现验收

本次仅重构 Qt 版本。代码在 `codex/qt-ui-r21`，Electron 源码未改动。
验收对象是实际运行的 Qt Quick 窗口，不是重新绘制的静态效果图。
最终验证代码为 `f4fc8572ae1ec45f2ab4c0eede903a9323c16e0c`，验收日期为 2026-11-03。
本文之后的文档提交不改变该安装包和已验证的应用代码。

## 设计依据与证据

设计入口：`/Users/huawei/.codex/visualizations/2026/10/28/01a182ad-467a-7d12-89ce-c132774adbac/woody-ui-review-r2.1/index.html`。
下表中的设计图片均位于该目录的 `assets/`；运行截图、日志和 JSON 结果位于仓库的 `dist/qt-ui-r21/`。
这些本机证据不提交 Git；CI 同时保存对应验证 artifacts。

| 设计板 | 核对内容 | 实际截图文件名 |
| --- | --- | --- |
| `00-platform.png` | macOS 原生按钮、Windows 单行标题栏与 Help | `native-main.png`、`native-trend.png`；macOS 菜单另用原生菜单/action 验证，见边界说明 |
| `01-tools.png` | 实时查看、快照、持续采样三个独立入口；设备/应用、设置和底部操作 | `watch.png`、`snap.png`、`peak.png`、`live.png` |
| `02-reports.png` | 报告库、选中操作条、列设置、固定操作列 | `reports.png`、`reports-selected.png`、`reports-mixed-selection.png` |
| `03-trend.png` | 单标题、元信息、四项统计、趋势图、分类、显示选项、悬浮框 | `trend.png`、`tooltip.png`、`chart-expanded.png`、`chart-display-options.png` |
| `04-snapshot.png` | 快照统计、条形图/环图、明细切换 | `snapshot.png`、`snapshot-donut.png`、`snapshot-detail.png` |
| `05-compare.png` | 趋势叠加、指标、时间对齐、差异表 | `compare-overlay.png`、`compare-baseline-c.png` |
| `06-points.png` | 小图选点、峰值定位、分类固定、两行差值 | `compare-picked.png`、`compare-fourth-report.png` |
| `07-snapshot-compare.png` | 总量摘要、差值条、分类筛选、独立基准 | `compare-snapshot.png`、`snapshot-declines.png` |
| `08-dialogs.png` | 设置、应用选择、环境信息、重命名、删除 | `settings.png`、`app-picker.png`、`environment.png`、`rename.png`、`delete-confirmation.png` |
| `09-states.png` | 无设备、等待应用、采样/采集状态 | 部署包 `watch.png`、`waiting-app.png`、`live.png`、`snapshot-progress.png` |
| `10-responsive.png` | 1024×680 主窗口，640×480 报告 | `main-minimum.png`、`report-narrow.png`、`narrow-categories.png` |
| `11-four-reports.png` | A/B/C/D 身份与配色不随基准改变 | `compare-baseline-c.png`、`compare-fourth-report.png` |
| `12-interaction-states.png` | 取消采集、退出确认、字段错误、弹出层 | `snapshot-progress.png`、`quit-confirmation.png`、`settings-invalid-path.png`、`about.png` |

## 比较方式与尺寸

设计板是带示例数据的图像概念稿，不包含可执行的数据源、字体文件或 Figma 尺寸标注。
02/03/06 为 1487×1058 px；04/05 为 1485×1059；07 为 1487×1058；11 为 1486×1059；
00/12 为 1513×1039；01/08 为 1500×1049；09 为 1717×916；10 为 1644×957。
组合设计板含多个窗口及说明文字，不能把整张图当成单个应用视口。

实际截图使用 `QQuickWindow::grabWindow()`；`native-*` 使用屏幕抓取，额外核对系统按钮。
本机 Retina 密度为 2：例如 640×480 逻辑视口生成 1280×960 px，1024×680 生成 2048×1360 px。
CI macOS/Windows 截图为 1 倍密度；原生窗口外框可能增加边框像素。
常规主窗口约 1280×820，独立报告 1280×840，对比窗口期望 1440×960；
初始窗口可能被 CI 屏幕工作区约束，因此还明确设置 1024×684 对比窗口进行检查。

比较时把源设计和运行截图放在同一次视觉输入中，并按窗口内容区域及逻辑密度比较。
全图检查信息顺序、主区域比例和视觉层级；标题栏、基准区域、统计条、表头/数值、
弹窗和图表控制区域再单独检查可读性。图像缩放仅用于观察，原始截图保留。
概念板中的中文报告名与运行 fixture 的 `Trend-1` / `Snapshot-1`、设备、曲线、数值不同；
这些不作为像素差异缺陷。本文不宣称逐像素一致或给出虚假的像素相似度。
最终局部对照保存在 `dist/qt-ui-r21/qa-crops/`：`snapshot-source.png` 与
`snapshot-actual.png` 对照总量摘要，`dialog-source.png` 与 `dialog-actual.png`
对照弹窗标题、分组和复制操作。实际截图取自最终 CI，裁切仅用于检查。

## 发现、修复与复查历史

| 优先级 | 发现与影响 | 修复 | 修复后证据 |
| --- | --- | --- | --- |
| P1 | 旧版标题栏、字号和颜色不统一，功能入口混杂 | 共享主题/控件、三个独立入口、单行标题栏，macOS 与 Windows 分别处理系统区域 | `iteration-13/native-main.png` 与 CI Windows `native-main.png` |
| P1 | 图例区域被布局挤到零宽，展开图表 Escape 不工作 | 为分类区分配宽度；修复弹层焦点和返回状态 | `iteration-5/trend.png`、后续 `chart-expanded.png` 及恢复断言 |
| P2 | 快照明细切换期间负索引造成 QML 错误 | 对空/未选状态安全取值，保留完整分类和高级明细 | `iteration-13/snapshot-detail.png`，无 QML 类型错误 |
| P2 | 峰值文字堆叠、尖角、表头与单元格留白不一致 | 只标最高可见峰值的文字，保留各峰值点；圆角连线、统一表头和填充列宽 | `iteration-13/trend.png`、`compare-overlay.png`、`snapshot.png` |
| P1 | 指针进入悬浮框后内容或位置跳动，窗口边缘可能遮挡 | 进入时保留当前样本，背景独立透明，翻转/夹紧位置并允许内部滚动 | `iteration-13/tooltip.png`；进入、离开及窄窗口断言 |
| P1 | PID 消失时把等待态统计为零，会误导分析 | 非测量样本不参与统计与峰值；空图和统计使用“—”，恢复 PID 后继续 | `waiting-app.png`，核心测试和 fake-hdc 重启测试 |
| P1 | 快照采集没有可用的取消闭环 | 增加进度/耗时/取消，取消后不发布半成品报告且可以重试 | `snapshot-progress.png`，后端取消与重试测试 |
| P2 | 设备页面重新加载后选中设备标签为空 | 从当前设备模型直接读取显示文本 | `iteration-13/main-minimum.png` |
| P1 | CI 矮屏中固定差异表高度把趋势图挤成细条 | 差异表高度随窗口调整；极小窗口允许外层纵向滚动 | `ci-2/.../built/compare-compact.png`、`compact-final/compare-minimum.png` |
| P1 | 移向显示选项时，图表悬浮框覆盖开关 | 显示选项/分类弹层打开时隐藏图表悬浮框并清除保留状态 | `ci-2/woody-qt-evidence-mac-x64/qt-evidence/built/chart-display-options.png` |
| P2 | macOS 创建对比页时出现 ColumnLayout height 绑定循环 | 外层改为尺寸独立的 Flickable，避免 ScrollView 隐式尺寸反馈 | `compact-final/application.log`；CI 第三轮三个平台全绿 |
| P1 | 快照对比缺少设计里的 Total 摘要，表格右侧大量空白 | 两份快照专用摘要、差值条、百分比和过滤；多份快照填满表格宽度 | 最终 CI 三平台 `compare-snapshot.png`、`snapshot-declines.png`；总量摘要局部对照 |
| P2 | 无横向溢出仍显示横向滚动条 | 无溢出时明确关闭横向滚动条 | 最终 CI `compare-snapshot.png`；窄窗口仍保留有实际溢出时的滚动 |
| P2 | 环境信息未按设计分组、设备信息重复，重命名缺少字段标签 | 统一弹窗标题区；环境信息按设备/采集分组、逐项复制；补齐标签 | `dialogs-final/environment.png`、`rename.png`，复制后粘贴值断言通过 |
| P1 | 窄窗口悬浮框向上翻转后可能遮住工具栏；模态窗口后仍残留悬浮框 | 悬浮框上边界限制为图表可见区域；模态状态显式抑制悬浮框 | 最终 CI `chart-display-options.png`、`rename.png`；悬浮框进入/保持/离开断言通过 |

测试基础设施另修正了 Windows 路径分隔符导致的选中记录不匹配、Popup 视觉子项查找、
键盘操作前窗口激活，以及无设备状态下先滚动到高级选项再点击。
悬浮框检查使用实际可见的保留内容：指针从图表进入悬浮框后，图表会收到 leave 事件，
因此不能要求图表的瞬时 hover 数据仍存在；仍断言悬浮框可见、14 行完整、进入后保持、离开后关闭。
这些修复没有改变通过条件：仍检查真实控件状态、基准/顺序/配色/缩放/选点不变、
固定列位置、主操作可见、报告不被误删、采集取消后可重试，并拒绝 QML 运行时错误。

本机 `iteration-14/15` 因桌面锁屏而不能满足 `root.active`，不能记为通过。
已读取系统会话确认锁屏，不绕过窗口激活断言；后续完整输入和部署包验证使用 CI 桌面。
锁屏期间的 `compact-final`、`snapshot-final` 仅证明布局渲染/数据绑定，不充当完整交互测试。

## 五类视觉一致性检查

| 检查面 | 结论与处理 |
| --- | --- |
| 字体/排版 | 正文 14、辅助 12、表头 13、页面标题 20；采用平台可用的系统字体回退，修复截断、标题重复与过多说明。不同系统的字形及抗锯齿保留原生差异，不打包字体制造一致性假象。 |
| 间距/布局 | 统一 40 高标题栏、180 宽侧栏、常规 24 边距、16 卡片内边距；窄窗口降低边距与折叠图例，正文不随窗口缩小。主操作固定，长表和明细可滚动。 |
| 颜色/状态 | `Theme.js` 对应 R2.1 淡紫主题：主色 #C4B5FD、选中 #EDE9FE、强调 #5B21B6、文字 #241D35、次级 #665E73、边框 #E7E2EF。差值用暖色增长/蓝色下降，红色用于错误和删除。 |
| 图像/图标 | 使用项目实际 Woody logo；界面图标来自官方 Ant Design outlined SVG 及附带许可证，统一尺寸和着色；图表为真实数据的原生绘制，不用图片代替功能。 |
| 文案/内容 | 去掉侧栏重复品牌、独立窗口冗余说明；按钮直接表达动作。基准有明确名称，数据缺失与数值零区分；进度不伪造百分比，路径错误就地显示。 |

## 验证与边界

- 后端 CTest：历史报告兼容、解析/存储、有效样本统计、hdc 生命周期、取消快照与重试。
- 原生 UI：导航、报告/快照/对比、缩放、悬浮框、透明度、分类、全屏图表、基准选择、四份报告、选点、表格滚动/列设置、重命名/删除取消、小窗口、菜单、关于、等待 PID、采集/退出取消。
- 部署包：隐藏 Qt SDK 后复测；Windows ZIP 解压至含中文和空格的目录；安装版安装、打开、卸载。
- 最终代码 `f4fc857`：[CI 41489181995](https://github.com/jerome-tan/woody-harmony/actions/runs/41489181995)，Windows x64、macOS arm64、macOS x64 三个平台完整通过；最终窗口截图已复查。
- macOS 菜单通过 Cocoa `NSMenu` 枚举确认 `Help/关于 Woody`，并调用其原生 action、断言关于窗口打开。最终 CI 的 `system-menu.png` 仍显示 Finder，不能算作 Woody 系统菜单的视觉证据；原生菜单动作检查与全局菜单截图检查的证明范围不同。
- fake-hdc 与历史 fixture 不代表连接真实 HarmonyOS 设备完成了一轮采集；这次 UI 验收没有新增真机性能或驱动兼容性结论。
- 系统安全弹窗/公证签名、Windows 多显示器和所有缩放比例、辅助技术读屏全流程不在本轮实测范围。

### 最终结果矩阵

| 平台 | CTest | 原生 UI | 隐藏 Qt SDK 后的部署包 | 安装/卸载 |
| --- | --- | --- | --- | --- |
| Windows x64 | 2 套通过 | 119 项通过 | ZIP 98 项、安装后 98 项通过 | 安装、启动、卸载通过；保留无关文件 |
| macOS arm64 | 2 套通过 | 119 项通过 | 98 项通过 | 应用包通过 |
| macOS x64 | 2 套通过 | 119 项通过 | 98 项通过 | 应用包通过 |

以上数量是 UI 场景内的检查步骤数。最终 built/deployed/portable/installed 日志没有
QML `TypeError`、`ReferenceError` 或绑定循环。启动、内存和交互 CPU 采样任务也已完成；
这不等同于真实设备采集性能。证据根目录为
`dist/qt-ui-r21/ci-final/woody-qt-evidence-{win-x64,mac-arm64,mac-x64}/qt-evidence/`，
包含 `ui-result.json`、应用日志、实际截图及 `performance/` 原始测量。

### 可试用安装包

本机 Apple Silicon 安装包使用相同的 `f4fc857` 代码构建，位于 `dist/qt-ui-r21/package/`，
已通过 `codesign --verify --deep --strict`；这是本机签名验证，不代表 Apple 公证。

| 本机产物 | 实际大小 |
| --- | --- |
| `Woody-0.1.0-qt-mac-arm64.dmg` | 32,245,398 bytes / 30.75 MiB |
| `Woody-0.1.0-qt-mac-arm64-portable.zip` | 29,963,535 bytes / 28.58 MiB |
| 展开后的 `Woody.app` | 81,388,758 bytes / 77.62 MiB |

大小、文件组成和 SHA-256 见同目录 `package-sizes.json`。CI artifacts 另提供三平台安装包：
Windows ZIP 27.84 MiB、安装版 17.84 MiB；macOS Intel ZIP 30.42 MiB、DMG 34.44 MiB；
macOS arm64 ZIP 27.70 MiB、DMG 31.04 MiB。不同构建主机的压缩产物大小略有差别。
本次只推送功能分支，未合并 `main`、打版本标签或发布新 Release。

## 后续细节

- P3：概念图的示例字体与系统字形、菜单阴影、原生按钮的像素形状存在平台差异。
- P3：图例在空间充足时直接显示全部分类；窄窗口通过“分类”弹层管理，避免隐藏可用数据。
- P3：时间与大小沿用明确单位和历史精度；概念图示例排版没有强行覆盖真实报告内容。

## 最终检查

- [x] 各窗口主题、入口、标题栏、图表、对比、弹窗完成实现。
- [x] 已发现的 P0/P1/P2 问题已修复并定向复查。
- [x] 最终提交在三个平台完整回归、部署包验证通过。
- [x] 检查最终平台窗口截图，确认无新增 P0/P1/P2 问题；系统菜单截图的证明边界另列。

final result: passed
