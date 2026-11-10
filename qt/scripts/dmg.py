#!/usr/bin/env python3
"""Create a styled DMG without Finder/Apple Events or globally installed packages."""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import tempfile
import venv

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "dist/dmg-tools"
LOCK = Path(__file__).with_name("dmg-requirements.txt")


def ensure_tools(check_only=False):
    if platform.system() != "Darwin":
        raise RuntimeError("DMG packaging requires macOS")
    if sys.version_info < (3, 10):
        raise RuntimeError("DMG packaging requires Python 3.10+ (or use --skip-installer)")
    python = TOOLS / "bin/python"
    expected = dict(line.split()[0].split("==") for line in LOCK.read_text().splitlines()
                    if line.strip() and not line.startswith("#"))
    probe = "import importlib.metadata as m,json; print(json.dumps({k:m.version(k) for k in " + repr(list(expected)) + "}))"
    ready = False
    if python.is_file():
        result = subprocess.run([str(python), "-c", probe], text=True, capture_output=True)
        if result.returncode == 0:
            ready = json.loads(result.stdout) == expected
    if ready:
        print("DMG layout tools ready (isolated environment).", flush=True)
        return python
    if check_only:
        print(f"DMG layout tools will be installed automatically into {TOOLS} on the first build.")
        return None
    print(f"Preparing pinned DMG layout tools in {TOOLS}", flush=True)
    venv.EnvBuilder(with_pip=True).create(TOOLS)
    subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                    "--only-binary=:all:", "--require-hashes", "-r", str(LOCK)], check=True)
    return python


def verify_dmg_contents(image):
    """Check the delivered app, not just the signature of the staging copy."""
    with tempfile.TemporaryDirectory(prefix="woody-dmg-verify-") as directory:
        result = subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                                 "-mountpoint", directory, "-plist", str(image)],
                                check=True, stdout=subprocess.PIPE)
        mounted = next(item for item in plistlib.loads(result.stdout)["system-entities"]
                       if item.get("mount-point"))
        try:
            volume = Path(mounted["mount-point"])
            subprocess.run(["codesign", "--verify", "--deep", "--strict",
                            str(volume / "Woody.app")], check=True)
            link = volume / "Applications"
            if not link.is_symlink() or link.readlink() != Path("/Applications"):
                raise RuntimeError("DMG is missing the Applications installation link")
        finally:
            subprocess.run(["hdiutil", "detach", mounted["dev-entry"]], check=True)


def build_dmg(app, destination):
    app, destination = Path(app).resolve(), Path(destination).resolve()
    if not (app / "Contents/MacOS/Woody").is_file():
        raise RuntimeError(f"Missing packaged Woody.app: {app}")
    python = ensure_tools()
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Keep the previous installer intact if layout generation or hdiutil fails.
    temporary = destination.with_name("." + destination.stem + ".pending.dmg")
    try:
        subprocess.run([str(python), "-m", "dmgbuild", "-s",
                        str(Path(__file__).with_name("dmg-settings.py")),
                        "-D", "app=" + str(app), "-D", "resources=" + str(ROOT / "qt/resources"),
                        "Woody", str(temporary)], check=True)
        subprocess.run(["hdiutil", "verify", str(temporary)], check=True)
        verify_dmg_contents(temporary)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"DMG ready: {destination}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true", help="Install/check build-only dependencies")
    parser.add_argument("--check", action="store_true", help="Check without installing anything")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.prepare or args.check:
        ensure_tools(check_only=args.check)
    else:
        if not args.app or not args.output:
            parser.error("--app and --output are required")
        build_dmg(args.app, args.output)


if __name__ == "__main__":
    main()
