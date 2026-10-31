#!/usr/bin/env python3
"""Exercise native windows with deterministic old-format reports and real Qt input events."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--exe',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--fixtures',type=Path,required=True);parser.add_argument('--hdc',type=Path);args=parser.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True);fixtures=args.fixtures.resolve()
    profile=output/'profile';profile.mkdir(exist_ok=True)
    settings={'sessionsDir':str(fixtures),'hdcPath':str(args.hdc.resolve()) if args.hdc else ''}
    (profile/'settings.json').write_text(json.dumps(settings),encoding='utf-8')
    report=lambda name:json.dumps(str(fixtures/name))
    steps=[]
    def add(name,**kwargs):steps.append(dict(name=name,**kwargs))
    add('main window',delay=700,eval='qa.nativePointer=true;qa.hover(root.bodyItem,2,2)',screenshot='main.png')
    for page in ['tools','watch','peak','snap','reports','settings']:
        add('navigate '+page,eval=f'root.go({json.dumps(page)})')
        add('render '+page,delay=160,screenshot=page+'.png')
    add('open trend',eval='backend.openReport('+report('Trend-1')+')',wait='root.childWindows.length===1')
    add('trend layout',delay=200,eval='var report=root.childWindows[0];var plot=qa.find(report,"memoryPlot");qa.hover(plot,0,0);',assert_='plot.width>300 && plot.height>200 && qa.find(report,"statCards").height===90',window='report',screenshot='trend.png')
    add('zoom native chart',eval='qa.wheel(plot,plot.width/2,plot.height/2,400)',assert_='plot.rangeEnd-plot.rangeStart<plot.totalSpan')
    add('hover sample',eval='qa.hover(plot,plot.width*.6,plot.height*.5)',wait='plot.tooltip.items && plot.tooltip.items.length===14',window='report',screenshot='tooltip.png')
    add('enter tooltip',eval='var tip=qa.find(report,"chartTip");qa.hover(tip.contentItem,40,30)')
    add('tooltip remains enterable',delay=500,assert_='tip.visible && tip.retained.items.length===14')
    add('leave tooltip',eval='qa.hover(report.bodyItem,2,2)')
    add('tooltip dismissed',wait='!tip.visible',timeout=2500)
    add('expand chart',eval='qa.click(qa.find(report,"maximizeChart"),-1,-1)',wait='qa.find(report,"expandedChart").opened')
    add('expanded screenshot',delay=200,window='report',screenshot='chart-expanded.png')
    add('restore expanded chart',eval='qa.key(report,16777216)',wait='!qa.find(report,"expandedChart").opened')
    add('reset chart',eval='plot.resetView();qa.hover(plot,0,0)',assert_='plot.rangeStart===0 && plot.rangeEnd===plot.totalSpan')
    add('rename report',eval='backend.renameReport('+report('Trend-1')+',"Trend-1 重命名");',wait='report.meta.taskName==="Trend-1 重命名"')
    add('restore name',eval='backend.renameReport('+report('Trend-1')+',"Trend-1")',wait='report.meta.taskName==="Trend-1"')
    add('open snapshot',eval='backend.openReport('+report('Snapshot-1')+')',wait='root.childWindows.length===2')
    add('snapshot',delay=200,window='root.childWindows[1]',screenshot='snapshot.png')
    paths=[str(fixtures/f'Trend-{i}') for i in range(1,5)]
    add('open four-report comparison',eval='backend.openCompare('+json.dumps(paths)+')',wait='root.childWindows.length===3')
    add('overlay layout',delay=250,eval='var compare=root.childWindows[2];var comparisonPlot=qa.find(compare,"memoryPlot");qa.hover(comparisonPlot,0,0)',assert_='comparisonPlot.width>300 && comparisonPlot.height>150',window='compare',screenshot='compare-overlay.png')
    add('peak alignment',eval='compare.alignment="peak";compare.metric="GL";',assert_='comparisonPlot.alignment==="peak" && comparisonPlot.metric==="GL"')
    add('end alignment',eval='compare.alignment="end";',assert_='comparisonPlot.totalSpan>=359')
    add('change baseline',eval='compare.move(3,0)',assert_='compare.ordered[0].meta.id==="Trend-4" && compare.ordered[0].compareColor==="#722ed1"')
    add('picked mode',eval='compare.tab=1')
    add('select a sample',delay=200,eval='var mini=qa.find(compare,"memoryPlot");qa.click(mini,mini.width*.35,mini.height*.4)',assert_='compare.selected(compare.ordered[0])!==123',window='compare',screenshot='compare-picked.png')
    add('snapshot comparison',eval='backend.openCompare('+json.dumps([str(fixtures/'Snapshot-1'),str(fixtures/'Snapshot-2')])+')',wait='root.childWindows.length===4')
    add('snapshot difference',delay=200,assert_='root.childWindows[3].differenceRows.length===14',window='root.childWindows[3]',screenshot='compare-snapshot.png')
    add('activate independent window',eval='var closingWindow=root.childWindows[1];closingWindow.raise();closingWindow.requestActivate()',wait='closingWindow.active')
    add('minimize independent window shortcut',eval='qa.key(closingWindow,77,67108864)',wait='closingWindow.visibility===3')
    add('restore independent window',eval='closingWindow.showNormal();closingWindow.raise();closingWindow.requestActivate()',wait='closingWindow.active')
    add('independent window close shortcut',eval='qa.key(closingWindow,87,'+str(67108864)+')',wait='root.childWindows.length===3',assert_='report.visible && compare.visible')
    add('narrow title and report',eval='report.width=640;report.height=680;',delay=100)
    add('narrow screenshot',delay=200,assert_='qa.find(report,"memoryPlot").width>200',window='report',screenshot='report-narrow.png')
    if args.hdc:
        add('live configuration',eval='root.raise();root.requestActivate();root.go("watch");',wait='backend.target.length>0 && qa.find(root,"startButton") && qa.find(root,"startButton").enabled')
        add('start live via button',eval='qa.click(qa.find(root,"startButton"),-1,-1)',wait='root.page==="live" && backend.live.count>=2',timeout=10000)
        add('live window',screenshot='live.png',assert_='backend.live.stats.last===196608')
        add('stop live via button',eval='qa.click(qa.find(root,"stopButton"),-1,-1)',wait='!backend.sampling && root.page==="watch"')
    for step in steps:
        if 'assert_' in step:step['assert']=step.pop('assert_')
    script=output/'scenario.json';script.write_text(json.dumps({'steps':steps},ensure_ascii=False,indent=2),encoding='utf-8')
    command=[str(args.exe.resolve()),'--profile',str(profile),'--qa',str(script),'--metrics',str(output/'startup.json')]
    if not args.hdc:command.append('--offline')
    env=os.environ.copy()
    if args.hdc:
        state=output/'hdc-state.json';state.write_text('{"pid":2411}',encoding='utf-8');env['WOODY_FAKE_STATE']=str(state)
    with (output/'application.log').open('w',encoding='utf-8') as log:
        result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
    log=(output/'application.log').read_text(encoding='utf-8',errors='replace');print(log)
    if result.returncode:
        if (output/'ui-result.json').exists():print((output/'ui-result.json').read_text(encoding='utf-8'))
        raise SystemExit(result.returncode)
    verification=json.loads((output/'ui-result.json').read_text(encoding='utf-8'))
    if not verification['passed']:raise SystemExit(2)
    if any(marker in log for marker in ['TypeError:','ReferenceError:','Unable to assign','Binding loop','failed to load component','Cannot specify','Row will not function']):
        raise RuntimeError('QML runtime diagnostics found; see application.log')
    print('PASS',len(verification['steps']),'native UI checks')


if __name__=='__main__':main()
