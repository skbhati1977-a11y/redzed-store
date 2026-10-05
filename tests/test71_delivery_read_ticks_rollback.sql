begin;
do $test$
declare actor uuid; profile uuid; cid uuid; chat uuid; share uuid; sent uuid; received uuid; unseen uuid; result jsonb; token text:='TEST-TICKS-'||gen_random_uuid(); device text:='TEST-DEVICE-'||gen_random_uuid();
begin
 select auth_user_id,id into actor,profile from rr_user_profiles where role_code='owner' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into rr_customers(customer_name) values('TEST TICKS '||gen_random_uuid()) returning id into cid;
 select id into chat from rr_customer_chat_v9433 where customer_id=cid and data_mode='TEST' and relation_kind='DIRECT_CUSTOMER';
 insert into rr_customer_chat_members_v9433(chat_id,profile_id,is_active) values(chat,profile,true) on conflict do nothing;
 insert into rr_market_share_v9420(customer_id,customer_name,token,data_mode,created_by) values(cid,'TEST TICKS',gen_random_uuid()::text,'TEST',actor) returning id into share;
 insert into rr_customer_session_v9590(session_token_hash,customer_id,chat_id,share_id,data_mode,device_id_hash) values(encode(extensions.digest(token,'sha256'),'hex'),cid,chat,share,'TEST',encode(extensions.digest(device,'sha256'),'hex'));
 insert into rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body) values(chat,'GROUP','STAFF',profile,'TEST OWNER','TEXT','Sent') returning id into sent;
 insert into rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body) values(chat,'GROUP','STAFF',profile,'TEST OWNER','TEXT','Unseen') returning id into unseen;
 result:=rr_chat_staff_receipts_test71(chat,array[sent],'{}');
 if (result->0->>'delivered')::boolean or (result->0->>'read')::boolean then raise exception 'Sender fabricated receipt'; end if;
 perform rr_chat_customer_receipts_test71(token,device,array[sent],'{}');
 result:=rr_chat_staff_receipts_test71(chat,array[sent],'{}');
 if not (result->0->>'delivered')::boolean or (result->0->>'read')::boolean then raise exception 'Delivered state incorrect'; end if;
 perform rr_chat_customer_receipts_test71(token,device,array[sent],array[sent]);
 result:=rr_chat_staff_receipts_test71(chat,array[sent],'{}');
 if not (result->0->>'read')::boolean then raise exception 'Customer read state missing'; end if;
 if exists(select 1 from rr_chat_member_receipts_v61 where message_id=unseen and (read_at is not null or delivered_at is not null)) then raise exception 'Unfetched message incorrectly read'; end if;
 insert into rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body) values(chat,'GROUP','CUSTOMER',cid,'TEST CUSTOMER','ATTACHMENT','Voice') returning id into received;
 perform rr_chat_staff_receipts_test71(chat,array[received],array[received]);
 result:=rr_chat_customer_receipts_test71(token,device,array[received],'{}');
 if not (result->0->>'own')::boolean or not (result->0->>'read')::boolean then raise exception 'Sales read receipt missing'; end if;
end $test$;
rollback;
