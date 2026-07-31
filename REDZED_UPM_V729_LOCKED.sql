-- REDZED UPM V729 LOCKED ALTER / REMAKE RESPONSIBILITY FLOW
-- Additive over current V726/V727 functions. No sample person, fallback UUID or manual name is accepted.
begin;
create extension if not exists pgcrypto;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('production-evidence','production-evidence',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists rr_upm_evidence_insert_v729 on storage.objects;
create policy rr_upm_evidence_insert_v729 on storage.objects for insert to authenticated
with check(bucket_id='production-evidence' and auth.uid() is not null);
drop policy if exists rr_upm_evidence_read_v729 on storage.objects;
create policy rr_upm_evidence_read_v729 on storage.objects for select to authenticated
using(bucket_id='production-evidence' and auth.uid() is not null);

create table if not exists public.rr_upm_remake_flow_v729(
 id uuid primary key default gen_random_uuid(),
 canonical_lot_id text not null,
 lot_no text not null,
 department_code text not null,
 colour_id uuid,
 colour_code text not null,
 colour_name text,
 size_code text not null,
 assignment_id uuid not null references public.rr_upm_work_assignments_v8(id) on delete restrict,
 worker_id uuid not null,
 worker_name text not null,
 line_man_id uuid not null,
 line_man_name text not null,
 cutting_master_id uuid not null,
 cutting_master_name text not null,
 alter_qty numeric(14,3) not null default 0 check(alter_qty>=0),
 remake_issued_qty numeric(14,3) not null default 0 check(remake_issued_qty>=0),
 remake_delivered_qty numeric(14,3) not null default 0 check(remake_delivered_qty>=0),
 remake_submitted_qty numeric(14,3) not null default 0 check(remake_submitted_qty>=0),
 evidence_urls jsonb not null default '[]'::jsonb,
 physical_submitted boolean not null default false,
 debit_stage text not null default 'CUTTING_MASTER' check(debit_stage in('CUTTING_MASTER','LINE_MAN','WORKER','NONE')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(canonical_lot_id,department_code,colour_code,size_code,assignment_id)
);

create table if not exists public.rr_upm_remake_flow_ledger_v729(
 id uuid primary key default gen_random_uuid(),flow_id uuid not null references public.rr_upm_remake_flow_v729(id) on delete restrict,
 action_type text not null check(action_type in('ALTER_FILL','REMAKE_ISSUE','REMAKE_DELIVERED','REMAKE_SUBMIT')),
 qty numeric(14,3) not null check(qty>0),actor_id uuid not null,actor_name text not null,
 debit_person_id uuid,debit_person_name text,debit_role text not null,
 evidence_urls jsonb not null default '[]'::jsonb,physical_submitted boolean,
 created_at timestamptz not null default now()
);
create index if not exists rr_upm_remake_flow_lookup_v729 on public.rr_upm_remake_flow_v729(canonical_lot_id,department_code,colour_code,size_code);

alter table public.rr_upm_remake_flow_v729 enable row level security;
alter table public.rr_upm_remake_flow_ledger_v729 enable row level security;
drop policy if exists rr_upm_remake_flow_read_v729 on public.rr_upm_remake_flow_v729;
create policy rr_upm_remake_flow_read_v729 on public.rr_upm_remake_flow_v729 for select to authenticated using(true);
drop policy if exists rr_upm_remake_ledger_read_v729 on public.rr_upm_remake_flow_ledger_v729;
create policy rr_upm_remake_ledger_read_v729 on public.rr_upm_remake_flow_ledger_v729 for select to authenticated using(true);

grant select on public.rr_upm_remake_flow_v729,public.rr_upm_remake_flow_ledger_v729 to authenticated;

create or replace function public.rr_upm_required_mapping_error_v729(p_role text,p_department text)
returns void language plpgsql as $$ begin
 raise exception 'Required mapping not found. Create % name and assign department %.',p_role,upper(coalesce(p_department,''));
end $$;

create or replace function public.rr_upm_flow_mapping_v729(p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text)
returns table(assignment_id uuid,worker_id uuid,worker_name text,line_man_id uuid,line_man_name text,cutting_master_id uuid,cutting_master_name text)
language plpgsql stable security definer set search_path=public as $$
declare a public.rr_upm_work_assignments_v8%rowtype;u public.rr_user_assignments_v2%rowtype;
begin
 select * into a from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
 and x.status in('ASSIGNED','IN_PROGRESS') and ((p_colour_id is not null and x.colour_id=p_colour_id) or upper(x.colour_code)=upper(p_colour_code)) order by x.assigned_at desc limit 1;
 if a.id is null then raise exception 'Active mapped Worker/Karigar not found for colour % in department %.',upper(p_colour_code),upper(p_department_code); end if;
 select * into u from public.rr_user_assignments_v2 where user_id=a.worker_id and is_active limit 1;
 if u.user_id is null then perform public.rr_upm_required_mapping_error_v729('Worker/Karigar',p_department_code); end if;
 if u.line_man_id is null or nullif(trim(u.line_man_name),'') is null then perform public.rr_upm_required_mapping_error_v729('Line Man',p_department_code); end if;
 if u.cutting_master_id is null or nullif(trim(u.cutting_master_name),'') is null then perform public.rr_upm_required_mapping_error_v729('Cutting Master','CUTTING MODULE'); end if;
 return query select a.id,a.worker_id,a.worker_name_snapshot,u.line_man_id,u.line_man_name,u.cutting_master_id,u.cutting_master_name;
end $$;

create or replace function public.rr_upm_alter_fill_v729(p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_urls jsonb,p_physical_submitted boolean,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;m record;b record;f public.rr_upm_remake_flow_v729%rowtype;actor jsonb;lot text;q numeric;cnt int:=0;
begin
 actor:=public.rr_up_user_context_v2();
 if upper(coalesce(actor->>'user_category',''))<>'LINE_MAN' then raise exception 'Alter Fill can be submitted only by mapped Department Line Man.'; end if;
 if jsonb_typeof(p_evidence_urls)<>'array' or jsonb_array_length(p_evidence_urls) not between 1 and 3 then raise exception 'Live camera evidence requires minimum 1 and maximum 3 images.'; end if;
 if not coalesce(p_physical_submitted,false) then raise exception 'Physical evidence submission is mandatory.'; end if;
 select lot_no into lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 for r in select value from jsonb_array_elements(p_rows) loop
  q:=coalesce((r->>'qty')::numeric,0); if q<=0 then continue; end if;
  select * into m from public.rr_upm_flow_mapping_v729(p_canonical_lot_id,p_department_code,nullif(r->>'colour_id','')::uuid,r->>'colour_code');
  if auth.uid()<>m.line_man_id then raise exception 'Logged-in Line Man is not mapped to this Worker/Department.'; end if;
  select * into b from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,nullif(r->>'colour_id','')::uuid,r->>'colour_code',r->>'size_code');
  if q>coalesce(b.pending_qty,0) then raise exception '% / %: Alter Fill % exceeds Pending %.',r->>'colour_code',r->>'size_code',q,b.pending_qty; end if;
  perform public.rr_upm_apply_actions_batch_v726(p_canonical_lot_id,p_department_code,jsonb_build_array(jsonb_build_object('request_id',gen_random_uuid(),'action_type','ALTER','qty',q,'colour_id',r->>'colour_id','colour_code',r->>'colour_code','colour_name',r->>'colour_name','size_code',r->>'size_code')),0,p_remarks);
  insert into public.rr_upm_remake_flow_v729(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,line_man_id,line_man_name,cutting_master_id,cutting_master_name,alter_qty,evidence_urls,physical_submitted,debit_stage)
  values(p_canonical_lot_id,lot,upper(p_department_code),nullif(r->>'colour_id','')::uuid,upper(r->>'colour_code'),r->>'colour_name',upper(r->>'size_code'),m.assignment_id,m.worker_id,m.worker_name,m.line_man_id,m.line_man_name,m.cutting_master_id,m.cutting_master_name,q,p_evidence_urls,true,'CUTTING_MASTER')
  on conflict(canonical_lot_id,department_code,colour_code,size_code,assignment_id) do update set alter_qty=rr_upm_remake_flow_v729.alter_qty+excluded.alter_qty,evidence_urls=excluded.evidence_urls,physical_submitted=true,debit_stage='CUTTING_MASTER',updated_at=now() returning * into f;
  insert into public.rr_upm_remake_flow_ledger_v729(flow_id,action_type,qty,actor_id,actor_name,debit_person_id,debit_person_name,debit_role,evidence_urls,physical_submitted)
  values(f.id,'ALTER_FILL',q,auth.uid(),actor->>'display_name',m.cutting_master_id,m.cutting_master_name,'CUTTING_MASTER',p_evidence_urls,true);cnt:=cnt+1;
 end loop;
 return jsonb_build_object('ok',true,'rows_saved',cnt);
end $$;

create or replace function public.rr_upm_remake_stage_v729(p_stage text,p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;f public.rr_upm_remake_flow_v729%rowtype;actor jsonb;q numeric;available numeric;cnt int:=0;action text;debitid uuid;debitname text;debitrole text;
begin
 actor:=public.rr_up_user_context_v2(); action:=upper(trim(p_stage));
 if action not in('REMAKE_ISSUE','REMAKE_DELIVERED','REMAKE_SUBMIT') then raise exception 'Invalid remake stage.'; end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  q:=coalesce((r->>'qty')::numeric,0); if q<=0 then continue; end if;
  select * into f from public.rr_upm_remake_flow_v729 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code) and upper(x.colour_code)=upper(r->>'colour_code') and upper(x.size_code)=upper(r->>'size_code') order by x.updated_at desc limit 1 for update;
  if f.id is null then raise exception 'Alter Fill record not found for % / %.',r->>'colour_code',r->>'size_code'; end if;
  if action='REMAKE_ISSUE' then
   if auth.uid()<>f.cutting_master_id then raise exception 'Remake Issue can be submitted only by mapped Cutting Master.'; end if;
   available:=f.alter_qty-f.remake_issued_qty; if q>available then raise exception 'Remake Issue % exceeds Alter Pending %.',q,available; end if;
   perform public.rr_upm_apply_actions_batch_v726(p_canonical_lot_id,p_department_code,jsonb_build_array(jsonb_build_object('request_id',gen_random_uuid(),'action_type','REMAKE_ISSUE','qty',q,'colour_id',r->>'colour_id','colour_code',r->>'colour_code','colour_name',r->>'colour_name','size_code',r->>'size_code')),0,p_remarks);
   update public.rr_upm_remake_flow_v729 set remake_issued_qty=remake_issued_qty+q,debit_stage='LINE_MAN',updated_at=now() where id=f.id;
   debitid:=f.line_man_id;debitname:=f.line_man_name;debitrole:='LINE_MAN';
  elsif action='REMAKE_DELIVERED' then
   if auth.uid()<>f.line_man_id then raise exception 'Remake Delivered can be submitted only by mapped Department Line Man.'; end if;
   available:=f.remake_issued_qty-f.remake_delivered_qty; if q>available then raise exception 'Remake Delivered % exceeds Remake Issued balance %.',q,available; end if;
   update public.rr_upm_remake_flow_v729 set remake_delivered_qty=remake_delivered_qty+q,debit_stage='WORKER',updated_at=now() where id=f.id;
   debitid:=f.worker_id;debitname:=f.worker_name;debitrole:='WORKER';
  else
   if auth.uid()<>f.worker_id then raise exception 'Remake Submit can be submitted only by mapped Worker/Karigar.'; end if;
   available:=f.remake_delivered_qty-f.remake_submitted_qty; if q>available then raise exception 'Remake Submit % exceeds Remake Delivered pending %.',q,available; end if;
   perform public.rr_upm_apply_actions_batch_v726(p_canonical_lot_id,p_department_code,jsonb_build_array(jsonb_build_object('request_id',gen_random_uuid(),'action_type','REMAKE_COMPLETE','qty',q,'colour_id',r->>'colour_id','colour_code',r->>'colour_code','colour_name',r->>'colour_name','size_code',r->>'size_code')),0,p_remarks);
   update public.rr_upm_remake_flow_v729 set remake_submitted_qty=remake_submitted_qty+q,debit_stage=case when remake_submitted_qty+q>=remake_delivered_qty then 'NONE' else 'WORKER' end,updated_at=now() where id=f.id;
   debitid:=null;debitname:=null;debitrole:='NONE';
  end if;
  insert into public.rr_upm_remake_flow_ledger_v729(flow_id,action_type,qty,actor_id,actor_name,debit_person_id,debit_person_name,debit_role)
  values(f.id,action,q,auth.uid(),actor->>'display_name',debitid,debitname,debitrole);cnt:=cnt+1;
 end loop;
 return jsonb_build_object('ok',true,'rows_saved',cnt,'stage',action);
end $$;

grant execute on function public.rr_upm_alter_fill_v729(text,text,jsonb,jsonb,boolean,text) to authenticated;
grant execute on function public.rr_upm_remake_stage_v729(text,text,text,jsonb,text) to authenticated;
commit;
