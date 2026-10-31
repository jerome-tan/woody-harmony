# Woody

[![Native Qt build](https://github.com/jerome-tan/woody-harmony/actions/workflows/qt.yml/badge.svg?branch=codex%2Fqt-6.12.0)](https://github.com/jerome-tan/woody-harmony/actions/workflows/qt.yml)
[![Release](https://img.shields.io/github/v/release/jerome-tan/woody-harmony)](https://github.com/jerome-tan/woody-harmony/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

鸿蒙开发调试桌面工具，支持 macOS / Windows。通过 hdc 执行 `hidumper`，提供实时内存趋势、单次快照、持续采样和多报告对比。

本分支为 **Qt 6.12.0 原生版**，使用 C++20 / Qt Quick。保留原 Electron 源码用于功能与性能对照；Qt 安装包不包含 Electron、Chromium、Node.js 或 WebEngine。

迁移范围、实际包体积、三轮性能对照和验证边界见 [Qt 验证报告](qt/VALIDATION.md)。

## 下载

Qt 分支构建在 [Native Qt Actions](https://github.com/jerome-tan/woody-harmony/actions/workflows/qt.yml) 的 Artifacts 下载。已发布的 [v0.1.0 Release](https://github.com/jerome-tan/woody-harmony/releases/tag/v0.1.0) 仍是 Electron 版；本次迁移不覆盖它。

`woody-qt-package-<平台>-<架构>` 包含安装包和免安装 ZIP；`woody-qt-evidence-*` 包含截图、测试结果、体积明细和性能原始数据。

| 平台 | 安装包 | 免安装包 |
| --- | --- | --- |
| macOS Apple Silicon（M 系列） | `Woody-<版本>-qt-mac-arm64.dmg` | `Woody-<版本>-qt-mac-arm64-portable.zip` |
| macOS Intel | `Woody-<版本>-qt-mac-x64.dmg` | `Woody-<版本>-qt-mac-x64-portable.zip` |
| Windows x64 | `Woody-<版本>-qt-win-x64-setup.exe` | `Woody-<版本>-qt-win-x64-portable.zip` |

Windows 免安装版是完整程序目录的 ZIP：将 ZIP 全部解压到独立文件夹，再双击其中的 `Woody.exe`，无需安装或管理员权限，也无需每次启动时临时解压。请保留同目录的 `qml/`、插件、DLL 等文件，不能只复制 `Woody.exe`。macOS 免安装版解压 ZIP 后直接打开 `Woody.app`，也可自行移动到常用目录。

从 Actions 下载时，Artifact 的外层 ZIP 内还包含上述免安装 ZIP，需要继续解压；从 Release 下载则直接获得程序 ZIP。

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

- Windows 10 1809+ / Windows 11（x64），或 macOS 14.4+（Apple Silicon / Intel）。这是所选 Qt 6.12 SDK 的系统基线。

- 本机有可用的 hdc（DevEco Studio 或 HarmonyOS / OpenHarmony SDK 自带）。Woody 会在常见 SDK 目录、`HDC_PATH` 和 PATH 中查找，也可在「设置」中手动指定路径。
- 鸿蒙设备已开启开发者模式 / USB 调试，并完成连接授权。
- smaps 和部分资源明细是否可用，取决于系统版本、应用构建类型及设备权限。

## 使用流程

1. 启动后确认顶部设备信息；必要时在「设置」中配置 hdc 路径。
2. 在「工具集」选择实时内存、持续内存采样或内存快照。
3. 选择目标设备和应用，配置参数并开始采集。
4. 持续采样结束或快照完成后，查看生成的报告；在「查看报告」中选择同类型报告进行对比。

实时查看和持续采样允许在应用尚未启动时开始：此时记录 `pid: null` 的零值占位样本，待手动启动应用后自动采集。Woody 不会自动启动应用。内存快照要求目标应用正在运行。

主窗口、报告窗口和对比窗口使用统一的单行顶栏。macOS 保留左上角系统按钮和屏幕顶部菜单；Windows 在顶栏左侧提供应用菜单按钮（也可按 `Alt` 或 `F10` 打开），右侧保留系统最小化、最大化、关闭按钮。编辑、窗口和关于操作作用于当前窗口，Windows 支持 `Ctrl+W` 关闭当前窗口、`Ctrl+M` 最小化、`Ctrl+Q` 退出应用。

## 数据保存

默认保存到用户主目录下的 `.woody/reports/`，可在「设置」中修改输出目录。

| 类型 | 内容 |
| --- | --- |
| 持续采样 | `meta.json`、`samples.jsonl`、`raw/` 下每次采集的原始文本 |
| 内存快照 | `meta.json`、`snapshot.json`、hidumper 原始文本；勾选 smaps 后另存 `.smaps.txt` |
| 实时查看 | 仅保留在内存中，不生成文件 |

## 开发

使用 Qt **6.12.0**、CMake 3.24+、C++20 编译器；macOS 使用 Apple Clang，Windows 使用 MSVC 2022。

```bash
python qt/scripts/install-qt.py --output dist/qt-sdk
cmake -S . -B dist/qt-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$PWD/dist/qt-sdk/6.12.0/macos" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4
cmake --build dist/qt-build --parallel
ctest --test-dir dist/qt-build --output-on-failure
```

Windows 构建器使用 `-G "Visual Studio 17 2022" -A x64`，Qt 路径指向 `6.12.0/msvc2022_64`，构建加 `--config Release`，测试加 `-C Release`。

原生代码位于 `qt/src/`，界面位于 `qt/qml/`，测试位于 `qt/tests/`。打包、交互回归和性能测试步骤见 [Qt 构建说明](qt/README.md)。应用、安装程序与发布标签统一读取根目录 `package.json` 的版本号。

原 Electron 代码仍位于 `src/`，使用 `npm ci && npm run dev` 运行，`npm run build` 生成性能对照所用的生产构建。其工作流仅支持手动运行，不参与本分支的自动发布。

## GitHub Actions 与版本发布

[Native Qt build and validation](.github/workflows/qt.yml) 自动构建 Windows x64、macOS arm64 和 macOS Intel：

- 推送 `main`、`codex/qt-*`，或提交面向 `main` 的 PR：编译、后端测试、原生界面回归、打包、部署后回归，以及三轮 Electron / Qt 性能对照。
- Windows 额外验证中文路径下 ZIP 解压启动、安装版启动和卸载保留用户文件。
- 推送 `v*` 标签：必须与 `package.json` 版本一致；三平台全部成功后，发布六个 Qt 包和 `SHA256SUMS.txt`。
- 普通分支推送只产生 Actions Artifacts，不发布 Release。Artifacts 保留 14 天。

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

## 许可证

[MIT](LICENSE)。Qt 动态库及其第三方组件的许可说明随包附带，见 [qt/licenses](qt/licenses)。
