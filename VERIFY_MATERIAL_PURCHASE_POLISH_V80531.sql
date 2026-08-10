select 'CORE_MAPPING_RPC_UNCHANGED' check_name,
       to_regprocedure('public.rr_material_source_search_v805_1(text,text,text,integer)') is not null pass
union all select 'BACKEND_AUTO_PURCHASE',
       to_regprocedure('public.rr_material_post_purchase_auto_v805_31(uuid,uuid,uuid,numeric,numeric,text,date,numeric,text,numeric,uuid,text)') is not null
union all select 'ADD_NEW_MATERIAL',
       to_regprocedure('public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb)') is not null
union all select 'ADD_NEW_SUPPLIER',
       to_regprocedure('public.rr_material_supplier_create_v805_31(text)') is not null
union all select 'SUPPLIER_MAP',
       to_regclass('public.rr_material_source_supplier_map_v805_31') is not null;

select ledger_name,ledger_kind,is_active
from public.rr_ledgers_v805
where ledger_name in('Krishna Material','Vinayak Material','Rishabh Material','Sunil Supplier')
order by ledger_name;
