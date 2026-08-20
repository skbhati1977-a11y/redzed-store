-- TEST ONLY: ALTER follows current goods department/worker before Good merge.
-- Do not apply to production until the test branch is approved.
begin;

CREATE OR REPLACE FUNCTION public.rr_upm_alter_transition_v771(p_action text, p_rows jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_action text := upper(trim(coalesce(p_action,'')));
  v_ctx jsonb := public.rr_up_user_context_v2();
  v_actor_role text;
  v_actor_name text;
  v_actor_worker_id uuid;
  v_req jsonb;
  v_j public.rr_upm_alter_journey_v740%rowtype;
  v_qty numeric;
  v_expected_stage text;
  v_to_stage text;
  v_resp_id uuid;
  v_resp_name text;
  v_resp_code text;
  v_resp_role text;
  v_resp_dept text;
  v_target_id uuid;
  v_saved integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_phone text;
  v_recipient_id uuid;
  v_recipient_name text;
  v_message text;
  v_wa text;
  v_outbox uuid;
  v_privileged boolean;
  v_holder_directory jsonb;
  v_current_department text;
  v_current_worker_id uuid;
  v_current_worker_name text;
  v_current_worker_code text;
  v_current_goods_route boolean := false;
  v_already_current_goods_route boolean := false;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select an exact Alter journey.'; end if;

  if v_action='RECEIVE_FROM_KARIGAR' then v_action:='KARIGAR_SUBMIT_GOOD'; end if;
  if v_action not in ('REMAKE_ISSUE','RECEIVE_FROM_MASTER','DELIVER_TO_KARIGAR','KARIGAR_SUBMIT_GOOD') then
    raise exception 'Invalid custody action %.',v_action;
  end if;

  v_actor_role := public.rr_upm_norm_role_v740(v_ctx->>'user_category');
  v_actor_name := coalesce(v_ctx->>'display_name',auth.uid()::text);
  v_actor_worker_id := public.rr_upm_actor_worker_id_v771();
  v_privileged := v_actor_role in ('OWNER','ADMIN');

  for v_req in
    select jsonb_build_object('journey_id',g.journey_id,'qty',g.qty)
    from (
      select (e.value->>'journey_id')::uuid as journey_id,
             sum(coalesce(nullif(e.value->>'qty','')::numeric,0)) as qty
      from jsonb_array_elements(p_rows) e(value)
      where nullif(e.value->>'journey_id','') is not null
      group by (e.value->>'journey_id')::uuid
    ) g
    where g.qty>0
  loop
    select * into v_j
    from public.rr_upm_alter_journey_v740
    where id=(v_req->>'journey_id')::uuid
    for update;
    if not found then raise exception 'Exact Alter journey not found.'; end if;
    if v_j.stage like 'CLOSED%' or v_j.open_qty<=0 then raise exception 'Journey % is already closed.',v_j.id; end if;

    v_qty := (v_req->>'qty')::numeric;
    if v_qty>v_j.open_qty then
      raise exception '% / % / %: Qty % exceeds exact holder balance %.',v_j.colour_code,v_j.size_code,'ALT-'||upper(substr(replace(v_j.id::text,'-',''),1,8)),v_qty,v_j.open_qty;
    end if;

    if v_action='REMAKE_ISSUE' then
      v_expected_stage:='LM_ALTER_PENDING'; v_to_stage:='CM_REMAKE_READY';
      if not v_privileged and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.cutting_master_id and auth.uid() is distinct from v_j.cutting_master_id then
        raise exception 'Only this journey''s Cutting Master can confirm Remake Issue.';
      end if;
      v_resp_id:=v_j.cutting_master_id; v_resp_name:=v_j.cutting_master_name; v_resp_code:=v_j.cutting_master_worker_code;
      v_resp_role:='CUTTING_MASTER'; v_resp_dept:='CUTTING';
    elsif v_action='RECEIVE_FROM_MASTER' then
      v_expected_stage:='CM_REMAKE_READY'; v_to_stage:='LM_DELIVERY_PENDING';
      if not v_privileged and v_actor_role<>'MANAGER'
         and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id and auth.uid() is distinct from v_j.enrolled_lm_id then
        raise exception 'Only % Line Man can receive this exact journey from Cutting Master.',coalesce(v_j.enrolled_lm_name,'assigned');
      end if;
      v_resp_id:=v_j.enrolled_lm_id; v_resp_name:=v_j.enrolled_lm_name; v_resp_code:=v_j.enrolled_lm_worker_code;
      select to_jsonb(w) into v_holder_directory
      from public.rr_worker_directory_unified_v1 w where w.worker_id=v_j.enrolled_lm_id limit 1;
      v_resp_role:='LINE_MAN'; v_resp_dept:=coalesce(v_holder_directory->>'department_code','LINE_MAN');
    elsif v_action='DELIVER_TO_KARIGAR' then
      v_expected_stage:='LM_DELIVERY_PENDING'; v_to_stage:='KARIGAR_REMAKE_PENDING';
      if not v_privileged and v_actor_role<>'MANAGER'
         and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id and auth.uid() is distinct from v_j.enrolled_lm_id then
        raise exception 'Only % Line Man can deliver this exact journey to Karigar.',coalesce(v_j.enrolled_lm_name,'assigned');
      end if;
      v_resp_id:=v_j.karigar_id; v_resp_name:=v_j.karigar_name; v_resp_code:=v_j.karigar_worker_code;
      v_resp_role:='WORKER'; v_resp_dept:=v_j.origin_department_code;
    else
      v_expected_stage:='KARIGAR_REMAKE_PENDING';
      v_to_stage:='CLOSED_GOOD';

      -- ALTER follows the goods' current department, not its origin department.
      select coalesce(c.current_department_code,l.current_department_code)
        into v_current_department
      from public.rr_lots l
      left join public.rr_lot_colours c
        on c.lot_id=l.id
       and (upper(c.colour_name)=upper(v_j.colour_name)
         or upper(c.colour_name)=upper(v_j.colour_code))
      where (l.id::text=v_j.canonical_lot_id or upper(l.lot_no)=upper(v_j.lot_no))
      order by c.updated_at desc nulls last
      limit 1;

      if nullif(trim(v_current_department),'') is not null
         and upper(v_current_department)<>upper(v_j.origin_department_code) then
        select a.worker_id,a.worker_name_snapshot,a.worker_code
          into v_current_worker_id,v_current_worker_name,v_current_worker_code
        from public.rr_upm_work_assignments_v8 a
        where a.canonical_lot_id=v_j.canonical_lot_id
          and upper(a.department_code)=upper(v_current_department)
          and (upper(a.colour_code)=upper(v_j.colour_code)
            or upper(a.colour_name)=upper(v_j.colour_name))
          and a.status in ('ASSIGNED','IN_PROGRESS')
          and exists (
            select 1 from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) s
            where upper(s->>'size_code')=upper(v_j.size_code)
              and coalesce(nullif(s->>'qty','')::numeric,0)>0
          )
        order by a.assigned_at desc
        limit 1;

        if v_current_worker_id is null then
          raise exception 'Current goods department % has no mapped active worker for % / %.',
            upper(v_current_department),v_j.colour_code,v_j.size_code;
        end if;

        v_already_current_goods_route := coalesce(v_j.route_version,'')='V771_CURRENT_GOODS_OWNER';

        if not v_already_current_goods_route then
          v_current_goods_route := true;
          v_to_stage:='KARIGAR_REMAKE_PENDING';
          v_resp_id:=v_current_worker_id;
          v_resp_name:=v_current_worker_name;
          v_resp_code:=v_current_worker_code;
          v_resp_role:='WORKER';
          v_resp_dept:=v_current_department;
        else
          if not v_privileged and v_actor_role<>'MANAGER'
             and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_current_worker_id
             and auth.uid() is distinct from v_current_worker_id then
            raise exception 'Only current goods department worker % can submit final Good.',
              coalesce(v_current_worker_name,'mapped worker');
          end if;
          v_resp_id:=null; v_resp_name:=null; v_resp_code:=null; v_resp_role:='NONE'; v_resp_dept:=null;
        end if;
      else
        if not v_privileged and v_actor_role<>'MANAGER'
           and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.karigar_id
           and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id
           and auth.uid() is distinct from v_j.karigar_id
           and auth.uid() is distinct from v_j.enrolled_lm_id then
          raise exception 'Only the responsible Karigar or this journey''s Line Man can submit/receive Good.';
        end if;
        v_resp_id:=null; v_resp_name:=null; v_resp_code:=null; v_resp_role:='NONE'; v_resp_dept:=null;
      end if;
    end if;

    if v_j.stage<>v_expected_stage then
      raise exception 'Journey % is currently %; expected % for action %.',
        'ALT-'||upper(substr(replace(v_j.id::text,'-',''),1,8)),v_j.stage,v_expected_stage,v_action;
    end if;

    if v_qty<v_j.open_qty then
      -- Exact source remainder stays under its existing holder.
      update public.rr_upm_alter_journey_v740
      set open_qty=open_qty-v_qty,updated_at=now(),route_version=case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end
      where id=v_j.id;

      -- Only the moved quantity advances and gets its own traceable child fragment.
      insert into public.rr_upm_alter_journey_v740(
        canonical_lot_id,lot_no,origin_department_code,colour_id,colour_code,colour_name,size_code,
        open_qty,stage,enrolled_lm_id,enrolled_lm_name,enrolled_lm_worker_code,
        cutting_master_id,cutting_master_name,cutting_master_worker_code,
        karigar_id,karigar_name,karigar_worker_code,
        responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,
        evidence_urls,physical_piece_confirmed,created_by,created_by_name,closed_at,close_reason,
        journey_group_id,parent_journey_id,holder_since,route_version
      ) values (
        v_j.canonical_lot_id,v_j.lot_no,v_j.origin_department_code,v_j.colour_id,v_j.colour_code,v_j.colour_name,v_j.size_code,
        v_qty,v_to_stage,v_j.enrolled_lm_id,v_j.enrolled_lm_name,v_j.enrolled_lm_worker_code,
        v_j.cutting_master_id,v_j.cutting_master_name,v_j.cutting_master_worker_code,
        v_j.karigar_id,v_j.karigar_name,v_j.karigar_worker_code,
        v_resp_id,v_resp_name,v_resp_code,v_resp_role,v_resp_dept,
        v_j.evidence_urls,v_j.physical_piece_confirmed,auth.uid(),v_actor_name,
        case when v_to_stage='CLOSED_GOOD' then now() else null end,
        case when v_to_stage='CLOSED_GOOD' then 'Karigar submitted Good / Line Man received Good' else null end,
        coalesce(v_j.journey_group_id,v_j.id),v_j.id,now(),case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end
      ) returning id into v_target_id;
    else
      update public.rr_upm_alter_journey_v740
      set stage=v_to_stage,
          responsible_id=v_resp_id,responsible_name=v_resp_name,responsible_worker_code=v_resp_code,
          responsible_role_code=v_resp_role,responsible_department_code=v_resp_dept,
          journey_group_id=coalesce(journey_group_id,id),holder_since=now(),route_version=case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end,
          closed_at=case when v_to_stage='CLOSED_GOOD' then now() else null end,
          close_reason=case when v_to_stage='CLOSED_GOOD' then 'Karigar submitted Good / Line Man received Good' else null end,
          updated_at=now()
      where id=v_j.id
      returning id into v_target_id;
    end if;

    insert into public.rr_upm_alter_events_v740(
      journey_id,event_type,qty,from_stage,to_stage,actor_id,actor_name,
      responsible_id,responsible_name,responsible_role_code,remarks
    ) values (
      v_target_id,v_action,v_qty,v_expected_stage,v_to_stage,auth.uid(),v_actor_name,
      v_resp_id,v_resp_name,v_resp_role,
      concat_ws(' Â· ',p_remarks,'V771 exact journey_id custody transfer','source='||v_j.id::text)
    );

    if v_to_stage='CM_REMAKE_READY' then
      v_recipient_id:=v_j.cutting_master_id; v_recipient_name:=v_j.cutting_master_name;
      v_message:=format('%s Line Man se Lot %s | %s | %s | %s PCS remake aapki custody me aaya.%sJourney: ALT-%s%sAb responsibility Cutting Master ki hai.',v_j.enrolled_lm_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
    elsif v_to_stage='LM_DELIVERY_PENDING' then
      v_recipient_id:=v_j.enrolled_lm_id; v_recipient_name:=v_j.enrolled_lm_name;
      v_message:=format('%s Cutting Master ne Lot %s | %s | %s | %s PCS aapko diya.%sJourney: ALT-%s%sAb responsibility Line Man ki hai.',v_j.cutting_master_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
    elsif v_to_stage='KARIGAR_REMAKE_PENDING' then
      if v_current_goods_route then
        v_recipient_id:=v_current_worker_id; v_recipient_name:=v_current_worker_name;
        v_message:=format('Alter journey forwarded to current goods department %s.%sLot %s | %s | %s | %s PCS%sJourney: ALT-%s%sCurrent department worker %s ko Good submit karke merge karna hai.',upper(v_current_department),E'\n',v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n',coalesce(v_current_worker_name,'mapped worker'));
      else
        v_recipient_id:=v_j.karigar_id; v_recipient_name:=v_j.karigar_name;
        v_message:=format('%s Line Man ne Lot %s | %s | %s | %s PCS remake aapko diya.%sJourney: ALT-%s%sAb responsibility Karigar ki hai. Complete karke Good submit karein.',v_j.enrolled_lm_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
      end if;
    else
      v_recipient_id:=v_j.enrolled_lm_id; v_recipient_name:=v_j.enrolled_lm_name;
      v_message:=format('Lot %s | %s | %s | %s PCS remake Good submit ho gaya.%sJourney: ALT-%s%sResponsibility cleared; Qty current goods department %s ki Good Qty me merge hui.',v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n',coalesce(nullif(v_current_department,''),v_j.origin_department_code));
    end if;

    select coalesce(to_jsonb(w)->>'mobile',to_jsonb(w)->>'phone',to_jsonb(w)->>'phone_no')
      into v_phone
    from public.rr_worker_directory_unified_v1 w
    where w.worker_id=v_recipient_id
    limit 1;
    v_wa:=public.rr_upm_whatsapp_url_v740(v_phone,v_message);
    insert into public.rr_upm_whatsapp_outbox_v740(
      journey_id,recipient_id,recipient_name,recipient_phone,message_text,evidence_urls,whatsapp_url
    ) values (
      v_target_id,v_recipient_id,v_recipient_name,v_phone,v_message,v_j.evidence_urls,v_wa
    ) returning id into v_outbox;

    v_saved:=v_saved+1;
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'source_journey_id',v_j.id,'target_journey_id',v_target_id,
      'journey_group_id',coalesce(v_j.journey_group_id,v_j.id),
      'qty',v_qty,'from_stage',v_expected_stage,'to_stage',v_to_stage,
      'responsible_id',v_resp_id,'responsible_name',v_resp_name,'responsible_role_code',v_resp_role
    ));
  end loop;

  if v_saved=0 then raise exception 'Enter a positive quantity against an exact journey.'; end if;
  return jsonb_build_object(
    'ok',true,'version','V771_EXACT_JOURNEY_CUSTODY','rows_saved',v_saved,
    'results',v_results,'whatsapp_url',v_wa,'outbox_id',v_outbox,
    'message',case when v_action='KARIGAR_SUBMIT_GOOD'
      then 'Good submitted; responsibility cleared and quantity returned to Good.'
      else 'Exact journey custody transferred successfully.' end
  );
end
$function$


CREATE OR REPLACE FUNCTION public.rr_upm_alter_custody_v771(p_canonical_lot_id text, p_colour_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rows jsonb := '[]'::jsonb;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if nullif(trim(coalesce(p_canonical_lot_id,'')),'') is null then
    raise exception 'Lot reference is required.';
  end if;

  select coalesce(jsonb_agg(x.payload order by x.colour_code,x.size_code,x.created_at,x.journey_id),'[]'::jsonb),
         count(*)
  into v_rows,v_count
  from (
    select
      j.colour_code,
      j.size_code,
      j.created_at,
      j.id as journey_id,
      jsonb_build_object(
        'journey_id',j.id,
        'journey_group_id',coalesce(j.journey_group_id,j.id),
        'parent_journey_id',j.parent_journey_id,
        'journey_code','ALT-'||upper(substr(replace(j.id::text,'-',''),1,8)),
        'canonical_lot_id',j.canonical_lot_id,
        'lot_no',j.lot_no,
        'origin_department_code',j.origin_department_code,
        'colour_id',j.colour_id,
        'colour_code',j.colour_code,
        'colour_name',j.colour_name,
        'size_code',j.size_code,
        'open_qty',j.open_qty,
        'stage',j.stage,
        'stage_label',case j.stage
          when 'LM_ALTER_PENDING' then 'ALTER WITH LINE MAN'
          when 'CM_REMAKE_READY' then 'REMAKE WITH CUTTING MASTER'
          when 'LM_DELIVERY_PENDING' then 'REMAKE WITH LINE MAN'
          when 'KARIGAR_REMAKE_PENDING' then 'REMAKE WITH KARIGAR'
          else replace(j.stage,'_',' ')
        end,
        'responsible_id',j.responsible_id,
        'responsible_name',j.responsible_name,
        'responsible_worker_code',j.responsible_worker_code,
        'responsible_role_code',j.responsible_role_code,
        'responsible_department_code',j.responsible_department_code,
        'line_man_id',j.enrolled_lm_id,
        'line_man_name',j.enrolled_lm_name,
        'line_man_worker_code',j.enrolled_lm_worker_code,
        'cutting_master_id',j.cutting_master_id,
        'cutting_master_name',j.cutting_master_name,
        'cutting_master_worker_code',j.cutting_master_worker_code,
        'karigar_id',j.karigar_id,
        'karigar_name',j.karigar_name,
        'karigar_worker_code',j.karigar_worker_code,
        'holder_since',j.holder_since,
        'route_version',j.route_version,
        'current_goods_department_code',case when j.route_version='V771_CURRENT_GOODS_OWNER' then j.responsible_department_code else null end,
        'current_goods_owner_name',case when j.route_version='V771_CURRENT_GOODS_OWNER' then j.responsible_name else null end,
        'custody_chain',case j.stage
          when 'LM_ALTER_PENDING' then format('%s (Line Man)',coalesce(j.enrolled_lm_name,'Line Man'))
          when 'CM_REMAKE_READY' then format('%s (LM) â†’ %s (Cutting Master)',coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.cutting_master_name,'Cutting Master'))
          when 'LM_DELIVERY_PENDING' then format('%s (LM) â†’ %s (CM) â†’ %s (LM)',coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.cutting_master_name,'Cutting Master'),coalesce(j.enrolled_lm_name,'Line Man'))
          when 'KARIGAR_REMAKE_PENDING' then case when j.route_version='V771_CURRENT_GOODS_OWNER'
            then format('%s (LM) â†’ %s (CM) â†’ %s (LM) â†’ %s (Current Goods Worker)',coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.cutting_master_name,'Cutting Master'),coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.responsible_name,'Current Goods Worker'))
            else format('%s (LM) â†’ %s (CM) â†’ %s (LM) â†’ %s (Karigar)',coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.cutting_master_name,'Cutting Master'),coalesce(j.enrolled_lm_name,'Line Man'),coalesce(j.karigar_name,'Karigar')) end
          else coalesce(j.responsible_name,'No active holder')
        end,
        'next_action',case j.stage
          when 'LM_ALTER_PENDING' then 'REMAKE_ISSUE'
          when 'CM_REMAKE_READY' then 'RECEIVE_FROM_MASTER'
          when 'LM_DELIVERY_PENDING' then 'DELIVER_TO_KARIGAR'
          when 'KARIGAR_REMAKE_PENDING' then 'KARIGAR_SUBMIT_GOOD'
          else null
        end,
        'next_action_label',case j.stage
          when 'LM_ALTER_PENDING' then 'LM â†’ CUTTING MASTER Â· CM RESPONSIBLE'
          when 'CM_REMAKE_READY' then 'CUTTING MASTER â†’ LINE MAN Â· LM RESPONSIBLE'
          when 'LM_DELIVERY_PENDING' then 'LINE MAN â†’ KARIGAR Â· KARIGAR RESPONSIBLE'
          when 'KARIGAR_REMAKE_PENDING' then case when j.route_version='V771_CURRENT_GOODS_OWNER'
            then 'CURRENT GOODS WORKER SUBMIT GOOD Â· MERGE IN CURRENT DEPARTMENT'
            else 'KARIGAR SUBMIT GOOD Â· RESPONSIBILITY CLEAR' end
          else null
        end
      ) as payload
    from public.rr_upm_alter_journey_v740 j
    where j.canonical_lot_id=p_canonical_lot_id
      and j.stage not like 'CLOSED%'
      and j.open_qty>0
      and (nullif(trim(coalesce(p_colour_code,'')),'') is null
           or upper(j.colour_code)=upper(trim(p_colour_code)))
  ) x;

  return jsonb_build_object(
    'ok',true,
    'version','V771_EXACT_JOURNEY_CUSTODY',
    'canonical_lot_id',p_canonical_lot_id,
    'active_count',v_count,
    'rows',v_rows
  );
end
$function$


commit;
