(() => {
  "use strict";
  let cache=[];
  const $=id=>document.getElementById(id);

  function esc(v){return RF853.esc(v)}
  function shortDate(v){try{return v?new Date(v).toLocaleString():""}catch{return String(v||"")}}

  function render(){
    const q=String($("filter").value||"").trim().toLowerCase();
    const rows=!q?cache:cache.filter(x=>JSON.stringify(x).toLowerCase().includes(q));
    const host=$("outbox");
    if(!rows.length){host.innerHTML='<div class="msg">No queued WhatsApp rows.</div>';return}
    host.innerHTML=`<div class="wa-list"><div class="wa-row head"><div>Created</div><div>Mobile</div><div>Message</div><div>Status</div><div>Action</div></div>${rows.map(r=>`
      <div class="wa-row" data-id="${esc(r.message_id)}">
        <div>${esc(shortDate(r.created_at))}</div>
        <div class="wa-mobile">${esc(r.recipient_mobile||"")}</div>
        <div class="wa-msg" title="${esc(r.message_text||"")}">${esc(r.message_text||"")}</div>
        <div>${esc(r.send_status||r.provider_code||"")}</div>
        <button type="button" class="wa-open open-row" data-id="${esc(r.message_id)}">OPEN WHATSAPP</button>
      </div>`).join("")}</div>`;
  }

  async function load(){
    try{
      cache=await RF853.rows("rr_comm_outbox_v853",{order:"created_at",limit:200});
      render();
      let l=[];try{l=await RF853.rows("rr_comm_delivery_log_v853",{order:"created_at",limit:200})}catch{}
      RF853.table("logs",l,["message_id","provider_status","provider_message_id","created_at","provider_payload"]);
    }catch(e){RF853.msg("msg",e.message,"error")}
  }

  function reserveWhatsappTab(){
    const w=window.open("about:blank","_blank");
    if(w){try{w.opener=null;w.document.title="Opening WhatsApp…";w.document.body.innerHTML='<div style="font:16px system-ui;padding:24px">Opening WhatsApp…</div>'}catch{}}
    return w;
  }

  async function openQueued(id){
    id=String(id||"").trim();
    if(!id){RF853.msg("msg","Message ID required.","error");return}

    // Reserve a tab immediately inside the user click event. This avoids popup blocking
    // after the asynchronous Supabase lookup finishes.
    const reserved=reserveWhatsappTab();
    try{
      const c=await RF853.client();
      const {data:r,error}=await c.from("rr_comm_outbox_v853")
        .select("message_id,recipient_mobile,message_text")
        .eq("message_id",id).single();
      if(error)throw error;
      if(!r?.recipient_mobile)throw new Error("WhatsApp mobile missing in queued message.");
      const url=RF853.whatsappUrl(r.recipient_mobile,r.message_text||"");
      if(reserved && !reserved.closed){reserved.location.replace(url)}
      else location.assign(url);
      try{await RF853.rpc("rr_comm_mark_whatsapp_opened_v853",{p_message_id:id})}catch(e){console.warn("WA open audit",e)}
      RF853.msg("msg","WhatsApp message opened. Send button WhatsApp me press karein.","ok");
      setTimeout(load,250);
    }catch(e){
      try{if(reserved && !reserved.closed)reserved.close()}catch{}
      RF853.msg("msg",e.message||String(e),"error");
    }
  }

  $("openById").onclick=()=>openQueued($("mid").value);
  $("manual").onclick=()=>{
    try{
      const p=$("phone").value, t=$("text").value;
      if(!String(t||"").trim())throw new Error("Message required.");
      RF853.openWhatsapp(p,t);
      RF853.msg("msg","Manual WhatsApp message opened.","ok");
    }catch(e){RF853.msg("msg",e.message,"error")}
  };
  $("outbox").addEventListener("click",e=>{
    const b=e.target.closest(".open-row");
    if(b)openQueued(b.dataset.id);
  });
  $("refresh").onclick=load;
  $("filter").oninput=render;
  $("dataMode").onchange=load;
  load();
})();
