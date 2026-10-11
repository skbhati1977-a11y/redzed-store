const OPERATOR='893c58dd-420b-4dfa-aff7-844e20e634c5';
const PROJECT='https://hruartsemierwhtzonei.supabase.co';
const ROLES=['worker','line_manager','manager','admin','accounts','sales'];
const FIXTURE='test71-independent-financial';
export function createHandler({env,fetcher=fetch,randomUUID=()=>crypto.randomUUID(),randomPassword=()=>{const bytes=crypto.getRandomValues(new Uint8Array(32));return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('')},now=()=>new Date()}){
 return async request=>{
  const respond=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'private, no-store'}});
  if(request.method!=='POST'||env('SUPABASE_URL')!==PROJECT)return respond({error:'Not found'},404);
  const authorization=request.headers.get('Authorization')||'';
  if(!authorization.startsWith('Bearer '))return respond({error:'Not found'},404);
  const caller=authorization.slice(7),service=env('SUPABASE_SERVICE_ROLE_KEY'),anon=env('SUPABASE_ANON_KEY');
  if(!service||!anon)return respond({error:'Unavailable'},503);
  const call=async(path,{body,token=caller,key=anon,method=body?'POST':'GET'}={})=>{
   const response=await fetcher(PROJECT+path,{method,headers:{apikey:key,Authorization:`Bearer ${token}`,'Content-Type':'application/json',Prefer:'return=representation'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});
   let data=null;if(response.status!==204)data=await response.json();return {ok:response.ok,status:response.status,data};
  };
  try{
   const user=await call('/auth/v1/user');if(!user.ok||user.data?.id!==OPERATOR)return respond({error:'Not found'},404);
   const profile=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${OPERATOR}&select=role_code,is_active,access_status&limit=2`);
   const identity=await call('/rest/v1/rpc/rr_upm_effective_identity_v200',{body:{}});
   if(!profile.ok||!Array.isArray(profile.data)||profile.data.length!==1||String(profile.data[0].role_code).toUpperCase()!=='SUPER_ADMIN'||!profile.data[0].is_active||profile.data[0].access_status!=='ACTIVE'||!identity.ok||identity.data?.on_behalf!==false||identity.data.operator_user_id!==OPERATOR||identity.data.effective_auth_user_id!==OPERATOR)return respond({error:'Not found'},404);
  }catch{return respond({error:'Unavailable'},503)}
  // Caller cannot choose role, UID, password, email, mode, or operation. Exactly six actors per bounded run.
  let input;try{input=await request.json()}catch{return respond({error:'Invalid request'},400)}
  if(input?.action!=='verify'||Object.keys(input).some(k=>k!=='action'))return respond({error:'Invalid request'},400);
  let claim;try{claim=await call('/rest/v1/rpc/rr_test71_independent_financial_claim',{body:{}})}catch{return respond({error:'Run guard unavailable'},503)}
  if(!claim.ok)return respond({error:'Run guard denied'},503);
  if(!claim.data?.claimed){if(claim.data?.status==='CACHED'&&claim.data.proof)return respond({...claim.data.proof,cached:true},claim.data.proof.complete?200:409);return respond({error:'Prior TEST run requires reconciliation',run_id:claim.data?.run_id},409)}
  const run=claim.data.run_id,roles=[],seen=new Set();let blocked=false;
  for(const role of ROLES){
   const email=`test71-financial-${role.replaceAll('_','-')}-${run}@realfactory.invalid`,password=randomPassword();
   let uid,token,profileCreated=false,authCreateAttempted=false,verifiedActor=false,loginAttempted=false;const proof={role:role.toUpperCase(),status:'FAIL',method:'independent_authenticated_api',checks:[],cleanup:{logout:false,auth_banned:false,profile_inactive:false}};
   try{
    authCreateAttempted=true;
    const created=await call('/auth/v1/admin/users',{key:service,token:service,body:{email,password,email_confirm:true,app_metadata:{fixture:FIXTURE,run_id:run,role,data_mode:'TEST'},user_metadata:{name:`TEST71 Financial ${role} ${run}`}}});
    uid=created.data?.id||created.data?.user?.id;if(!created.ok||!uid||seen.has(uid))throw Error('auth_create_failed');seen.add(uid);
    const verifyCreated=await call(`/auth/v1/admin/users/${uid}`,{key:service,token:service});const verifiedCreated=verifyCreated.data?.user||verifyCreated.data;
    if(!verifyCreated.ok||verifiedCreated?.email!==email||verifiedCreated.app_metadata?.fixture!==FIXTURE||verifiedCreated.app_metadata.run_id!==run||verifiedCreated.app_metadata.role!==role)throw Error('auth_create_failed');verifiedActor=true;
    const existingProfile=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}&select=id&limit=2`);
    if(!existingProfile.ok||!Array.isArray(existingProfile.data)||existingProfile.data.length>1)throw Error('profile_create_failed');
    const inserted=await call(existingProfile.data.length?`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}`:'/rest/v1/rr_user_profiles',{method:existingProfile.data.length?'PATCH':'POST',body:{auth_user_id:uid,full_name:`TEST71 Financial ${role} ${run}`,email,role_code:role,is_active:true,access_status:'ACTIVE',access_reason:`${FIXTURE}:${run}`}});
    if(!inserted.ok)throw Error('profile_create_failed');profileCreated=true;
    loginAttempted=true;
    const login=await call('/auth/v1/token?grant_type=password',{token:anon,body:{email,password}});
    token=login.data?.access_token;if(!login.ok||!token||login.data?.user?.id!==uid)throw Error('independent_login_failed');
    const user=await call('/auth/v1/user',{token});const ownProfile=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}&select=role_code,is_active,access_status&limit=2`,{token});const effective=await call('/rest/v1/rpc/rr_upm_effective_identity_v200',{token,body:{}});
    if(!user.ok||user.data?.id!==uid||!ownProfile.ok||!Array.isArray(ownProfile.data)||ownProfile.data.length!==1||!ownProfile.data[0].is_active||ownProfile.data[0].access_status!=='ACTIVE'||String(ownProfile.data[0].role_code).toLowerCase()!==role||!effective.ok||effective.data?.on_behalf!==false||effective.data.operator_user_id!==uid||effective.data.effective_auth_user_id!==uid||String(effective.data.resolved_role||effective.data.role_code).toLowerCase()!==role)throw Error('independent_identity_failed');
    const allowed=['admin','accounts'].includes(role),toDate=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(now());
    for(const [rpc,body] of [['rr_trial_balance_v806',{p_from_date:'2026-01-01',p_to_date:toDate,p_data_mode:'TEST'}],['rr_accounts_real_chat_home_v500',{p_status:'OPEN',p_data_mode:'TEST'}]]){
     const answer=await call('/rest/v1/rpc/'+rpc,{token,body});const pass=allowed?answer.ok:(!answer.ok&&(answer.data?.code==='42501'||(rpc==='rr_accounts_real_chat_home_v500'&&answer.data?.code==='P0001'&&answer.data?.message==='Accounts permission required.')));proof.checks.push({rpc,expected:allowed?'ALLOW':'DENY',status:pass?'PASS':'FAIL',http_status:answer.status});
    }
    proof.status=proof.checks.every(c=>c.status==='PASS')?'PASS':'FAIL';
   }catch(error){proof.reason=['auth_create_failed','profile_create_failed','independent_login_failed','independent_identity_failed'].includes(error.message)?error.message:'request_failed'}
   finally{
    if(authCreateAttempted&&!uid){
     // A timed-out create can have committed. Recover ONLY exact namespace+server app_metadata.
     blocked=true;
     try{for(let page=1;page<=10;page++){const list=await call(`/auth/v1/admin/users?page=${page}&per_page=100`,{key:service,token:service});const users=list.data?.users;if(!list.ok||!Array.isArray(users))break;const match=users.find(u=>u.email===email&&u.app_metadata?.fixture===FIXTURE&&u.app_metadata.run_id===run&&u.app_metadata.role===role);if(match){uid=match.id;verifiedActor=true;break}if(users.length<100)break}}catch{}
    }
    if(loginAttempted&&!token&&verifiedActor){
     // An uncertain login can create a session. Recover a fresh token, then revoke only this new fixture's sessions.
     blocked=true;
     try{const recovered=await call('/auth/v1/token?grant_type=password',{token:anon,body:{email,password}});if(recovered.ok&&recovered.data?.user?.id===uid)token=recovered.data.access_token}catch{}
     if(token){try{proof.cleanup.logout=(await call('/auth/v1/logout?scope=global',{token,method:'POST'})).ok}catch{}}
    }else if(token){try{proof.cleanup.logout=(await call('/auth/v1/logout?scope=local',{token,method:'POST'})).ok}catch{}}
    if(uid){
     // Only the exact Auth UID created in this request is ever banned. Never update existing actor credentials.
     try{const check=await call(`/auth/v1/admin/users/${uid}`,{key:service,token:service});const u=check.data?.user||check.data;if(check.ok&&u?.email===email&&u?.app_metadata?.fixture===FIXTURE&&u.app_metadata.run_id===run){const banned=await call(`/auth/v1/admin/users/${uid}`,{key:service,token:service,method:'PUT',body:{ban_duration:'876000h'}});const verify=await call(`/auth/v1/admin/users/${uid}`,{key:service,token:service});const verified=verify.data?.user||verify.data;proof.cleanup.auth_banned=banned.ok&&verify.ok&&Date.parse(verified?.banned_until)>now().getTime()}}catch{}
     if(verifiedActor){try{
      const rows=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}&select=id,is_active,access_status&limit=2`);
      if(rows.ok&&Array.isArray(rows.data)&&rows.data.length===0)proof.cleanup.profile_inactive=true;
      else if(rows.ok&&Array.isArray(rows.data)&&rows.data.length===1){
       const inactive=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}`,{method:'PATCH',body:{is_active:false,access_status:'BLOCKED',access_reason:`${FIXTURE}:${run}:retired`}});
       const verify=await call(`/rest/v1/rr_user_profiles?auth_user_id=eq.${uid}&select=id,is_active,access_status&limit=2`);
       proof.cleanup.profile_inactive=inactive.ok&&verify.ok&&Array.isArray(verify.data)&&verify.data.length===1&&verify.data[0].is_active===false&&verify.data[0].access_status==='BLOCKED';
      }
     }catch{}}

    }
    if(!proof.cleanup.auth_banned|| (uid&&!proof.cleanup.profile_inactive)||(token&&!proof.cleanup.logout))proof.status='FAIL';
   }
   roles.push(proof);
   // Stop creation if cleanup failed; no expanding residue on retry/error.
   if(blocked||(token&&!proof.cleanup.logout)||(uid&&!proof.cleanup.auth_banned)||(uid&&!proof.cleanup.profile_inactive)){blocked=true;break;}
  }
  const proof={run_id:run,scope:'TEST read-only financial authority using six fresh independent Auth sessions',roles,complete:!blocked&&roles.length===6&&roles.every(r=>r.status==='PASS'),full_clean_chit:false,requires_reconciliation:blocked};
  try{const stored=await call('/rest/v1/rpc/rr_test71_independent_financial_finish',{body:{p_run_id:run,p_blocked:blocked,p_proof:proof}});if(!stored.ok){proof.complete=false;proof.requires_reconciliation=true}}catch{proof.complete=false;proof.requires_reconciliation=true}
  return respond(proof,proof.complete?200:409);
 };
}
