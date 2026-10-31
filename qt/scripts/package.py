#!/usr/bin/env python3
"""Deploy only native Qt dependencies, create installers and directory ZIPs, and measure bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = json.loads((ROOT/'package.json').read_text(encoding='utf-8'))['version']


def run(command, **kwargs):
    print('+', ' '.join(map(str, command)), flush=True)
    return subprocess.run(list(map(str, command)), check=True, **kwargs)


def copy_notices(destination):
    shutil.copytree(ROOT/'qt/licenses', destination/'licenses', dirs_exist_ok=True)
    shutil.copy2(ROOT/'LICENSE', destination/'LICENSE.txt')


def mac_package(args, staging, output, prefix):
    app = staging/'Woody.app'
    shutil.copytree(args.build/'qt/Woody.app', app, symlinks=True)
    run([args.qt/'bin/macdeployqt', app, '-qmldir='+str(ROOT/'qt/qml'), '-always-overwrite', '-no-codesign'])
    copy_notices(app/'Contents/Resources')
    # Official macOS SDKs are Universal. Each artifact contains its advertised architecture only.
    for file in app.rglob('*'):
        if not file.is_file() or file.is_symlink():
            continue
        with file.open('rb') as stream:
            magic=stream.read(4)
        if magic not in (b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'):
            continue
        archs=subprocess.check_output(['lipo','-archs',str(file)],text=True).strip().split()
        target='x86_64' if args.arch=='x64' else 'arm64'
        if target not in archs:
            raise RuntimeError(f'{file} does not contain {target}: {archs}')
        if len(archs)>1:
            thin=file.with_name(file.name+'.thin')
            run(['lipo',file,'-thin',target,'-output',thin],stdout=subprocess.DEVNULL)
            thin.chmod(file.stat().st_mode);thin.replace(file)
        dependencies=subprocess.check_output(['otool','-L',str(file)],text=True)
        if str(args.qt) in dependencies or '/Users/qt/' in dependencies:
            raise RuntimeError('Undeployed SDK dependency: '+str(file))
    run(['codesign','--force','--deep','--sign','-','--timestamp=none',app])
    run(['codesign','--verify','--deep','--strict',app])
    portable=output/(prefix+'-portable.zip')
    run(['ditto','-c','-k','--sequesterRsrc','--keepParent',app,portable])
    artifacts=[portable]
    if not args.skip_installer:
        (staging/'Applications').symlink_to('/Applications')
        dmg=output/(prefix+'.dmg')
        run(['hdiutil','create','-volname','Woody','-srcfolder',staging,'-ov','-format','UDZO','-fs','HFS+',dmg])
        artifacts.append(dmg)
    return app,artifacts


def nsis_quote(value):
    return str(value).replace('$','$$').replace('"','$\\"')


def windows_package(args, staging, output, prefix):
    folder=staging/'Woody'
    folder.mkdir()
    source=args.build/'qt/Release/Woody.exe'
    if not source.exists():source=args.build/'qt/Woody.exe'
    shutil.copy2(source,folder/'Woody.exe')
    run([args.qt/'bin/windeployqt.exe','--release','--no-compiler-runtime','--no-translations','--qmldir',ROOT/'qt/qml',folder/'Woody.exe'])
    # App-local CRT makes the ZIP usable on clean Windows without running a redistributable installer.
    vswhere=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
    visual_studio=Path(subprocess.check_output([str(vswhere),'-latest','-products','*','-property','installationPath'],text=True).strip())
    crt_dirs=sorted((visual_studio/'VC/Redist/MSVC').glob('*/x64/Microsoft.VC*.CRT'))
    if not crt_dirs:raise RuntimeError('MSVC app-local runtime not found')
    for dll in crt_dirs[-1].glob('*.dll'):shutil.copy2(dll,folder/dll.name)
    copy_notices(folder)
    portable=output/(prefix+'-portable.zip')
    with zipfile.ZipFile(portable,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for file in sorted(folder.rglob('*')):
            if file.is_file():archive.write(file,file.relative_to(staging).as_posix())
    artifacts=[portable]
    if not args.skip_installer:
        setup=output/(prefix+'-setup.exe')
        installed=[p.relative_to(folder) for p in folder.rglob('*') if p.is_file()]
        directories=sorted([p.relative_to(folder) for p in folder.rglob('*') if p.is_dir()],key=lambda p:len(p.parts),reverse=True)
        deletes='\n'.join('  Delete "$INSTDIR\\'+nsis_quote(str(p))+'"' for p in installed)
        removes='\n'.join('  RMDir "$INSTDIR\\'+nsis_quote(str(p))+'"' for p in directories)
        script=output/'installer.nsi'
        script.write_text(f'''Unicode True
!include "MUI2.nsh"
Name "Woody (Qt)"
OutFile "{nsis_quote(setup)}"
InstallDir "$LOCALAPPDATA\\Programs\\WoodyQt"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ICON "{nsis_quote(ROOT/'qt/resources/icon.ico')}"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "{nsis_quote(ROOT/'LICENSE')}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"
Section "Woody"
  SetOutPath "$INSTDIR"
  File /r "{nsis_quote(folder)}\\*"
  WriteUninstaller "$INSTDIR\\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\\Woody (Qt)"
  CreateShortcut "$SMPROGRAMS\\Woody (Qt)\\Woody.lnk" "$INSTDIR\\Woody.exe"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WoodyQt" "DisplayName" "Woody (Qt)"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WoodyQt" "DisplayVersion" "{VERSION}"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WoodyQt" "UninstallString" '$"$INSTDIR\\Uninstall.exe$"'
SectionEnd
Section "Uninstall"
{deletes}
{removes}
  Delete "$INSTDIR\\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\\Woody (Qt)\\Woody.lnk"
  RMDir "$SMPROGRAMS\\Woody (Qt)"
  DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WoodyQt"
SectionEnd
''',encoding='utf-8-sig')
        makensis=shutil.which('makensis') or str(Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'NSIS/makensis.exe')
        run([makensis,'/V2',script])
        artifacts.append(setup)
    return folder,artifacts


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--build',type=Path,required=True);parser.add_argument('--qt',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--arch',choices=['arm64','x64'],required=True);parser.add_argument('--skip-installer',action='store_true');args=parser.parse_args()
    args.build=args.build.resolve();args.qt=args.qt.resolve();output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    staging=output/'staging'
    if staging.exists():shutil.rmtree(staging)
    staging.mkdir()
    host='mac' if platform.system()=='Darwin' else 'win';prefix=f'Woody-{VERSION}-qt-{host}-{args.arch}'
    package,artifacts=(mac_package if host=='mac' else windows_package)(args,staging,output,prefix)
    files=[p for p in package.rglob('*') if p.is_file() and not p.is_symlink()]
    sizes=[{'file':p.relative_to(package).as_posix(),'bytes':p.stat().st_size} for p in files]
    data={'version':VERSION,'qt':'6.12.0','platform':host,'arch':args.arch,'expandedBytes':sum(p['bytes'] for p in sizes),'fileCount':len(sizes),'artifacts':[{'name':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in artifacts],'largestFiles':sorted(sizes,key=lambda p:p['bytes'],reverse=True)[:30]}
    (output/'package-sizes.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in data.items() if k!='largestFiles'},indent=2))


if __name__=='__main__':main()
