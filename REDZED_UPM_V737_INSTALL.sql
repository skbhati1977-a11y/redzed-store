-- REDZED UPM V737 — LINE MAN BASED ALTER JOURNEY + WHATSAPP OUTBOX
begin;
create extension if not exists pgcrypto;

create table if not exists public.rr_upm_alter_journey_v737(
 id uuid primary key default gen_random_uuid(),
 canonical_lot_id text not null,
 lot_no text not null,
 department_code text not null,
 colour_id uuid,
 colour_code text not null,
 colour_name text not null,
 size_code text not null,
 open_qty numeric(14,3) not null check(open_qty>=0),
 stage text not null check(stage in('CUTTING_MASTER_PENDING','LINE_MAN_COLLECT_PENDING','LINE_MAN_DELIVERY_PENDING','KARIGAR_REMAKE_PENDING','CLOSED')),
 line_man_id uuid,line_man_name text,line_man_worker_code text,line_man_department_code text,
 cutting_master_id uuid,cutting_master_name text,cutting_master_worker_code text,
 karigar_id uuid,karigar_name text,karigar_worker_code text,karigar_department_code text,
 responsible_id uuid,responsible_name text,responsible_worker_code text,responsible_role_code text,responsible_department_code text,
 evidence_urls jsonb not null default '[]'::jsonb,
 physical_submitted boolean not null default false,
 created_by uuid default auth.uid(),created_by_name text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),closed_at timestamptz
);

create table if not exists public.rr_upm_alter_events_v737(
 id uuid primary key default gen_random_uuid(),journey_id uuid not null references public.rr_upm_alter_journey_v737(id),
 event_type text not null,qty numeric(14,3) not null check(qty>0),actor_id uuid default auth.uid(),actor_name text,
 from_stage text,to_stage text,responsible_id uuid,responsible_name text,responsible_role_code text,responsible_department_code text,
 evidence_urls jsonb not null default '[]'::jsonb,remarks text,created_at timestamptz not null default now()
);

create table if not exists public.rr_upm_whatsapp_outbox_v737(
 id uuid primary key default gen_random_uuid(),journey_id uuid references public.rr_upm_alter_journey_v737(id),
 recipient_id uuid,recipient_name text,recipient_phone text,message_text text not null,evidence_urls jsonb not null default '[]'::jsonb,
 whatsapp_url text,status text not null default 'READY',created_at timestamptz not null default now(),opened_at timestamptz
);

alter table public.rr_upm_alter_journey_v737 enable row level security;
alter table public.rr_upm_alter_events_v737 enable row level security;
alter table public.rr_upm_whatsapp_outbox_v737 enable row level security;
drop policy if exists rr_v737_journey_read on public.rr_upm_alter_journey_v737;
create policy rr_v737_journey_read on public.rr_upm_alter_journey_v737 for select to authenticated using(true);
drop policy if exists rr_v737_event_read on public.rr_upm_alter_events_v737;
create policy rr_v737_event_read on public.rr_upm_alter_events_v737 for select to authenticated using(true);
drop policy if exists rr_v737_wa_read on public.rr_upm_whatsapp_outbox_v737;
create policy rr_v737_wa_read on public.rr_upm_whatsapp_outbox_v737 for select to authenticated using(true);

create or replace function public.rr_upm_phone_from_json_v737(p jsonb) returns text language sql immutable as $$
 select regexp_replace(coalesce(nullif(p->>'whatsapp_no',''),nullif(p->>'whatsapp_number',''),nullif(p->>'mobile',''),nullif(p->>'mobile_no',''),nullif(p->>'phone',''),nullif(p->>'phone_no','')),'[^0-9]','','g');
$$;

create or replace function public.rr_upm_mapped_person_v737(p_role text,p_department text default null,p_worker uuid default null)
returns table(person_id uuid,person_name text,worker_code text,department_code text,phone text)
language plpgsql stable security definer set search_path=public as $$
begin
 if p_worker is not null then
  return query select w.worker_id,w.worker_name,w.worker_code,w.department_code,
    public.rr_upm_phone_from_json_v737(to_jsonb(w))
  from public.rr_worker_directory_unified_v1 w where w.worker_id=p_worker and coalesce(w.is_active,true) limit 1;
  return;
 end if;
 return query
 select u.user_id,u.display_name,u.worker_code,u.department_code,
   coalesce(public.rr_upm_phone_from_json_v737(to_jsonb(u)),public.rr_upm_phone_from_json_v737(to_jsonb(p)))
 from public.rr_user_assignments_v2 u
 left join public.rr_user_profiles p on p.auth_user_id=u.user_id
 where u.is_active and upper(u.user_category)=upper(p_role)
   and (p_department is null or upper(coalesce(u.department_code,p_department))=upper(p_department)
        or upper(p_role)='CUTTING_MASTER')
 order by case when upper(coalesce(u.department_code,''))=upper(coalesce(p_department,'')) then 0 else 1 end,u.updated_at desc
 limit 1;
end;$$;

create or replace function public.rr_upm_wa_url_v737(p_phone text,p_message text) returns text language sql immutable as $$
 select case when nullif(p_phone,'') is null then null else 'https://wa.me/'||case when length(p_phone)=10 then '91'||p_phone else p_phone end||'?text='||replace(replace(replace(replace(p_message,'%','%25'),' ','%20'),E'\n','%0A'),'&','%26') end;
$$;

create or replace function public.rr_upm_alter_active_summary_v737(p_canonical_lot_id text)
returns table(journey_id uuid,colour_id uuid,colour_code text,colour_name text,size_code text,open_qty numeric,stage text,
 responsible_id uuid,responsible_name text,responsible_worker_code text,responsible_role_code text,responsible_role_short text,
 responsible_department_code text,responsible_department_name text,updated_at timestamptz)
language sql stable security definer set search_path=public as $$
 select j.id,j.colour_id,j.colour_code,j.colour_name,j.size_code,j.open_qty,j.stage,j.responsible_id,j.responsible_name,j.responsible_worker_code,j.responsible_role_code,
 case upper(j.responsible_role_code) when 'LINE_MAN' then 'LM' when 'CUTTING_MASTER' then 'CM' when 'WORKER' then 'KR' else j.responsible_role_code end,
 j.responsible_department_code,coalesce(d.department_name,j.responsible_department_code),j.updated_at
 from public.rr_upm_alter_journey_v737 j left join public.rr_upm_departments d on upper(d.department_code)=upper(j.responsible_department_code)
 where j.canonical_lot_id=p_canonical_lot_id and j.stage<>'CLOSED' and j.open_qty>0 order by j.updated_at;
$$;

grant select on public.rr_upm_alter_journey_v737,public.rr_upm_alter_events_v737,public.rr_upm_whatsapp_outbox_v737 to authenticated;
grant execute on function public.rr_upm_alter_active_summary_v737(text) to authenticated;

create or replace function public.rr_upm_alter_stage_v737(
 p_stage text,p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_urls jsonb default '[]'::jsonb,p_physical_submitted boolean default false,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; lotrec record; ass record; ctx jsonb; actor text; role text; lm record; cm record; kr record; j public.rr_upm_alter_journey_v737%rowtype;
 q numeric; from_stage text; to_stage text; resp record; msg text; wa text; out_id uuid; saved int:=0;
begin
 ctx:=public.rr_up_user_context_v2();actor:=coalesce(ctx->>'display_name',auth.uid()::text);role:=upper(coalesce(ctx->>'user_category',''));
 select lot_no into lotrec from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if lotrec.lot_no is null then raise exception 'Lot is not registered.'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'No rows supplied.'; end if;

 for r in select value from jsonb_array_elements(p_rows) loop
  q:=coalesce((r->>'qty')::numeric,0); if q<=0 then continue; end if;
  select a.*,w.worker_name,w.worker_code into ass from public.rr_upm_work_assignments_v8 a
   left join public.rr_worker_directory_unified_v1 w on w.worker_id=a.worker_id
   where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in('ASSIGNED','IN_PROGRESS')
    and ((nullif(r->>'colour_id','') is not null and a.colour_id=(r->>'colour_id')::uuid) or upper(a.colour_code)=upper(r->>'colour_code'))
   order by a.assigned_at desc limit 1;
  if ass.id is null then raise exception 'Active mapped Karigar not found for % / %.',r->>'colour_code',r->>'size_code'; end if;
  select * into lm from public.rr_upm_mapped_person_v737('LINE_MAN',p_department_code,null) limit 1;
  if lm.person_id is null then raise exception 'Required mapping not found: LINE MAN. Create Line Man name and assign department %.',p_department_code; end if;
  select * into cm from public.rr_upm_mapped_person_v737('CUTTING_MASTER',null,null) limit 1;
  if cm.person_id is null then raise exception 'Required mapping not found: CUTTING MASTER. Create Cutting Master and map Cutting Module.'; end if;
  select * into kr from public.rr_upm_mapped_person_v737('WORKER',p_department_code,ass.worker_id) limit 1;

  if upper(p_stage)='ALTER_FILL' then
   if role not in('LINE_MAN','OWNER','ADMIN','MANAGER') then raise exception 'Only mapped Line Man can Alter Fill.'; end if;
   if not p_physical_submitted or jsonb_array_length(coalesce(p_evidence_urls,'[]'))<1 or jsonb_array_length(coalesce(p_evidence_urls,'[]'))>3 then raise exception '1–3 live camera images and physical evidence are required.'; end if;
   insert into public.rr_upm_alter_journey_v737(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,open_qty,stage,
    line_man_id,line_man_name,line_man_worker_code,line_man_department_code,cutting_master_id,cutting_master_name,cutting_master_worker_code,
    karigar_id,karigar_name,karigar_worker_code,karigar_department_code,responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,
    evidence_urls,physical_submitted,created_by_name)
   values(p_canonical_lot_id,lotrec.lot_no,upper(p_department_code),nullif(r->>'colour_id','')::uuid,upper(r->>'colour_code'),coalesce(r->>'colour_name',r->>'colour_code'),upper(r->>'size_code'),q,'CUTTING_MASTER_PENDING',
    lm.person_id,lm.person_name,lm.worker_code,lm.department_code,cm.person_id,cm.person_name,cm.worker_code,kr.person_id,kr.person_name,kr.worker_code,kr.department_code,
    cm.person_id,cm.person_name,cm.worker_code,'CUTTING_MASTER','CUTTING',p_evidence_urls,true,actor)
   returning * into j;
   from_stage:=null;to_stage:='CUTTING_MASTER_PENDING';
   msg:=format('Namaste %s ji,%sLot: %s | Colour: %s | Size: %s | Qty: %s%s%s Line Man ne live evidence aur physical piece ke saath Alter Fill kiya hai.%sKripya remake kaat kar REMAKE ISSUE kar dein.%sREDZED Production',cm.person_name,E'\n',lotrec.lot_no,r->>'colour_name',upper(r->>'size_code'),q,E'\n',lm.person_name,E'\n',E'\n');
   resp:=cm;
  else
   select * into j from public.rr_upm_alter_journey_v737 where canonical_lot_id=p_canonical_lot_id and department_code=upper(p_department_code)
    and upper(colour_code)=upper(r->>'colour_code') and upper(size_code)=upper(r->>'size_code') and stage<>'CLOSED' order by updated_at desc limit 1 for update;
   if j.id is null then raise exception 'Active Alter journey not found.'; end if;
   if q>j.open_qty then raise exception 'Qty % exceeds current responsibility Qty %.',q,j.open_qty; end if;

   if upper(p_stage)='REMAKE_ISSUE' then
    if role not in('CUTTING_MASTER','OWNER','ADMIN') then raise exception 'Only mapped Cutting Master can Remake Issue.'; end if;
    if j.stage<>'CUTTING_MASTER_PENDING' then raise exception 'Current stage is not Cutting Master Pending.'; end if;
    to_stage:='LINE_MAN_COLLECT_PENDING'; resp:=lm;
    msg:=format('Namaste %s ji,%s%s Cutting Master ne Lot %s | %s | Size %s | Qty %s remake issue kar diya hai.%sKripya Master se remake receive karein.%sREDZED Production',lm.person_name,E'\n',cm.person_name,lotrec.lot_no,j.colour_name,j.size_code,q,E'\n',E'\n');
   elsif upper(p_stage)='RECEIVE_FROM_MASTER' then
    if role not in('LINE_MAN','OWNER','ADMIN','MANAGER') then raise exception 'Only mapped Line Man can receive from Master.'; end if;
    if j.stage<>'LINE_MAN_COLLECT_PENDING' then raise exception 'Current stage is not Master se lena.'; end if;
    to_stage:='LINE_MAN_DELIVERY_PENDING'; resp:=lm;
    msg:=format('%s ji,%sLot %s | %s | Size %s | Qty %s remake aapne Master se receive kar liya.%sAb mapped Karigar %s ko deliver karein.%sREDZED Production',lm.person_name,E'\n',lotrec.lot_no,j.colour_name,j.size_code,q,E'\n',kr.person_name,E'\n');
   elsif upper(p_stage)='DELIVER_TO_KARIGAR' then
    if role not in('LINE_MAN','OWNER','ADMIN','MANAGER') then raise exception 'Only mapped Line Man can deliver to Karigar.'; end if;
    if j.stage<>'LINE_MAN_DELIVERY_PENDING' then raise exception 'Current stage is not Karigar delivery pending.'; end if;
    to_stage:='KARIGAR_REMAKE_PENDING'; resp:=kr;
    msg:=format('Namaste %s ji,%s%s Line Man ne Lot %s | %s | Size %s | Qty %s remake aapko deliver kiya hai.%sAb is Qty ki responsibility aapki hai. Kaam complete karke physical piece Line Man ko dein.%sREDZED Production',kr.person_name,E'\n',lm.person_name,lotrec.lot_no,j.colour_name,j.size_code,q,E'\n',E'\n');
   elsif upper(p_stage)='RECEIVE_FROM_KARIGAR' then
    if role not in('LINE_MAN','OWNER','ADMIN','MANAGER') then raise exception 'Only mapped Line Man can final receive from Karigar.'; end if;
    if j.stage<>'KARIGAR_REMAKE_PENDING' then raise exception 'Current stage is not Karigar Remake Pending.'; end if;
    to_stage:='CLOSED'; resp:=kr;
    msg:=format('Remake closed.%sLot %s | %s | Size %s | Qty %s%sReceived by: %s Line Man%sKarigar responsibility cleared. Qty returned to Good.%sREDZED Production',E'\n',lotrec.lot_no,j.colour_name,j.size_code,q,E'\n',lm.person_name,E'\n',E'\n');
   else raise exception 'Invalid stage %.',p_stage; end if;

   from_stage:=j.stage;
   update public.rr_upm_alter_journey_v737 set open_qty=open_qty-q,updated_at=now() where id=j.id;
   if q<j.open_qty then
    insert into public.rr_upm_alter_journey_v737(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,open_qty,stage,
     line_man_id,line_man_name,line_man_worker_code,line_man_department_code,cutting_master_id,cutting_master_name,cutting_master_worker_code,karigar_id,karigar_name,karigar_worker_code,karigar_department_code,
     responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,evidence_urls,physical_submitted,created_by_name,closed_at)
    values(j.canonical_lot_id,j.lot_no,j.department_code,j.colour_id,j.colour_code,j.colour_name,j.size_code,q,to_stage,j.line_man_id,j.line_man_name,j.line_man_worker_code,j.line_man_department_code,
     j.cutting_master_id,j.cutting_master_name,j.cutting_master_worker_code,j.karigar_id,j.karigar_name,j.karigar_worker_code,j.karigar_department_code,
     case when to_stage='CLOSED' then null else resp.person_id end,case when to_stage='CLOSED' then null else resp.person_name end,case when to_stage='CLOSED' then null else resp.worker_code end,
     case to_stage when 'CUTTING_MASTER_PENDING' then 'CUTTING_MASTER' when 'LINE_MAN_COLLECT_PENDING' then 'LINE_MAN' when 'LINE_MAN_DELIVERY_PENDING' then 'LINE_MAN' when 'KARIGAR_REMAKE_PENDING' then 'WORKER' else 'NONE' end,
     case when to_stage='CLOSED' then null else resp.department_code end,j.evidence_urls,j.physical_submitted,actor,case when to_stage='CLOSED' then now() else null end) returning * into j;
   else
    update public.rr_upm_alter_journey_v737 set stage=to_stage,responsible_id=case when to_stage='CLOSED' then null else resp.person_id end,
     responsible_name=case when to_stage='CLOSED' then null else resp.person_name end,responsible_worker_code=case when to_stage='CLOSED' then null else resp.worker_code end,
     responsible_role_code=case to_stage when 'CUTTING_MASTER_PENDING' then 'CUTTING_MASTER' when 'LINE_MAN_COLLECT_PENDING' then 'LINE_MAN' when 'LINE_MAN_DELIVERY_PENDING' then 'LINE_MAN' when 'KARIGAR_REMAKE_PENDING' then 'WORKER' else 'NONE' end,
     responsible_department_code=case when to_stage='CLOSED' then null else resp.department_code end,open_qty=q,closed_at=case when to_stage='CLOSED' then now() else null end,updated_at=now() where id=j.id returning * into j;
   end if;
  end if;

  insert into public.rr_upm_alter_events_v737(journey_id,event_type,qty,actor_name,from_stage,to_stage,responsible_id,responsible_name,responsible_role_code,responsible_department_code,evidence_urls,remarks)
  values(j.id,upper(p_stage),q,actor,from_stage,to_stage,case when to_stage='CLOSED' then null else resp.person_id end,case when to_stage='CLOSED' then null else resp.person_name end,
   case to_stage when 'CUTTING_MASTER_PENDING' then 'CUTTING_MASTER' when 'LINE_MAN_COLLECT_PENDING' then 'LINE_MAN' when 'LINE_MAN_DELIVERY_PENDING' then 'LINE_MAN' when 'KARIGAR_REMAKE_PENDING' then 'WORKER' else 'NONE' end,
   case when to_stage='CLOSED' then null else resp.department_code end,p_evidence_urls,p_remarks);
  wa:=public.rr_upm_wa_url_v737(resp.phone,msg);
  insert into public.rr_upm_whatsapp_outbox_v737(journey_id,recipient_id,recipient_name,recipient_phone,message_text,evidence_urls,whatsapp_url)
  values(j.id,resp.person_id,resp.person_name,resp.phone,msg,coalesce(p_evidence_urls,j.evidence_urls),wa) returning id into out_id;
  saved:=saved+1;
 end loop;
 return jsonb_build_object('ok',true,'rows_saved',saved,'whatsapp_url',wa,'outbox_id',out_id,'message',msg);
end;$$;

grant execute on function public.rr_upm_alter_stage_v737(text,text,text,jsonb,jsonb,boolean,text) to authenticated;
commit;
