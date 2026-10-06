(() => {
  'use strict';
  // Same business-input authority as real-common.js; lightweight Real Chat shell.
  const RR = window.RR || {};
  RR.businessUppercaseExempt=(el)=>{if(!(el instanceof HTMLInputElement||el instanceof HTMLTextAreaElement))return true;const type=String(el.type||'text').toLowerCase(),key=[el.id,el.name,el.placeholder,el.getAttribute('aria-label'),el.dataset.rrUppercase].filter(Boolean).join(' ').toLowerCase();if(el.dataset.rrUppercase==='off')return true;if(['password','email','url','search','file','number','date','time','datetime-local','month','week','color','range','checkbox','radio','hidden','button','submit'].includes(type))return true;if(/(?:password|email|e-mail|url|website|search|remark|remarks|note|notes|description|comment|comments|caption|message|address|reason|query)/i.test(key))return true;return false;};
  RR.uppercaseBusinessValue=(el)=>{if(RR.businessUppercaseExempt(el)||el.readOnly||el.disabled)return;const before=el.value,after=String(before||'').toLocaleUpperCase('en-IN');if(before===after)return;const s=el.selectionStart,e=el.selectionEnd;el.value=after;try{if(s!=null&&e!=null)el.setSelectionRange(s,e)}catch(_){}};
  RR.installBusinessUppercaseInputs=()=>{if(document.documentElement.dataset.rrBusinessUppercaseReady==='1')return;document.documentElement.dataset.rrBusinessUppercaseReady='1';const apply=e=>RR.uppercaseBusinessValue(e.target);document.addEventListener('input',apply,true);document.addEventListener('change',apply,true);document.addEventListener('focusout',apply,true);document.addEventListener('submit',e=>{e.target?.querySelectorAll?.('input,textarea').forEach(RR.uppercaseBusinessValue)},true);};
  RR.installBusinessUppercaseInputs();
})();
