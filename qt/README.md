# Woody native Qt edition

This branch replaces the Electron runtime with C++20, Qt 6.12.0, and Qt Quick.
The original Electron sources remain available as the reference implementation.

## Build

Install Qt **6.12.0 exactly**, with Qt Base, Declarative, SVG, Tools, Shader Tools,
and Translations. `scripts/install-qt.py` downloads the official SDK, checks
archive hashes, and supports Qt 6.12's nested repository layout.

```sh
python qt/scripts/install-qt.py --output dist/qt-sdk
cmake -S . -B dist/qt-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/absolute/path/to/Qt/6.12.0/macos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4
cmake --build dist/qt-build --parallel
ctest --test-dir dist/qt-build --output-on-failure
```

On Windows use MSVC 2022, generator `Visual Studio 17 2022`, `-A x64`, and the
`msvc2022_64` Qt kit. Build and test with `--config Release` / `-C Release`.
On macOS explicitly select `-DCMAKE_OSX_ARCHITECTURES=arm64` or `x86_64`.
Qt 6.12 requires macOS 14.4 or newer; Windows targets Windows 10 1809+ and 11.

## Run and validate

```sh
python qt/scripts/generate-fixtures.py dist/qt-fixtures
python qt/scripts/ui-smoke.py \
  --exe dist/qt-build/qt/Woody.app/Contents/MacOS/Woody \
  --hdc dist/qt-build/qt/woody_fake_hdc \
  --fixtures dist/qt-fixtures --output dist/qt-evidence
python qt/scripts/package.py --build dist/qt-build \
  --qt /absolute/path/to/Qt/6.12.0/macos \
  --arch arm64 --output dist/qt-package
```

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
- `tests/`: parser/storage tests, a controllable fake hdc, capture integration tests,
  and the explicit local CLI UI automation harness.

Qt remains dynamically linked. This application does not use Qt WebEngine,
Qt Charts, or Qt Graphs. See `licenses/` for redistribution notices.

The `qt.yml` workflow builds pushes to main and codex/qt-* plus PRs to main on
Windows x64, macOS arm64, and macOS Intel. Tags matching package.json publish the
six native packages after every test succeeds. Existing published releases are
never overwritten. The Electron reference workflow is manual-only.

## Reproduce the performance comparison

```sh
npm ci && npm run build
python -m pip install psutil==7.1.3
python qt/scripts/generate-fixtures.py dist/qt-fixtures --benchmark
python qt/scripts/benchmark.py \
  --qt-exe dist/qt-package/staging/Woody.app/Contents/MacOS/Woody \
  --electron-exe node_modules/electron/dist/Electron.app/Contents/MacOS/Electron \
  --fixtures dist/qt-fixtures --output dist/qt-performance --runs 3
```

Use the corresponding .exe paths on Windows. Run on an otherwise idle host.
The same 3,600-point report, 13 categories, 40 Hz hover and 10 Hz wheel workload
is sent to both applications. Measurements include every process in each tree.
The JSON contains raw samples and per-run results; startup is a warm process
launch (filesystem caches are not cleared). RSS can count shared pages more
than once; USS is included only where the OS permits it. Timer delay is a
harness diagnostic, not FPS or input-to-photon latency.

