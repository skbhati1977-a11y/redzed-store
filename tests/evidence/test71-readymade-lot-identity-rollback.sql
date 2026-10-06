begin;
select set_config('request.jwt.claim.sub',(select auth_user_id::text from rr_user_profiles where is_active and lower(role_code)='owner' limit 1),true);
do $$
declare hint jsonb;a jsonb;j jsonb;pid uuid;failed boolean;
begin
 hint:=rr_rm_lot_hint_test71();if hint->>'suggested_lot' !~ '^RM[0-9]+$' then raise exception 'Bad hint';end if;
 a:=jsonb_build_array(jsonb_build_object('lot_no',hint->>'suggested_lot','item_name','Audit','qty',1,'purchase_rate',100));
 j:=rr_rm_purchase_save_test71(null,'Lot audit supplier','Lot audit unique bill',current_date,a,false);pid:=(j->>'purchase_id')::uuid;
 failed:=false;begin perform rr_rm_purchase_save_test71(null,'Lot audit supplier','Another bill',current_date,a,false);exception when others then failed:=sqlerrm like 'Lot %already belongs%';end;if not failed then raise exception 'Duplicate not blocked';end if;
 failed:=false;begin perform rr_rm_purchase_save_test71(null,'Lot audit supplier','Numeric bill',current_date,jsonb_build_array(jsonb_build_object('lot_no','2640','item_name','Audit','qty',1,'purchase_rate',100)),false);exception when others then failed:=sqlerrm like 'New Readymade Lot must%';end;if not failed then raise exception 'Numeric namespace not blocked';end if;
 perform rr_rm_purchase_save_test71(pid,'Lot audit supplier','Lot audit unique bill',current_date,a,false);
 if rr_rm_lot_hint_test71()->>'suggested_lot'=hint->>'suggested_lot' then raise exception 'Hint repeated used lot';end if;
 raise notice 'PASS: RM suggestion, unique draft, duplicate block, numeric namespace block, existing draft edit and next unused suggestion';
end $$;
rollback;
