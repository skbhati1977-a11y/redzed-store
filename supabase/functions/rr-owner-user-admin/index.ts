import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,x-client-info,apikey,content-type"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const clean=(value:unknown)=>String(value||"").trim().toLowerCase();
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 try{
  const url=Deno.env.get("SUPABASE_URL")!,key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin=createClient(url,key,{auth:{persistSession:false}}),token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
  const actorResult=await admin.auth.getUser(token),actor=actorResult.data.user;if(!actor)return json({error:"Authenticated Owner/Admin required."},401);
  const actorProfile=await admin.from("rr_user_profiles").select("role_code,is_active,access_status").eq("auth_user_id",actor.id).maybeSingle();
  const actorRole=clean(actorProfile.data?.role_code),active=actorProfile.data?.is_active&&clean(actorProfile.data?.access_status||"active")==="active";
  if(!active||!["owner","super_admin","admin"].includes(actorRole))return json({error:"Owner/Admin permission required."},403);
  const body=await req.json(),action=clean(body.action);
  if(action==="list_users"){
   const listed=await admin.auth.admin.listUsers({page:1,perPage:1000});if(listed.error)throw listed.error;
   return json({users:listed.data.users.map(u=>({auth_user_id:u.id,id:u.id,email:u.email,auth_created_at:u.created_at,last_sign_in_at:u.last_sign_in_at}))});
  }
  if(action==="create_user"){
   const role=clean(body.role_code),department=clean(body.department_code);
   if(["owner","super_admin","admin"].includes(role)&&!["owner","super_admin"].includes(actorRole))return json({error:"Only Owner can create Admin."},403);
   const created=await admin.auth.admin.createUser({email:String(body.email||"").trim(),password:String(body.password||""),email_confirm:true,app_metadata:{role_code:role,department_code:department}});
   if(created.error||!created.data.user)throw created.error||new Error("Auth user creation failed.");
   const profile=await admin.from("rr_user_profiles").insert({auth_user_id:created.data.user.id,full_name:String(body.full_name||"").trim(),email:String(body.email||"").trim(),role_code:role,department_code:department,is_active:true,access_status:"ACTIVE"});
   if(profile.error){await admin.auth.admin.deleteUser(created.data.user.id);throw profile.error;}return json({ok:true,auth_user_id:created.data.user.id});
  }
  if(action==="set_role"){
   if(!["owner","super_admin"].includes(actorRole))return json({error:"Only Owner can change primary roles."},403);
   const role=clean(body.role_code),department=clean(body.department_code),profileId=String(body.profile_id||"");
   if(!profileId||!role||!department)return json({error:"Profile, role and department required."},400);
   const updated=await admin.from("rr_user_profiles").update({role_code:role,department_code:department,updated_at:new Date().toISOString()}).eq("id",profileId).select("id").maybeSingle();
   if(updated.error||!updated.data)throw updated.error||new Error("Profile not found.");
   if(body.auth_user_id)await admin.auth.admin.updateUserById(String(body.auth_user_id),{app_metadata:{role_code:role,department_code:department}});
   return json({ok:true,role_code:role,department_code:department});
  }
  if(action==="reset_password"){
   if(!body.auth_user_id||String(body.password||"").length<8)return json({error:"Valid user and 8-character password required."},400);
   const target=await admin.from("rr_user_profiles").select("role_code").eq("auth_user_id",body.auth_user_id).maybeSingle();
   if(["owner","super_admin","admin"].includes(clean(target.data?.role_code))&&!["owner","super_admin"].includes(actorRole))return json({error:"Only Owner can reset Admin credentials."},403);
   const changed=await admin.auth.admin.updateUserById(String(body.auth_user_id),{password:String(body.password)});if(changed.error)throw changed.error;return json({ok:true});
  }
  return json({error:"Unsupported action."},400);
 }catch(error){return json({error:error instanceof Error?error.message:"Request failed."},400);}
});
