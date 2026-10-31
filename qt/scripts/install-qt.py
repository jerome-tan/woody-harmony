#!/usr/bin/env python3
"""Install the pinned official Qt 6.12 SDK, including its new nested repository layout."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import xml.etree.ElementTree as ET

VERSION = '6.12.0'
HOST = 'mac_x64' if platform.system() == 'Darwin' else 'windows_x86'
ARCH = 'clang_64' if platform.system() == 'Darwin' else 'win64_msvc2022_64'
KIT = 'macos' if platform.system() == 'Darwin' else 'msvc2022_64'
SUBREPO = 'qt6_6120' if platform.system() == 'Darwin' else 'qt6_6120_msvc2022_64'
MODULES = {'qtbase', 'qtdeclarative', 'qttools', 'qtsvg', 'qttranslations', 'qtshadertools', 'd3dcompiler_47', 'opengl32sw'}


def fetch(relative, destination, mirrors):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return destination
    temporary = destination.with_suffix(destination.suffix + '.partial')
    for mirror in mirrors:
        url = mirror.rstrip('/') + '/' + relative
        result = subprocess.run(['curl', '-fL', '--retry', '2', '--connect-timeout', '15', '--max-time', '900', '-o', str(temporary), url], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode == 0:
            temporary.replace(destination)
            return destination
    raise RuntimeError(f'Could not download {relative}: {result.stderr.decode(errors="replace")[-500:]}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mirror', default='https://download.qt.io')
    args = parser.parse_args()
    output = args.output.resolve()
    kit = output / VERSION / KIT
    archives = output / 'archives' / HOST
    mirrors = [args.mirror, 'https://mirrors.ustc.edu.cn/qtproject']
    repository = f'online/qtsdkrepository/{HOST}/desktop/qt6_6120/{SUBREPO}/'
    metadata = fetch(repository + 'Updates.xml', archives / 'Updates.xml', mirrors)
    jobs = []
    for package in ET.parse(metadata).getroot().findall('PackageUpdate'):
        name = package.findtext('Name', '')
        if name not in [f'qt.qt6.6120.{ARCH}', f'qt.qt6.6120.addons.qtshadertools.{ARCH}']:
            continue
        for archive in package.findtext('DownloadableArchives', '').split(', '):
            if archive.split('-')[0] not in MODULES:
                continue
            jobs.append((repository + name + '/' + package.findtext('Version') + archive, archives / archive))
    if len(jobs) < 6:
        raise RuntimeError('Incomplete official SDK metadata; refusing to use another Qt version')

    def download(job):
        relative, destination = job
        checksum = fetch(relative + '.sha1', Path(str(destination) + '.sha1'), mirrors).read_text().split()[0]
        archive = fetch(relative, destination, mirrors)
        if hashlib.sha1(archive.read_bytes()).hexdigest() != checksum:
            raise RuntimeError(f'Checksum mismatch: {archive}')
        print('Verified', archive.name, archive.stat().st_size, flush=True)
        return archive

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        files = list(pool.map(download, jobs))
    kit.mkdir(parents=True, exist_ok=True)
    for archive in files:
        if platform.system() == 'Darwin':
            command = ['bsdtar', '-xf', str(archive), '-C', str(kit)]
        else:
            sevenzip = shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'
            command = [sevenzip, 'x', '-y', '-o' + str(kit), str(archive)]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    (kit / 'bin/qt.conf').write_text('[Paths]\nPrefix=..\n', encoding='utf-8')
    if (kit / 'libexec').is_dir():
        (kit / 'libexec/qt.conf').write_text('[Paths]\nPrefix=..\n', encoding='utf-8')
    manifest = [{'archive': f.name, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest(), 'bytes': f.stat().st_size} for f in files]
    (output / 'sdk-manifest.json').write_text(json.dumps({'version': VERSION, 'kit': KIT, 'archives': manifest}, indent=2), encoding='utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as f:
            f.write(f'QT_ROOT={kit}\n')
        with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as f:
            f.write(str(kit / 'bin') + '\n')
    print(kit)


if __name__ == '__main__':
    main()
