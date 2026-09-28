#!/usr/bin/env node
const fs=require('fs');
const vm=require('vm');
const p='test70-real-chat-live-v70.js';
const s=fs.readFileSync(p,'utf8');
const fail=[];
try{new vm.Script(s)}catch(e){fail.push('main Real Chat JavaScript parse failure: '+e.message)}
const must=[
 ['V709 projection helper','async function departmentProjectionV709'],
 ['Cutting single adapter','async function cuttingProjectionV712'],
 ['Directory canonical count helper','async function departmentGroupVisibleCountsV730']
];
for(const [n,x] of must)if(!s.includes(x))fail.push('missing '+n);
const retired=[
 ['generic group direct V685','departmentOperationalV685(id,S.status)'],
 ['fabrication old render mirror','fabricationMirrorV667(S.status)'],
 ['cutting direct render','allRows=await cuttingCanonicalRowsV681']
];
for(const [n,x] of retired)if(s.includes(x))fail.push('retired path returned: '+n);
if(!s.includes("departmentProjectionV709('FABRICATION',S.status)"))fail.push('Fabrication group is not on V709');
if(!s.includes("allRows=await cuttingProjectionV712(S.status)"))fail.push('Cutting group is not on V712 adapter');
if(!s.includes('async function inbox(){S.active=null;syncStatusButtons();const rootGen=++S.rootRenderSeq'))fail.push('inbox root generation guard missing');
if(!s.includes("async function openDepartment(id,push=true){const nav=++S.navigationSeq"))fail.push('department navigation token missing');
if(!s.includes("async function openChat(kind,id,push=true,parentDepartment=null){const navigationSeq=++S.navigationSeq"))fail.push('chat navigation token missing');
if(!s.includes('const S={rootRenderSeq:0,navigationSeq:0,'))fail.push('navigation/root generation state missing');
if(!s.includes("const sts=S.search?mirrorSearchStatuses(d.department_code):[]"))fail.push('root still depends on mirror search when search is empty');
if(s.includes("if(nav!==S.navigationSeq||S.active)return;$('rows').innerHTML=h"))fail.push('root directory paint can still be silently cancelled');
if(s.includes("Object.values(S.workCounts).reduce"))fail.push('legacy root card total authority returned');
if(!s.includes("if(resumeState.view==='inbox'&&cacheReady"))fail.push('deterministic boot cache rule missing');
if(!s.includes("if(resumeState.view!=='inbox')restoreView(resumeState);else{S.active=null;await inbox()}"))fail.push('boot final root render missing');
if(!s.includes("async function inbox(){S.active=null;syncStatusButtons();const rootGen=++S.rootRenderSeq"))fail.push('standalone root render contract missing');
if(fail.length){console.error('REAL CHAT PROJECTION GATE FAIL\n'+fail.join('\n'));process.exit(1)}
console.log('REAL CHAT PROJECTION GATE PASS: V709 generic + Fabrication, V712 Cutting; root generation + navigation guards active; retired UI forks absent.');
