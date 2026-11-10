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
