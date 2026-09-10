import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const allowed = (origin: string) => /^https:\/\/(?:skbhati1977-a11y\.github\.io|[a-z0-9-]+\.vercel\.app)$/.test(origin) ? origin : "https://skbhati1977-a11y.github.io";
const response = (body: unknown, status: number, origin: string) => new Response(JSON.stringify(body), {status,headers:{"Content-Type":"application/json","Access-Control-Allow-Origin":allowed(origin),"Access-Control-Allow-Headers":"content-type,apikey","Vary":"Origin"}});

Deno.serve(async (request) => {
  const origin=request.headers.get("origin")||"";
  if(request.method==="OPTIONS") return response({},200,origin);
  try {
    const body=await request.json(), action=String(body.action||""), identifier=String(body.identifier||"").trim();
    if(!["login","reset"].includes(action)||!identifier||identifier.length>160) return response({error:"Invalid request."},400,origin);
    const url=Deno.env.get("SUPABASE_URL")!, serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, anonKey=Deno.env.get("SUPABASE_ANON_KEY")!;
    const admin=createClient(url,serviceKey,{auth:{persistSession:false}});
    const target=await admin.rpc("rr_internal_login_target_v9750",{p_identifier:identifier});
    if(target.error||!target.data) return response(action==="reset"?{ok:true}:{error:"Invalid login credentials."},action==="reset"?200:401,origin);
    const userResult=await admin.auth.admin.getUserById(target.data);
    const email=userResult.data.user?.email;
    if(!email) return response(action==="reset"?{ok:true}:{error:"Invalid login credentials."},action==="reset"?200:401,origin);
    const auth=createClient(url,anonKey,{auth:{persistSession:false}});
    if(action==="reset") {
      await auth.auth.resetPasswordForEmail(email,{redirectTo:"https://skbhati1977-a11y.github.io/redzed-store/reset-password.html"});
      return response({ok:true},200,origin);
    }
    const signed=await auth.auth.signInWithPassword({email,password:String(body.password||"")});
    if(signed.error||!signed.data.session) return response({error:"Invalid login credentials."},401,origin);
    return response({session:{access_token:signed.data.session.access_token,refresh_token:signed.data.session.refresh_token}},200,origin);
  } catch { return response({error:"Request could not be processed."},400,origin); }
});
