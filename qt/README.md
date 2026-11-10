# Woody native Qt edition

Woody uses C++20, Qt 6.12.0, and Qt Quick. This is the only maintained runtime;
building and packaging do not require Node.js or npm. See the
[historical migration measurements and validation boundaries](VALIDATION.md).

The R2.1 UI uses the lavender theme, independent live/snapshot/recording entries,
platform-aware titlebars, and explicit comparison baselines that preserve report
identities, colors and selected samples. See the [design QA report](../design-qa.md)
for native screenshots, fixes, responsive states and validation boundaries.

## Compare reports and export an image

Sampling comparisons open with stacked charts on the left and the category
table on the right. Two to four reports share the scrollable chart column; drag
the vertical divider to change its width, or expand an individual chart to inspect and select a sample. The table keeps
its header and category column fixed while scrolling.

Choose **设为基准** on a report card to move it and its table column first,
keeping its letter, color and sample selection. **当前基准** marks that report.
Unchecking another report hides its chart, table column/summary row and export
content; its collapsed card remains available to restore it. The current baseline
stays selected until another report becomes the baseline.

Each comparison cell uses one line, for example `1.22 GB (+104.0 MB)`.
The absolute value stays prominent; the smaller parenthesized delta is red for
increased memory and green for decreased memory. Category differences omit percentages.

Choose **一键截图 → 复制图片 / 另存为…** to generate a complete PNG containing
the charts and table. It renders the selected reports over their full time range
and every row in the current table filter/sort order, including rows outside the
window. The current sample selection, baseline, and overlay metric/alignment are
preserved. Window size, scrolling, and chart zoom do not crop the export. PNG
width is 2880 pixels; height grows with the content. Snapshots export
their complete comparison table. Saving uses the system file dialog.

## Build

For local builds, prefer the cross-platform driver at the repository root:

```sh
python3 build.py                 # macOS (native Apple Silicon or Intel)
# py -3 build.py                 # Windows x64; regular PowerShell/cmd works
python3 build.py --check         # preflight only; does not download or build
python3 build.py --jobs 8
python3 build.py --skip-installer # keep tests and ZIP; omit DMG/NSIS installer
python3 build.py --skip-tests     # omit test compilation and execution; still package
python3 build.py --skip-tests --skip-installer # quick local build with ZIP only
python3 build.py --qt /absolute/path/to/Qt/6.12.0/macos
```

On Windows replace `python3` with `py -3`, and use the `msvc2022_64` kit
for `--qt`. The driver checks system prerequisites, downloads and verifies the
pinned official Qt SDK if missing, configures Release with tests enabled by default, builds,
runs all CTest groups, and packages only after successful tests. It stops on the
first failure and returns a nonzero exit code. No device is required for CTest;
the hdc lifecycle tests use an isolated simulated device.

For faster local builds, `--skip-tests` sets `BUILD_TESTING=OFF` and skips CTest,
while still compiling and packaging the application. It applies only to that
invocation: running without the flag explicitly restores `BUILD_TESTING=ON`
and runs tests again. The completion message indicates when tests were skipped.
GitHub Actions continues to run tests.

Python 3.10+ on macOS (3.9+ on Windows), Git and CMake 3.24+ must be on PATH. macOS also needs Xcode Command
Line Tools and Ninja. Windows needs Visual Studio/Build Tools 2022 with desktop
C++ (MSVC v143), a Windows 10/11 SDK, 7-Zip for SDK extraction, and NSIS 3 for the
installer (`--skip-installer` removes the NSIS requirement). System tools are
checked, not installed automatically. macOS DMG packaging automatically prepares
`dmgbuild` and its dependencies in `dist/dmg-tools`, using pinned versions and
verified wheel hashes; no global pip packages or Finder automation permission
are needed. This first-time setup requires network access. Existing complete kits skip SDK download
and extraction. `--check` with no SDK validates bootstrap prerequisites and
reports that the real build will download Qt; it does not test network access.

All paths are anchored to the repository, even when invoked from another working
directory. The driver reuses `dist/qt-build.noindex`, `dist/qt-sdk` and
`dist/qt-package`; it does not create per-build app copies, launch the app, or
publish to GitHub. Exit the packaged Woody app before rebuilding. An incompatible
CMake cache produces an actionable error rather than being deleted automatically.
Remove only `dist/qt-build.noindex` when switching kits/generators/architectures.
Old packages may remain after a failure; only the final success message confirms
a newly completed build. See the [Chinese quick start](../README.md#开发).

The commands below are the equivalent manual steps for advanced use.

Install Qt **6.12.0 exactly**, with Qt Base, Declarative, SVG, Tools, Shader Tools,
and Translations. `scripts/install-qt.py` downloads the official SDK, checks
archive hashes, and supports Qt 6.12's nested repository layout.

```sh
python qt/scripts/install-qt.py --output dist/qt-sdk
cmake -S . -B dist/qt-build.noindex -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/absolute/path/to/Qt/6.12.0/macos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4
cmake --build dist/qt-build.noindex --parallel
ctest --test-dir dist/qt-build.noindex --output-on-failure
```

On Windows use MSVC 2022, generator `Visual Studio 17 2022`, `-A x64`, and the
`msvc2022_64` Qt kit. Build and test with `--config Release` / `-C Release`.
On macOS explicitly select `-DCMAKE_OSX_ARCHITECTURES=arm64` or `x86_64`.
Qt 6.12 requires macOS 14.4 or newer; Windows targets Windows 10 1809+ and 11.

## Run and validate

```sh
python qt/scripts/generate-fixtures.py dist/qt-fixtures
python qt/scripts/ui-smoke.py \
  --exe dist/qt-build.noindex/qt/Woody.app/Contents/MacOS/Woody \
  --hdc dist/qt-build.noindex/qt/woody_fake_hdc \
  --fixtures dist/qt-fixtures --output dist/qt-evidence
python qt/scripts/package.py --build dist/qt-build.noindex \
  --qt /absolute/path/to/Qt/6.12.0/macos \
  --arch arm64
```

Local iterations always reuse `dist/qt-build.noindex` for intermediate builds
and `dist/qt-package` for the current app and installers. `package.py` defaults
to this fixed output directory and replaces its staging app on each run. Do not
create another package directory for each UI change; keep per-change screenshots
and logs separately. The app to launch is
`dist/qt-package/staging/Woody.app`, and the DMG/ZIP are in `dist/qt-package`.

The DMG opens a 640 × 432 point Finder window with lavender 1x/2x artwork,
Woody on the left, Applications on the right, and drag-to-install instructions.
The layout is generated headlessly for both local builds and CI. Background
sources and regeneration instructions are in [resources/dmg](resources/dmg/README.md).
Eject any previously mounted image before inspecting a rebuilt DMG.

The `.noindex` build directory keeps the SDK-linked development bundle out of
Spotlight's file index ([Apple documentation](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file)).
Use the packaged app for everyday local testing. CI continues to use its own
ephemeral build directory and may explicitly override `--output`.

The UI harness uses isolated settings and deterministic historical reports. It
exercises real Qt pointer events, multi-window loading, zoom, hover, comparison,
renaming, and simulated hdc capture. It saves screenshots and a machine-readable
result. Simulated hdc tests do not establish physical-device compatibility.

`--offline` opens reports without device discovery. `--profile DIRECTORY` isolates
settings for validation. Normal runs continue using Woody's existing settings
and `~/.woody/reports`, including its historical report JSON/JSONL format.

## Implementation

- `src/HdcClient.*`: asynchronous subprocess boundary and device/app discovery.
- `src/Backend.*`: capture lifecycle, cancellation, report management and settings.
- `src/MemoryParser.*`, `src/ReportStore.*`: compatible parsing and persistent format.
- `src/Report.*`: native report data and statistics.
- `src/MemoryPlot.*`, `src/SnapshotPlot.*`: native charts, exact samples, hover and zoom.
- `qml/`: reusable controls and the main, live, report and comparison windows.
- `resources/`: source SVGs and prebuilt application icons for macOS and Windows.
- `tests/`: parser/storage tests, a controllable fake hdc, capture integration tests,
  and the explicit local CLI UI automation harness.

Qt remains dynamically linked. This application does not use Qt WebEngine,
Qt Charts, or Qt Graphs. See `licenses/` for redistribution notices.

The `qt.yml` workflow builds pushes to main and codex/qt-* plus PRs to main on
Windows x64, macOS arm64, and macOS Intel. Tags matching the root `VERSION` file publish the
six native packages after every test succeeds. Existing published releases are
never overwritten. CMake and the package script read the same `VERSION` file.

## Measure Qt performance

```sh
python -m pip install psutil==7.1.3
python qt/scripts/generate-fixtures.py dist/qt-fixtures --benchmark
python qt/scripts/benchmark.py \
  --qt-exe dist/qt-package/staging/Woody.app/Contents/MacOS/Woody \
  --fixtures dist/qt-fixtures --output dist/qt-performance --runs 3
```

Use the corresponding .exe paths on Windows. Run on an otherwise idle host.
The 3,600-point report contains 13 categories. The interaction workload sends
40 Hz hover and 10 Hz wheel events. Measurements include the entire Qt process tree.
The JSON contains raw samples and per-run results; startup is a warm process
launch (filesystem caches are not cleared). RSS can count shared pages more
than once. Private working set (USS) is also sampled on Windows; macOS Mach VM
page walks are excluded because they can block monitoring and disturb timing.
Timer delay is a harness diagnostic, not FPS or input-to-photon latency.

The earlier Electron comparison remains available as recorded data in
`validation/`. Reproducing that historical two-runtime comparison requires
checking out the commits identified in `VALIDATION.md`.
