begin;
do $test$
declare actor uuid; cid uuid; cname text:='TEST71 SIGNED VALUE '||gen_random_uuid(); r jsonb; pid uuid; stock record; rejected boolean;
begin
 select auth_user_id into actor from rr_user_profiles where role_code='sales' and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into rr_customers(customer_name) values(cname) returning id into cid;
 r:=rr_fg_save_pi_value_adjustment_test71(null,cname,'AUDIT','[{"lot_no":"VALUE-A","stock_type":"REGULAR","qty":36,"rate":250},{"lot_no":"VALUE-B","stock_type":"REGULAR","qty":36,"rate":259}]',null,-1,300,50,0,false,'TEST');
 pid:=(r->>'pi_id')::uuid;
 if (r->>'value_added_amount')::numeric<>-183.24 or (r->>'grand_total')::numeric<>18490 or (r->>'round_off')::numeric<>-0.76 then raise exception 'Screenshot calculation mismatch: %',r; end if;
 if (select value_added_pct from rr_fg_pi_v787 where id=pid)<>-1 or (select packing_other from rr_fg_pi_v787 where id=pid)<>50 then raise exception 'Signed percentage merged into charges'; end if;
 if (rr_sales_pi_detail_v500(pid)->>'value_added_pct')::numeric<>-1 then raise exception 'Saved percent not restored'; end if;
 if (select (snapshot->'header'->>'value_added_pct')::numeric from rr_fg_pi_versions_v787 where pi_id=pid)<>-1 then raise exception 'Version missing signed adjustment'; end if;
 if (select allowed_discount_per_piece from rr_customers where id=cid)<>0 then raise exception 'Percentage changed permanent party discount'; end if;
 select * into stock from rr_fg_stock_balance_v787 where data_mode='TEST' and stock_type='REGULAR' and available_qty>=1 limit 1;
 if not found then raise exception 'CI stock fixture missing'; end if;
 r:=rr_fg_save_pi_value_adjustment_test71(null,cname,'AUDIT',jsonb_build_array(jsonb_build_object('lot_no',stock.lot_no,'stock_type','REGULAR','qty',1,'rate',100)),null,-1,0,0,0,true,'TEST');
 pid:=(r->>'pi_id')::uuid;
 if (select status from rr_fg_pi_v787 where id=pid)<>'CI_FINAL' or (select taxable_amount from rr_fg_pi_v787 where id=pid)<>99 then raise exception 'CI signed adjustment missing'; end if;
 rejected:=false;
 begin perform rr_fg_save_pi_value_adjustment_test71(null,cname,'AUDIT','[]',null,-101);
 exception when others then if sqlerrm like 'Value Added percent%' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Invalid percentage allowed'; end if;
 rejected:=false;
 begin perform rr_fg_save_pi_value_adjustment_test71(null,cname,'AUDIT','[]',null,-1,0,-10);
 exception when others then if sqlerrm='Invalid commercial charges.' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Negative Other Charges allowed'; end if;
end $test$;
rollback;
