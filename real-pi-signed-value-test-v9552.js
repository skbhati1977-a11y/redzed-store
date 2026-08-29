(()=>{
  'use strict';
  if(window.__RR_PI_SIGNED_VALUE_TEST_V9552__)return;
  window.__RR_PI_SIGNED_VALUE_TEST_V9552__=true;
  if(!window.RF853?.rpc)return;
  const baseRpc=window.RF853.rpc.bind(window.RF853);
  const num=id=>Number(document.getElementById(id)?.value||0);
  window.RF853.rpc=(name,args={})=>{
    if(name!=='rr_fg_save_pi_v816')return baseRpc(name,args);
    const valuePct=num('value'),freight=num('freight'),other=num('other');
    if(!Number.isFinite(valuePct)||!Number.isFinite(freight)||!Number.isFinite(other))return Promise.reject(Error('Invalid commercial charges.'));
    if(freight<0||other<0)return Promise.reject(Error('Freight / Other Charges negative nahi ho sakte.'));
    return baseRpc('rr_fg_save_pi_signed_value_v9552',{
      p_pi_id:args.p_pi_id??null,
      p_customer_name:args.p_customer_name,
      p_dispatch_details:args.p_dispatch_details,
      p_lines:args.p_lines,
      p_value_added_pct:valuePct,
      p_freight_amount:freight,
      p_packing_other:other,
      p_gst_pct:Number(args.p_gst_pct||0),
      p_finalize:!!args.p_finalize,
      p_data_mode:args.p_data_mode||'TEST'
    });
  };
})();
