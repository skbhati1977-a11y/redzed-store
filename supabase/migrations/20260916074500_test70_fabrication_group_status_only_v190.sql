-- TEST70 V190: a Fabrication group projection explains source work but never
-- duplicates the source worker's actionable Alter/Remake button.
begin;

create or replace function public.rr_real_chat_work_inbox_v81(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v80(p_status,p_search,p_department_code,p_limit);
  select coalesce(jsonb_agg(
    case when upper(coalesce(card->>'department_code',''))='FABRICATION'
      and nullif(card->>'source_department_code','') is not null
    then card||jsonb_build_object(
      'operational_group_name','Fabrication / Line Man',
      'department_name',public.rr_costing_department_display_v760(card->>'source_department_code'),
      'source_worker_name',card->>'worker_name',
      'message',concat('Source ',public.rr_costing_department_display_v760(card->>'source_department_code'),
        ' · ',coalesce(card->>'message','Lineman operational journey'),
        case when coalesce((card->>'group_only')::boolean,false)
          then ' · Action source worker chat में होगा' else '' end),
      'actions',case when coalesce((card->>'group_only')::boolean,false)
        then '[]'::jsonb else coalesce(card->'actions','[]'::jsonb) end,
      'requires_action',case when coalesce((card->>'group_only')::boolean,false)
        then false else coalesce((card->>'requires_action')::boolean,false) end
    ) else card end order by ord
  ),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord);
  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN') department_code,count(*) cnt
    from jsonb_array_elements(v_cards)x group by 1)s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}',
    to_jsonb('TEST70_REAL_CHAT_WORK_V81_FABRICATION_STATUS_ONLY'::text),true),
    '{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v81(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v81(text,text,text,integer) to authenticated;

commit;
