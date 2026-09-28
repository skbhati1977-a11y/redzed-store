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

const universal=[
 ['universal visible projection dispatcher',/async function departmentVisibleProjectionV763\s*\(/],
 ['Admin visible adapter',/dep==='ADMIN'.*adminVisibleCountsV762/s],
 ['Purchase visible adapter',/dep==='PURCHASE'.*purchaseVisibleCountsV763/s],
 ['Commercial visible adapter',/\['SALES','ACCOUNTS','COSTING'\]\.includes\(dep\).*commercialVisibleCountsV763/s],
 ['Cutting visible adapter',/dep==='CUTTING'.*cuttingProjectionV712/s],
 ['Fabrication visible adapter',/dep==='FABRICATION'.*departmentProjectionV709/s],
 ['Production visible adapter',/RR_PRODUCTION_DEPARTMENTS_V763\.has\(dep\).*departmentProjectionV709/s],
 ['Dispatch covered by production adapter',/RR_PRODUCTION_DEPARTMENTS_V763=new Set\(\[[^\]]*'DISPATCH'/s],
 ['directory uses universal dispatcher',/departmentGroupVisibleCountsV730\(d\.department_code\)/],
 ['department directory uses universal dispatcher',/departmentGroupVisibleCountsV730\(id\)/]
];
for(const [n,re] of universal)if(!re.test(s))fail.push('missing '+n);
const allDepartments=['PURCHASE','CUTTING','PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','COSTING','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DISPATCH','FABRICATION','SALES','ACCOUNTS','ADMIN'];
for(const dep of allDepartments){const covered=dep==='ADMIN'?/dep==='ADMIN'/.test(s):dep==='PURCHASE'?/dep==='PURCHASE'/.test(s):['SALES','ACCOUNTS','COSTING'].includes(dep)?/\['SALES','ACCOUNTS','COSTING'\]\.includes\(dep\)/.test(s):dep==='CUTTING'?/dep==='CUTTING'/.test(s):dep==='FABRICATION'?/dep==='FABRICATION'/.test(s):new RegExp("RR_PRODUCTION_DEPARTMENTS_V763=new Set\\(\\[[^\\]]*'"+dep+"'","s").test(s);if(!covered)fail.push('department adapter coverage missing: '+dep)}
if(!/Promise\.all\(countRows\.map/.test(s)||!/rootGen!==S\.rootRenderSeq\|\|S\.active/.test(s))fail.push('atomic generation-scoped root count hydration missing');
if(!/function costingVisibleCardsV764/.test(s)||!/commercialVisibleCountsV763[\s\S]*costingVisibleCardsV764/.test(s))fail.push('shared costing visible semantics missing');
if(!/purchaseVisibleCountsV763[\s\S]*MATCHING_PURCHASE/.test(s))fail.push('purchase CB + matching parity missing');
if(!/function syncStatusButtons\(\)\{[\s\S]{0,260}const root=!S\.active[\s\S]{0,320}if\(root\|\|status==='CLOSE'\)/.test(s))fail.push('root status controls are not hard hidden');
if(!/function changeStatus\(status\)\{if\(S\.costEditorActive\|\|!S\.active\)return/.test(s))fail.push('root status change guard missing');
if(!/if\(rootGen!==S\.rootRenderSeq\|\|S\.active\)return/.test(s))fail.push('late root count navigation guard missing');
if(!/departmentCountCache:new Map\(\)/.test(s))fail.push('confirmed department count cache missing');
if(!/departmentCounts:Object\.fromEntries\(S\.departmentCountCache\)/.test(s)||!/S\.departmentCountCache=new Map\(Object\.entries\(c\.departmentCounts\|\|\{\}\)\)/.test(s))fail.push('confirmed counts are not persisted/restored');
if(!/cachedCount=S\.departmentCountCache\.get/.test(s))fail.push('root does not paint last confirmed counts');
if(/Department count batch hydrate[\s\S]{0,260}count unavailable/.test(s))fail.push('refresh failure still destroys confirmed count');
if(!/if\(!prev\|\|Number\(prev\.OPEN\)!==next\.OPEN\|\|Number\(prev\.WORKING\)!==next\.WORKING\)/.test(s))fail.push('unchanged counts still repaint');
if(!/TEST70_REAL_CHAT_FAST_V110:[^\n]*RR_ON_BEHALF_ACTIVE/.test(s)&&!/function cacheKey\(\)\{const actor=window\.RR_ON_BEHALF_ACTIVE/.test(s))fail.push('count cache is not actor scoped');
if(!/people=globalRole\?arr\(directory\.people\):arr\(directory\.people\)\.filter\(x=>String\(x\.worker_id\)===selectedId\|\|visiblePeople\.has/.test(s))fail.push('Act As still collapses department roster to selected actor');
if(!/function canonicalBackV767\(\)/.test(s))fail.push('canonical parent back navigation missing');
if(/\$\('back'\)\.onclick=\(\)=>history\.back\(\)/.test(s))fail.push('browser-history back regression returned');
if(!/rr_upm_salaried_team_context_v694/.test(s)||!/team\?\.is_team===true/.test(s)||!/rr_upm_claim_team_assignment_v694/.test(s))fail.push('Accept & Count team claim is not gated by canonical team context');
if(!/rr_upm_confirm_worker_lot_receipts_v692/.test(s))fail.push('canonical worker Accept & Count receipt confirmation missing');
if(!/rr_upm_ready_submit_to_receiver_v204/.test(s))fail.push('worker submit request/receiver handover path missing');
if(!/rr_upm_salaried_team_context_v694/.test(s)||!/team\?\.is_team===true/.test(s))fail.push('Accept fallback is not gated by canonical salaried-team context');
if(/not mapped to this worker\|effective worker identity[\s\S]{0,220}rr_upm_claim_team_assignment_v694/.test(s)&&!/team\?\.is_team===true/.test(s))fail.push('piece-rate Accept can still enter team claim path');
if(!/\$\('back'\)\.onclick=\(\)=>canonicalBackV767\(\)/.test(s))fail.push('back button is not bound to canonical parent navigation');
if(!/rr_upm_salaried_team_context_v694/.test(s)||!/team\?\.is_team===true/.test(s))fail.push('receipt fallback is not gated by canonical team context');
if(!/rr_upm_claim_team_assignment_v694/.test(s))fail.push('canonical team claim path missing');
if(!/rr_upm_salaried_team_context_v694/.test(s)||!/team\?\.is_team===true/.test(s)||!/rr_upm_claim_team_assignment_v694/.test(s))fail.push('team claim is not guarded by canonical team context');
if(/not mapped to this worker\|effective worker identity[^\n]{0,500}rr_upm_claim_team_assignment_v694/.test(s)&&!/team\?\.is_team===true/.test(s))fail.push('piece-rate receipt can still fall through to team claim');
if(!/rr_upm_ready_submit_to_receiver_v204/.test(s))fail.push('worker submit is not using shared ready-to-receiver lifecycle');
if(!/if\(!active&&!search&&!fast\)[\s\S]{0,700}await inbox\(\);return/.test(s))fail.push('root is not decoupled from projection lifecycle');
if(/departmentGroupVisibleCountsV730[\s\S]{0,1800}rr_real_chat_department_operational_v685/.test(s))fail.push('legacy V685 count fallback returned');

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
