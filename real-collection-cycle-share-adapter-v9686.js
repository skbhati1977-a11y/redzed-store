(()=>{
  'use strict';
  if(window.__RR_COLLECTION_CYCLE_SHARE_ADAPTER_V9686__)return;
  window.__RR_COLLECTION_CYCLE_SHARE_ADAPTER_V9686__=true;
  let tries=0;
  function install(){
    if(!window.RF853?.rpc){if(++tries<80)setTimeout(install,100);return}
    if(window.RF853.rpc.__rrCycle9686)return;
    const original=window.RF853.rpc.bind(window.RF853);
    const reads=new Set(['rr_market_share_view_v9420','rr_collection_customer_requirement_summary_v9637','rr_collection_customer_pricing_v9637']);
    const wrapped=async(name,args={})=>{
      if(!reads.has(name)||!args.p_token)return original(name,args);
      const state=await original('rr_collection_current_state_v9633',{p_token:args.p_token});
      const current={...args,p_token:state?.latest_collection_token||args.p_token};
      return original(name==='rr_market_share_view_v9420'?'rr_collection_cycle_share_view_v9686':name,current);
    };
    wrapped.__rrCycle9686=true;
    window.RF853.rpc=wrapped;
  }
  install();
})();
