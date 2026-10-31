.pragma library
function bytes(kb) { kb=Number(kb)||0; return Math.abs(kb)>=1048576?(kb/1048576).toFixed(2)+" GB":Math.abs(kb)>=1024?(kb/1024).toFixed(1)+" MB":Math.round(kb)+" kB" }
function delta(kb) { return (kb>=0?"+":"−")+bytes(Math.abs(kb)) }
function duration(ms) { var s=Math.round((Number(ms)||0)/1000);return s<60?s+"s":Math.floor(s/60)+"m"+s%60+"s" }
function date(ms) { if(!ms)return "—";return Qt.formatDateTime(new Date(Number(ms)),"yyyy-MM-dd HH:mm:ss") }
function device(d,fallback) { d=d||{};var name=d.marketName||d.model||"",sn=d.serialNumber||d.targetId||fallback||"",v=(d.softwareVersion||"").replace(/^HarmonyOS\s*/i,""),api=d.apiVersion||"";return [(name?(sn?name+"["+sn+"]":name):sn),(v?(api?v+"("+api+")":v):api)].filter(function(s){return !!s}).join(" ")||"未知设备" }
function title(meta) {return meta.taskName||meta.appLabel||meta.bundleName||"报告"}
function taskName(){return "Task-"+Qt.formatDateTime(new Date(),"yyyyMMdd-HHmmss")}
function mb(kb){return (Number(kb||0)/1024).toFixed(2)}
function categoryRows(s) {s=s||{};var rows=[];if(!s.total)return rows;rows.push(Object.assign({name:"Total",fixed:true},s.total));Object.keys(s.categories||{}).forEach(function(k){rows.push(Object.assign({name:k},s.categories[k]))});Object.keys(s.nativeHeapDetail||{}).forEach(function(k){rows.push(Object.assign({name:"↳ "+k},s.nativeHeapDetail[k]))});return rows}
var comparisonColors=["#1677ff","#fa8c16","#52c41a","#722ed1"]
