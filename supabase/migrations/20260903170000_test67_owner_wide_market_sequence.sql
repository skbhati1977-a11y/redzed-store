-- TEST67: owner-wide Collection/Requirement reference sequence.
-- Additive and TEST-only; REAL numbering is not changed.

create table if not exists public.rr_market_owner_sequence_v67 (
  owner_key text not null,
  data_mode text not null,
  prefix text not null,
  current_no bigint not null default 0 check (current_no >= 0),
  updated_at timestamptz not null default now(),
  primary key (owner_key, data_mode),
  check (data_mode in ('TEST','REAL')),
  check (prefix ~ '^[A-Z0-9]{2,12}$')
);

alter table public.rr_market_owner_sequence_v67 enable row level security;
revoke all on public.rr_market_owner_sequence_v67 from public, anon, authenticated;
grant all on public.rr_market_owner_sequence_v67 to service_role;

insert into public.rr_market_owner_sequence_v67(owner_key,data_mode,prefix,current_no)
select 'REDZED','TEST','RZ',coalesce(max(collection_no),0)
from public.rr_collection_cycle_v9586 where data_mode='TEST'
on conflict (owner_key,data_mode) do nothing;

create or replace function public.rr_market_next_owner_ref_v67(
  p_owner_key text, p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_key text:=upper(nullif(trim(p_owner_key),''));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));
  v_row public.rr_market_owner_sequence_v67%rowtype;
  v_no bigint;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if v_mode<>'TEST' then raise exception 'TEST67 numbering is TEST-only.'; end if;
  if v_key is null then raise exception 'Owner key is required.'; end if;
  select * into v_row from public.rr_market_owner_sequence_v67
   where owner_key=v_key and data_mode=v_mode for update;
  if not found then raise exception 'Owner prefix is not configured.'; end if;
  v_no:=v_row.current_no+1;
  update public.rr_market_owner_sequence_v67 set current_no=v_no,updated_at=now()
   where owner_key=v_key and data_mode=v_mode;
  return jsonb_build_object('owner_key',v_key,'data_mode',v_mode,'sequence_no',v_no,
    'human_ref',v_row.prefix||'-'||lpad(v_no::text,3,'0'));
end $$;

create or replace function public.rr_collection_create_first_v67(
  p_customer_id uuid, p_lots text[], p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));
  v_chat uuid; v_cycle uuid; v_share jsonb; v_share_id uuid;
  v_ref jsonb; v_no bigint; v_human_ref text;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if v_mode<>'TEST' then raise exception 'TEST67 Collection is TEST-only.'; end if;
  if p_customer_id is null then raise exception 'Customer is required.'; end if;
  if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.'; end if;
  select id into v_chat from public.rr_customer_chat_v9433
   where customer_id=p_customer_id and data_mode=v_mode and status='OPEN'
   order by created_at asc limit 1;
  if v_chat is null then raise exception 'Permanent customer chat is required.'; end if;
  v_ref:=public.rr_market_next_owner_ref_v67('REDZED',v_mode);
  v_no:=(v_ref->>'sequence_no')::bigint; v_human_ref:=v_ref->>'human_ref';
  insert into public.rr_collection_cycle_v9586(
    customer_id,chat_id,data_mode,collection_no,display_no,status,created_by
  ) values(p_customer_id,v_chat,v_mode,v_no::int,v_human_ref,'DRAFT',auth.uid())
  returning id into v_cycle;
  v_share:=public.rr_market_create_share_v9420(p_lots,p_customer_id,
    (select customer_name from public.rr_customer_chat_v9433 where id=v_chat),v_mode);
  v_share_id:=(v_share->>'share_id')::uuid;
  insert into public.rr_collection_send_v9586(
    collection_cycle_id,share_id,send_seq,send_kind,sent_by
  ) values(v_cycle,v_share_id,1,'FIRST',auth.uid());
  update public.rr_collection_cycle_v9586 set status='SENT_NOT_OPENED' where id=v_cycle;
  return v_share||jsonb_build_object('collection_cycle_id',v_cycle,'collection_no',v_no,
    'collection_display_no',v_human_ref,'requirement_no',v_human_ref,
    'send_seq',1,'send_kind','FIRST');
end $$;

create or replace function public.rr_collection_submit_requirement_v67(
  p_token text, p_customer_name text, p_mobile text, p_message text,
  p_lines jsonb, p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_result jsonb; v_requirement_id uuid;
  v_cycle public.rr_collection_cycle_v9586%rowtype; v_ref text;
begin
  v_result:=public.rr_collection_submit_requirement_v9588(
    p_token,p_customer_name,p_mobile,p_message,p_lines,p_requirement_id);
  v_requirement_id:=(v_result->>'requirement_id')::uuid;
  select c.* into v_cycle from public.rr_collection_cycle_v9586 c
   where c.id=(v_result->>'collection_cycle_id')::uuid;
  if v_cycle.id is null then raise exception 'Collection flow missing.'; end if;
  if v_cycle.data_mode<>'TEST' then raise exception 'TEST67 Requirement is TEST-only.'; end if;
  v_ref:=nullif(trim(v_cycle.display_no),'');
  if v_ref is null then raise exception 'Collection reference missing.'; end if;
  update public.rr_market_requirements_v9420 set requirement_no=v_ref
   where id=v_requirement_id and requirement_no is distinct from v_ref;
  update public.rr_collection_activity_v9633
   set payload=jsonb_set(coalesce(payload,'{}'::jsonb),'{requirement_no}',to_jsonb(v_ref),true)
   where collection_cycle_id=v_cycle.id and reference_id=v_requirement_id;
  return v_result||jsonb_build_object('requirement_no',v_ref,
    'collection_display_no',v_ref,'human_ref',v_ref);
end $$;

revoke all on function public.rr_market_next_owner_ref_v67(text,text) from public,anon;
revoke all on function public.rr_collection_create_first_v67(uuid,text[],text) from public,anon;
revoke all on function public.rr_collection_submit_requirement_v67(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_market_next_owner_ref_v67(text,text) to authenticated,service_role;
grant execute on function public.rr_collection_create_first_v67(uuid,text[],text) to authenticated,service_role;
grant execute on function public.rr_collection_submit_requirement_v67(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;
