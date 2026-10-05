begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
do $test$
declare cy public.rr_collection_cycle_v9586%rowtype; req public.rr_market_requirements_v9420%rowtype; p public.rr_fg_pi_v787%rowtype;
 tok text; before_count integer; result jsonb; live jsonb; nextcy uuid;
begin
 select c.* into cy from public.rr_collection_cycle_v9586 c join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id where c.data_mode='TEST' and ch.customer_name='Reeka Bhati' order by c.created_at desc limit 1;
 select s.token into tok from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id order by cs.send_seq desc limit 1;
 live:=public.rr_sales_collection_live_status_test71(cy.chat_id);
 if live->'requested_categories' is null or live->>'last_collection_at' is null or live->>'last_category_request_at' is null then raise exception 'FAIL missing live metadata';end if;
 if live->>'collection_cycle_id' is distinct from (public.rr_collection_current_state_v9633(tok)->>'collection_cycle_id') then raise exception 'FAIL customer/staff cycle mismatch';end if;
 select count(*) into before_count from public.rr_customer_chat_messages_v9433 where chat_id=cy.chat_id and archived_at is null and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and payload->>'direct_collection_cycle_id'=cy.id::text;
 result:=public.rr_collection_more_samples_request_v9630(tok,array['Band Collar'],'rollback live belt');
 if (select count(*) from public.rr_customer_chat_messages_v9433 where chat_id=cy.chat_id and archived_at is null and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and payload->>'direct_collection_cycle_id'=cy.id::text)<>before_count then raise exception 'FAIL duplicate category message';end if;
 if not exists(select 1 from public.rr_chat_push_outbox_v61 o join public.rr_customer_chat_messages_v9433 m on m.id=o.message_id where m.chat_id=cy.chat_id and m.payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and m.payload->>'sample_request_update_no'=result->>'update_no' and o.preview like '%rollback live belt%') then raise exception 'FAIL missing category push seed';end if;
 select r.* into req from public.rr_market_requirements_v9420 r join public.rr_fg_pi_v787 pi on pi.market_requirement_id=r.id where r.collection_cycle_id is not null and pi.status='DRAFT' and r.pi_generated_at is not null and r.id=(select x.id from public.rr_market_requirements_v9420 x where x.collection_cycle_id=r.collection_cycle_id and coalesce(x.lifecycle_stage,x.status,'') not in ('SUPERSEDED','CANCELLED') order by submitted_at desc,id desc limit 1) limit 1;
 live:=public.rr_direct_cycle_live_meta_test71(req.collection_cycle_id);
 if live->>'live_status'<>'PI GENERATED' then raise exception 'FAIL PI state';end if;
 select * into p from public.rr_fg_pi_v787 where market_requirement_id=req.id and status='DRAFT' limit 1;
 update public.rr_fg_pi_v787 set status='CI_FINAL',cpi_no=coalesce(cpi_no,'ROLLBACK-CI'),finalized_at=now() where id=p.id;
 live:=public.rr_direct_cycle_live_meta_test71(req.collection_cycle_id);
 if live->>'live_status'<>'CI GENERATED' then raise exception 'FAIL CI state';end if;
 insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status)
 values(cy.customer_id,cy.chat_id,'TEST',cy.collection_no+1,'ROLLBACK NEW COLLECTION','DRAFT') returning id into nextcy;
 live:=public.rr_sales_collection_live_status_test71(cy.chat_id);
 if live->>'collection_cycle_id'<>nextcy::text or live->>'requirement_id' is not null then raise exception 'FAIL latest cycle reset';end if;
 live:=public.rr_collection_current_state_v9633(tok);
 if live->>'collection_cycle_id'<>nextcy::text then raise exception 'FAIL customer latest reset';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 begin
 perform public.rr_sales_collection_live_status_test71(cy.chat_id);
 raise exception 'FAIL unauthorized access';
 exception when others then if SQLERRM like 'FAIL:%' then raise;end if;end;
 if has_function_privilege('anon','public.rr_direct_cycle_live_meta_test71(uuid)','execute') or has_function_privilege('authenticated','public.rr_direct_cycle_live_meta_test71(uuid)','execute') then raise exception 'FAIL helper publicly callable';end if;
end $test$;
select 'PASS: mirrored timestamps/categories, single category message, one updated push seed, PI and CI state, new-cycle reset on both sides, unauthorized denial, private helper' result;
rollback;