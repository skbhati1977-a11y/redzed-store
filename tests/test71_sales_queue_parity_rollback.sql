begin;
set local jit=off;
do $test$
declare actor uuid; t timestamptz; fresh jsonb; old jsonb; a jsonb; b jsonb; status text; search text;
begin
select auth_user_id into actor from public.rr_user_profiles where role_code='owner' and is_active limit 1;
perform set_config('request.jwt.claim.sub',actor::text,true);
foreach search in array array[null::text,'LUKMAN','not-a-real-customer'] loop
t:=clock_timestamp();fresh:=public.rr_sales_real_chat_queue_test71('OPEN',search,'TEST');
if clock_timestamp()-t>interval '1 second' then raise exception 'Queue exceeded 1 second';end if;
old:=public.rr_sales_real_chat_queue_v500('OPEN',search,'TEST');
select jsonb_agg(x order by x->>'id') into a from jsonb_array_elements(fresh->'cards') x;
select jsonb_agg(x order by x->>'id') into b from jsonb_array_elements(old->'cards') x;
if a is distinct from b then raise exception 'OPEN queue parity failed';end if;
end loop;
foreach status in array array['WORKING','CLOSE'] loop
fresh:=public.rr_sales_real_chat_queue_test71(status,null,'TEST');old:=public.rr_sales_real_chat_queue_v500(status,null,'TEST');
if fresh is distinct from old then raise exception 'Saved bill queue changed';end if;
end loop;
begin perform public.rr_sales_real_chat_queue_test71('OPEN',null,'PROD');raise exception 'Production scope allowed';exception when others then if sqlerrm='Production scope allowed' then raise;end if;end;
perform set_config('request.jwt.claim.sub','',true);
begin perform public.rr_sales_real_chat_queue_test71('OPEN',null,'TEST');raise exception 'Unauthenticated access allowed';exception when others then if sqlerrm='Unauthenticated access allowed' then raise;end if;end;
end $test$;
rollback;
