(()=>{
  "use strict";
  const target=name=>{
    const raw=new URLSearchParams(location.search).get(name);
    if(!raw)return null;
    try{const url=new URL(raw,location.href);return url.origin===location.origin?url.pathname+url.search+url.hash:null}catch{return null}
  };
  const success=()=>{const url=target("success_return")||target("return");if(url)location.replace(url);else history.back()};
  window.RRActionReturn={back:()=>history.back(),success,hasReturn:()=>!!target("return")};
})();
