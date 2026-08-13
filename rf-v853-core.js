
(() => {
  "use strict";
  const aliases = () => [window.supabaseClient,window.supabaseDb,window.redzedSupabase,window.sb].find(x=>x?.from || x?.rpc);
  const esc = v => String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const normalizePhone = value => { let x=String(value||"").replace(/\D/g,""); if(x.length===10)x="91"+x; return x; };
  const whatsappUrl = (phone,message) => {
    const n=normalizePhone(phone); if(!n) throw new Error("WhatsApp number required.");
    return `https://wa.me/${n}?text=${encodeURIComponent(String(message||""))}`;
  };
  async function client(){ const c=aliases(); if(!c) throw new Error("Supabase client unavailable. Keep canonical config.js + real-common.js."); return c; }
  async function rows(name, opts={}) {
    const c=await client(); let q=c.from(name).select(opts.select||"*");
    if(opts.eq) Object.entries(opts.eq).forEach(([k,v])=>q=q.eq(k,v));
    if(opts.ilike) Object.entries(opts.ilike).forEach(([k,v])=>q=q.ilike(k,v));
    if(opts.order) q=q.order(opts.order,{ascending:opts.ascending??false});
    if(opts.limit) q=q.limit(opts.limit);
    const {data,error}=await q; if(error) throw error; return data||[];
  }
  async function rpc(name,args={}) { const c=await client(); const {data,error}=await c.rpc(name,args); if(error) throw error; return data; }
  function table(el, data, preferred=[]) {
    const node=typeof el==="string"?document.getElementById(el):el; if(!node)return;
    if(!Array.isArray(data)||!data.length){node.innerHTML='<div class="msg">No rows.</div>';return}
    const cols=[...preferred.filter(c=>data.some(r=>Object.prototype.hasOwnProperty.call(r,c))),...Object.keys(data[0]).filter(c=>!preferred.includes(c))].slice(0,16);
    node.innerHTML=`<div class="scroll"><table><thead><tr>${cols.map(c=>`<th>${esc(c.replaceAll("_"," "))}</th>`).join("")}</tr></thead><tbody>${data.map(r=>`<tr>${cols.map(c=>`<td>${esc(typeof r[c]==="object"?JSON.stringify(r[c]):r[c])}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }
  function msg(el,text,type=""){const n=typeof el==="string"?document.getElementById(el):el;if(n){n.className="msg "+type;n.textContent=text}}
  function openWhatsapp(phone,message,{sameTabFallback=true}={}) {
    const url=whatsappUrl(phone,message);
    const w=window.open(url,"_blank","noopener,noreferrer");
    if(!w && sameTabFallback){location.assign(url);return false}
    if(!w) throw new Error("Browser blocked WhatsApp popup."); return true;
  }
  function mode(){return (document.getElementById("dataMode")?.value||"TEST").toUpperCase()}
  window.RF853={client,rows,rpc,table,msg,esc,normalizePhone,whatsappUrl,openWhatsapp,mode};
})();
