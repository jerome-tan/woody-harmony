"""Regression checks for the local build driver; no SDK or compiler required."""
import importlib.util
import contextlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("woody_build", ROOT / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildDriverTest(unittest.TestCase):
    def test_native_targets_and_unsupported_host(self):
        for system, machine, arch in [("Darwin", "arm64", "arm64"),
                                      ("Darwin", "x86_64", "x64"),
                                      ("Windows", "AMD64", "x64")]:
            with self.subTest(system=system, machine=machine), \
                    patch.object(build.platform, "system", return_value=system), \
                    patch.object(build.platform, "machine", return_value=machine):
                self.assertEqual(build.host_target(), (system, arch))
        with patch.object(build.platform, "system", return_value="Linux"):
            with self.assertRaises(build.BuildError):
                build.host_target()

    def exercise(self, system="Darwin", arch="arm64", arguments=(), failure=None,
                 missing=None, version="6.12.0"):
        calls = []

        def command(cmd, env=None, capture=False):
            cmd = list(map(str, cmd))
            calls.append((cmd, env.copy()))
            if cmd[0] == failure:
                raise subprocess.CalledProcessError(1, cmd)
            return version if capture else None

        with patch.object(build, "host_target", return_value=(system, arch)), \
                patch.object(build, "check_dependencies", return_value=Path("C:/VS 2022") if system == "Windows" else None) as deps, \
                patch.object(build, "check_cache"), \
                patch.object(build, "qt_missing", side_effect=missing or [[], []]), \
                patch.object(build, "run", side_effect=command), \
                contextlib.redirect_stdout(io.StringIO()):
            try:
                build.main(list(arguments))
            except (build.BuildError, subprocess.CalledProcessError) as error:
                return calls, deps.call_args, error
        return calls, deps.call_args, None

    def test_native_release_pipeline_and_windows_runtime_path(self):
        for system, arch in [("Darwin", "arm64"), ("Darwin", "x64"), ("Windows", "x64")]:
            with self.subTest(system=system, arch=arch):
                calls, _, error = self.exercise(system, arch, arguments=["--jobs", "4"])
                self.assertIsNone(error)
                dmg_calls = [c for c in calls if str(build.ROOT / "qt/scripts/dmg.py") in c[0]]
                calls = [c for c in calls if c not in dmg_calls]
                self.assertEqual(len(dmg_calls), 1 if system == "Darwin" else 0)
                if dmg_calls:
                    self.assertEqual(dmg_calls[0][0][-1], "--prepare")
                qmake, configure, compile_cmd, test, package = [c[0] for c in calls]
                self.assertIn("-DBUILD_TESTING=ON", configure)
                self.assertEqual(compile_cmd[-4:], ["--config", "Release", "--parallel", "4"])
                self.assertEqual(test[0], "ctest")
                self.assertIn("--no-tests=error", test)
                self.assertIn(str(build.ROOT / "qt/scripts/package.py"), package)
                self.assertEqual(package[package.index("--arch") + 1], arch)
                kit = str(Path(qmake[0]).parent)
                self.assertTrue(calls[3][1]["PATH"].startswith(kit + os.pathsep))
                if system == "Windows":
                    self.assertIn("Visual Studio 17 2022", configure)
                    self.assertIn(f"-DCMAKE_GENERATOR_INSTANCE={Path('C:/VS 2022')}", configure)
                    self.assertEqual(package[-2:], ["--vs-install", str(Path("C:/VS 2022"))])
                else:
                    self.assertIn("-DCMAKE_OSX_ARCHITECTURES=" + ("arm64" if arch == "arm64" else "x86_64"), configure)

    def test_failed_tests_never_package(self):
        calls, _, error = self.exercise(failure="ctest")
        self.assertIsInstance(error, subprocess.CalledProcessError)
        self.assertEqual(calls[-1][0][0], "ctest")
        self.assertFalse(any(str(build.ROOT / "qt/scripts/package.py") in c[0] for c in calls))

    def test_skip_tests_and_restore_default_on_each_platform(self):
        for system, arch in [("Darwin", "arm64"), ("Windows", "x64")]:
            for arguments in (["--skip-tests"], ["--skip-tests", "--skip-installer"], []):
                with self.subTest(system=system, arguments=arguments):
                    calls, _, error = self.exercise(system, arch, arguments=arguments)
                    self.assertIsNone(error)
                    commands = [c[0] for c in calls]
                    configure = next(c for c in commands if c[0] == "cmake" and "-S" in c)
                    skipped = "--skip-tests" in arguments
                    self.assertIn("-DBUILD_TESTING=" + ("OFF" if skipped else "ON"), configure)
                    self.assertEqual(any(c[0] == "ctest" for c in commands), not skipped)
                    self.assertTrue(any(c[0] == "cmake" and "--build" in c for c in commands))
                    self.assertIn(str(build.ROOT / "qt/scripts/package.py"), commands[-1])
                    self.assertEqual("--skip-installer" in commands[-1], "--skip-installer" in arguments)

    def test_skip_tests_does_not_ignore_build_failure(self):
        def fail_compile(cmd, env=None, capture=False):
            if "--build" in cmd:
                raise subprocess.CalledProcessError(1, cmd)
            return "6.12.0" if capture else None

        with patch.object(build, "host_target", return_value=("Darwin", "arm64")), \
                patch.object(build, "check_dependencies"), patch.object(build, "check_cache"), \
                patch.object(build, "qt_missing", return_value=[]), \
                patch.object(build, "run", side_effect=fail_compile) as run, \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                build.main(["--skip-tests", "--skip-installer"])
            self.assertIn("--build", run.call_args.args[0])

    def test_incomplete_sdk_bootstraps_before_configure(self):
        calls, deps, error = self.exercise(missing=[["bin/qmake"], []])
        self.assertIsNone(error)
        self.assertTrue(deps.args[2])
        self.assertIn(str(build.ROOT / "qt/scripts/install-qt.py"), calls[0][0])
        self.assertEqual(calls[3][0][0], "cmake")

    def test_check_does_not_install_or_build(self):
        calls, _, error = self.exercise(arguments=["--check"], missing=[["bin/qmake"]])
        self.assertIsNone(error)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0][-1], "--check")
        calls, _, error = self.exercise(arguments=["--check"])
        self.assertIsNone(error)
        self.assertEqual(len(calls), 2)  # Checks DMG tools and the existing kit version.

    def test_wrong_qt_version_stops_before_configuring(self):
        calls, _, error = self.exercise(version="6.11.0")
        self.assertIsInstance(error, build.BuildError)
        self.assertEqual(len(calls), 1)

    def test_custom_kit_and_zip_only_preserve_tests(self):
        with tempfile.TemporaryDirectory(prefix="Woody kit ") as folder:
            kit = Path(folder).resolve()
            calls, deps, error = self.exercise(arguments=["--qt", folder, "--skip-installer", "--jobs", "2"])
            self.assertIsNone(error)
            self.assertFalse(deps.args[2])  # No bootstrap tools needed.
            self.assertFalse(deps.args[3])  # No installer dependency needed.
            self.assertIn(f"-DCMAKE_PREFIX_PATH={kit}", calls[1][0])
            self.assertEqual(calls[2][0][-1], "2")
            self.assertEqual(calls[3][0][0], "ctest")
            self.assertEqual(calls[-1][0][-1], "--skip-installer")

    def test_custom_incomplete_kit_never_downloads(self):
        calls, _, error = self.exercise(arguments=["--qt", "missing kit"], missing=[["bin/qmake"]])
        self.assertIsInstance(error, build.BuildError)
        self.assertEqual(calls, [])

    def test_cache_conflict_preserves_existing_files(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(build, "BUILD", Path(folder)):
            cache = Path(folder) / "CMakeCache.txt"
            content = "CMAKE_GENERATOR:INTERNAL=Unix Makefiles\n"
            cache.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(build.BuildError, "CMAKE_GENERATOR"):
                build.check_cache("Darwin", "arm64", Path("/Qt/macos"))
            self.assertEqual(cache.read_text(encoding="utf-8"), content)

    def test_windows_missing_dependencies_are_reported_together(self):
        with patch.object(build, "find_tool", side_effect=lambda name, *args: name if name in ("cmake", "ctest", "git", "curl") else None), \
                patch.object(build, "run", return_value="cmake version 3.24.0"), \
                patch.object(build, "windows_sdk_present", return_value=False):
            with self.assertRaises(build.BuildError) as caught:
                build.check_dependencies("Windows", {"PATH": ""}, True, True)
        for component in ("7-Zip", "NSIS", "MSVC 2022", "Windows 10/11 SDK"):
            self.assertIn(component, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
