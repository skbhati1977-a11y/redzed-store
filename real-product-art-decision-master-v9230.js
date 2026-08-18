(()=>{
"use strict";
if(window.__RR_PM_ART_DECISION_MASTER_9230__)return;
window.__RR_PM_ART_DECISION_MASTER_9230__=true;

const $=id=>document.getElementById(id);

function text(el){return String(el?.textContent||"").trim();}
function esc(value){return String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));}

function childStatus(card){
  const metrics=[...card.querySelectorAll(".metric")];
  const byLabel=label=>{
    const row=metrics.find(m=>text(m.querySelector("small")).toLowerCase()===label.toLowerCase());
    return text(row?.querySelector("strong"))||"—";
  };
  return {
    d:text(card.querySelector(".card-head strong"))||byLabel("D No."),
    art:byLabel("Art"),
    print:byLabel("Print"),
    sticker:byLabel("Sticker"),
    metal:byLabel("Metal ID"),
    state:text(card.querySelector(".chip"))||"ART DUE"
  };
}

function enhanceGallery(){
  const gallery=$("gallery");
  if(!gallery)return;

  gallery.querySelectorAll(".mc-card [data-assign]").forEach(node=>node.remove());

  gallery.querySelectorAll("[data-assign]").forEach(button=>{
    if(button.closest(".mc-card"))return;
    button.textContent="Art Decision Master";
    button.setAttribute("aria-label","Open child Art Decision Master");
  });
}

function closeDetailSheet(){
  const sheet=$("detailSheet");
  if(!sheet)return;
  sheet.classList.add("hidden");
  sheet.setAttribute("aria-hidden","true");
  if(!document.querySelector(".sheet:not(.hidden)"))document.body.style.overflow="";
}

function openChildDecision(unitId){
  const source=document.querySelector(`#gallery [data-assign="${CSS.escape(String(unitId))}"]`);
  if(!source)return;
  closeDetailSheet();
  source.click();
}

function enhanceCbDetail(){
  const body=$("detailBody");
  if(!body)return;

  const isCb=text($("detailKicker")).toUpperCase()==="CB DETAILS";
  if(!isCb){
    body.querySelector("#rrChildArtDecisionMaster9230")?.remove();
    return;
  }
  if(body.querySelector("#rrChildArtDecisionMaster9230"))return;

  const cbNo=text($("detailTitle"));
  const childCards=[...document.querySelectorAll("#gallery .card")]
    .filter(card=>!card.classList.contains("mc-card"))
    .filter(card=>text(card.querySelector(".card-head h3"))===cbNo)
    .filter(card=>card.querySelector("[data-assign]"));

  if(!childCards.length)return;

  const section=document.createElement("section");
  section.id="rrChildArtDecisionMaster9230";
  section.className="form-card spaced";
  section.innerHTML=`
    <div class="section-row">
      <div>
        <p class="kicker">CHILD MASTER MODULE</p>
        <h3>Art Decision Master</h3>
        <p class="muted">Har child ka complete workflow: Art → Print → Sticker → Metal ID → Save & Exit.</p>
      </div>
    </div>
    <div class="history-list" style="margin-top:12px">
      ${childCards.map(card=>{
        const button=card.querySelector("[data-assign]");
        const s=childStatus(card);
        return `<article class="history">
          <div class="section-row">
            <div>
              <span class="status-chip ${/DECIDED/i.test(s.state)?"good":"bad"}">${esc(s.state)}</span>
              <h4 style="margin:8px 0 4px">${esc(s.d||"Child")}</h4>
              <small>Art ${esc(s.art)} · Print ${esc(s.print)} · Sticker ${esc(s.sticker)} · Metal ID ${esc(s.metal)}</small>
            </div>
            <button class="primary" type="button" data-child-art-master="${esc(button.dataset.assign)}">Open Art Decision</button>
          </div>
        </article>`;
      }).join("")}
    </div>`;

  const first=body.firstElementChild;
  if(first)first.insertAdjacentElement("afterend",section);else body.appendChild(section);
  section.querySelectorAll("[data-child-art-master]").forEach(button=>{
    button.addEventListener("click",()=>openChildDecision(button.dataset.childArtMaster));
  });
}

function enhanceAssignSheet(){
  const sheet=$("assignSheet");
  if(!sheet)return;
  const kicker=sheet.querySelector(".sheet-head .kicker");
  if(kicker)kicker.textContent="ART DECISION MASTER · CHILD WORKFLOW";
  const context=$("assignContext");
  if(context&&!context.dataset.masterContext9230){
    context.dataset.masterContext9230="1";
  }
}

function enhance(){
  enhanceGallery();
  enhanceCbDetail();
  enhanceAssignSheet();
}

const observer=new MutationObserver(()=>enhance());
observer.observe(document.documentElement,{childList:true,subtree:true});

document.addEventListener("click",event=>{
  if(event.target.closest("[data-cb-detail], [data-assign], [data-mc-detail]"))setTimeout(enhance,0);
},true);

if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",enhance,{once:true});
else enhance();
})();