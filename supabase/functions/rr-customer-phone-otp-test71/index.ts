import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
const projectUrl=Deno.env.get("SUPABASE_URL")||"",anonKey=Deno.env.get("SUPABASE_ANON_KEY")||"",serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
const allowed=new Set(["https://redzed-customer-collection.jggfab2011.chatgpt.site","https://glorious-halibut-5vvvx96x4j69f76xx-8000.app.github.dev","http://localhost:8000","http://127.0.0.1:8000"]);
const client=createClient(projectUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(async request=>{
 const origin=request.headers.get("Origin")||"",headers={"Content-Type":"application/json","Access-Control-Allow-Origin":allowed.has(origin)?origin:"https://redzed-customer-collection.jggfab2011.chatgpt.site","Access-Control-Allow-Headers":"apikey,authorization,content-type","Access-Control-Allow-Methods":"POST,OPTIONS","Vary":"Origin","Cache-Control":"no-store"};
 const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!allowed.has(origin))return reply(403,{error:"Origin unavailable."});
 if(request.method==="OPTIONS")return new Response(null,{status:204,headers});
 if(request.method!=="POST")return reply(405,{error:"POST required."});
 try{
  const raw=await request.text();if(raw.length>4096)return reply(413,{error:"Request too large."});
  const body=JSON.parse(raw),device=String(body.device_id||"").trim();
  if(device.length<24||device.length>256)return reply(400,{error:"Trusted device binding required."});
  if(body.action==="send"){
   const {data,error}=await client.rpc("rr_customer_login_otp_prepare_test71",{p_token:String(body.token||""),p_customer_name:String(body.customer_name||""),p_mobile:String(body.mobile||""),p_device_id:device});
   if(error)return reply(400,{error:/paused/i.test(error.message)?"Customer access paused by Super Admin.":"Use the original registered mobile for this collection."});
   const sent=await fetch(projectUrl+"/auth/v1/otp",{method:"POST",headers:{"apikey":anonKey,"Content-Type":"application/json"},body:JSON.stringify({phone:data.phone,create_user:true,channel:"sms"})});
   if(!sent.ok){const failure=await sent.json().catch(()=>({}));return reply(sent.status===429?429:503,{error:sent.status===429?"OTP भेजने से पहले कुछ देर इंतज़ार करें।":/disabled|provider|unsupported|not enabled/i.test(String(failure.msg||failure.message||failure.error_description||""))?"SMS verification service अभी activate नहीं है। Admin से संपर्क करें। आपकी approval request नहीं भेजी गई।":"SMS OTP भेजा नहीं जा सका। बाद में फिर कोशिश करें।"});}
   return reply(200,{challenge_id:data.challenge_id,customer_name:data.customer_name,phone:data.phone,otp_sent:true});
  }
  if(body.action==="verify"){
   const otp=String(body.otp||"").trim();if(!/^\d{6}$/.test(otp))return reply(400,{error:"6 digit SMS OTP required."});
   const {data:challenge,error:challengeError}=await client.rpc("rr_customer_login_otp_challenge_service_test71",{p_challenge_id:body.challenge_id,p_device_id:device});
   if(challengeError)return reply(400,{error:"OTP expired or too many attempts. नया OTP लें।"});
   const verified=await fetch(projectUrl+"/auth/v1/verify",{method:"POST",headers:{"apikey":anonKey,"Content-Type":"application/json"},body:JSON.stringify({type:"sms",phone:challenge.phone,token:otp})});
   if(!verified.ok)return reply(400,{error:"OTP गलत या expired है। सही OTP भरें या नया OTP लें।"});
   const authResult=await verified.json();
   const {data:userResult,error:userError}=await client.auth.getUser(authResult.access_token);
   if(userError||!userResult.user?.phone_confirmed_at||!authResult.access_token)return reply(400,{error:"SMS ownership verification failed."});
   const payload=JSON.parse(atob(authResult.access_token.split(".")[1].replace(/-/g,"+").replace(/_/g,"/")));
   const {data,error}=await client.rpc("rr_customer_login_otp_complete_service_test71",{p_challenge_id:body.challenge_id,p_device_id:device,p_auth_user_id:userResult.user.id,p_auth_session_id:payload.session_id});
   if(error)return reply(400,{error:"Phone verification unavailable or device mismatch. नया OTP लें।"});
   return reply(200,data);
  }
  return reply(400,{error:"Unknown action."});
 }catch(_){return reply(400,{error:"Phone verification failed. फिर कोशिश करें।"});}
});
