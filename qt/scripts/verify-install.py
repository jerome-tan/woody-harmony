#!/usr/bin/env python3
"""Install the generated NSIS package, exercise it, then verify uninstall isolation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    for option in ['package', 'fixtures', 'output']:
        parser.add_argument('--' + option, type=Path, required=True)
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('This test runs on Windows only')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    target = output / '中文 安装目录'
    setup, = args.package.resolve().glob('*-setup.exe')
    # NSIS /D consumes the unquoted remainder of the command line and must be last.
    command = subprocess.list2cmdline([str(setup), '/S']) + ' /D=' + str(target)
    subprocess.run(command, check=True, timeout=120)
    executable = target / 'Woody.exe'
    if not executable.is_file():
        raise RuntimeError('Installer did not create Woody.exe')
    sentinel = target / '用户文件.txt'
    sentinel.write_text('Uninstall must preserve files it did not install.', encoding='utf-8')
    subprocess.run([sys.executable, str(Path(__file__).with_name('ui-smoke.py')),
                    '--exe', str(executable), '--fixtures', str(args.fixtures.resolve()),
                    '--output', str(output / 'ui')], check=True, timeout=150)
    subprocess.run([str(target / 'Uninstall.exe'), '/S'], check=True, timeout=120)
    deadline = time.monotonic() + 30
    while executable.exists() and time.monotonic() < deadline:
        time.sleep(.2)
    if executable.exists() or not sentinel.exists():
        raise RuntimeError('Uninstall failed or deleted the user file')
    (output / 'installer-result.json').write_text(json.dumps({
        'installed': True, 'uiPassed': True, 'uninstalled': True,
        'preservedUnrelatedFile': True, 'unicodePath': str(target)
    }, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
