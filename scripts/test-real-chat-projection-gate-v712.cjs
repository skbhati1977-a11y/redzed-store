#!/usr/bin/env node
const fs=require('fs');
const p='test70-real-chat-live-v70.js';
const s=fs.readFileSync(p,'utf8');
const fail=[];
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
if(fail.length){console.error('REAL CHAT PROJECTION GATE FAIL\n'+fail.join('\n'));process.exit(1)}
console.log('REAL CHAT PROJECTION GATE PASS: V709 generic + Fabrication, V712 Cutting; retired UI forks absent.');
