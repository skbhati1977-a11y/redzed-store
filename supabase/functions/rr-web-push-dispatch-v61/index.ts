import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

function customerPushRoute71(target: string | null, route: string | null): string {
 const publicBase='https://redzed-customer-collection.jggfab2011.chatgpt.site';
 for(const value of [target,route]){
  try {const dest=new URL(value||'');
   if(dest.pathname.endsWith('/s.html'))return publicBase+'/s.html'+dest.search;
  }catch(_){}
 }
 return publicBase+'/s.html';
}


function uniquePushSubscriptions71(all: any[]): any[] {
 const keyedActors=new Set(all.filter(x=>x.device_key).map(x=>String(x.worker_id||x.actor_kind+'|'+x.actor_id)));
 const chosen=new Map<string,any>();
 for(const row of all){
  const actor=String(row.worker_id||row.actor_kind+'|'+row.actor_id);
  if(!row.device_key&&keyedActors.has(actor))continue;
  const key=actor+'|'+(row.device_key||'legacy');
  const previous=chosen.get(key);
  if(!previous||String(row.updated_at||'')>String(previous.updated_at||''))chosen.set(key,row);
 }
 return [...chosen.values()];
}

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return new Response("method", { status: 405 });
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await request.json();
    if (body.material_outbox_id && body.dispatch_token) {
      const { data: outbox } = await db.from("rr_material_reorder_push_outbox_v675").select("*").eq("id", body.material_outbox_id).eq("dispatch_token", body.dispatch_token).is("processed_at", null).maybeSingle();
      if (!outbox) return new Response("already processed", { status: 200 });
      const { data: alert } = await db.from("rr_material_reorder_alerts_v805_2").select("*").eq("id", outbox.alert_id).eq("status","OPEN").maybeSingle();
      const { data: allowed } = await db.from("rr_user_profiles").select("auth_user_id,role_code").eq("is_active",true).eq("access_status","ACTIVE").in("role_code",["owner","OWNER","super_admin","SUPER_ADMIN","admin","ADMIN","accounts","ACCOUNTS","manager","MANAGER"]);
      const authIds=[...new Set((allowed||[]).map((x:any)=>x.auth_user_id).filter(Boolean))];
      const { data: workers }=authIds.length?await db.from("rr_worker_directory_unified_v1").select("worker_id,linked_auth_user_id").in("linked_auth_user_id",authIds):{data:[]};
      const workerIds=[...new Set((workers||[]).map((x:any)=>x.worker_id).filter(Boolean))];
      let subscriptions:any[]=[]; if(workerIds.length){const {data}=await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled",true).in("worker_id",workerIds);const all=data||[];const preferred=new Set(all.filter((x:any)=>x.device_key).map((x:any)=>String(x.worker_id)));subscriptions=all.filter((x:any)=>Boolean(x.device_key)||!preferred.has(String(x.worker_id)))}
      webpush.setVapidDetails("https://skbhati1977-a11y.github.io/redzed-store/",Deno.env.get("VAPID_PUBLIC_KEY")!,Deno.env.get("VAPID_PRIVATE_KEY")!);
      let sent=0; for(const subscription of subscriptions){const payload=JSON.stringify({material_alert_id:alert?.id,customer_name:"REDZED Material Alert",preview:outbox.preview,url:"test70-cb-purchase-real-chat-pilot.html?rc_material_alert="+encodeURIComponent(String(alert?.id||""))+"&rc_status=OPEN&rc_view=chat&rc_kind=group&rc_id=ADMIN&rc_parent=ADMIN"});try{await webpush.sendNotification({endpoint:subscription.endpoint,keys:{p256dh:subscription.p256dh,auth:subscription.auth}},payload,{TTL:300,urgency:"high"});sent++}catch(error:any){if(error?.statusCode===404||error?.statusCode===410)await db.from("rr_web_push_subscriptions_v61").update({enabled:false,updated_at:new Date().toISOString()}).eq("id",subscription.id)}}
      await db.from("rr_material_reorder_push_outbox_v675").update({processed_at:new Date().toISOString(),dispatch_token:crypto.randomUUID()}).eq("id",outbox.id).eq("dispatch_token",body.dispatch_token);
      return new Response(JSON.stringify({ok:true,sent,subscriptions:subscriptions.length,kind:"MATERIAL_REORDER"}),{headers:{"Content-Type":"application/json"}});
    }
    if (body.accessory_outbox_id && body.dispatch_token) {
      const {data:outbox}=await db.from("rr_accessory_requirement_push_outbox_v685").select("*").eq("id",body.accessory_outbox_id).eq("dispatch_token",body.dispatch_token).is("processed_at",null).maybeSingle();
      if(!outbox)return new Response("already processed",{status:200});
      const {data:alert}=await db.from("rr_accessory_requirement_alerts_v685").select("*").eq("id",outbox.alert_id).eq("status","OPEN").maybeSingle();
      const {data:allowed}=await db.from("rr_user_profiles").select("auth_user_id,role_code").eq("is_active",true).eq("access_status","ACTIVE").in("role_code",["owner","OWNER","super_admin","SUPER_ADMIN","admin","ADMIN"]);
      const authIds=[...new Set((allowed||[]).map((x:any)=>x.auth_user_id).filter(Boolean))];
      const {data:workers}=authIds.length?await db.from("rr_worker_directory_unified_v1").select("worker_id,linked_auth_user_id").in("linked_auth_user_id",authIds):{data:[]};
      const workerIds=[...new Set((workers||[]).map((x:any)=>x.worker_id).filter(Boolean))];let subscriptions:any[]=[];
      if(workerIds.length){const {data}=await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled",true).in("worker_id",workerIds);const all=data||[],preferred=new Set(all.filter((x:any)=>x.device_key).map((x:any)=>String(x.worker_id)));subscriptions=all.filter((x:any)=>Boolean(x.device_key)||!preferred.has(String(x.worker_id)))}
      webpush.setVapidDetails("https://skbhati1977-a11y.github.io/redzed-store/",Deno.env.get("VAPID_PUBLIC_KEY")!,Deno.env.get("VAPID_PRIVATE_KEY")!);
      let sent=0;for(const subscription of subscriptions){const payload=JSON.stringify({accessory_alert_id:alert?.id,customer_name:"REDZED Purchase Requirement",preview:outbox.preview,url:"test70-cb-purchase-real-chat-pilot.html?rc_accessory_alert="+encodeURIComponent(String(alert?.id||""))+"&rc_status=OPEN&rc_view=chat&rc_kind=group&rc_id=ADMIN&rc_parent=ADMIN"});try{await webpush.sendNotification({endpoint:subscription.endpoint,keys:{p256dh:subscription.p256dh,auth:subscription.auth}},payload,{TTL:300,urgency:"high"});sent++}catch(error:any){if(error?.statusCode===404||error?.statusCode===410)await db.from("rr_web_push_subscriptions_v61").update({enabled:false,updated_at:new Date().toISOString()}).eq("id",subscription.id)}}
      await db.from("rr_accessory_requirement_push_outbox_v685").update({processed_at:new Date().toISOString(),dispatch_token:crypto.randomUUID()}).eq("id",outbox.id).eq("dispatch_token",body.dispatch_token);
      return new Response(JSON.stringify({ok:true,sent,subscriptions:subscriptions.length,kind:"ACCESSORY_REQUIREMENT"}),{headers:{"Content-Type":"application/json"}});
    }
    if (body.targeted_outbox_id && body.dispatch_token) {
      const { data: outbox } = await db.from("rr_targeted_push_outbox_v708").select("*").eq("id", body.targeted_outbox_id).eq("dispatch_token", body.dispatch_token).is("processed_at", null).maybeSingle();
      if (!outbox) return new Response("already processed", { status: 200 });
      if(outbox.payload?.source==="CUSTOMER_LOGIN_APPROVAL_TEST71"){
        const {data:claimed,error:claimError}=await db.from("rr_targeted_push_outbox_v708").update({processed_at:new Date().toISOString(),dispatch_token:crypto.randomUUID()}).eq("id",outbox.id).eq("dispatch_token",body.dispatch_token).is("processed_at",null).select("id").maybeSingle();
        if(claimError)throw claimError;if(!claimed)return new Response("already processed",{status:200});
        const {data:pending,error:pendingError}=await db.rpc("rr_customer_login_push_pending_test71",{p_request_id:outbox.payload.login_request_id,p_recipient_worker_id:outbox.recipient_worker_id});
        if(pendingError)throw pendingError;
        if(!pending)return new Response(JSON.stringify({ok:true,sent:0,skipped:"APPROVAL_RESOLVED"}),{headers:{"Content-Type":"application/json"}});
      }
      const { data: worker } = await db.from("rr_worker_directory_unified_v1").select("worker_id,linked_auth_user_id").or("worker_id.eq."+outbox.recipient_worker_id+",linked_auth_user_id.eq."+outbox.recipient_worker_id).limit(1).maybeSingle();
      const ids=[...new Set([outbox.recipient_worker_id,worker?.worker_id].filter(Boolean))];
      let subscriptions:any[]=[]; if(ids.length){const {data}=await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled",true).in("worker_id",ids);const all=data||[],preferred=new Set(all.filter((x:any)=>x.device_key).map((x:any)=>String(x.worker_id)));subscriptions=all.filter((x:any)=>Boolean(x.device_key)||!preferred.has(String(x.worker_id)))}
      webpush.setVapidDetails("https://skbhati1977-a11y.github.io/redzed-store/",Deno.env.get("VAPID_PUBLIC_KEY")!,Deno.env.get("VAPID_PRIVATE_KEY")!);
      let sent=0; for(const subscription of subscriptions){const payload=JSON.stringify({customer_name:outbox.title,preview:outbox.body,url:outbox.payload?.source==="CUSTOMER_LOGIN_APPROVAL_TEST71"?(()=>{try{const u=new URL(subscription.route_url);u.pathname=u.pathname.replace(/[^/]*$/,"test70-cb-purchase-real-chat-pilot.html");u.search=new URL(outbox.route_url,u).search;return u.href}catch(_){return outbox.route_url||"./"}})():outbox.route_url||subscription.route_url||"./",event_key:outbox.event_key,...(outbox.payload||{})});try{await webpush.sendNotification({endpoint:subscription.endpoint,keys:{p256dh:subscription.p256dh,auth:subscription.auth}},payload,{TTL:300,urgency:"high"});sent++}catch(error:any){if(error?.statusCode===404||error?.statusCode===410)await db.from("rr_web_push_subscriptions_v61").update({enabled:false,updated_at:new Date().toISOString()}).eq("id",subscription.id)}}
      await db.from("rr_targeted_push_outbox_v708").update({processed_at:new Date().toISOString(),dispatch_token:crypto.randomUUID()}).eq("id",outbox.id).eq("dispatch_token",body.dispatch_token);
      return new Response(JSON.stringify({ok:true,sent,subscriptions:subscriptions.length,kind:"TARGETED_BUSINESS_PUSH"}),{headers:{"Content-Type":"application/json"}});
    }
    if (!body.outbox_id || !body.dispatch_token) return new Response("unauthorized", { status: 401 });
    // Atomic token claim prevents concurrent requests from sending the same outbox twice.
    const claimToken=crypto.randomUUID();
    const { data: outbox, error: claimError } = await db.from("rr_chat_push_outbox_v61").update({dispatch_token:claimToken,processed_at:new Date().toISOString()}).eq("id", body.outbox_id).eq("dispatch_token", body.dispatch_token).is("processed_at", null).select("*").maybeSingle();
    if(claimError)throw claimError;
    if (!outbox) return new Response("already processed", { status: 200 });
    const { data: message } = await db.from("rr_customer_chat_messages_v9433").select("sender_kind,sender_customer_id,sender_profile_id,sender_name,payload,created_at,archived_at").eq("id", outbox.message_id).maybeSingle();
    // Superseded technical requirement messages must never create a second notification.
    if(!message||message.archived_at){
      await db.from("rr_chat_push_outbox_v61").update({processed_at:new Date().toISOString()}).eq("id",outbox.id).eq("dispatch_token",claimToken);
      return new Response(JSON.stringify({ok:true,sent:0,reason:"ARCHIVED_OR_MISSING_MESSAGE"}),{headers:{"Content-Type":"application/json"}});
    }
    const { data: chat } = await db.from("rr_customer_chat_v9433").select("customer_id,relation_kind").eq("id", outbox.chat_id).maybeSingle();
    const { data: relation } = await db.from("rr_market_partner_relation_chat_v67").select("relation_kind,owner_customer_id,partner_customer_id").eq("chat_id", outbox.chat_id).eq("status", "ACTIVE").maybeSingle();
    const sender = String(message?.sender_kind || "").toUpperCase();
    let actorKind = "", actorId = "";
    if (chat?.relation_kind === "DIRECT_CUSTOMER") {
      if (sender === "CUSTOMER") actorKind = "STAFF";
      else { actorKind = "CUSTOMER"; actorId = chat.customer_id || ""; }
    } else if (relation?.relation_kind === "DISTRIBUTOR_CUSTOMER") {
      if (sender === "DISTRIBUTOR") { actorKind = "PARTNER_CUSTOMER"; actorId = relation.partner_customer_id || ""; }
      else { actorKind = "DISTRIBUTOR"; actorId = relation.owner_customer_id || ""; }
    } else if (relation?.relation_kind === "DISTRIBUTOR_REDZED") {
      if (sender === "DISTRIBUTOR") actorKind = "STAFF";
      else { actorKind = "DISTRIBUTOR"; actorId = relation.owner_customer_id || ""; }
    }
    let subscriptions: any[] = [];
    if (actorKind === "STAFF") {
      const { data: allowed } = await db.from("rr_worker_directory_unified_v1").select("worker_id").eq("is_active", true).eq("access_status", "ACTIVE").in("department_code", ["sales", "accounts", "admin", "SALES", "ACCOUNTS", "ADMIN"]);
      const ids = [...new Set((allowed || []).map((item: any) => item.worker_id))];
      if (ids.length) { const { data } = await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled", true).in("worker_id", ids); const all=data||[],preferred=new Set(all.filter((x:any)=>x.device_key).map((x:any)=>String(x.worker_id)));subscriptions=all.filter((x:any)=>Boolean(x.device_key)||!preferred.has(String(x.worker_id))); }
    } else if (actorKind && actorId) {
      const { data } = await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled", true).eq("actor_kind", actorKind).eq("actor_id", actorId);
      const all=data||[],preferred=new Set(all.filter((x:any)=>x.device_key).map((x:any)=>String(x.actor_kind)+"|"+String(x.actor_id)));subscriptions=all.filter((x:any)=>Boolean(x.device_key)||!preferred.has(String(x.actor_kind)+"|"+String(x.actor_id)));
    }
    subscriptions=uniquePushSubscriptions71(subscriptions);
    webpush.setVapidDetails("https://skbhati1977-a11y.github.io/redzed-store/", Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);
    let sent = 0;
    for (const subscription of subscriptions) {
      const payload = JSON.stringify({ message_id: outbox.message_id, chat_id: outbox.chat_id, customer_name: message?.sender_name || outbox.customer_name, preview: outbox.preview || (String(message?.payload?.mime_type||"").startsWith("audio/")?"Voice message":"New message"), url: actorKind === "STAFF" ? (()=>{try{const u=new URL(subscription.route_url);u.pathname=u.pathname.replace(/[^/]*$/, "real-sales-live-chat-v9434.html");u.search="";u.searchParams.set("chat_id",outbox.chat_id);return u.href}catch(_){return subscription.route_url||"./"}})() : customerPushRoute71(outbox.target_url, subscription.route_url), event_revision:message?.created_at||outbox.created_at, collection_cycle_id: outbox.collection_cycle_id || null, event_key: `${outbox.message_id}:${message?.created_at||outbox.created_at}` });
      try {
        await webpush.sendNotification({ endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } }, payload, { TTL: 300, urgency: "high" }); sent++;
      } catch (error: any) {
        if (error?.statusCode === 404 || error?.statusCode === 410) await db.from("rr_web_push_subscriptions_v61").update({ enabled: false, updated_at: new Date().toISOString() }).eq("id", subscription.id);
      }
    }
    await db.from("rr_chat_push_outbox_v61").update({ processed_at: new Date().toISOString(), dispatch_token: crypto.randomUUID() }).eq("id", outbox.id).eq("dispatch_token", claimToken);
    return new Response(JSON.stringify({ ok: true, sent, subscriptions: subscriptions.length, actor_kind: actorKind }), { headers: { "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error instanceof Error ? error.message : error) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});

