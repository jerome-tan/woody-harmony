"""DMG failure handling can be checked on every host, without mounting a disk."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("woody_dmg", ROOT / "qt/scripts/dmg.py")
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)


class DmgTest(unittest.TestCase):
    def test_invalid_signature_still_detaches_verification_volume(self):
        attach = subprocess.CompletedProcess([], 0, stdout=plistlib.dumps({
            "system-entities": [{"mount-point": "/fake/volume", "dev-entry": "/dev/testdisk"}]
        }))
        with patch.object(dmg.subprocess, "run", side_effect=[
                attach, subprocess.CalledProcessError(1, ["codesign"]),
                subprocess.CompletedProcess([], 0)]) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                dmg.verify_dmg_contents(Path("test.dmg"))
        self.assertEqual(command.call_args.args[0], ["hdiutil", "detach", "/dev/testdisk"])

    def test_check_without_tools_does_not_create_environment(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(dmg, "TOOLS", Path(directory) / "missing"), \
                patch.object(dmg.platform, "system", return_value="Darwin"), \
                patch.object(dmg.venv, "EnvBuilder") as builder, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertIsNone(dmg.ensure_tools(check_only=True))
            builder.assert_not_called()
            self.assertFalse(dmg.TOOLS.exists())

    def test_failed_image_verification_preserves_previous_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Woody.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            (app / "Contents/MacOS/Woody").touch()
            destination = root / "Woody.dmg"
            destination.write_bytes(b"previous installer")
            pending = root / ".Woody.pending.dmg"

            def command(args, **kwargs):
                if args[0] == "hdiutil":
                    raise subprocess.CalledProcessError(1, args)
                pending.write_bytes(b"unverified installer")

            with patch.object(dmg, "ensure_tools", return_value=Path("python")), \
                    patch.object(dmg.subprocess, "run", side_effect=command):
                with self.assertRaises(subprocess.CalledProcessError):
                    dmg.build_dmg(app, destination)
            self.assertEqual(destination.read_bytes(), b"previous installer")
            self.assertFalse(pending.exists())


if __name__ == "__main__":
    unittest.main()
