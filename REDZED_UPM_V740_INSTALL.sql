begin;
create or replace function public.rr_upm_lot_identity_v733(p_canonical_lot_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_reg public.rr_upm_lot_registry%rowtype;v_cut public.rr_cutting_lots_v3%rowtype;v_cb_no text;v_division text;v_art text;v_print text;v_frames text;
begin
 select * into v_reg from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 if not found then raise exception 'Lot not found in Universal Production registry.'; end if;
 select * into v_cut from public.rr_cutting_lots_v3 c where c.id::text=v_reg.source_id or upper(trim(c.lot_no))=upper(trim(v_reg.lot_no)) order by case when c.id::text=v_reg.source_id then 0 else 1 end,c.created_at desc nulls last limit 1;
 if not found then raise exception 'Released Cutting Lot mapping not found for Lot %.',v_reg.lot_no; end if;
 select coalesce(nullif(trim(fp.cb_no),''),nullif(trim(u.cb_base_no),''),nullif(trim(u.cb_code),'')),coalesce(nullif(trim(u.cb_code),''),case when u.division_index is not null then 'D'||u.division_index end)
 into v_cb_no,v_division from public.rr_cb_units u left join public.rr_fabric_purchases fp on fp.id=coalesce(v_cut.cb_purchase_id,u.purchase_id) where u.id=v_cut.cb_unit_id;
 v_art:=coalesce(nullif(trim(v_cut.art_no),''),nullif(trim(v_reg.art_no),''));
 v_print:=coalesce(nullif(trim(v_cut.print_no),''),nullif(trim(v_reg.metadata->>'print_no'),''));
 if v_print is not null then
  select string_agg(distinct f.frame_no, ', ' order by f.frame_no) into v_frames
  from regexp_split_to_table(v_print,'\s*,\s*') z join public.rr_print_master pm on upper(trim(pm.print_no))=upper(trim(z))
  left join public.rr_print_frames f on f.print_id=pm.id and upper(coalesce(f.frame_status,'ACTIVE')) not in ('RETIRED','CANCELLED');
 end if;
 return jsonb_build_object('lot_no',v_reg.lot_no,'cb_no',coalesce(v_cb_no,'MAPPING REQUIRED'),'division_code',coalesce(v_division,'MAPPING REQUIRED'),'art_no',coalesce(v_art,'MAPPING REQUIRED'),'print_no',coalesce(v_print,'MAPPING REQUIRED'),'frame_no',coalesce(nullif(trim(v_frames),''),case when v_print is null then 'MAPPING REQUIRED' else 'FRAME MAPPING REQUIRED' end),'item_name',v_reg.item_name,'cutting_lot_id',v_cut.id,'identity_source','CUTTING_RELEASE_SNAPSHOT');
end $$;
grant execute on function public.rr_upm_lot_identity_v733(text) to authenticated;

create or replace function public.rr_upm_action_balance_v733(p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text)
returns table(inbound_qty numeric,direct_good_qty numeric,alter_registered_qty numeric,remake_issued_qty numeric,remake_completed_qty numeric,damage_pending_qty numeric,damage_alter_qty numeric,damage_remake_qty numeric,damage_total_qty numeric,pending_qty numeric,alter_open_qty numeric,line_man_pending_qty numeric,worker_remake_pending_qty numeric,remake_open_qty numeric,good_total_qty numeric,outbound_qty numeric,submit_ready_qty numeric)
language sql stable security definer set search_path=public as $$
with b as(select * from public.rr_upm_action_balance_v731(p_canonical_lot_id,p_department_code,p_colour_id,p_colour_code,p_size_code)),f as(select count(*)::integer flow_rows from public.rr_upm_remake_flow_v729 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(trim(p_department_code)) and upper(x.size_code)=upper(trim(p_size_code)) and ((p_colour_id is not null and x.colour_id=p_colour_id) or (p_colour_id is null and upper(x.colour_code)=upper(trim(p_colour_code)))))
select b.inbound_qty,b.direct_good_qty,b.alter_registered_qty,b.remake_issued_qty,b.remake_completed_qty,b.damage_pending_qty,b.damage_alter_qty,b.damage_remake_qty,b.damage_total_qty,b.pending_qty,b.alter_open_qty,case when f.flow_rows>0 then b.line_man_pending_qty else 0 end,case when f.flow_rows>0 then b.worker_remake_pending_qty else greatest(b.remake_issued_qty-b.remake_completed_qty-b.damage_remake_qty,0) end,case when f.flow_rows>0 then b.worker_remake_pending_qty else greatest(b.remake_issued_qty-b.remake_completed_qty-b.damage_remake_qty,0) end,b.good_total_qty,b.outbound_qty,b.submit_ready_qty from b cross join f;
$$;
grant execute on function public.rr_upm_action_balance_v733(text,text,uuid,text,text) to authenticated;

create or replace function public.rr_upm_universal_form_v733(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_base jsonb;v_identity jsonb;v_rows jsonb:='[]'::jsonb;v_row jsonb;v_bal record;v_summary jsonb;
begin
 v_base:=public.rr_upm_universal_form_v731(p_canonical_lot_id,p_department_code);v_identity:=public.rr_upm_lot_identity_v733(p_canonical_lot_id);
 for v_row in select value from jsonb_array_elements(coalesce(v_base->'rows','[]'::jsonb)) loop
  select * into v_bal from public.rr_upm_action_balance_v733(p_canonical_lot_id,p_department_code,nullif(v_row->>'colour_id','')::uuid,v_row->>'colour_code',v_row->>'size_code');
  v_row:=v_row||jsonb_build_object('line_man_pending_qty',v_bal.line_man_pending_qty,'worker_remake_pending_qty',v_bal.worker_remake_pending_qty,'remake_open_qty',v_bal.remake_open_qty,'remake_qty',v_bal.remake_open_qty);v_rows:=v_rows||jsonb_build_array(v_row);
 end loop;
 select jsonb_build_object('assigned',coalesce(sum((r->>'assigned_qty')::numeric),0),'inbound',coalesce(sum((r->>'inbound_qty')::numeric),0),'good',coalesce(sum((r->>'good_qty')::numeric),0),'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),'line_man_pending',coalesce(sum((r->>'line_man_pending_qty')::numeric),0),'remake',coalesce(sum((r->>'worker_remake_pending_qty')::numeric),0),'damage',coalesce(sum((r->>'damage_qty')::numeric),0),'pending',coalesce(sum((r->>'pending_qty')::numeric),0),'ready_to_submit',coalesce(sum((r->>'submit_ready_qty')::numeric),0),'outbound',coalesce(sum((r->>'outbound_qty')::numeric),0)) into v_summary from jsonb_array_elements(v_rows) r;
 return v_base||jsonb_build_object('lot',(coalesce(v_base->'lot','{}'::jsonb)||v_identity),'rows',v_rows,'summary',v_summary,'balance_version','V733_LEGACY_SAFE','identity_version','CUTTING_RELEASE_SNAPSHOT');
end $$;
grant execute on function public.rr_upm_universal_form_v733(text,text) to authenticated;

create or replace function public.rr_upm_debug_lot_flow_v733(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb;v_identity jsonb;v_issues jsonb:='[]'::jsonb;v_workers integer;
begin
 v_identity:=public.rr_upm_lot_identity_v733(p_canonical_lot_id);v_context:=public.rr_upm_universal_form_v733(p_canonical_lot_id,p_department_code);select count(*) into v_workers from public.rr_upm_worker_list_v731(p_department_code);
 if v_identity->>'cb_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('CB mapping missing in released Cutting Lot'); end if;if v_identity->>'art_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Art No missing in released Cutting Lot'); end if;if v_identity->>'print_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Print No missing in released Cutting Lot/metadata snapshot'); end if;if v_workers=0 then v_issues:=v_issues||jsonb_build_array('No exact current-department worker is available'); end if;
 return jsonb_build_object('ok',jsonb_array_length(v_issues)=0,'issues',v_issues,'identity',v_identity,'department_code',upper(p_department_code),'exact_department_workers',v_workers,'context',v_context,'versions',jsonb_build_object('universal_form','V733','balance','V733_LEGACY_SAFE','identity','CUTTING_RELEASE_SNAPSHOT'));
end $$;
grant execute on function public.rr_upm_debug_lot_flow_v733(text,text) to authenticated;
commit;

-- ================================================================
-- REDZED UPM V740 FINAL TARGETED
-- Immutable identity + lot-level role enrolment + line-man Alter chain
-- + route lock + mapped WhatsApp + untraceable owner approval.
-- Requires existing V726/V727 production core. V733 identity foundation
-- is included before this section by the build package.
-- ================================================================
begin;
create extension if not exists pgcrypto;

create table if not exists public.rr_upm_lot_identity_lock_v740(
  canonical_lot_id text primary key,
  cutting_lot_id uuid not null,
  lot_no text not null,
  cb_no text not null,
  division_code text,
  art_no text not null,
  print_no text,
  frame_no text,
  item_name text,
  source_version text not null default 'CUTTING_RELEASE_LOCK_V740',
  locked_at timestamptz not null default now(),
  locked_by uuid default auth.uid()
);

create table if not exists public.rr_upm_route_lock_v740(
  canonical_lot_id text not null,
  from_department_code text not null,
  to_department_code text not null,
  locked_at timestamptz not null default now(),
  locked_by uuid default auth.uid(),
  primary key(canonical_lot_id,from_department_code)
);

create table if not exists public.rr_upm_lot_role_enrolment_v740(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  role_code text not null,
  person_id uuid not null,
  person_name_snapshot text not null,
  worker_code_snapshot text,
  department_code_snapshot text,
  phone_snapshot text,
  status text not null default 'ACTIVE' check(status in('ACTIVE','TRANSFERRED','CLOSED')),
  enrolled_at timestamptz not null default now(),
  enrolled_by uuid default auth.uid(),
  ended_at timestamptz,
  ended_by uuid,
  reason text
);
create unique index if not exists rr_upm_lot_role_enrolment_v740_active_uq
on public.rr_upm_lot_role_enrolment_v740(canonical_lot_id,role_code) where status='ACTIVE';

create table if not exists public.rr_upm_lot_role_transfer_v740(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  role_code text not null,
  from_enrolment_id uuid references public.rr_upm_lot_role_enrolment_v740(id),
  to_enrolment_id uuid references public.rr_upm_lot_role_enrolment_v740(id),
  transfer_mode text not null check(transfer_mode in('HANDOVER','LEAVE','FORCE_REENROL','INACTIVE_REPLACEMENT')),
  traceable_qty numeric(14,3) not null default 0,
  untraceable_qty numeric(14,3) not null default 0,
  physical_handover_confirmed boolean not null default false,
  reason text not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.rr_upm_alter_journey_v740(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  origin_department_code text not null,
  colour_id uuid,
  colour_code text not null,
  colour_name text not null,
  size_code text not null,
  open_qty numeric(14,3) not null check(open_qty>=0),
  stage text not null check(stage in(
    'LM_ALTER_PENDING','CM_REMAKE_READY','LM_DELIVERY_PENDING',
    'KARIGAR_REMAKE_PENDING','UNTRACEABLE_APPROVAL','CLOSED_GOOD','CLOSED_DAMAGE')),
  enrolled_lm_id uuid,
  enrolled_lm_name text,
  enrolled_lm_worker_code text,
  cutting_master_id uuid,
  cutting_master_name text,
  cutting_master_worker_code text,
  karigar_id uuid,
  karigar_name text,
  karigar_worker_code text,
  responsible_id uuid,
  responsible_name text,
  responsible_worker_code text,
  responsible_role_code text,
  responsible_department_code text,
  evidence_urls jsonb not null default '[]'::jsonb,
  physical_piece_confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  created_by_name text,
  closed_at timestamptz,
  close_reason text
);
create index if not exists rr_upm_alter_journey_v740_lookup
on public.rr_upm_alter_journey_v740(canonical_lot_id,stage,colour_code,size_code);

create table if not exists public.rr_upm_alter_events_v740(
  id uuid primary key default gen_random_uuid(),
  journey_id uuid not null references public.rr_upm_alter_journey_v740(id),
  event_type text not null,
  qty numeric(14,3) not null check(qty>0),
  from_stage text,
  to_stage text,
  actor_id uuid default auth.uid(),
  actor_name text,
  responsible_id uuid,
  responsible_name text,
  responsible_role_code text,
  remarks text,
  created_at timestamptz not null default now()
);

create table if not exists public.rr_upm_whatsapp_outbox_v740(
  id uuid primary key default gen_random_uuid(),
  journey_id uuid references public.rr_upm_alter_journey_v740(id),
  recipient_id uuid,
  recipient_name text,
  recipient_phone text,
  message_text text not null,
  evidence_urls jsonb not null default '[]'::jsonb,
  whatsapp_url text,
  status text not null default 'READY',
  created_at timestamptz not null default now(),
  opened_at timestamptz
);

create table if not exists public.rr_upm_untraceable_request_v740(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  previous_lm_id uuid,
  previous_lm_name text,
  manager_id uuid default auth.uid(),
  manager_name text not null,
  manager_remark text not null,
  journey_rows jsonb not null,
  total_qty numeric(14,3) not null check(total_qty>0),
  status text not null default 'OWNER_PENDING' check(status in('OWNER_PENDING','APPROVED_COMPANY_LOSS','DENIED_MANAGER_DEBIT','RETURNED_RECHECK')),
  owner_id uuid,
  owner_name text,
  owner_remark text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.rr_upm_lot_identity_lock_v740 enable row level security;
alter table public.rr_upm_route_lock_v740 enable row level security;
alter table public.rr_upm_lot_role_enrolment_v740 enable row level security;
alter table public.rr_upm_lot_role_transfer_v740 enable row level security;
alter table public.rr_upm_alter_journey_v740 enable row level security;
alter table public.rr_upm_alter_events_v740 enable row level security;
alter table public.rr_upm_whatsapp_outbox_v740 enable row level security;
alter table public.rr_upm_untraceable_request_v740 enable row level security;

do $$ declare t text; begin
 foreach t in array array['rr_upm_lot_identity_lock_v740','rr_upm_route_lock_v740','rr_upm_lot_role_enrolment_v740','rr_upm_lot_role_transfer_v740','rr_upm_alter_journey_v740','rr_upm_alter_events_v740','rr_upm_whatsapp_outbox_v740','rr_upm_untraceable_request_v740'] loop
  execute format('drop policy if exists %I on public.%I','read_'||t,t);
  execute format('create policy %I on public.%I for select to authenticated using(true)','read_'||t,t);
 end loop;
end $$;

grant select on public.rr_upm_lot_identity_lock_v740,public.rr_upm_route_lock_v740,
 public.rr_upm_lot_role_enrolment_v740,public.rr_upm_lot_role_transfer_v740,
 public.rr_upm_alter_journey_v740,public.rr_upm_alter_events_v740,
 public.rr_upm_whatsapp_outbox_v740,public.rr_upm_untraceable_request_v740 to authenticated;

create or replace function public.rr_upm_norm_role_v740(p text) returns text
language sql immutable as $$
 select case
  when regexp_replace(upper(coalesce(p,'')),'[^A-Z0-9]+','','g') in('LINEMAN','LINEMANAGER') then 'LINE_MAN'
  when regexp_replace(upper(coalesce(p,'')),'[^A-Z0-9]+','','g') in('CUTTINGMASTER','MASTER') then 'CUTTING_MASTER'
  when regexp_replace(upper(coalesce(p,'')),'[^A-Z0-9]+','','g') in('OWNER') then 'OWNER'
  when regexp_replace(upper(coalesce(p,'')),'[^A-Z0-9]+','','g') in('ADMIN') then 'ADMIN'
  when regexp_replace(upper(coalesce(p,'')),'[^A-Z0-9]+','','g') in('MANAGER','DEPARTMENTHEAD','FABRICATIONMANAGER') then 'MANAGER'
  else 'WORKER' end;
$$;

create or replace function public.rr_upm_phone_v740(p jsonb) returns text
language sql immutable as $$
 select regexp_replace(coalesce(nullif(p->>'mobile',''),nullif(p->>'whatsapp_no',''),nullif(p->>'phone',''),nullif(p->>'mobile_no','')),'[^0-9]','','g');
$$;

create or replace function public.rr_upm_is_management_v740() returns boolean
language sql stable security definer set search_path=public as $$
 select public.rr_upm_norm_role_v740(public.rr_up_user_context_v2()->>'user_category') in('OWNER','ADMIN','MANAGER');
$$;

create or replace function public.rr_upm_worker_candidates_v740(p_role_code text,p_department_code text default null)
returns table(worker_id uuid,worker_name text,worker_code text,role_code text,department_code text,mobile text)
language sql stable security definer set search_path=public as $$
 with dep as(
   select upper(trim(p_department_code)) code,
          upper(coalesce(parent_department_code,'')) parent
   from public.rr_upm_departments where upper(department_code)=upper(trim(p_department_code)) limit 1
 ), w as(
   select x.worker_id,x.worker_name,x.worker_code,x.role_code,x.department_code,
          public.rr_upm_phone_v740(to_jsonb(x)) mobile,
          public.rr_upm_norm_role_v740(x.role_code) norm_role,
          upper(coalesce(x.department_code,'')) dep_code
   from public.rr_worker_directory_unified_v1 x
   where coalesce(x.is_active,true) and upper(coalesce(x.access_status,'ACTIVE'))='ACTIVE'
 )
 select w.worker_id,w.worker_name,w.worker_code,w.role_code,w.department_code,w.mobile
 from w left join dep on true
 where w.norm_role=public.rr_upm_norm_role_v740(p_role_code)
   and (
     public.rr_upm_norm_role_v740(p_role_code)='CUTTING_MASTER'
     or p_department_code is null
     or w.dep_code=dep.code
     or (dep.parent<>'' and w.dep_code=dep.parent)
     or (public.rr_upm_norm_role_v740(p_role_code)='LINE_MAN' and w.dep_code='FABRICATION')
   )
 order by case when w.dep_code=dep.code then 0 when w.dep_code=dep.parent then 1 when w.dep_code='FABRICATION' then 2 else 3 end,w.worker_name;
$$;

grant execute on function public.rr_upm_worker_candidates_v740(text,text) to authenticated;

create or replace function public.rr_upm_resolve_identity_v740(p_canonical_lot_id text,p_force boolean default false,p_reason text default null)
returns public.rr_upm_lot_identity_lock_v740
language plpgsql security definer set search_path=public as $$
declare r public.rr_upm_lot_identity_lock_v740; reg record; cut record; cb text; divcode text; frames text; actor_role text;
begin
 select * into r from public.rr_upm_lot_identity_lock_v740 where canonical_lot_id=p_canonical_lot_id;
 if found and not p_force then return r; end if;
 if p_force then
  actor_role:=public.rr_upm_norm_role_v740(public.rr_up_user_context_v2()->>'user_category');
  if actor_role not in('OWNER','ADMIN') then raise exception 'Only Owner/Admin can re-sync locked identity.'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Re-sync reason is required.'; end if;
 end if;
 select canonical_lot_id,lot_no,source_id::uuid source_id,item_name,art_no,metadata into reg
 from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 if reg.source_id is null then raise exception 'Cutting source missing for Lot identity.'; end if;
 select c.id,c.lot_no,c.cb_purchase_id,c.cb_unit_id,c.art_no,c.print_no into cut
 from public.rr_cutting_lots_v3 c where c.id=reg.source_id limit 1;
 if cut.id is null then raise exception 'Released Cutting Lot mapping missing.'; end if;
 select fp.cb_no into cb from public.rr_fabric_purchases fp where fp.id=cut.cb_purchase_id;
 select coalesce(u.cb_code,concat('D',u.division_index)) into divcode from public.rr_cb_units u where u.id=cut.cb_unit_id;
 select string_agg(f.frame_no,', ' order by f.colour_order,f.frame_no) into frames
 from public.rr_print_master p join public.rr_print_frames f on f.print_id=p.id
 where upper(p.print_no)=upper(coalesce(cut.print_no,reg.metadata->>'print_no')) and upper(coalesce(f.frame_status,'ACTIVE'))<>'RETIRED';
 if nullif(trim(coalesce(cb,'')),'') is null then raise exception 'CB mapping missing in released Cutting Lot.'; end if;
 if nullif(trim(coalesce(cut.art_no,reg.art_no,'')),'') is null then raise exception 'Art No mapping missing in released Cutting Lot.'; end if;
 if p_force then delete from public.rr_upm_lot_identity_lock_v740 where canonical_lot_id=p_canonical_lot_id; end if;
 insert into public.rr_upm_lot_identity_lock_v740(canonical_lot_id,cutting_lot_id,lot_no,cb_no,division_code,art_no,print_no,frame_no,item_name)
 values(p_canonical_lot_id,cut.id,cut.lot_no,cb,divcode,coalesce(cut.art_no,reg.art_no),coalesce(cut.print_no,reg.metadata->>'print_no'),frames,reg.item_name)
 on conflict(canonical_lot_id) do nothing returning * into r;
 if r.canonical_lot_id is null then select * into r from public.rr_upm_lot_identity_lock_v740 where canonical_lot_id=p_canonical_lot_id; end if;
 return r;
end;$$;
grant execute on function public.rr_upm_resolve_identity_v740(text,boolean,text) to authenticated;

create or replace function public.rr_upm_enrol_lm_v740(p_canonical_lot_id text,p_department_code text,p_line_man_id uuid default null,p_reason text default 'First Alter enrollment')
returns public.rr_upm_lot_role_enrolment_v740
language plpgsql security definer set search_path=public as $$
declare e public.rr_upm_lot_role_enrolment_v740;c record;n int;ident public.rr_upm_lot_identity_lock_v740;
begin
 select * into e from public.rr_upm_lot_role_enrolment_v740 where canonical_lot_id=p_canonical_lot_id and role_code='LINE_MAN' and status='ACTIVE';
 if found then return e; end if;
 ident:=public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null);
 if p_line_man_id is null then
  select count(*) into n from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code);
  if n=0 then raise exception 'No active LINE MAN mapping found in Worker Directory / Fabrication.'; end if;
  if n>1 then raise exception 'Multiple Line Men mapped. Select one for this Lot.'; end if;
  select * into c from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code) limit 1;
 else
  select * into c from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code) where worker_id=p_line_man_id limit 1;
  if c.worker_id is null then raise exception 'Selected Line Man is not active/eligible.'; end if;
 end if;
 insert into public.rr_upm_lot_role_enrolment_v740(canonical_lot_id,lot_no,role_code,person_id,person_name_snapshot,worker_code_snapshot,department_code_snapshot,phone_snapshot,reason)
 values(p_canonical_lot_id,ident.lot_no,'LINE_MAN',c.worker_id,c.worker_name,c.worker_code,c.department_code,c.mobile,p_reason) returning * into e;
 return e;
end;$$;
grant execute on function public.rr_upm_enrol_lm_v740(text,text,uuid,text) to authenticated;

create or replace function public.rr_upm_transfer_lm_v740(p_canonical_lot_id text,p_department_code text,p_new_line_man_id uuid,p_mode text,p_reason text,p_physical_handover boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare olde public.rr_upm_lot_role_enrolment_v740;newe public.rr_upm_lot_role_enrolment_v740;c record;ctx jsonb;actor uuid;role text;openq numeric;tid uuid;
begin
 ctx:=public.rr_up_user_context_v2();actor:=auth.uid();role:=public.rr_upm_norm_role_v740(ctx->>'user_category');
 select * into olde from public.rr_upm_lot_role_enrolment_v740 where canonical_lot_id=p_canonical_lot_id and role_code='LINE_MAN' and status='ACTIVE' for update;
 if olde.id is null then raise exception 'Current Lot Line Man enrollment missing.'; end if;
 if role not in('OWNER','ADMIN','MANAGER') and olde.person_id<>actor then raise exception 'Only enrolled Line Man or authorized Manager/Admin can transfer.'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Transfer reason is required.'; end if;
 select * into c from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code) where worker_id=p_new_line_man_id limit 1;
 if c.worker_id is null then raise exception 'New Line Man is not active/eligible.'; end if;
 if c.worker_id=olde.person_id then raise exception 'New Line Man is same as current Line Man.'; end if;
 select coalesce(sum(open_qty),0) into openq from public.rr_upm_alter_journey_v740 where canonical_lot_id=p_canonical_lot_id and stage not like 'CLOSED%';
 update public.rr_upm_lot_role_enrolment_v740 set status='TRANSFERRED',ended_at=now(),ended_by=actor,reason=p_reason where id=olde.id;
 insert into public.rr_upm_lot_role_enrolment_v740(canonical_lot_id,lot_no,role_code,person_id,person_name_snapshot,worker_code_snapshot,department_code_snapshot,phone_snapshot,reason)
 values(olde.canonical_lot_id,olde.lot_no,'LINE_MAN',c.worker_id,c.worker_name,c.worker_code,c.department_code,c.mobile,p_reason) returning * into newe;
 update public.rr_upm_alter_journey_v740 set enrolled_lm_id=c.worker_id,enrolled_lm_name=c.worker_name,enrolled_lm_worker_code=c.worker_code,
  responsible_id=case when responsible_role_code='LINE_MAN' then c.worker_id else responsible_id end,
  responsible_name=case when responsible_role_code='LINE_MAN' then c.worker_name else responsible_name end,
  responsible_worker_code=case when responsible_role_code='LINE_MAN' then c.worker_code else responsible_worker_code end,
  responsible_department_code=case when responsible_role_code='LINE_MAN' then c.department_code else responsible_department_code end,updated_at=now()
 where canonical_lot_id=p_canonical_lot_id and stage not like 'CLOSED%';
 insert into public.rr_upm_lot_role_transfer_v740(canonical_lot_id,role_code,from_enrolment_id,to_enrolment_id,transfer_mode,traceable_qty,physical_handover_confirmed,reason)
 values(p_canonical_lot_id,'LINE_MAN',olde.id,newe.id,upper(p_mode),openq,p_physical_handover,p_reason) returning id into tid;
 return jsonb_build_object('ok',true,'transfer_id',tid,'new_line_man',to_jsonb(newe));
end;$$;
grant execute on function public.rr_upm_transfer_lm_v740(text,text,uuid,text,text,boolean) to authenticated;

create or replace function public.rr_upm_whatsapp_url_v740(p_phone text,p_message text) returns text
language sql immutable as $$
 select case when nullif(p_phone,'') is null then null else 'https://wa.me/'||case when length(p_phone)=10 then '91'||p_phone else p_phone end||'?text='||replace(replace(replace(replace(replace(p_message,'%','%25'),' ','%20'),E'\n','%0A'),'&','%26'),'#','%23') end;
$$;

create or replace function public.rr_upm_active_alter_summary_v740(p_canonical_lot_id text)
returns table(journey_id uuid,stage text,stage_label text,colour_code text,colour_name text,size_code text,qty numeric,responsible_name text,responsible_worker_code text,responsible_role_short text,responsible_department_code text,evidence_urls jsonb,updated_at timestamptz)
language sql stable security definer set search_path=public as $$
 select j.id,j.stage,
 case j.stage when 'LM_ALTER_PENDING' then 'ALTER' when 'CM_REMAKE_READY' then 'REMAKE READY' when 'LM_DELIVERY_PENDING' then 'DELIVERY' when 'KARIGAR_REMAKE_PENDING' then 'REMAKE' when 'UNTRACEABLE_APPROVAL' then 'OWNER APPROVAL' else j.stage end,
 j.colour_code,j.colour_name,j.size_code,j.open_qty,j.responsible_name,j.responsible_worker_code,
 case j.responsible_role_code when 'LINE_MAN' then 'LM' when 'CUTTING_MASTER' then 'CM' when 'WORKER' then 'KR' when 'OWNER' then 'OWNER' else j.responsible_role_code end,
 j.responsible_department_code,j.evidence_urls,j.updated_at
 from public.rr_upm_alter_journey_v740 j where j.canonical_lot_id=p_canonical_lot_id and j.stage not like 'CLOSED%' and j.open_qty>0 order by j.updated_at;
$$;
grant execute on function public.rr_upm_active_alter_summary_v740(text) to authenticated;

create or replace function public.rr_upm_mapping_context_v740(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare ident public.rr_upm_lot_identity_lock_v740;enrol record;lm jsonb;cm jsonb;run jsonb;route text;
begin
 ident:=public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null);
 select to_jsonb(e) into enrol from public.rr_upm_lot_role_enrolment_v740 e where e.canonical_lot_id=p_canonical_lot_id and e.role_code='LINE_MAN' and e.status='ACTIVE';
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into lm from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code)x;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into cm from public.rr_upm_worker_candidates_v740('CUTTING_MASTER',null)x;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.department_name),'[]'::jsonb) into run from(
  select distinct dep.department_code,dep.department_name
  from public.rr_upm_departments dep
  where dep.is_active and (
   exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(dep.department_code) and a.status in('ASSIGNED','IN_PROGRESS'))
   or exists(select 1 from public.rr_upm_colour_state c where c.canonical_lot_id=p_canonical_lot_id and upper(c.current_department_code)=upper(dep.department_code))
  )
 )d;
 select to_department_code into route from public.rr_upm_route_lock_v740 where canonical_lot_id=p_canonical_lot_id and upper(from_department_code)=upper(p_department_code);
 return jsonb_build_object('identity',to_jsonb(ident),'line_man_enrolment',enrol,'line_man_candidates',lm,'cutting_master_candidates',cm,'running_departments',run,'route_locked_to',route);
end;$$;
grant execute on function public.rr_upm_mapping_context_v740(text,text) to authenticated;

create or replace function public.rr_upm_alter_stage_v740(p_stage text,p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_urls jsonb default '[]'::jsonb,p_physical_confirmed boolean default false,p_line_man_id uuid default null,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;ident public.rr_upm_lot_identity_lock_v740;enrol public.rr_upm_lot_role_enrolment_v740;cm record;ass public.rr_upm_work_assignments_v8%rowtype;kar record;j public.rr_upm_alter_journey_v740%rowtype;
 q numeric;actor_ctx jsonb;actor_role text;actor_name text;froms text;tos text;resp_id uuid;resp_name text;resp_code text;resp_role text;resp_dep text;phone text;msg text;wa text;saved int:=0;last_out uuid;
begin
 actor_ctx:=public.rr_up_user_context_v2();actor_role:=public.rr_upm_norm_role_v740(actor_ctx->>'user_category');actor_name:=coalesce(actor_ctx->>'display_name',auth.uid()::text);
 ident:=public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null);
 enrol:=public.rr_upm_enrol_lm_v740(p_canonical_lot_id,p_department_code,p_line_man_id,'Alter journey enrollment');
 select * into cm from public.rr_upm_worker_candidates_v740('CUTTING_MASTER',null) limit 1;
 if cm.worker_id is null then raise exception 'Mapped Cutting Master not found in Worker Directory.'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'No selected Alter rows.'; end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  q:=coalesce((r->>'qty')::numeric,0);if q<=0 then continue;end if;
  select * into ass from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in('ASSIGNED','IN_PROGRESS') and ((nullif(r->>'colour_id','') is not null and a.colour_id=(r->>'colour_id')::uuid) or upper(a.colour_code)=upper(r->>'colour_code')) order by a.assigned_at desc limit 1;
  if ass.id is null then raise exception 'Active assigned Karigar missing for %.',r->>'colour_code';end if;
  select worker_id,worker_name,worker_code,department_code,public.rr_upm_phone_v740(to_jsonb(w)) mobile into kar from public.rr_worker_directory_unified_v1 w where w.worker_id=ass.worker_id and coalesce(w.is_active,true) limit 1;
  if upper(p_stage)='ALTER_FILL' then
   if actor_role not in('OWNER','ADMIN','MANAGER') and auth.uid()<>enrol.person_id then raise exception 'Only enrolled Lot Line Man can Alter Fill.';end if;
   if not p_physical_confirmed or jsonb_array_length(coalesce(p_evidence_urls,'[]'::jsonb))<1 or jsonb_array_length(coalesce(p_evidence_urls,'[]'::jsonb))>3 then raise exception '1–3 live camera images and physical piece confirmation required.';end if;
   insert into public.rr_upm_alter_journey_v740(canonical_lot_id,lot_no,origin_department_code,colour_id,colour_code,colour_name,size_code,open_qty,stage,enrolled_lm_id,enrolled_lm_name,enrolled_lm_worker_code,cutting_master_id,cutting_master_name,cutting_master_worker_code,karigar_id,karigar_name,karigar_worker_code,responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,evidence_urls,physical_piece_confirmed,created_by_name)
   values(p_canonical_lot_id,ident.lot_no,upper(p_department_code),nullif(r->>'colour_id','')::uuid,upper(r->>'colour_code'),coalesce(r->>'colour_name',r->>'colour_code'),upper(r->>'size_code'),q,'LM_ALTER_PENDING',enrol.person_id,enrol.person_name_snapshot,enrol.worker_code_snapshot,cm.worker_id,cm.worker_name,cm.worker_code,kar.worker_id,kar.worker_name,kar.worker_code,enrol.person_id,enrol.person_name_snapshot,enrol.worker_code_snapshot,'LINE_MAN',enrol.department_code_snapshot,p_evidence_urls,true,actor_name) returning * into j;
   froms:=null;tos:='LM_ALTER_PENDING';resp_id:=enrol.person_id;resp_name:=enrol.person_name_snapshot;resp_code:=enrol.worker_code_snapshot;resp_role:='LINE_MAN';resp_dep:=enrol.department_code_snapshot;phone:=cm.mobile;
   msg:=format('Namaste %s ji,%s%s Line Man ne live evidence aur physical piece ke saath Alter Fill kiya hai.%sLot: %s | Colour: %s | Size: %s | Qty: %s PCS%sKripya remake kaat kar REMAKE ISSUE karein.%sREDZED Production',cm.worker_name,E'\n',enrol.person_name_snapshot,E'\n',ident.lot_no,j.colour_name,j.size_code,q,E'\n',E'\n');
  else
   select * into j from public.rr_upm_alter_journey_v740 where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(r->>'colour_code') and upper(size_code)=upper(r->>'size_code') and stage not like 'CLOSED%' order by updated_at desc limit 1 for update;
   if j.id is null then raise exception 'Active Alter journey missing for % / %.',r->>'colour_code',r->>'size_code';end if;
   if q>j.open_qty then raise exception 'Qty % exceeds current open Qty %.',q,j.open_qty;end if;
   froms:=j.stage;
   if upper(p_stage)='REMAKE_ISSUE' then
    if actor_role not in('OWNER','ADMIN') and auth.uid()<>j.cutting_master_id then raise exception 'Only mapped Cutting Master can Remake Issue.';end if;
    if j.stage<>'LM_ALTER_PENDING' then raise exception 'Current stage is not Alter Pending with Line Man.';end if;
    tos:='CM_REMAKE_READY';resp_id:=j.cutting_master_id;resp_name:=j.cutting_master_name;resp_code:=j.cutting_master_worker_code;resp_role:='CUTTING_MASTER';resp_dep:='CUTTING';phone:=enrol.phone_snapshot;
    msg:=format('Namaste %s ji,%s%s Cutting Master ne Lot %s | %s | Size %s | Qty %s PCS remake issue kar diya hai.%sKripya Master se remake receive karke Karigar ko deliver karein.%sREDZED Production',enrol.person_name_snapshot,E'\n',j.cutting_master_name,ident.lot_no,j.colour_name,j.size_code,q,E'\n',E'\n');
   elsif upper(p_stage)='RECEIVE_FROM_MASTER' then
    if actor_role not in('OWNER','ADMIN','MANAGER') and auth.uid()<>enrol.person_id then raise exception 'Only enrolled Lot Line Man can receive from Master.';end if;
    if j.stage<>'CM_REMAKE_READY' then raise exception 'Current stage is not Master Remake Ready.';end if;
    tos:='LM_DELIVERY_PENDING';resp_id:=enrol.person_id;resp_name:=enrol.person_name_snapshot;resp_code:=enrol.worker_code_snapshot;resp_role:='LINE_MAN';resp_dep:=enrol.department_code_snapshot;phone:=enrol.phone_snapshot;
    msg:=format('%s ji,%sLot %s | %s | Size %s | Qty %s PCS Master se receive ho gaya.%sAb mapped Karigar %s ko deliver karein.%sREDZED Production',enrol.person_name_snapshot,E'\n',ident.lot_no,j.colour_name,j.size_code,q,E'\n',j.karigar_name,E'\n');
   elsif upper(p_stage)='DELIVER_TO_KARIGAR' then
    if actor_role not in('OWNER','ADMIN','MANAGER') and auth.uid()<>enrol.person_id then raise exception 'Only enrolled Lot Line Man can deliver to Karigar.';end if;
    if j.stage<>'LM_DELIVERY_PENDING' then raise exception 'Current stage is not Line Man Delivery Pending.';end if;
    tos:='KARIGAR_REMAKE_PENDING';resp_id:=j.karigar_id;resp_name:=j.karigar_name;resp_code:=j.karigar_worker_code;resp_role:='WORKER';resp_dep:=j.origin_department_code;phone:=kar.mobile;
    msg:=format('Namaste %s ji,%s%s Line Man ne Lot %s | %s | Size %s | Qty %s PCS remake aapko deliver kiya hai.%sAb is Qty ki responsibility aapki hai. Kaam complete karke physical piece Line Man ko dein.%sREDZED Production',j.karigar_name,E'\n',enrol.person_name_snapshot,ident.lot_no,j.colour_name,j.size_code,q,E'\n',E'\n');
   elsif upper(p_stage)='RECEIVE_FROM_KARIGAR' then
    if actor_role not in('OWNER','ADMIN','MANAGER') and auth.uid()<>enrol.person_id then raise exception 'Only enrolled Lot Line Man can receive from Karigar.';end if;
    if j.stage<>'KARIGAR_REMAKE_PENDING' then raise exception 'Current stage is not Karigar Remake Pending.';end if;
    tos:='CLOSED_GOOD';resp_id:=null;resp_name:=null;resp_code:=null;resp_role:='NONE';resp_dep:=null;phone:=null;
    msg:=format('Alter journey closed.%sLot %s | %s | Size %s | Qty %s PCS%sReceived by %s Line Man. Qty returned to Good.%sREDZED Production',E'\n',ident.lot_no,j.colour_name,j.size_code,q,E'\n',enrol.person_name_snapshot,E'\n');
   else raise exception 'Invalid Alter stage %.',p_stage;end if;
   if q=j.open_qty then
    update public.rr_upm_alter_journey_v740 set stage=tos,responsible_id=resp_id,responsible_name=resp_name,responsible_worker_code=resp_code,responsible_role_code=resp_role,responsible_department_code=resp_dep,updated_at=now(),closed_at=case when tos like 'CLOSED%' then now() else null end,close_reason=case when tos='CLOSED_GOOD' then 'Line Man final receive' else close_reason end where id=j.id returning * into j;
   else
    update public.rr_upm_alter_journey_v740 set open_qty=open_qty-q,updated_at=now() where id=j.id;
    insert into public.rr_upm_alter_journey_v740(canonical_lot_id,lot_no,origin_department_code,colour_id,colour_code,colour_name,size_code,open_qty,stage,enrolled_lm_id,enrolled_lm_name,enrolled_lm_worker_code,cutting_master_id,cutting_master_name,cutting_master_worker_code,karigar_id,karigar_name,karigar_worker_code,responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,evidence_urls,physical_piece_confirmed,created_by_name,closed_at,close_reason)
    select canonical_lot_id,lot_no,origin_department_code,colour_id,colour_code,colour_name,size_code,q,tos,enrolled_lm_id,enrolled_lm_name,enrolled_lm_worker_code,cutting_master_id,cutting_master_name,cutting_master_worker_code,karigar_id,karigar_name,karigar_worker_code,resp_id,resp_name,resp_code,resp_role,resp_dep,evidence_urls,physical_piece_confirmed,actor_name,case when tos like 'CLOSED%' then now() else null end,case when tos='CLOSED_GOOD' then 'Line Man final receive' else null end from public.rr_upm_alter_journey_v740 where id=j.id returning * into j;
   end if;
  end if;
  insert into public.rr_upm_alter_events_v740(journey_id,event_type,qty,from_stage,to_stage,actor_name,responsible_id,responsible_name,responsible_role_code,remarks)
  values(j.id,upper(p_stage),q,froms,tos,actor_name,resp_id,resp_name,resp_role,p_remarks);
  wa:=public.rr_upm_whatsapp_url_v740(phone,msg);
  insert into public.rr_upm_whatsapp_outbox_v740(journey_id,recipient_id,recipient_name,recipient_phone,message_text,evidence_urls,whatsapp_url)
  values(j.id,resp_id,resp_name,phone,msg,coalesce(p_evidence_urls,j.evidence_urls),wa) returning id into last_out;
  saved:=saved+1;
 end loop;
 return jsonb_build_object('ok',true,'rows_saved',saved,'whatsapp_url',wa,'outbox_id',last_out,'message',msg);
end;$$;
grant execute on function public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text) to authenticated;

create or replace function public.rr_upm_request_untraceable_v740(p_canonical_lot_id text,p_journey_ids uuid[],p_manager_remark text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ctx jsonb;role text;ident public.rr_upm_lot_identity_lock_v740;rows jsonb;qty numeric;prev record;req uuid;owner record;msg text;wa text;
begin
 ctx:=public.rr_up_user_context_v2();role:=public.rr_upm_norm_role_v740(ctx->>'user_category');
 if role not in('OWNER','ADMIN','MANAGER') then raise exception 'Only Manager/Admin/Owner can request untraceable damage approval.';end if;
 if nullif(trim(p_manager_remark),'') is null then raise exception 'Manager investigation remark is required.';end if;
 ident:=public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null);
 select coalesce(jsonb_agg(jsonb_build_object('journey_id',id,'colour',colour_name,'size',size_code,'qty',open_qty,'stage',stage,'responsible',responsible_name)),'[]'::jsonb),coalesce(sum(open_qty),0) into rows,qty from public.rr_upm_alter_journey_v740 where canonical_lot_id=p_canonical_lot_id and id=any(p_journey_ids) and stage not like 'CLOSED%';
 if qty<=0 then raise exception 'No open Alter quantity selected.';end if;
 select * into prev from public.rr_upm_lot_role_enrolment_v740 where canonical_lot_id=p_canonical_lot_id and role_code='LINE_MAN' order by enrolled_at desc limit 1;
 insert into public.rr_upm_untraceable_request_v740(canonical_lot_id,lot_no,previous_lm_id,previous_lm_name,manager_name,manager_remark,journey_rows,total_qty)
 values(p_canonical_lot_id,ident.lot_no,prev.person_id,prev.person_name_snapshot,coalesce(ctx->>'display_name',auth.uid()::text),p_manager_remark,rows,qty) returning id into req;
 update public.rr_upm_alter_journey_v740 set stage='UNTRACEABLE_APPROVAL',responsible_role_code='OWNER',responsible_name='OWNER APPROVAL',responsible_id=null,updated_at=now() where id=any(p_journey_ids);
 select * into owner from public.rr_upm_worker_candidates_v740('OWNER',null) limit 1;
 msg:=format('Namaste Sir,%sUntraceable Alter Damage Approval Required%sPrevious Line Man: %s%sLot: %s | Total Qty: %s PCS%sManager Remark: %s%sCompany Loss approve karein, deny karein, ya recheck ke liye return karein.%sREDZED Production',E'\n',E'\n',coalesce(prev.person_name_snapshot,'—'),E'\n',ident.lot_no,qty,E'\n',p_manager_remark,E'\n',E'\n');
 wa:=public.rr_upm_whatsapp_url_v740(owner.mobile,msg);
 insert into public.rr_upm_whatsapp_outbox_v740(recipient_id,recipient_name,recipient_phone,message_text,whatsapp_url) values(owner.worker_id,owner.worker_name,owner.mobile,msg,wa);
 return jsonb_build_object('ok',true,'request_id',req,'whatsapp_url',wa,'qty',qty);
end;$$;
grant execute on function public.rr_upm_request_untraceable_v740(text,uuid[],text) to authenticated;

create or replace function public.rr_upm_decide_untraceable_v740(p_request_id uuid,p_decision text,p_owner_remark text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ctx jsonb;role text;r public.rr_upm_untraceable_request_v740%rowtype;j jsonb;st text;
begin
 ctx:=public.rr_up_user_context_v2();role:=public.rr_upm_norm_role_v740(ctx->>'user_category');
 if role not in('OWNER','ADMIN') then raise exception 'Only Owner/Admin can decide untraceable request.';end if;
 select * into r from public.rr_upm_untraceable_request_v740 where id=p_request_id for update;
 if r.id is null or r.status<>'OWNER_PENDING' then raise exception 'Pending approval request not found.';end if;
 st:=case upper(p_decision) when 'APPROVE' then 'APPROVED_COMPANY_LOSS' when 'DENY' then 'DENIED_MANAGER_DEBIT' when 'RECHECK' then 'RETURNED_RECHECK' else null end;
 if st is null then raise exception 'Decision must be APPROVE, DENY or RECHECK.';end if;
 update public.rr_upm_untraceable_request_v740 set status=st,owner_id=auth.uid(),owner_name=coalesce(ctx->>'display_name',auth.uid()::text),owner_remark=p_owner_remark,decided_at=now() where id=r.id;
 for j in select value from jsonb_array_elements(r.journey_rows) loop
  if st='APPROVED_COMPANY_LOSS' then update public.rr_upm_alter_journey_v740 set stage='CLOSED_DAMAGE',responsible_role_code='NONE',responsible_name=null,responsible_id=null,closed_at=now(),close_reason='Owner approved company loss',updated_at=now() where id=(j->>'journey_id')::uuid;
  elsif st='DENIED_MANAGER_DEBIT' then update public.rr_upm_alter_journey_v740 set stage='CLOSED_DAMAGE',responsible_role_code='MANAGER',responsible_name=r.manager_name,closed_at=now(),close_reason='Owner denied; Manager debit claim',updated_at=now() where id=(j->>'journey_id')::uuid;
  else update public.rr_upm_alter_journey_v740 set stage='LM_ALTER_PENDING',responsible_role_code='LINE_MAN',responsible_name=r.previous_lm_name,responsible_id=r.previous_lm_id,updated_at=now() where id=(j->>'journey_id')::uuid;
  end if;
 end loop;
 return jsonb_build_object('ok',true,'status',st);
end;$$;
grant execute on function public.rr_upm_decide_untraceable_v740(uuid,text,text) to authenticated;

create or replace function public.rr_upm_universal_form_v740(
  p_canonical_lot_id text,
  p_department_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  base jsonb;
  ident public.rr_upm_lot_identity_lock_v740;
  mapctx jsonb;
  active jsonb := '[]'::jsonb;
  rows_out jsonb := '[]'::jsonb;
  sumj jsonb;
  r jsonb;
  enriched jsonb;
  v_main numeric := 0;
  v_damage numeric := 0;
  v_alter numeric := 0;
  v_lm numeric := 0;
  v_worker numeric := 0;
  v_good numeric := 0;
  s_main numeric := 0;
  s_good numeric := 0;
  s_alter numeric := 0;
  s_lm numeric := 0;
  s_worker numeric := 0;
  s_damage numeric := 0;
begin
  base := public.rr_upm_universal_form_v733(
    p_canonical_lot_id,
    p_department_code
  );

  ident := public.rr_upm_resolve_identity_v740(
    p_canonical_lot_id,
    false,
    null
  );

  mapctx := public.rr_upm_mapping_context_v740(
    p_canonical_lot_id,
    p_department_code
  );

  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
    into active
  from public.rr_upm_active_alter_summary_v740(p_canonical_lot_id) as x;

  for r in
    select value
    from jsonb_array_elements(coalesce(base->'rows', '[]'::jsonb))
  loop
    v_main := coalesce(nullif(r->>'cutting_qty','')::numeric, 0);
    v_damage := coalesce(nullif(r->>'damage_qty','')::numeric, 0);

    select coalesce(sum(j.open_qty), 0)
      into v_alter
    from public.rr_upm_alter_journey_v740 j
    where j.canonical_lot_id = p_canonical_lot_id
      and upper(j.colour_code) = upper(r->>'colour_code')
      and upper(j.size_code) = upper(r->>'size_code')
      and j.stage = 'LM_ALTER_PENDING';

    select coalesce(sum(j.open_qty), 0)
      into v_lm
    from public.rr_upm_alter_journey_v740 j
    where j.canonical_lot_id = p_canonical_lot_id
      and upper(j.colour_code) = upper(r->>'colour_code')
      and upper(j.size_code) = upper(r->>'size_code')
      and j.stage in ('CM_REMAKE_READY', 'LM_DELIVERY_PENDING');

    select coalesce(sum(j.open_qty), 0)
      into v_worker
    from public.rr_upm_alter_journey_v740 j
    where j.canonical_lot_id = p_canonical_lot_id
      and upper(j.colour_code) = upper(r->>'colour_code')
      and upper(j.size_code) = upper(r->>'size_code')
      and j.stage = 'KARIGAR_REMAKE_PENDING';

    v_good := greatest(
      v_main - v_damage - v_alter - v_lm - v_worker,
      0
    );

    enriched :=
      (r
        - 'good_qty'
        - 'alter_open_qty'
        - 'remake_open_qty'
        - 'line_man_pending_qty'
        - 'worker_remake_pending_qty')
      || jsonb_build_object(
        'main_qty', v_main,
        'good_qty', v_good,
        'alter_open_qty', v_alter,
        'line_man_pending_qty', v_lm,
        'worker_remake_pending_qty', v_worker
      );

    rows_out := rows_out || jsonb_build_array(enriched);

    s_main := s_main + v_main;
    s_good := s_good + v_good;
    s_alter := s_alter + v_alter;
    s_lm := s_lm + v_lm;
    s_worker := s_worker + v_worker;
    s_damage := s_damage + v_damage;
  end loop;

  sumj := jsonb_build_object(
    'main', s_main,
    'good', s_good,
    'alter', s_alter,
    'line_man_pending', s_lm,
    'remake', s_worker,
    'damage', s_damage
  );

  base := jsonb_set(
    base,
    '{lot}',
    coalesce(base->'lot', '{}'::jsonb) || to_jsonb(ident),
    true
  );

  base := jsonb_set(base, '{rows}', rows_out, true);
  base := jsonb_set(base, '{summary}', sumj, true);

  base := base || jsonb_build_object(
    'active_alter_summary', active,
    'mapping_context', mapctx,
    'running_departments', coalesce(mapctx->'running_departments', '[]'::jsonb),
    'route_locked_to', mapctx->>'route_locked_to',
    'versions', jsonb_build_object(
      'universal_form', 'V740',
      'identity', 'IMMUTABLE_CUTTING_LOCK',
      'alter', 'LOT_LM_ENROLMENT',
      'routing', 'FIRST_SUBMIT_ROUTE_LOCK'
    )
  );

  return base;
end;
$$;

grant execute on function public.rr_upm_universal_form_v740(text,text)
to authenticated;

create or replace function public.rr_upm_submit_colours_v740(p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_next_department_code text default null,p_rate numeric default 0,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare locked text;dep record;v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_colour_id uuid;v_colour text;v_assign public.rr_upm_work_assignments_v8%rowtype;v_cut record;v_bal record;v_actions jsonb;v_handoff numeric;v_submitted numeric:=0;v_colours int:=0;
begin
 select to_department_code into locked from public.rr_upm_route_lock_v740 where canonical_lot_id=p_canonical_lot_id and upper(from_department_code)=upper(p_department_code);
 if locked is null then
  if nullif(trim(coalesce(p_next_department_code,'')),'') is null then raise exception 'SELECT_NEXT_DEPARTMENT_REQUIRED';end if;
  select * into dep from public.rr_upm_departments where upper(department_code)=upper(p_next_department_code) and is_active and upper(department_code)<>upper(p_department_code);
  if dep.id is null then raise exception 'Selected next department is inactive or invalid.';end if;
  locked:=upper(dep.department_code);
  insert into public.rr_upm_route_lock_v740(canonical_lot_id,from_department_code,to_department_code) values(p_canonical_lot_id,upper(p_department_code),locked);
 elsif p_next_department_code is not null and upper(p_next_department_code)<>upper(locked) then
  raise exception 'Route already locked to % for remaining Colours.',locked;
 end if;
 if not public.rr_upm_action_permission_v727('GOOD',p_department_code) then raise exception 'Submit Work permission denied.';end if;
 select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;if not found then raise exception 'Lot not registered.';end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_colour_id:=nullif(v_row->>'colour_id','')::uuid;v_colour:=upper(trim(v_row->>'colour_code'));
  select * into v_assign from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in('ASSIGNED','IN_PROGRESS') and ((v_colour_id is not null and a.colour_id=v_colour_id) or upper(a.colour_code)=v_colour) order by a.assigned_at desc limit 1;
  if v_assign.id is null then raise exception 'Active assignment missing for colour %.',v_colour;end if;
  v_actions:='[]'::jsonb;
  for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no)c where ((v_assign.colour_id is not null and c.colour_id=v_assign.colour_id) or upper(c.colour_code)=upper(v_assign.colour_code)) loop
   select * into v_bal from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
   if coalesce(v_bal.pending_qty,0)>0 then v_actions:=v_actions||jsonb_build_array(jsonb_build_object('request_id',gen_random_uuid(),'colour_id',v_cut.colour_id,'colour_code',v_cut.colour_code,'colour_name',v_cut.colour_name,'size_code',v_cut.size_code,'action_type','GOOD','source_bucket','PENDING','qty',v_bal.pending_qty));end if;
  end loop;
  if jsonb_array_length(v_actions)>0 then perform public.rr_upm_apply_actions_batch_v726(p_canonical_lot_id,p_department_code,v_actions,p_rate,coalesce(p_remarks,'Colour Submit'));end if;
  v_handoff:=0;
  for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no)c where ((v_assign.colour_id is not null and c.colour_id=v_assign.colour_id) or upper(c.colour_code)=upper(v_assign.colour_code)) loop
   select * into v_bal from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
   if coalesce(v_bal.submit_ready_qty,0)>0 then
    insert into public.rr_upm_department_handoffs_v727(canonical_lot_id,lot_no,from_department_code,to_department_code,colour_id,colour_code,colour_name,size_code,qty,assignment_id,worker_id,worker_name,remarks,actor_user_id)
    values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),locked,v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_bal.submit_ready_qty,v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,p_remarks,auth.uid());
    v_handoff:=v_handoff+v_bal.submit_ready_qty;
   end if;
  end loop;
  if v_handoff<=0 then raise exception 'Colour % has no new Good Qty to Submit.',v_colour;end if;
  update public.rr_upm_colour_state set current_department_code=locked,status='PENDING',updated_at=now() where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(v_assign.colour_code);
  update public.rr_upm_work_assignments_v8 set status='COMPLETED',completed_at=now(),updated_at=now() where id=v_assign.id;
  v_submitted:=v_submitted+v_handoff;v_colours:=v_colours+1;
 end loop;
 return jsonb_build_object('ok',true,'colours_submitted',v_colours,'qty_forwarded',v_submitted,'next_department_code',locked,'route_locked',true,'context',public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code));
end;$$;
grant execute on function public.rr_upm_submit_colours_v740(text,text,jsonb,text,numeric,text) to authenticated;

create or replace function public.rr_upm_debug_v740(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c jsonb;m jsonb;issues jsonb:='[]'::jsonb;
begin
 begin c:=public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);exception when others then return jsonb_build_object('ok',false,'issues',jsonb_build_array(sqlerrm));end;
 m:=c->'mapping_context';
 if nullif(c->'lot'->>'cb_no','') is null then issues:=issues||jsonb_build_array('Locked CB mapping missing');end if;
 if nullif(c->'lot'->>'art_no','') is null then issues:=issues||jsonb_build_array('Locked Art mapping missing');end if;
 if jsonb_array_length(coalesce(m->'line_man_candidates','[]'::jsonb))=0 then issues:=issues||jsonb_build_array('No Line Man candidate in Worker Directory/Fabrication');end if;
 if jsonb_array_length(coalesce(m->'cutting_master_candidates','[]'::jsonb))=0 then issues:=issues||jsonb_build_array('No Cutting Master candidate in Worker Directory');end if;
 return jsonb_build_object('ok',jsonb_array_length(issues)=0,'issues',issues,'context',c,'versions',c->'versions');
end;$$;
grant execute on function public.rr_upm_debug_v740(text,text) to authenticated;

commit;
