import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await request.json(), subscription = body.subscription || {};
    if (body.action !== "subscribe" || !subscription.endpoint || !subscription.keys?.p256dh || !subscription.keys?.auth) return json({ error: "invalid subscription" }, 400);
    let actorKind = "", actorId = "", workerId: string | null = null, chatId: string | null = null;
    const bearer = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (bearer) {
      const { data: { user } } = await db.auth.getUser(bearer);
      if (user) {
        const { data: worker } = await db.from("rr_worker_directory_unified_v1").select("worker_id").eq("linked_auth_user_id", user.id).eq("is_active", true).limit(1).maybeSingle();
        if (worker?.worker_id) { actorKind = "STAFF"; actorId = worker.worker_id; workerId = worker.worker_id; }
      }
    }
    if (!actorId && body.session_token && body.device_id) {
      const downstream = await db.rpc("rr_market_partner_customer_session_validate_v67", { p_session_token: body.session_token, p_device_id: body.device_id });
      if (!downstream.error && downstream.data?.partner_customer_id) {
        actorKind = "PARTNER_CUSTOMER"; actorId = downstream.data.partner_customer_id; chatId = downstream.data.chat_id || null;
      }
      if (!actorId) {
        const distributor = await db.rpc("rr_market_partner_context_v67", { p_session_token: body.session_token, p_device_id: body.device_id });
        if (!distributor.error && distributor.data?.owner_customer_id) { actorKind = "DISTRIBUTOR"; actorId = distributor.data.owner_customer_id; }
      }
      if (!actorId) {
        const customer = await db.rpc("rr_customer_session_validate_v9590", { p_session_token: body.session_token, p_device_id: body.device_id });
        const customerId = customer.data?.customer_id;
        if (!customer.error && customerId) {
          actorKind = "CUSTOMER"; actorId = customerId;
          const { data: chat } = await db.from("rr_customer_chat_v9433").select("id").eq("customer_id", customerId).eq("relation_kind", "DIRECT_CUSTOMER").eq("status", "OPEN").limit(1).maybeSingle();
          chatId = chat?.id || null;
        }
      }
    }
    if (!actorId) return json({ error: "valid staff, customer or distributor session required" }, 401);
    const row = { worker_id: workerId, actor_kind: actorKind, actor_id: actorId, chat_id: chatId, endpoint: subscription.endpoint, p256dh: subscription.keys.p256dh, auth: subscription.keys.auth, user_agent: request.headers.get("user-agent"), route_url: String(body.route_url || "").slice(0, 1500), enabled: true, updated_at: new Date().toISOString() };
    const { error } = await db.from("rr_web_push_subscriptions_v61").upsert(row, { onConflict: "endpoint" });
    if (error) throw error;
    return json({ ok: true, actor_kind: actorKind });
  } catch (error) { return json({ error: String(error instanceof Error ? error.message : error) }, 400); }
});
