(()=>{
  "use strict";
  const target=name=>{
    const raw=new URLSearchParams(location.search).get(name);
    if(!raw)return null;
    try{const url=new URL(raw,location.href);return url.origin===location.origin?url.pathname+url.search+url.hash:null}catch{return null}
  };
  const success=(options={})=>{let url=target("success_return")||target("return"),status=String(options?.status||"").toUpperCase(),focus=String(options?.focus||"").trim(),action=new URLSearchParams(location.search).get("rr_action")||"";if(url&&(status||focus)){const next=new URL(url,location.href);if(status)next.searchParams.set("rc_status",status);if(focus)next.searchParams.set("rc_focus_cb",focus);url=next.pathname+next.search+next.hash}if(window.parent!==window&&new URLSearchParams(location.search).get("embed")==="1"){window.parent.postMessage({type:"RR_REAL_CHAT_ACTION_SUCCESS",action,status,focus},location.origin);return}if(url)location.replace(url);else history.back()};
  window.RRActionReturn={back:()=>history.back(),success,hasReturn:()=>!!target("return")};
})();
