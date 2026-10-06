begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$
declare d jsonb;blocked boolean:=false;share jsonb;before_qty numeric;before_rate numeric;
begin
if exists(select 1 from public.rr_web_window_cards_v9329('RF-E2E-TRD-20260814-01',null,null,'TEST',150,0) where lot_no='RF-E2E-TRD-20260814-01') then raise exception 'Pending lot leaked into MW';end if;
if not exists(select 1 from public.rr_web_window_cards_v9329('1101',null,null,'TEST',150,0) where lot_no='1101') then raise exception 'Ready approved lot missing';end if;
begin perform public.rr_market_create_share_v9420(array['RF-E2E-TRD-20260814-01'],null,null,'TEST');exception when others then blocked:=true;end;
if not blocked then raise exception 'Pending direct share accepted';end if;
share:=public.rr_market_create_share_v9420(array['1101'],null,null,'TEST');
d:=public.rr_market_share_view_v9420((select token from public.rr_market_share_v9420 where id='202c3635-6489-478c-ba42-c5ae5bb831c2'));
if exists(select 1 from jsonb_array_elements(d->'rows') e where e->>'lot_no'='RF-E2E-TRD-20260814-01') then raise exception 'Retired card returned in open collection';end if;
d:=public.rr_pi_requirement_bootstrap_test71('550be2f2-aa88-446b-814c-14d675565b93');
if exists(select 1 from jsonb_array_elements(d->'lines') e where e->>'lot_no'='RF-E2E-TRD-20260814-01') then raise exception 'Retired card returned in PI';end if;
select available_qty,purchase_rate into before_qty,before_rate from public.rr_rm_stock_v849_2c6 where lot_no='RF-E2E-TRD-20260814-01' and data_mode='TEST';
perform set_config('request.jwt.claim.sub','688bc76c-3f66-4084-b3da-fc3d54220a28',true);
d:=public.rr_rm_complete_mapping_test71('RF-E2E-TRD-20260814-01',jsonb_build_object('item_name','TEST E2E TRADED ITEM','category',(select category_name from public.rr_art_categories where is_active limit 1),'size_text','L, XL, XXL','final_image_url','https://example.com/fixture.jpg'));
if not (d->>'mapping_ready')::boolean or (d->>'market_ready')::boolean then raise exception 'Mapping confused with rate approval';end if;
if exists(select 1 from public.rr_rm_stock_v849_2c6 where lot_no='RF-E2E-TRD-20260814-01' and data_mode='TEST' and (purchase_rate<>before_rate or available_qty<>before_qty)) then raise exception 'Financial stock changed during mapping';end if;
perform set_config('request.jwt.claim.sub','41b511ec-8067-48f7-898e-bb983c0c81cd',true);
blocked:=false;begin perform public.rr_rm_complete_mapping_test71('1101','{}');exception when others then blocked:=true;end;
if not blocked then raise exception 'Sales changed protected mapping';end if;
if has_function_privilege('anon','public.rr_rm_complete_mapping_test71(text,jsonb)','execute') or has_function_privilege('authenticated','public.rr_web_window_snapshot_test71(text,text,text,text,integer,integer)','execute') then raise exception 'Internal helper exposed';end if;
perform set_config('rm.readiness.audit','PASS: pending hidden; direct share blocked; approved share allowed; retired excluded from open collection and PI; Manager metadata completion; financial values preserved; Sales/anon denied',true);
end $$;
select current_setting('rm.readiness.audit') audit;
rollback;
