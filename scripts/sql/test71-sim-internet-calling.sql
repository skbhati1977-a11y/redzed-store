-- TEST71: reuse existing call/signalling tables; no SMS or paid voice provider.
create or replace function public.rr_chat_call_test71(
 p_action text, p_chat_id uuid default null, p_recipient_profile_id uuid default null,
 p_call_id uuid default null, p_after_id bigint default 0, p_signal_type text default null,
 p_payload jsonb default '{}'::jsonb, p_session_token text default null, p_device_id text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.rr_user_profiles%rowtype; ch public.rr_customer_chat_v9433%rowtype;
 c public.rr_customer_calls_v9433%rowtype; r public.rr_user_profiles%rowtype;
 x jsonb; customer uuid; actor uuid; kind text; nm text; act text:=upper(p_action); cid uuid; outj jsonb;
begin
 if p_session_token is not null then
  x:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id);
  customer:=(x->>'customer_id')::uuid; p_chat_id:=(x->>'chat_id')::uuid;
  if x->>'data_mode'<>'TEST' then raise exception 'TEST calling only'; end if;
  kind:='CUSTOMER';
 else
  perform public.rr_assert_active_user_v1(); a:=public.rr_chat_actor_profile_v9433();
  if a.id is null or not a.is_active or upper(coalesce(a.access_status,'ACTIVE'))<>'ACTIVE' then raise exception 'Active login required'; end if;
  actor:=a.id; kind:='STAFF'; nm:=a.full_name;
 end if;
 if act='INCOMING' then
  return coalesce((select jsonb_agg(jsonb_build_object('call_id',q.id,'chat_id',q.chat_id,'caller_name',q.caller_name)) from
    (select c0.* from public.rr_customer_calls_v9433 c0 join public.rr_customer_chat_v9433 h on h.id=c0.chat_id
     where h.data_mode='TEST' and c0.call_mode='WEBRTC' and c0.status='RINGING' and c0.created_at>now()-interval '60 seconds'
     and ((kind='CUSTOMER' and c0.recipient_customer_id=customer and c0.chat_id=p_chat_id)
      or (kind='STAFF' and c0.recipient_profile_id=actor and exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=c0.chat_id and m.profile_id=actor and m.is_active)))
     order by c0.created_at desc limit 1) q),'[]'::jsonb);
 end if;
 if p_call_id is not null then
  select * into c from public.rr_customer_calls_v9433 where id=p_call_id
   and ((kind='CUSTOMER' and chat_id=p_chat_id and (caller_customer_id=customer or recipient_customer_id=customer))
    or (kind='STAFF' and (caller_profile_id=actor or recipient_profile_id=actor)));
  if c.id is null then raise exception 'Call unavailable'; end if;
  p_chat_id:=c.chat_id;
 end if;
 select * into ch from public.rr_customer_chat_v9433 where id=p_chat_id and data_mode='TEST';
 if ch.id is null then raise exception 'Chat unavailable'; end if;
 if kind='STAFF' and not exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=ch.id and m.profile_id=actor and m.is_active) then raise exception 'Active group membership required'; end if;
 if kind='CUSTOMER' then nm:=ch.customer_name; end if;
 if act='CONTACTS' then
  select coalesce(jsonb_agg(jsonb_build_object('profile_id',p.id,'name',p.full_name) order by p.full_name),'[]'::jsonb) into outj
   from public.rr_customer_chat_members_v9433 m join public.rr_user_profiles p on p.id=m.profile_id
   where m.chat_id=ch.id and m.is_active and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' and p.id is distinct from actor;
  if kind='STAFF' then outj:=jsonb_build_array(jsonb_build_object('profile_id',null,'name',ch.customer_name))||outj; end if;
  return outj;
 end if;
 if act in ('DIAL','START') then
  if p_recipient_profile_id is not null then
   select p.* into r from public.rr_user_profiles p join public.rr_customer_chat_members_v9433 m on m.profile_id=p.id
    where m.chat_id=ch.id and m.is_active and p.id=p_recipient_profile_id and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' and p.id is distinct from actor;
   if r.id is null then raise exception 'Selected member unavailable'; end if;
  elsif kind<>'STAFF' then raise exception 'Select a member'; end if;
  if act='DIAL' then return jsonb_build_object('mobile',case when r.id is null then ch.mobile else r.mobile end); end if;
  -- A chat lock prevents duplicate starts from double taps across tabs.
  perform pg_advisory_xact_lock(hashtextextended(ch.id::text,71));
  if exists(select 1 from public.rr_customer_calls_v9433 q where q.call_mode='WEBRTC' and q.ended_at is null
   and ((q.status='RINGING' and q.created_at>now()-interval '60 seconds') or (q.status='CONNECTED' and coalesce((select max(s.created_at) from public.rr_customer_call_signal_v9435 s where s.call_id=q.id),q.created_at)>now()-interval '90 seconds'))
   and ((actor is not null and actor in(q.caller_profile_id,q.recipient_profile_id)) or (customer is not null and customer in(q.caller_customer_id,q.recipient_customer_id))
     or (r.id is not null and r.id in(q.caller_profile_id,q.recipient_profile_id)) or (r.id is null and ch.customer_id in(q.caller_customer_id,q.recipient_customer_id)))) then raise exception 'Already on a call. End it first.'; end if;
  insert into public.rr_customer_calls_v9433(chat_id,caller_name,recipient_name,caller_profile_id,caller_customer_id,recipient_profile_id,recipient_customer_id,channel,status,call_mode)
  values(ch.id,nm,coalesce(r.full_name,ch.customer_name),actor,customer,r.id,case when r.id is null then ch.customer_id end,'GROUP','RINGING','WEBRTC') returning id into cid;
  return jsonb_build_object('call_id',cid,'name',coalesce(r.full_name,ch.customer_name));
 end if;
 if c.id is null then raise exception 'Call required'; end if;
 if act='POLL' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'type',s.signal_type,'payload',s.payload) order by s.id)
   from public.rr_customer_call_signal_v9435 s where s.call_id=c.id and s.id>greatest(coalesce(p_after_id,0),0)
    and not (coalesce(kind='STAFF' and s.sender_profile_id=actor,false) or coalesce(kind='CUSTOMER' and s.sender_customer_id=customer,false))), '[]'::jsonb);
 end if;
 if act='SIGNAL' then
  p_signal_type:=upper(p_signal_type);
  if p_signal_type not in ('OFFER','ANSWER','ICE','HANGUP','DECLINE') or octet_length(coalesce(p_payload,'{}')::text)>65536 then raise exception 'Invalid call signal'; end if;
  if c.ended_at is not null then return jsonb_build_object('ended',true); end if;
  if p_signal_type='OFFER' and not ((actor is not null and c.caller_profile_id=actor) or (customer is not null and c.caller_customer_id=customer)) then raise exception 'Caller only'; end if;
  if p_signal_type in('ANSWER','DECLINE') and not ((actor is not null and c.recipient_profile_id=actor) or (customer is not null and c.recipient_customer_id=customer)) then raise exception 'Recipient only'; end if;
  insert into public.rr_customer_call_signal_v9435(call_id,sender_kind,sender_profile_id,sender_customer_id,signal_type,payload)
  values(c.id,kind,actor,customer,p_signal_type,coalesce(p_payload,'{}'));
  if p_signal_type in('HANGUP','DECLINE') then update public.rr_customer_calls_v9433 set status=case when p_signal_type='DECLINE' then 'DECLINED' else 'ENDED' end,ended_at=now() where id=c.id;
  elsif p_signal_type='ANSWER' then update public.rr_customer_calls_v9433 set status='CONNECTED',connected_at=now(),started_at=now() where id=c.id; end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Unknown call action';
end $$;
revoke all on function public.rr_chat_call_test71(text,uuid,uuid,uuid,bigint,text,jsonb,text,text) from public;
grant execute on function public.rr_chat_call_test71(text,uuid,uuid,uuid,bigint,text,jsonb,text,text) to anon,authenticated;
