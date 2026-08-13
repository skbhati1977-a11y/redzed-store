
(() => {let c={};
const f=a=>{const s=q.value.toLowerCase();return !s?a:a.filter(x=>JSON.stringify(x).toLowerCase().includes(s))}
function render(){RF853.table("rules",f(c.rules||[]),["cost_code","cost_name","business_stream","rate_per_pc","annual_amount","monthly_amount","allocation_driver","source_type","effective_from","is_active"]);
RF853.table("pool",f(c.pool||[]),["expense_code","expense_name","expense_group","business_stream","allocation_driver","period_start","period_end","amount","source_type"]);
RF853.table("effective",f(c.effective||[]),["cost_code","cost_name","business_stream","rate_per_pc","normalized_monthly_amount","allocation_driver","source_type"]);
RF853.table("tests",c.tests||[],["test_code","passed","details"])}
async function load(){try{const m=RF853.mode();const get=async(n,eq=true)=>{try{return await RF853.rows(n,eq?{eq:{data_mode:m}}:{})}catch{return await RF853.rows(n)}};
[c.rules,c.pool,c.effective,c.tests]=await Promise.all([get("rr_cost_fixed_rule_v850"),get("rr_cost_expense_pool_v850"),get("rr_cost_rule_effective_v850"),get("rr_cost_test_result_v850",false)]);render();RF853.msg("msg","Costing backend loaded.","ok")}catch(e){RF853.msg("msg",e.message,"error")}}
refresh.onclick=load;q.oninput=render;dataMode.onchange=load;load()})();
