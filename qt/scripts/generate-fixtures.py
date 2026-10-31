#!/usr/bin/env python3
"""Deterministic reports shared by the Electron and Qt UI/performance checks."""
import argparse
import json
import math
from pathlib import Path

KEYS = ['pssTotalKb', 'sharedCleanKb', 'sharedDirtyKb', 'privateCleanKb', 'privateDirtyKb', 'swapTotalKb', 'swapPssTotalKb', 'heapSizeKb', 'heapAllocKb', 'heapFreeKb']
CATEGORIES = ['GL', 'Graph', 'ark ts heap', 'native heap', 'stack', '.so', '.hap', 'AnonPage other', 'FilePage other', 'dev', '.db', '.ttf', 'guard']
START = 1793404800000
DEVICE = dict(targetId='WOODY-QA-001', marketName='HUAWEI Mate 60 Pro', model='ALN-AL80', softwareVersion='HarmonyOS 6.1.1.120', apiVersion='18', serialNumber='WOODY-QA-001', ramTotalKb=12*1024*1024, screenResolution='1260 × 2720')

def memory(kb):
    return dict(zip(KEYS, [kb, int(kb*.09), int(kb*.02), int(kb*.16), int(kb*.63), 0, int(kb*.01), int(kb*.8), int(kb*.6), int(kb*.2)]))

def sample(index, variant=0):
    cats = {name: memory(max(0, int((13-i)*1500*(1+.16*math.sin(index/21+i)+.0003*index)*(1+variant*.08)))) for i,name in enumerate(CATEGORIES)}
    if index == 123: cats['native heap'] = memory(cats['native heap']['pssTotalKb'] + 130000)
    if variant == 2 and 30 <= index < 80: del cats['GL']
    total = {key: sum(row[key] for row in cats.values()) for key in KEYS}
    return dict(timestamp=START+index*1000, pid=2411+variant, total=total, categories=cats, nativeHeapDetail={'jemalloc heap':memory(cats['native heap']['pssTotalKb']-1024),'jemalloc meta':memory(1024)}, purgSumKb=128, purgPinKb=64, dmaKb=4096, ashmemTotalKb=8192)

def write_report(root, name, count, variant=0, snapshot=False):
    directory = root/name
    directory.mkdir(parents=True, exist_ok=True)
    meta = dict(id=name, taskName=name, type='snapshot' if snapshot else 'trend', bundleName='com.example.woodyqa', appLabel='Woody QA', device=DEVICE, config=dict(intervalMs=1000,showAshmem=False,showDmabuf=False,showGpumem=False), startedAt=START, endedAt=START+(count-1)*1000, sampleCount=1 if snapshot else count, sessionDir=str(directory.resolve()))
    (directory/'meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    if snapshot:
        s=sample(123,variant); s['capturedAt']=s.pop('timestamp')
        s.update(ashmemDetail=[dict(name='Create PixelMap',fd=7,virtualBytes=8388608,physicalBytes=4194304)],dmabufDetail=[dict(name='RenderXComponent',fd=9,ino=123456,sizeBytes=4194304)],gpuDetail=dict(channels=[dict(name='GL',totalBytes=67108864),dict(name='Graph',totalBytes=8388608)],totalUsedBytes=75497472,totalAllocatedBytes=83886080))
        (directory/'snapshot.json').write_text(json.dumps(s,ensure_ascii=False,indent=2),encoding='utf-8')
    else:
        with (directory/'samples.jsonl').open('w',encoding='utf-8') as f:
            for i in range(count): f.write(json.dumps(sample(i,variant),separators=(',',':'))+'\n')
    return directory

def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path);parser.add_argument('--benchmark',action='store_true');args=parser.parse_args();root=args.directory.resolve();root.mkdir(parents=True,exist_ok=True)
    if args.benchmark: write_report(root,'benchmark-3600',3600)
    for i,count in enumerate([180,240,300,360]):write_report(root,f'Trend-{i+1}',count,i)
    for i in range(2):write_report(root,f'Snapshot-{i+1}',1,i,True)
    print(root)
if __name__=='__main__':main()
