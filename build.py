#!/usr/bin/env python3
"""Build, test and package Woody on the current macOS or Windows host."""
import argparse
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
QT_VERSION = "6.12.0"
BUILD = ROOT / "dist/qt-build.noindex"
OUTPUT = ROOT / "dist/qt-package"
SDK = ROOT / "dist/qt-sdk"


class BuildError(RuntimeError):
    pass


def run(command, env=None, capture=False):
    command = list(map(str, command))
    print("+ " + subprocess.list2cmdline(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, env=env, check=True,
                            text=True, encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def host_target():
    system, machine = platform.system(), platform.machine().lower()
    if system == "Darwin" and machine in ("arm64", "x86_64"):
        return system, "arm64" if machine == "arm64" else "x64"
    if system == "Windows" and machine in ("amd64", "x86_64"):
        return system, "x64"
    raise BuildError("仅支持 macOS Apple Silicon/Intel 和 Windows x64 本机构建。")


def find_tool(name, env, candidates=()):
    found = shutil.which(name, path=env.get("PATH"))
    if not found:
        found = next((str(p) for p in candidates if p.is_file()), None)
        if found:
            env["PATH"] = str(Path(found).parent) + os.pathsep + env.get("PATH", "")
    return found


def qt_missing(kit, system):
    suffix = ".exe" if system == "Windows" else ""
    deploy = "windeployqt" if system == "Windows" else "macdeployqt"
    required = [f"bin/qmake{suffix}", f"bin/{deploy}{suffix}",
                "lib/cmake/Qt6/Qt6Config.cmake"]
    for module in ("Core", "Gui", "Qml", "Quick", "QuickControls2", "Concurrent",
                   "Test", "Svg", "ShaderTools"):
        required.append(f"lib/cmake/Qt6{module}/Qt6{module}Config.cmake")
    return [item for item in required if not (kit / item).is_file()]


def windows_sdk_present(env):
    import winreg
    roots = [env.get("WindowsSdkDir", "")]
    for view in (winreg.KEY_WOW64_32KEY, winreg.KEY_WOW64_64KEY):
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                r"SOFTWARE\Microsoft\Windows Kits\Installed Roots",
                                0, winreg.KEY_READ | view) as key:
                roots.append(winreg.QueryValueEx(key, "KitsRoot10")[0])
        except OSError:
            pass
    for root in filter(None, roots):
        for include in (Path(root) / "Include").glob("10.*"):
            if ((include / "um/Windows.h").is_file()
                    and (include / "ucrt/corecrt.h").is_file()
                    and (Path(root) / "Lib" / include.name / "um/x64/kernel32.lib").is_file()):
                return True
    return False


def check_dependencies(system, env, need_sdk, installer):
    problems = []
    required = {"cmake": "安装 CMake 3.24+ 并加入 PATH",
                "ctest": "安装 CMake（包含 CTest）并加入 PATH",
                "git": "安装 Git 并加入 PATH"}
    if need_sdk:
        required["curl"] = "安装 curl 并加入 PATH（用于下载 Qt SDK）"
    if system == "Darwin":
        if installer and sys.version_info < (3, 10):
            problems.append("DMG 布局工具需要 Python 3.10+；或使用 --skip-installer 仅生成 ZIP")
        required.update({"ninja": "安装 Ninja，例如 brew install ninja",
                         "xcrun": "安装 Xcode Command Line Tools：xcode-select --install",
                         "lipo": "安装 Xcode Command Line Tools：xcode-select --install",
                         "otool": "安装 Xcode Command Line Tools：xcode-select --install",
                         "codesign": "需要 macOS 系统工具 codesign",
                         "ditto": "需要 macOS 系统工具 ditto"})
        if need_sdk:
            required["bsdtar"] = "需要 macOS 系统工具 bsdtar（用于解压 Qt SDK）"
        if installer:
            required["hdiutil"] = "需要 macOS 系统工具 hdiutil（用于生成 DMG）"
            required["tiffutil"] = "需要 macOS 系统工具 tiffutil（用于 Retina 安装背景）"
            required["SetFile"] = "安装 Xcode Command Line Tools（用于磁盘图标）"
        version = tuple(map(int, platform.mac_ver()[0].split(".")[:2]))
        if version < (14, 4):
            problems.append("需要 macOS 14.4 或更新版本")
    for name, help_text in required.items():
        if not find_tool(name, env):
            problems.append(f"缺少 {name}：{help_text}")
    if find_tool("cmake", env):
        text = run(["cmake", "--version"], env, capture=True)
        version = re.search(r"cmake version (\d+)\.(\d+)", text)
        if not version or tuple(map(int, version.groups())) < (3, 24):
            problems.append("CMake 版本过低，需要 3.24+")
    vs = None
    if system == "Darwin" and find_tool("xcrun", env):
        try:
            run(["xcrun", "--find", "clang++"], env, capture=True)
            run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env, capture=True)
        except subprocess.CalledProcessError:
            problems.append("Apple Clang/macOS SDK 不可用，请安装并配置 Xcode Command Line Tools")
    if system == "Windows":
        program_files = Path(env.get("ProgramFiles", r"C:\Program Files"))
        program_files_x86 = Path(env.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
        if need_sdk and not find_tool("7z", env, [program_files / "7-Zip/7z.exe"]):
            problems.append("缺少 7-Zip：安装 7-Zip x64（用于解压 Qt SDK）")
        if installer and not find_tool("makensis", env, [program_files_x86 / "NSIS/makensis.exe",
                                                       program_files / "NSIS/makensis.exe"]):
            problems.append("缺少 NSIS：安装 NSIS 3；或使用 --skip-installer 仅生成 ZIP")
        vswhere = find_tool("vswhere", env, [program_files_x86 / "Microsoft Visual Studio/Installer/vswhere.exe"])
        if vswhere:
            location = run([vswhere, "-utf8", "-latest", "-products", "*", "-version", "[17.0,18.0)",
                            "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                            "-property", "installationPath"], env, capture=True)
            if location:
                vs = Path(location)
        if not vs:
            problems.append("缺少 MSVC 2022：安装 Visual Studio 2022/Build Tools 的“使用 C++ 的桌面开发”工作负载")
        elif not list((vs / "VC/Redist/MSVC").glob("*/x64/Microsoft.VC*.CRT/*.dll")):
            problems.append("MSVC 2022 的 x64 运行库缺失，请通过 Visual Studio Installer 修复 C++ 工具")
        if not windows_sdk_present(env):
            problems.append("缺少 Windows 10/11 SDK，请通过 Visual Studio Installer 安装")
    if problems:
        raise BuildError("依赖检查未通过：\n- " + "\n- ".join(problems))
    return vs


def check_cache(system, arch, kit):
    cache_path = BUILD / "CMakeCache.txt"
    if not cache_path.is_file():
        return
    cache = {}
    for line in cache_path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"([^:#]+):[^=]+=(.*)", line)
        if match:
            cache[match[1]] = match[2]
    generator = "Ninja" if system == "Darwin" else "Visual Studio 17 2022"
    expected = {"CMAKE_GENERATOR": generator,
                "CMAKE_HOME_DIRECTORY": ROOT.as_posix(),
                "Qt6_DIR": (kit / "lib/cmake/Qt6").as_posix()}
    if system == "Darwin":
        expected["CMAKE_OSX_ARCHITECTURES"] = "arm64" if arch == "arm64" else "x86_64"
    else:
        expected["CMAKE_GENERATOR_PLATFORM"] = "x64"
    differences = [key for key, value in expected.items()
                   if cache.get(key) and os.path.normcase(cache[key]) != os.path.normcase(value)]
    if differences:
        raise BuildError("现有构建缓存与当前配置不一致（" + ", ".join(differences)
                         + f"）。请移除构建缓存目录 {BUILD} 后重试；脚本不会自动删除它。")


def positive_int(value):
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("必须为正整数")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qt", type=Path, help="使用已有 Qt 6.12.0 kit（macos 或 msvc2022_64 目录）")
    parser.add_argument("--jobs", type=positive_int, default=min(os.cpu_count() or 1, 4), help="并行编译数（默认最多 4）")
    parser.add_argument("--check", action="store_true", help="只检查环境，不下载、不编译、不打包")
    parser.add_argument("--skip-tests", action="store_true", help="跳过测试程序的编译和 CTest 执行（默认执行测试）")
    parser.add_argument("--skip-installer", action="store_true", help="生成程序目录和 ZIP，但不生成 DMG/EXE 安装包；默认仍执行测试")
    args = parser.parse_args(argv)
    if sys.version_info < (3, 9):
        raise BuildError("需要 Python 3.9 或更新版本")
    system, arch = host_target()
    kit = args.qt.expanduser().resolve() if args.qt else SDK / QT_VERSION / ("macos" if system == "Darwin" else "msvc2022_64")
    missing = qt_missing(kit, system)
    if args.qt and missing:
        raise BuildError("指定的 Qt kit 不完整：" + str(kit) + "\n缺少：" + ", ".join(missing))
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    print(f"Woody 本机构建：{system} / {arch} / Release", flush=True)
    vs = check_dependencies(system, env, bool(missing), not args.skip_installer)
    check_cache(system, arch, kit)
    if system == "Darwin" and not args.skip_installer and args.check:
        run([sys.executable, ROOT / "qt/scripts/dmg.py", "--check"], env)
    if missing:
        if args.check:
            print(f"系统依赖检查通过；正式构建时将自动下载/补全 Qt {QT_VERSION}：{kit}")
            return 0
        run([sys.executable, ROOT / "qt/scripts/install-qt.py", "--output", SDK], env)
        missing = qt_missing(kit, system)
        if missing:
            raise BuildError("安装后的 Qt SDK 不完整：" + ", ".join(missing))
    env["PATH"] = str(kit / "bin") + os.pathsep + env.get("PATH", "")
    qmake = kit / "bin" / ("qmake.exe" if system == "Windows" else "qmake")
    version = run([qmake, "-query", "QT_VERSION"], env, capture=True)
    if version != QT_VERSION:
        raise BuildError(f"需要 Qt {QT_VERSION}，当前 kit 为 {version}")
    if args.check:
        print("系统依赖、Qt SDK 和构建缓存检查通过。")
        return 0
    if system == "Darwin" and not args.skip_installer:
        run([sys.executable, ROOT / "qt/scripts/dmg.py", "--prepare"], env)
    configure = ["cmake", "-S", ROOT, "-B", BUILD, f"-DBUILD_TESTING={'OFF' if args.skip_tests else 'ON'}",
                 f"-DCMAKE_PREFIX_PATH={kit}"]
    if system == "Darwin":
        configure += ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
                      "-DCMAKE_OSX_ARCHITECTURES=" + ("arm64" if arch == "arm64" else "x86_64"),
                      "-DCMAKE_OSX_DEPLOYMENT_TARGET=14.4"]
    else:
        configure += ["-G", "Visual Studio 17 2022", "-A", "x64",
                      f"-DCMAKE_GENERATOR_INSTANCE={vs}"]
    run(configure, env)
    run(["cmake", "--build", BUILD, "--config", "Release", "--parallel", args.jobs], env)
    if args.skip_tests:
        print("已按 --skip-tests 跳过测试。", flush=True)
    else:
        run(["ctest", "--test-dir", BUILD, "-C", "Release", "--output-on-failure", "--no-tests=error"], env)
    package = [sys.executable, ROOT / "qt/scripts/package.py", "--build", BUILD,
               "--qt", kit, "--output", OUTPUT, "--arch", arch]
    if vs:
        package += ["--vs-install", vs]
    if args.skip_installer:
        package.append("--skip-installer")
    run(package, env)
    app = OUTPUT / "staging" / ("Woody.app" if system == "Darwin" else "Woody/Woody.exe")
    result = "构建、打包完成（已跳过测试）" if args.skip_tests else "构建、测试、打包完成"
    print(f"\n{result}。\n程序：{app}\n安装包 / ZIP：{OUTPUT}")
    return 0


if __name__ == "__main__":
    # Keep Chinese diagnostics readable when redirected on Windows as well.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    try:
        sys.exit(main())
    except (BuildError, OSError, subprocess.CalledProcessError) as error:
        print(f"\n构建失败：{error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n构建已取消。", file=sys.stderr)
        sys.exit(130)
