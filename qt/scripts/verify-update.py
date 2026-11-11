#!/usr/bin/env python3
"""Exercise the native replacement helper, including rollback and Unicode paths."""
import argparse
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='woody-update-验证 ') as root:
        root = Path(root)
        for fails in (False, True):
            case = root / ('rollback' if fails else 'success')
            target = case / ('Woody' if os.name == 'nt' else 'Woody.app')
            source = case / 'payload'
            temporary = case / 'temp.noindex'
            temporary.mkdir(parents=True)
            relative = Path('Woody.exe') if os.name == 'nt' else Path('Contents/MacOS/Woody')
            for directory, mode in ((target, 'old'), (source, 'fail' if fails else 'new')):
                exe = directory / relative
                exe.parent.mkdir(parents=True)
                shutil.copy2(args.probe, exe)
                (exe.parent / 'probe-mode.txt').write_text(mode)
                (directory / '.woody-files').write_text('Woody.exe\nprobe-mode.txt\n.woody-files\n')
            (target / '用户报告.txt').write_text('keep me', encoding='utf-8')
            # A real parent process exits shortly after the helper starts.
            parent = subprocess.Popen([str(target / relative)])
            result = case / 'result.txt'
            run = subprocess.Popen([str(args.helper.resolve()), str(parent.pid), str(target), str(source),
                                    'directory', str(result), str(temporary)])
            parent.wait(timeout=5)
            assert run.wait(timeout=60) == (1 if fails else 0), result.read_text(encoding='utf-8')
            time.sleep(1.2)  # Let the replacement/rollback probe release Windows file handles.
            text = result.read_text(encoding='utf-8')
            assert text.startswith('ERROR:' if fails else 'OK'), text
            assert (target / relative).is_file()
            assert (target / relative.parent / 'probe-mode.txt').read_text() == ('old' if fails else 'new')
            if os.name == 'nt' or fails:
                assert (target / '用户报告.txt').read_text(encoding='utf-8') == 'keep me'
            assert not list(case.glob('.woody-old-*'))
            assert not list(case.glob('.woody-new-*'))
            print('PASS', 'rollback after startup failure' if fails else 'replacement and restart', flush=True)


if __name__ == '__main__':
    main()
