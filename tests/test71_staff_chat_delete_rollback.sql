begin;
do $test$
declare actor uuid; profile uuid; cid uuid; chat uuid; mine uuid; other uuid; n integer;
begin
 select auth_user_id,id into actor,profile from public.rr_user_profiles where role_code='owner' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.rr_customers(customer_name) values('TEST DELETE '||gen_random_uuid()) returning id into cid;
 select id into chat from public.rr_customer_chat_v9433 where customer_id=cid and data_mode='TEST' and relation_kind='DIRECT_CUSTOMER';
 insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active) values(chat,profile,true) on conflict do nothing;
 insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body) values(chat,'GROUP','STAFF',profile,'TEST OWNER','TEXT','mine') returning id into mine;
 insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body) values(chat,'GROUP','CUSTOMER',cid,'TEST CUSTOMER','TEXT','incoming') returning id into other;
 select count(*) into n from public.rr_chat_staff_messages_test71(chat,'GROUP',200);if n<>2 then raise exception 'Initial messages missing';end if;
 perform public.rr_chat_staff_delete_test71(chat,mine,'ME');
 if exists(select 1 from public.rr_chat_staff_messages_test71(chat,'GROUP',200) x where x.id=mine) then raise exception 'Hidden message reappeared';end if;
 if exists(select 1 from public.rr_customer_chat_messages_v9433 where id=mine and archived_at is not null) then raise exception 'ME removed message for everyone';end if;
 begin perform public.rr_chat_staff_delete_test71(chat,other,'ALL');raise exception 'Unexpected ALL allowed';exception when others then if sqlerrm='Unexpected ALL allowed' then raise;end if;end;
 perform public.rr_chat_staff_delete_test71(chat,mine,'ALL');
 if not exists(select 1 from public.rr_customer_chat_messages_v9433 where id=mine and archived_at is not null) then raise exception 'ALL not archived';end if;
 perform public.rr_chat_staff_archive_test71(chat,'Rollback test');
 if not exists(select 1 from public.rr_customer_chat_v9433 where id=chat and status='ARCHIVED') then raise exception 'Chat not archived';end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.rr_chat_staff_messages_test71(chat,'GROUP',200);raise exception 'Unauthenticated access allowed';exception when others then if sqlerrm='Unauthenticated access allowed' then raise;end if;end;
end $test$;
rollback;
