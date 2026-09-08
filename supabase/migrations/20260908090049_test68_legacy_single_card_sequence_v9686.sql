-- TEST68: cumulative cycle view plus recoverable legacy single-card cleanup.
create or replace function public.rr_collection_cycle_share_view_v9686(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_cycle public.rr_collection_cycle_v9586%rowtype; v_data jsonb;
 v_rows jsonb:='[]'::jsonb; v_update integer:=0; x record;
begin
 select c.* into v_cycle from public.rr_market_share_v9420 s
 join public.rr_collection_send_v9586 cs on cs.share_id=s.id
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
 where (s.token=p_token or s.short_code=upper(p_token)) and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1;
 if v_cycle.id is null then return public.rr_market_share_view_v9420(p_token); end if;
 for x in select s.token,cs.send_seq from public.rr_collection_send_v9586 cs
  join public.rr_market_share_v9420 s on s.id=cs.share_id
  where cs.collection_cycle_id=v_cycle.id and s.status='ACTIVE' order by cs.send_seq
 loop
  v_data:=public.rr_market_share_view_v9420(x.token);
  v_rows:=v_rows||coalesce(v_data->'rows','[]'::jsonb);
  v_update:=greatest(v_update,x.send_seq-1);
 end loop;
 select coalesce(jsonb_agg(q.val order by q.ord),'[]'::jsonb) into v_rows from (
  select distinct on (e.value->>'lot_no') e.value val,e.ordinality ord
  from jsonb_array_elements(v_rows) with ordinality e(value,ordinality)
  order by e.value->>'lot_no',e.ordinality desc
 ) q;
 return coalesce(v_data,'{}'::jsonb)||jsonb_build_object('rows',v_rows,
  'collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
  'collection_display_no',v_cycle.display_no,'collection_update_no',v_update);
end $function$;
revoke all on function public.rr_collection_cycle_share_view_v9686(text) from public;
grant execute on function public.rr_collection_cycle_share_view_v9686(text) to anon,authenticated,service_role;

with candidates as (
 select m.id message_id,m.created_at,s.id share_id,r.collection_cycle_id,
  row_number() over(partition by r.collection_cycle_id order by m.created_at,m.id) rn
 from public.rr_customer_chat_messages_v9433 m
 join public.rr_market_share_v9420 s on s.token=(regexp_match(m.body,'[?&]t=([a-f0-9]+)'))[1]
 join public.rr_market_requirements_v9420 r on r.id=((regexp_match(m.body,'[?&]r=([0-9a-f-]{36})'))[1])::uuid
 join public.rr_collection_cycle_v9586 c on c.id=r.collection_cycle_id and c.chat_id=m.chat_id
 where m.archived_at is null and lower(coalesce(m.body,'')) like '%open collection:%'
  and m.body ~ '[?&]r=[0-9a-f-]{36}'
  and not exists(select 1 from public.rr_collection_send_v9586 z where z.share_id=s.id)
), numbered as (
 select x.*,coalesce((select max(z.send_seq) from public.rr_collection_send_v9586 z
  where z.collection_cycle_id=x.collection_cycle_id),0)+x.rn send_seq from candidates x
)
insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_at)
select collection_cycle_id,share_id,send_seq,case when send_seq=1 then 'FIRST' else 'UPDATE' end,created_at
from numbered on conflict do nothing;

with mapped as (
 select m.id,cs.collection_cycle_id,cs.send_seq,c.collection_no,c.display_no,
  row_number() over(partition by cs.collection_cycle_id order by cs.send_seq desc,m.created_at desc,m.id desc) rn
 from public.rr_customer_chat_messages_v9433 m
 join public.rr_market_share_v9420 s on s.token=(regexp_match(m.body,'[?&]t=([a-f0-9]+)'))[1]
 join public.rr_collection_send_v9586 cs on cs.share_id=s.id
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id and c.chat_id=m.chat_id
 where m.archived_at is null and lower(coalesce(m.body,'')) like '%open collection:%'
)
update public.rr_customer_chat_messages_v9433 m set
 body=regexp_replace(m.body,'^REDZED COLLECTION',x.display_no||case when x.send_seq>1 then ' · UPDATE '||(x.send_seq-1) else ' · ORIGINAL' end),
 payload=coalesce(m.payload,'{}'::jsonb)||jsonb_build_object('direct_collection_cycle_id',x.collection_cycle_id,
  'collection_no',x.collection_no,'collection_display_no',x.display_no,'collection_update_no',x.send_seq-1),
 archived_at=case when x.rn>1 then clock_timestamp() else null end,
 archive_reason=case when x.rn>1 then 'LEGACY_COLLECTION_SUPERSEDED_SINGLE_CARD' else null end,
 archive_meta=case when x.rn>1 then coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('collection_cycle_id',x.collection_cycle_id) else coalesce(m.archive_meta,'{}'::jsonb) end
from mapped x where m.id=x.id;

with mapped as (
 select m.id,m.chat_id,r.id requirement_id,coalesce(r.root_requirement_id,r.id) root_id,
  r.collection_cycle_id,r.requirement_display_no,r.requirement_update_no,
  row_number() over(partition by m.chat_id,coalesce(r.root_requirement_id,r.id) order by m.created_at desc,m.id desc) rn
 from public.rr_customer_chat_messages_v9433 m
 join public.rr_market_requirements_v9420 r on r.id=coalesce(nullif(m.payload->>'requirement_id','')::uuid,
  ((regexp_match(m.body,'\[REQ:([0-9a-f-]{36})\]'))[1])::uuid)
 where m.archived_at is null and m.message_type='REQUIREMENT'
)
update public.rr_customer_chat_messages_v9433 m set
 body='[REQ:'||x.requirement_id::text||'] '||x.requirement_display_no,
 payload=coalesce(m.payload,'{}'::jsonb)||jsonb_build_object('requirement_id',x.requirement_id,
  'direct_requirement_root_id',x.root_id,'direct_collection_cycle_id',x.collection_cycle_id,
  'requirement_display_no',x.requirement_display_no,'requirement_update_no',x.requirement_update_no),
 archived_at=case when x.rn>1 then clock_timestamp() else null end,
 archive_reason=case when x.rn>1 then 'LEGACY_REQUIREMENT_SUPERSEDED_SINGLE_CARD' else null end,
 archive_meta=case when x.rn>1 then coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('requirement_root_id',x.root_id) else coalesce(m.archive_meta,'{}'::jsonb) end
from mapped x where m.id=x.id;

comment on function public.rr_collection_cycle_share_view_v9686(text) is
 'Token-authorized cumulative Collection read model across original and ordered updates.';
