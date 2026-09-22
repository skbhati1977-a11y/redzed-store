(()=>{
  "use strict";
  const initialParams=new URLSearchParams(location.search);
  const targetFromRaw=raw=>{
    if(!raw)return null;
    try{const url=new URL(raw,location.href);return url.origin===location.origin?url.pathname+url.search+url.hash:null}catch{return null}
  };
  // Capture the bridge contract before an action form rewrites its own URL.
  // Canonical forms may replaceState after a new record gains its permanent ID;
  // that must never erase the parent return/focus route or fall through to the
  // joint-session history (which can navigate the top-level app to login).
  const returnTarget=targetFromRaw(initialParams.get("return"));
  const successTarget=targetFromRaw(initialParams.get("success_return"));
  const embedded=window.parent!==window&&initialParams.get("embed")==="1";
  const action=initialParams.get("rr_action")||"";
  const success=(options={})=>{let url=successTarget||returnTarget,status=String(options?.status||"").toUpperCase(),focus=String(options?.focus||"").trim();if(url&&(status||focus)){const next=new URL(url,location.href);if(status)next.searchParams.set("rc_status",status);if(focus)next.searchParams.set("rc_focus_cb",focus);url=next.pathname+next.search+next.hash}if(embedded){window.parent.postMessage({type:"RR_REAL_CHAT_ACTION_SUCCESS",action,status,focus},location.origin);return}if(url)location.replace(url);else history.back()};
  window.RRActionReturn={back:()=>history.back(),success,hasReturn:()=>!!(successTarget||returnTarget)};
})();
