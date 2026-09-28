const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const files=['supabase/migrations/20260928160500_test71_substantive_lifecycle_costing_cleanup_v721.sql','supabase/migrations/20260928161500_test71_substantive_product_foc_monthly_v721.sql','supabase/migrations/20260928162000_test71_targeted_push_delivery_v721.sql','supabase/migrations/20260928162100_test71_final_rate_push_v714.sql'];
const s=files.map(f=>fs.readFileSync(f,'utf8')).join('\n');
test('submit chain has canonical core and no v689-to-v327 recursion',()=>{assert.match(s,/rr_upm_finalize_submit_handover_v204/);const m=s.match(/create or replace function public\.rr_upm_finalize_submit_handover_v689[\s\S]*?\$function\$;/i)?.[0]||'';assert.doesNotMatch(m,/rr_upm_finalize_submit_handover_v327\(/);});
test('FOC is single product-cost authority',()=>{assert.match(s,/rr_upm_product_cost_actual_v709/);assert.match(s,/FOC_THREAD_1_50_ONLY/);assert.match(s,/PRODUCT COST USES FOC ONCE/);});
test('legacy first-box trigger is retired',()=>assert.match(s,/automatic first-box trigger is disabled/));
test('targeted push uses canonical identity and real chat route',()=>{assert.match(s,/rr_push_worker_id_v712/);assert.match(s,/rr_real_chat_route_v713/);assert.match(s,/rr_pack_rate_web_push_v714/);});
