#!/usr/bin/env python3
"""Compare whole process trees with shared production reports; run on an otherwise idle host.

RSS is the sum of process resident sets (shared pages can be counted more than once).
USS, where the OS exposes it, counts private resident pages. CPU 100% means one core.
Startup is externally timed spawn-to-ready; caches are not flushed, so these are warm launches.
"""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time
import psutil

ROOT=Path(__file__).resolve().parents[2]


def qt_command(executable,output,fixtures,mode):
    profile=output/'profile';profile.mkdir(exist_ok=True)
    (profile/'settings.json').write_text(json.dumps({'hdcPath':'','sessionsDir':str(fixtures)}))
    steps=[{'name':'settle','delay':1000,'eval':'qa.mark("idle")'}, {'name':'idle','delay':3000}]
    if mode=='report':
        steps += [{'name':'load report','eval':'qa.mark("loading");backend.openReport('+json.dumps(str(fixtures/'benchmark-3600'))+')','wait':'root.childWindows.length===1'},
                  {'name':'report settle','delay':2000,'eval':'qa.mark("report-idle"); var plot=qa.find(root.childWindows[0],"memoryPlot");qa.hover(plot,0,0)'},
                  {'name':'interactive workload','delay':3000,'eval':'qa.runWorkload(plot,10000)','wait':'qa.workloadDone','timeout':16000}]
    else:steps.append({'name':'done','eval':'qa.mark("done")'})
    script=output/'scenario.json';script.write_text(json.dumps({'steps':steps}),encoding='utf-8')
    return [str(executable),'--offline','--profile',str(profile),'--qa',str(script),'--ready-file',str(output/'ready')]


def measure(label,command,output,environment):
    output.mkdir(parents=True,exist_ok=True)
    for name in ['ready','phase.json','interaction.json']:
        (output/name).unlink(missing_ok=True)
    phases=defaultdict(list);cpu_totals={};last_phase='starting';started=time.perf_counter();ready_ms=None
    log=(output/'application.log').open('w',encoding='utf-8')
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=environment)
    parent=psutil.Process(process.pid);uss_done=set();uss={}
    try:
        while process.poll() is None:
            now=time.perf_counter()
            if now-started>100:raise RuntimeError('Benchmark timed out: '+label)
            if ready_ms is None and (output/'ready').exists():ready_ms=(now-started)*1000
            try:last_phase=json.loads((output/'phase.json').read_text(encoding='utf-8'))['phase']
            except (OSError,json.JSONDecodeError):pass
            try:tree=[parent]+parent.children(recursive=True)
            except psutil.Error:tree=[]
            rss=0
            for item in tree:
                try:
                    with item.oneshot():
                        rss+=item.memory_info().rss
                        times=item.cpu_times();cpu_totals[item.pid]=times.user+times.system
                except psutil.Error:pass
            phases[last_phase].append({'time':now-started,'rss':rss,'cpu':sum(cpu_totals.values()),'processes':len(tree)})
            # USS is more expensive to query; take one settled sample rather than perturbing every frame.
            if last_phase in ['idle','report-idle','interaction'] and last_phase not in uss_done and len(phases[last_phase])>=30:
                uss_done.add(last_phase)
                try:uss[last_phase]=sum(p.memory_full_info().uss for p in tree)
                except (psutil.Error,AttributeError):uss[last_phase]=None
            time.sleep(.05)
        if process.returncode:raise RuntimeError(f'{label} exited {process.returncode}; see {output}/application.log')
    finally:
        if process.poll() is None:
            for child in parent.children(recursive=True):
                try:child.terminate()
                except psutil.Error:pass
            process.terminate();process.wait(timeout=10)
        log.close()
    summary={'label':label,'startupMs':ready_ms,'phases':{}}
    for phase,rows in phases.items():
        if phase not in ['idle','report-idle','interaction'] or len(rows)<2:continue
        elapsed=rows[-1]['time']-rows[0]['time']
        summary['phases'][phase]={'durationSeconds':elapsed,'meanRssBytes':statistics.mean(r['rss'] for r in rows),'peakRssBytes':max(r['rss'] for r in rows),'privateResidentBytes':uss.get(phase),'meanCpuPercentOneCore':100*(rows[-1]['cpu']-rows[0]['cpu'])/elapsed,'processCount':max(r['processes'] for r in rows)}
    if (output/'interaction.json').exists():
        summary['interaction']=json.loads((output/'interaction.json').read_text(encoding='utf-8'))
        if summary['interaction']['inputTicks'] != 400:raise RuntimeError('Incomplete input workload')
    (output/'observations.json').write_text(json.dumps({'summary':summary,'samples':dict(phases)},indent=2),encoding='utf-8')
    print(json.dumps(summary,indent=2),flush=True)
    return summary


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--qt-exe',type=Path,required=True);parser.add_argument('--electron-exe',type=Path,required=True);parser.add_argument('--fixtures',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--runs',type=int,default=3);args=parser.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True);fixtures=args.fixtures.resolve()
    rows=[]
    for mode in ['main','report']:
        for repetition in range(args.runs):
            for label,executable in [('electron',args.electron_exe.resolve()),('qt',args.qt_exe.resolve())]:
                folder=output/f'{mode}-{repetition+1}-{label}';folder.mkdir(parents=True,exist_ok=True)
                env=os.environ.copy();env.pop('ELECTRON_RUN_AS_NODE',None);env.pop('ELECTRON_RENDERER_URL',None)
                if label=='qt':command=qt_command(executable,folder,fixtures,mode)
                else:
                    config=folder/'config.json';config.write_text(json.dumps({'output':str(folder),'fixtures':str(fixtures),'mode':mode}));env['WOODY_PERF_CONFIG']=str(config);command=[str(executable),str(ROOT/'qt/scripts/electron-perf.cjs')]
                result=measure(label,command,folder,env);result.update(mode=mode,repetition=repetition+1);rows.append(result)
                time.sleep(1)
    data={'host':platform.platform(),'machine':platform.machine(),'logicalCpus':psutil.cpu_count(),'physicalMemoryBytes':psutil.virtual_memory().total,'qt':'6.12.0','electron':json.loads((ROOT/'node_modules/electron/package.json').read_text(encoding='utf-8'))['version'],'sampleCount':3600,'categoryCount':13,'notes':['Warm process launches: filesystem caches were not cleared.','RSS sums every process and can double-count shared pages; USS is separately sampled where available.','CPU includes the full app process tree; 100% is one logical core.','The 10-second chart workload sends exactly 400 hover and 100 wheel events, catching up delayed timer ticks. Timer-delay diagnostics are not FPS or input-to-photon latency.','Electron uses the unchanged production out/main entry with device discovery mocked; Qt uses the provided executable.'],'runs':rows}
    (output/'benchmark.json').write_text(json.dumps(data,indent=2),encoding='utf-8')


if __name__=='__main__':main()
