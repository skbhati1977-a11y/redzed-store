(() => {
  "use strict";
  if (!/\/art-v9148\/?$/i.test(window.location.pathname)) return;

  const LABELS = ["Collar","Neck","Sleeve","Placket","Panels","Stitch / Finish"];
  const css = document.createElement("style");
  css.textContent = `
    .art-craft-map-card{margin-top:16px;border:1px solid var(--art-border,#dfe3e8);border-radius:16px;background:#fff;padding:15px;box-shadow:0 5px 18px rgba(16,24,40,.04)}
    .art-craft-map-head{display:flex;align-items:flex-start;justify-content:space-between;gap:10px;margin-bottom:10px}.art-craft-map-head label{margin:0;font-weight:900;color:#20242a}.art-craft-map-head span{font-size:10px;font-weight:900;padding:5px 8px;border-radius:999px;background:#eef4ff;color:#175cd3}
    .art-craft-map-select{width:100%;min-height:48px;border:1px solid #cfd4dc;border-radius:12px;background:#fff;color:#101828;padding:0 14px;font-size:16px}
    .art-craft-map-chips{display:flex;flex-wrap:wrap;gap:7px;margin-top:10px;min-height:36px}.art-craft-map-chip{display:inline-flex;align-items:center;gap:6px;padding:7px 10px;border:1px solid #d0d5dd;border-radius:999px;background:#f8fafc;color:#344054;font-size:12px;font-weight:800}.art-craft-map-chip.is-current{background:#111;color:#fff;border-color:#111}.art-craft-map-chip b{font-size:10px;opacity:.72;text-transform:uppercase}.art-craft-map-empty{color:#98a2b3;font-size:12px;padding:7px 0}.art-craft-map-help{display:block;margin-top:8px;color:#697386;font-size:12px;line-height:1.45}.art-craft-map-json{display:none!important}
    @media(max-width:520px){.art-craft-map-card{padding:13px}.art-craft-map-head{align-items:center}.art-craft-map-chip{flex:1 1 calc(50% - 7px);justify-content:center;text-align:center;border-radius:12px;min-height:42px}}
  `;
  document.head.appendChild(css);

  const norm = v => String(v || "").trim().toLowerCase().replace(/\s+/g," ");
  const cleanText = b => String(b?.textContent || "").replace(/^\s*✓\s*/,"").replace(/\s*×\s*$/,"").trim();
  const groupName = group => {
    const h=norm(group?.querySelector("h4")?.textContent);
    if(h.includes("collar"))return "Collar"; if(h.includes("neck"))return "Neck";
    if(h.includes("sleeve")||h.includes("cuff"))return "Sleeve"; if(h.includes("placket"))return "Placket";
    if(h.includes("panel")||h.includes("shoulder")||h.includes("pocket")||h.includes("waist")||h.includes("bottom")||h.includes("fit")||h.includes("construction"))return "Panels";
    if(h.includes("stitch")||h.includes("finish"))return "Stitch / Finish"; return null;
  };
  function selectedCraft(){
    const builder=document.getElementById("artCaptionBuilder"); if(!builder)return [];
    const out=[];
    builder.querySelectorAll(".rr-caption-group").forEach(group=>{
      const label=groupName(group); if(!label||!LABELS.includes(label))return;
      group.querySelectorAll(".rr-caption-pill.selected").forEach(button=>{const value=cleanText(button);if(value)out.push({group:label,value,key:`${label}::${norm(value)}`});});
    });
    const seen=new Set(); return out.filter(x=>!seen.has(x.key)&&seen.add(x.key));
  }
  function ensureCard(){
    const item=document.getElementById("itemName"); if(!item)return null;
    let card=document.getElementById("artCraftMapCard"); if(card)return card;
    const design=item.closest(".art-field-card")||item.parentElement; if(!design)return null;
    card=document.createElement("div"); card.id="artCraftMapCard"; card.className="art-craft-map-card";
    card.innerHTML=`<div class="art-craft-map-head"><label for="artCraftMapSelect">Craft Details</label><span>UPM READY</span></div><select id="artCraftMapSelect" class="art-craft-map-select"><option value="">Select mapped Craft Detail</option></select><div id="artCraftMapChips" class="art-craft-map-chips"><span class="art-craft-map-empty">Craft Features select karne par mapped details yahan aayengi.</span></div><input id="artCraftMapJson" class="art-craft-map-json" type="hidden" value="[]"><small class="art-craft-map-help">Selected Craft Features ka structured group/value map. UPM child modules isi canonical detail ko use kar sakte hain.</small>`;
    design.insertAdjacentElement("afterend",card); card.querySelector("select").addEventListener("change",render); return card;
  }
  function render(){
    const card=ensureCard(); if(!card)return;
    const select=card.querySelector("#artCraftMapSelect"),chips=card.querySelector("#artCraftMapChips"),json=card.querySelector("#artCraftMapJson");
    const items=selectedCraft(), old=select.value;
    select.innerHTML=`<option value="">Select mapped Craft Detail</option>`+items.map((x,i)=>`<option value="${i}">${x.group} — ${x.value}</option>`).join("");
    if(old!==""&&items[Number(old)])select.value=old; else if(items.length===1)select.value="0";
    const current=select.value===""?null:items[Number(select.value)]||null;
    chips.innerHTML=items.length?items.map(x=>`<span class="art-craft-map-chip ${current?.key===x.key?"is-current":""}"><b>${x.group}</b>${x.value}</span>`).join(""):`<span class="art-craft-map-empty">Craft Features tab se details select karo.</span>`;
    const mapping={selected:current,available:items}; json.value=JSON.stringify(mapping); window.RR_ART_CRAFT_UPM_MAPPING=mapping;
    window.dispatchEvent(new CustomEvent("redzed:art-craft-mapping",{detail:mapping}));
  }
  function boot(){
    ensureCard(); const builder=document.getElementById("artCaptionBuilder");
    if(builder){new MutationObserver(()=>setTimeout(render,0)).observe(builder,{childList:true,subtree:true,attributes:true,attributeFilter:["class"]});builder.addEventListener("click",()=>setTimeout(render,0),true);builder.addEventListener("change",()=>setTimeout(render,0),true);}
    document.getElementById("cancelEdit")?.addEventListener("click",()=>setTimeout(render,50)); render();
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();