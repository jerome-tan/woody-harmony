#!/usr/bin/env python3
"""Replace and relaunch a real deployed app, using an isolated profile and copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = 'Woody' if os.name == 'nt' else 'Woody.app'
    target = output / '应用 安装位置' / name
    payload = output / 'payload' / name
    for path in (target, payload):
        if path.exists():
            shutil.rmtree(path)
        shutil.copytree(args.package.resolve(), path, symlinks=True)
    relative = Path('Woody.exe') if os.name == 'nt' else Path('Contents/MacOS/Woody')
    helper_relative = relative.with_name('woody_updater.exe' if os.name == 'nt' else 'woody_updater')
    temporary = output / 'helper.noindex'
    temporary.mkdir(exist_ok=True)
    helper = temporary / helper_relative.name
    shutil.copy2(target / helper_relative, helper)
    obsolete = target / 'old-managed-file.txt'
    obsolete.write_text('must be removed by replacement')
    if os.name == 'nt':
        with (target / '.woody-files').open('a', encoding='utf-8') as stream:
            stream.write('old-managed-file.txt\n')
        (target / '用户文件.txt').write_text('preserve', encoding='utf-8')
    profile = output / 'profile'
    profile.mkdir(exist_ok=True)
    reports = output / 'reports'
    reports.mkdir(exist_ok=True)
    sentinel = reports / 'saved-report.txt'
    sentinel.write_text('preserve reports', encoding='utf-8')
    # An existing harmless executable prevents SDK auto-discovery in the newly
    # launched app, keeping this test away from any real connected device.
    no_hdc = str(Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32/where.exe') if os.name == 'nt' else '/usr/bin/false'
    settings = json.dumps({'sessionsDir': str(reports), 'hdcPath': no_hdc})
    (profile / 'settings.json').write_text(settings, encoding='utf-8')
    ready = output / 'before-ready'
    ready.unlink(missing_ok=True)
    result = output / 'update-result.txt'
    result.unlink(missing_ok=True)
    parent = subprocess.Popen([str(target / relative), '--offline', '--profile', str(profile),
                               '--ready-file', str(ready), '--quit-after', '4000'],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    new_pid = None
    try:
        deadline = time.monotonic() + 30
        while not ready.exists() and parent.poll() is None and time.monotonic() < deadline:
            time.sleep(.1)
        if not ready.exists():
            raise RuntimeError('Original deployed app did not open')
        update = subprocess.Popen([str(helper), str(parent.pid), str(target), str(payload), 'directory',
                                   str(result), str(temporary), str(profile)])
        parent.wait(timeout=30)
        if update.wait(timeout=180) != 0:
            raise RuntimeError(result.read_text(encoding='utf-8') if result.exists() else 'Updater failed without a result')
        text = result.read_text(encoding='utf-8')
        assert text.startswith('OK:'), text
        new_pid = int(text.split(':', 1)[1])
        assert not obsolete.exists(), 'Obsolete managed file survived replacement'
        if os.name == 'nt':
            assert (target / '用户文件.txt').read_text(encoding='utf-8') == 'preserve'
        else:
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)
        assert sentinel.read_text(encoding='utf-8') == 'preserve reports'
        assert (profile / 'settings.json').read_text(encoding='utf-8') == settings
        assert hashlib.sha256((target / relative).read_bytes()).digest() == hashlib.sha256((payload / relative).read_bytes()).digest()
        (output / 'deployed-update-result.json').write_text(json.dumps({
            'passed': True, 'replacedAndRestarted': True, 'preservedSettingsAndReports': True,
            'removedObsoleteManagedFiles': True, 'unicodePath': str(target)
        }, indent=2), encoding='utf-8')
        print('PASS deployed application replacement, restart and data preservation')
    finally:
        if parent.poll() is None:
            parent.terminate(); parent.wait(timeout=10)
        if new_pid:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(new_pid), '/T', '/F'], check=True, timeout=15)
            else:
                os.kill(new_pid, signal.SIGTERM)


if __name__ == '__main__':
    main()
