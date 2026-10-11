// CI-only secure bootstrap: no secrets, sessions or financial payloads are printed or written.
const {runnerHeaders}=require('../tests/e2e/session');
const PROJECT='https://hruartsemierwhtzonei.supabase.co';
const KEY='sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga';
const BRANCH='test71-real-chat-e2e-finalization';
const SLUG='test71-independent-financial';
async function run({env=process.env,fetcher=fetch,headers=runnerHeaders,wait=ms=>new Promise(r=>setTimeout(r,ms))}={}){
 const base=env.E2E_BASE_URL,sha=env.E2E_EXPECTED_DEPLOYMENT_SHA||env.GITHUB_SHA;
 if(!base||!sha||!/^https:\/\/redzed-test65-[a-z0-9-]+\.vercel\.app\/?$/i.test(base))throw Error('Missing exact TEST preview URL or commit');
 const authorization=await headers();let session;
 for(let attempt=0;attempt<12;attempt++){
  const response=await fetcher(new URL('/api/e2e-session',base),{method:'POST',headers:authorization,signal:AbortSignal.timeout(25000)});
  if(response.status===503&&response.headers.get('x-test71-upstream-unavailable')==='1')throw Error('TEST Auth unavailable; independent verification not started');
  if(response.ok){const candidate=await response.json();if(candidate.deployment?.branch===BRANCH&&candidate.deployment.environment==='preview'&&candidate.deployment.commit_sha===sha){session=candidate;break;}
   if(candidate.access_token){const rejected=await fetcher(`${PROJECT}/auth/v1/logout?scope=local`,{method:'POST',headers:{apikey:KEY,Authorization:`Bearer ${candidate.access_token}`},signal:AbortSignal.timeout(5000)}).catch(()=>null);if(!rejected?.ok)throw Error('Rejected preview session cleanup failed');}}
  else if(![404,503].includes(response.status))throw Error('Secure TEST bootstrap denied');
  if(attempt<11)await wait(5000);
 }
 if(!session?.access_token)throw Error('Exact TEST preview unavailable; independent verification not started');
 // GitHub log redaction is defense in depth; tokens are never otherwise printed.
 if(env.GITHUB_ACTIONS==='true')for(const token of [session.access_token,session.refresh_token])if(token)process.stdout.write(`::add-mask::${token}\n`);
 let proof;
 try{
  const response=await fetcher(`${PROJECT}/functions/v1/${SLUG}`,{method:'POST',headers:{apikey:KEY,Authorization:`Bearer ${session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({action:'verify'}),signal:AbortSignal.timeout(120000)});
  const body=await response.json();
  if(!Array.isArray(body.roles)||typeof body.run_id!=='string')throw Error('Independent role function did not return proof');
  proof={run_id:body.run_id,scope:body.scope,complete:body.complete===true,full_clean_chit:false,deployment_sha:sha,roles:body.roles.map(r=>({role:r.role,status:r.status,method:r.method,checks:(r.checks||[]).map(c=>({rpc:c.rpc,expected:c.expected,status:c.status,http_status:c.http_status})),cleanup:{logout:r.cleanup?.logout===true,auth_banned:r.cleanup?.auth_banned===true,profile_inactive:r.cleanup?.profile_inactive===true},...(r.reason?{reason:r.reason}:{})}))};
  if(!response.ok)proof.complete=false;
 }finally{
  const revoked=await fetcher(`${PROJECT}/auth/v1/logout?scope=local`,{method:'POST',headers:{apikey:KEY,Authorization:`Bearer ${session.access_token}`},signal:AbortSignal.timeout(5000)}).catch(()=>null);
  if(!revoked?.ok){if(proof){proof.complete=false;proof.bootstrap_cleanup='FAIL'}else throw Error('TEST bootstrap session cleanup failed')}
 }
 return proof;
}
if(require.main===module)run().then(proof=>{const fs=require('node:fs');fs.mkdirSync('test-results',{recursive:true});fs.writeFileSync('test-results/test71-independent-financial-role-proof.json',JSON.stringify(proof,null,2)+'\n');console.log(JSON.stringify(proof,null,2));process.exitCode=proof.complete?0:1}).catch(()=>{console.error('TEST71 independent role verification could not complete; no clean chit issued.');process.exitCode=1});
module.exports={run};
