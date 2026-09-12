import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return new Response("method", { status: 405 });
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await request.json();
    if (!body.outbox_id || !body.dispatch_token) return new Response("unauthorized", { status: 401 });
    const { data: outbox } = await db.from("rr_chat_push_outbox_v61").select("*").eq("id", body.outbox_id).eq("dispatch_token", body.dispatch_token).is("processed_at", null).maybeSingle();
    if (!outbox) return new Response("already processed", { status: 200 });
    const { data: message } = await db.from("rr_customer_chat_messages_v9433").select("sender_kind,sender_customer_id,sender_profile_id,sender_name").eq("id", outbox.message_id).maybeSingle();
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
      if (ids.length) { const { data } = await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled", true).in("worker_id", ids); subscriptions = data || []; }
    } else if (actorKind && actorId) {
      const { data } = await db.from("rr_web_push_subscriptions_v61").select("*").eq("enabled", true).eq("actor_kind", actorKind).eq("actor_id", actorId);
      subscriptions = data || [];
    }
    webpush.setVapidDetails("https://skbhati1977-a11y.github.io/redzed-store/", Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);
    let sent = 0;
    for (const subscription of subscriptions) {
      const payload = JSON.stringify({ message_id: outbox.message_id, chat_id: outbox.chat_id, customer_name: message?.sender_name || outbox.customer_name, preview: outbox.preview, url: subscription.route_url || "./" });
      try {
        await webpush.sendNotification({ endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } }, payload, { TTL: 300, urgency: "high" }); sent++;
      } catch (error: any) {
        if (error?.statusCode === 404 || error?.statusCode === 410) await db.from("rr_web_push_subscriptions_v61").update({ enabled: false, updated_at: new Date().toISOString() }).eq("id", subscription.id);
      }
    }
    await db.from("rr_chat_push_outbox_v61").update({ processed_at: new Date().toISOString(), dispatch_token: crypto.randomUUID() }).eq("id", outbox.id).eq("dispatch_token", body.dispatch_token);
    return new Response(JSON.stringify({ ok: true, sent, subscriptions: subscriptions.length, actor_kind: actorKind }), { headers: { "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error instanceof Error ? error.message : error) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
