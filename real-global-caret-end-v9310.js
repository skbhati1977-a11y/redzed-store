(()=>{
 "use strict";
 if(window.__RR_GLOBAL_CARET_END_V9310__)return;
 window.__RR_GLOBAL_CARET_END_V9310__=true;
 const TEXT_TYPES=new Set(["","text","search","tel","url","email","password","number"]);
 const skip=el=>!el||el.disabled||/^(button|submit|reset|checkbox|radio|file|range|color|date|time|datetime-local|month|week|hidden)$/i.test(el.type||"");
 const isTarget=el=>el&&(el.matches?.("textarea,[contenteditable='true']")||(el.matches?.("input")&&TEXT_TYPES.has(String(el.type||"").toLowerCase())&&!skip(el)));
 function endContentEditable(el){try{const r=document.createRange();r.selectNodeContents(el);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r)}catch(_e){}}
 function endInput(el){if(!isTarget(el))return;const v=String(el.value??el.textContent??"");if(!v)return;if(el.isContentEditable){endContentEditable(el);return}try{el.setSelectionRange(v.length,v.length)}catch(_e){try{const t=el.type;el.type="text";el.setSelectionRange(v.length,v.length);el.type=t}catch(_e2){try{el.value=v}catch(_e3){}}}}
 function schedule(el){if(!isTarget(el))return;requestAnimationFrame(()=>endInput(el));setTimeout(()=>endInput(el),40)}
 document.addEventListener("focusin",e=>schedule(e.target),true);
 document.addEventListener("pointerup",e=>schedule(e.target),true);
 document.addEventListener("click",e=>schedule(e.target),true);
 document.addEventListener("touchend",e=>schedule(e.target),true);
 document.addEventListener("redzed:focus-caret-end",e=>schedule(e.detail?.target||document.activeElement));
})();
