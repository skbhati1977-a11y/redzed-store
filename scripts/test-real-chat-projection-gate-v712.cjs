#!/usr/bin/env node
const fs=require('fs'),vm=require('vm');
const p='test70-real-chat-live-v70.js',s=fs.readFileSync(p,'utf8'),fail=[];
try{new vm.Script(s)}catch(e){fail.push('main Real Chat JavaScript parse failure: '+e.message)}
const need=[
 ['V709 projection helper',/async function departmentProjectionV709\s*\(/],
 ['Cutting V712 adapter',/async function cuttingProjectionV712\s*\(/],
 ['canonical count helper',/async function departmentGroupVisibleCountsV730\s*\(/],
 ['root generation state',/rootRenderSeq\s*:\s*0/],
 ['navigation generation state',/navigationSeq\s*:\s*0/],
 ['root generation increment',/async function inbox\s*\(\)[\s\S]{0,220}rootGen\s*=\s*\+\+S\.rootRenderSeq/],
 ['department navigation increment',/async function openDepartment\s*\([^)]*\)[\s\S]{0,180}\+\+S\.navigationSeq/],
 ['chat navigation increment',/async function openChat\s*\([^)]*\)[\s\S]{0,180}\+\+S\.navigationSeq/],
 ['deterministic cache boot',/resumeState\.view==='inbox'&&cacheReady/],
 ['final inbox boot render',/else\s*\{S\.active=null;await inbox\(\)\}/],
 ['Fabrication V709 render',/departmentProjectionV709\('FABRICATION',S\.status\)/],
 ['Cutting V712 render',/allRows=await cuttingProjectionV712\(S\.status\)/]
];
for(const [n,re] of need)if(!re.test(s))fail.push('missing '+n);
const retired=[
 ['generic group direct V685',/departmentOperationalV685\(id,S\.status\)/],
 ['fabrication old render mirror',/fabricationMirrorV667\(S\.status\)/],
 ['cutting direct render',/allRows=await cuttingCanonicalRowsV681/],
 ['legacy root card total',/Object\.values\(S\.workCounts\)\.reduce/]
];
for(const [n,re] of retired)if(re.test(s))fail.push('retired path returned: '+n);
if(!/const sts=S\.search\?mirrorSearchStatuses\(d\.department_code\):\[\]/.test(s))fail.push('root normal render still depends on mirror search');
if(fail.length){console.error('REAL CHAT PROJECTION GATE FAIL\n'+fail.join('\n'));process.exit(1)}
console.log('REAL CHAT PROJECTION GATE PASS: JavaScript parses; V709 generic/Fabrication + V712 Cutting active; root/navigation generation guards active; deterministic boot present; retired UI forks absent.');
