begin;
do $test$
declare kind text;
begin
 foreach kind in array array['CUSTOMER','PARTNER_CUSTOMER','DISTRIBUTOR'] loop
 insert into public.rr_web_push_subscriptions_v61(worker_id,actor_kind,actor_id,endpoint,p256dh,auth,enabled)
 values(null,kind,gen_random_uuid(),'https://push.invalid/test71-'||kind,'test-only','test-only',false);
 end loop;
 insert into public.rr_web_push_subscriptions_v61(worker_id,actor_kind,actor_id,endpoint,p256dh,auth,enabled)
 values(gen_random_uuid(),'STAFF',gen_random_uuid(),'https://push.invalid/test71-staff','test-only','test-only',false);
 begin
 insert into public.rr_web_push_subscriptions_v61(actor_kind,actor_id,endpoint,p256dh,auth,enabled)
 values('STAFF',gen_random_uuid(),'https://push.invalid/test71-reject','test-only','test-only',false);
 raise exception 'Staff without worker unexpectedly accepted';
 exception when check_violation then null; end;
 begin
 insert into public.rr_web_push_subscriptions_v61(actor_kind,endpoint,p256dh,auth,enabled)
 values('CUSTOMER','https://push.invalid/test71-reject2','test-only','test-only',false);
 raise exception 'Customer without identity unexpectedly accepted';
 exception when check_violation then null; end;
end $test$;
rollback;