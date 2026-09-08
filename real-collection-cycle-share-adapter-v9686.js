(()=>{
  'use strict';
  if(window.__RR_COLLECTION_CYCLE_SHARE_ADAPTER_V9686__)return;
  window.__RR_COLLECTION_CYCLE_SHARE_ADAPTER_V9686__=true;
  let tries=0;
  function install(){
    if(!window.RF853?.rpc){if(++tries<80)setTimeout(install,100);return}
    if(window.RF853.rpc.__rrCycle9686)return;
    const original=window.RF853.rpc.bind(window.RF853);
    const wrapped=(name,args)=>original(name==='rr_market_share_view_v9420'?'rr_collection_cycle_share_view_v9686':name,args);
    wrapped.__rrCycle9686=true;
    window.RF853.rpc=wrapped;
  }
  install();
})();
