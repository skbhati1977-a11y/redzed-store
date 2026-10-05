begin;
do $test$
declare actor uuid; cid uuid; req uuid; share uuid; cname text:='TEST71 DRAFT REUSE '||gen_random_uuid(); r jsonb; first_pi uuid; orphan uuid; lines jsonb:='[{"lot_no":"DRAFT-A","stock_type":"REGULAR","qty":2,"rate":100}]';
begin
 select auth_user_id into actor from rr_user_profiles where role_code='owner' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into rr_customers(customer_name) values(cname) returning id into cid;
 insert into rr_market_share_v9420(token,customer_id,customer_name,created_by,data_mode) values(gen_random_uuid()::text,cid,cname,actor,'TEST') returning id into share;
 insert into rr_market_requirements_v9420(share_id,customer_id,customer_name) values(share,cid,cname) returning id into req;
 r:=rr_pi_requirement_save_test71(req,null,cname,'AUDIT',lines,0,0);
 first_pi:=(r->>'pi_id')::uuid;
 r:=rr_pi_requirement_save_test71(req,null,cname,'AUDIT',lines,0,0);
 if (r->>'pi_id')::uuid<>first_pi then raise exception 'Second session created a different draft'; end if;
 r:=rr_fg_save_pi_value_adjustment_test71(null,cname,'OLD PARTIAL',lines,0,0);orphan:=(r->>'pi_id')::uuid;
 lines:=lines||'[{"lot_no":"DRAFT-B","stock_type":"REGULAR","qty":3,"rate":200}]'::jsonb;
 r:=rr_pi_requirement_save_test71(req,orphan,cname,'AUDIT',lines,0,0);
 if (r->>'pi_id')::uuid<>first_pi or (select count(*) from rr_fg_pi_v787 where market_requirement_id=req and status='DRAFT')<>1 then raise exception 'Duplicate draft reuse failed'; end if;
 if (select count(*) from rr_fg_pi_lines_v787 where pi_id=first_pi)<>2 then raise exception 'Added item not saved'; end if;
 r:=rr_pi_requirement_bootstrap_v9541(req);
 if (r->>'pi_id')::uuid<>first_pi or jsonb_array_length(r->'lines')<>2 then raise exception 'Reload lost saved draft items'; end if;
end $test$;
rollback;
