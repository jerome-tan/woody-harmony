#!/usr/bin/env python3
"""Build a public, API-quota-free update manifest for a complete GitHub Release."""
import argparse
import json
from pathlib import Path
import re


def build_manifest(directory, version, notes=''):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Expected a stable major.minor.patch version')
    tag = 'v' + version
    names = [f'Woody-{version}-qt-{platform}-{arch}-{kind}'
             for platform, arch, kind in (
                 ('mac', 'arm64', 'portable.zip'), ('mac', 'x64', 'portable.zip'),
                 ('win', 'x64', 'portable.zip'), ('win', 'x64', 'setup.exe'))]
    names += ['SHA256SUMS.txt']
    assets = []
    for name in names:
        size = (directory / name).stat().st_size
        if size <= 0:
            raise ValueError('Empty release asset: ' + name)
        assets.append({'name': name, 'size': size, 'state': 'uploaded',
                       'browser_download_url': f'https://github.com/jerome-tan/woody-harmony/releases/download/{tag}/{name}'})
    return {'tag_name': tag, 'draft': False, 'prerelease': False,
            'body': notes or '查看 Release 页面了解本版本改动。', 'assets': assets}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--notes', type=Path)
    args = parser.parse_args()
    notes = args.notes.read_text(encoding='utf-8') if args.notes and args.notes.is_file() else ''
    data = build_manifest(args.directory, args.version, notes)
    (args.directory / 'update.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
