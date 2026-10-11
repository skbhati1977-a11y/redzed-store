// Independent Auth sessions only. No Act As, JWT simulation, writes, or fixture creation.
const ROLES=['WORKER','LINE_MANAGER','MANAGER','ADMIN','ACCOUNTS','SALES'];
const URL='https://hruartsemierwhtzonei.supabase.co';
const KEY='sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga';
const normalize=r=>String(r||'').toUpperCase()==='ACCOUNT'?'ACCOUNTS':String(r||'').toUpperCase();
async function checkRole(role, env=process.env, fetcher=fetch){
 const email=env[`TEST71_ROLE_${role}_EMAIL`],password=env[`TEST71_ROLE_${role}_PASSWORD`];
 if(!email||!password)return {role,status:'BLOCKED',reason:'independent_role_credentials_missing'};
 let token;let result;let authenticatedUid;
 const call=async(path,body)=>{
  const response=await fetcher(URL+path,{method:body?'POST':'GET',headers:{apikey:KEY,...(token?{Authorization:`Bearer ${token}`} : {}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});
  const data=await response.json();return {ok:response.ok,status:response.status,data};
 };
 try{
  const auth=await call('/auth/v1/token?grant_type=password',{email,password});
  if(!auth.ok||!auth.data.access_token)throw Error('independent_login_failed');
  token=auth.data.access_token;
  const user=await call('/auth/v1/user');
  if(!user.ok||!user.data.id||user.data.id!==auth.data.user?.id)throw Error('authenticated_user_mismatch');
  authenticatedUid=user.data.id;
  const profile=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${encodeURIComponent(user.data.id)}&select=role_code,is_active,access_status&limit=2`);
  if(!profile.ok||profile.data.length!==1||!profile.data[0].is_active||String(profile.data[0].access_status||'ACTIVE').toUpperCase()!=='ACTIVE'||normalize(profile.data[0].role_code)!==role)throw Error('active_profile_role_mismatch');
  const identity=await call('/rest/v1/rpc/rr_upm_effective_identity_v200',{});
  if(!identity.ok||identity.data.on_behalf!==false||identity.data.operator_user_id!==authenticatedUid||identity.data.effective_auth_user_id!==authenticatedUid||normalize(identity.data.resolved_role||identity.data.role_code)!==role)throw Error('independent_effective_role_mismatch');
  const expected=role==='ADMIN'||role==='ACCOUNTS';
  const checks=[];
  for(const [rpc,args] of [['rr_trial_balance_v806',{p_from_date:'2026-01-01',p_to_date:new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),p_data_mode:'TEST'}],['rr_accounts_real_chat_home_v500',{p_status:'OPEN',p_data_mode:'TEST'}]]){
   const answer=await call('/rest/v1/rpc/'+rpc,args);
   const passed=expected?answer.ok:(!answer.ok&&answer.data.code==='42501');
   checks.push({rpc,expected:expected?'ALLOW':'DENY',status:passed?'PASS':'FAIL',http_status:answer.status});
  }
  result={role,status:checks.every(c=>c.status==='PASS')?'PASS':'FAIL',method:'independent_authenticated_api',checks};
 }catch(error){result={role,status:'FAIL',reason:['independent_login_failed','authenticated_user_mismatch','active_profile_role_mismatch','independent_effective_role_mismatch'].includes(error.message)?error.message:'request_failed'};}
 finally{
  if(token){try{const logout=await fetcher(URL+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:KEY,Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(5000)});if(!logout.ok)result={...result,status:'FAIL',cleanup:'session_logout_failed'};}catch{result={...result,status:'FAIL',cleanup:'session_logout_failed'};}}
 }
 if(authenticatedUid)Object.defineProperty(result,"authenticatedUid",{value:authenticatedUid,enumerable:false});
 return result;
}
async function run(env=process.env,fetcher=fetch){const roles=[];const seen=new Map();for(const role of ROLES){const result=await checkRole(role,env,fetcher);if(result.authenticatedUid){if(seen.has(result.authenticatedUid)){result.status='FAIL';result.reason='duplicate_authenticated_user';const previous=seen.get(result.authenticatedUid);previous.status='FAIL';previous.reason='duplicate_authenticated_user';}else seen.set(result.authenticatedUid,result);}roles.push(result);}return {scope:'TEST read-only independent financial API authority; browser and business transaction journeys not certified',roles,full_clean_chit:false};}
if(require.main===module)run().then(result=>{console.log(JSON.stringify(result,null,2));process.exitCode=result.roles.every(r=>r.status==='PASS')?0:1;});
module.exports={checkRole,run,ROLES};
