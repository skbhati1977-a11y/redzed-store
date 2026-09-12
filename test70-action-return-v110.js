(()=>{
  "use strict";
  const target=name=>{
    const raw=new URLSearchParams(location.search).get(name);
    if(!raw)return null;
    try{const url=new URL(raw,location.href);return url.origin===location.origin?url.pathname+url.search+url.hash:null}catch{return null}
  };
  const go=name=>{const url=target(name);if(url)location.assign(url);else history.back()};
  window.RRActionReturn={back:()=>go("return"),success:()=>go("success_return"),hasReturn:()=>!!target("return")};
})();
