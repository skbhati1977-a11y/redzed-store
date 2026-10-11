const test=require('node:test');const assert=require('node:assert/strict');
const {checkRole,run}=require('../scripts/test71-independent-role-financial.cjs');
function fixture(role,{identityRole=role,onBehalf=false,rpcError='42501'}={}){
 const calls=[];const env={[`TEST71_ROLE_${role}_EMAIL`]:'fixture@example.invalid',[`TEST71_ROLE_${role}_PASSWORD`]:'fixture-only'};
 const fetcher=async(url,options)=>{calls.push({url,options});let data,status=200;
 if(url.includes('/token?'))data={access_token:'fixture-token',user:{id:'fixture-user'}};
 else if(url.endsWith('/user'))data={id:'fixture-user'};
 else if(url.includes('/rr_user_profiles?'))data=[{role_code:role,is_active:true,access_status:'ACTIVE'}];
 else if(url.includes('rr_upm_effective_identity'))data={resolved_role:identityRole,on_behalf:onBehalf,operator_user_id:"fixture-user",effective_auth_user_id:"fixture-user"};
 else if(url.includes('/rpc/')){if(role==='ADMIN'||role==='ACCOUNTS')data={};else {data={code:rpcError};status=403;}}
 else data={};return {ok:status<300,status,json:async()=>data};};return {env,fetcher,calls};
}
test('missing credentials remain blocked without auth requests',async()=>{const result=await checkRole('WORKER',{},()=>assert.fail('request forbidden'));assert.equal(result.status,'BLOCKED');});
test('worker uses independent login, TEST-only reads and definite denial',async()=>{const f=fixture('WORKER');const r=await checkRole('WORKER',f.env,f.fetcher);assert.equal(r.status,'PASS');assert.equal(f.calls.filter(c=>c.url.includes('/rpc/')).length,3);assert.ok(f.calls.filter(c=>/trial_balance|accounts_real_chat/.test(c.url)).every(c=>JSON.parse(c.options.body).p_data_mode==='TEST'));assert.ok(f.calls.at(-1).url.endsWith('/logout?scope=local'));assert.ok(!JSON.stringify(r).includes('fixture-token'));});
test('administrator authority passes only successful reads',async()=>{const f=fixture('ADMIN');assert.equal((await checkRole('ADMIN',f.env,f.fetcher)).status,'PASS');});
test('Act As and mismatched role never count as independent evidence',async()=>{for(const options of [{onBehalf:true},{identityRole:'SUPER_ADMIN'}]){const f=fixture('WORKER',options);assert.equal((await checkRole('WORKER',f.env,f.fetcher)).status,'FAIL');assert.equal(f.calls.filter(c=>/trial_balance|accounts_real_chat/.test(c.url)).length,0);}});
test('network/schema failure does not count as permission denial',async()=>{const f=fixture('SALES',{rpcError:'57014'});assert.equal((await checkRole('SALES',f.env,f.fetcher)).status,'FAIL');});

test('malformed auth and profile JSON fail without exposing upstream content',async()=>{for(const path of ['/token?','/rr_user_profiles?']){const f=fixture('ADMIN');const base=f.fetcher;f.fetcher=async(url,options)=>url.includes(path)?{ok:true,status:200,json:async()=>{throw Error('private upstream body')}}:base(url,options);const result=await checkRole('ADMIN',f.env,f.fetcher);assert.equal(result.status,'FAIL');assert.equal(result.reason,'request_failed');assert.ok(!JSON.stringify(result).includes('private upstream body'));}});
test('duplicate authenticated IDs invalidate both role evidence entries',async()=>{const env={};for(const role of ['WORKER','ADMIN']){env[`TEST71_ROLE_${role}_EMAIL`]=role;env[`TEST71_ROLE_${role}_PASSWORD`]='fixture-only';}let role;const fetcher=async(url,options)=>{if(url.includes('/token?'))role=JSON.parse(options.body).email;return fixture(role).fetcher(url,options);};const result=await run(env,fetcher);for(const row of result.roles.filter(r=>['WORKER','ADMIN'].includes(r.role)))assert.equal(row.reason,'duplicate_authenticated_user');assert.ok(!JSON.stringify(result).includes('fixture-user'));});
