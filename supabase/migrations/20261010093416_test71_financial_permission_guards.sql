-- TEST71: report authorization follows canonical Accounts effective-identity policy.
BEGIN;
CREATE OR REPLACE FUNCTION public.rr_accounts_report_access_assert_test71()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public
AS $guard$
BEGIN
 IF auth.uid() IS NULL OR NOT public.rr_acct_can_view_v805() THEN
 RAISE EXCEPTION 'Accounts permission required.' USING ERRCODE='42501';
 END IF;
END;
$guard$;
REVOKE ALL ON FUNCTION public.rr_accounts_report_access_assert_test71() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_accounts_report_access_assert_test71() TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_balance_sheet_v806(p_as_of_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));

  v_assets numeric:=0;
  v_liabilities numeric:=0;
  v_equity numeric:=0;

  v_current_profit numeric:=0;

  v_asset_rows jsonb;
  v_liability_rows jsonb;
  v_equity_rows jsonb;

  v_first_date date;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  select coalesce(min(created_at::date),p_as_of_date)
  into v_first_date
  from public.rr_account_reporting_base_v806
  where data_mode=v_mode;

  v_current_profit:=
    coalesce(
      (
        public.rr_profit_loss_v806(
          v_first_date,
          p_as_of_date,
          v_mode
        )->>'net_profit_loss'
      )::numeric,
      0
    );


  -- ASSETS
  select
    coalesce(sum(amount),0),
    coalesce(jsonb_agg(to_jsonb(x) order by x.report_section,x.ledger_name),'[]'::jsonb)
  into
    v_assets,
    v_asset_rows
  from (
    select
      report_section,
      ledger_id,
      ledger_code,
      ledger_name,
      round(
        sum(coalesce(dr_amount,0)-coalesce(cr_amount,0)),
        2
      ) as amount
    from public.rr_account_reporting_base_v806
    where data_mode=v_mode
      and report_type='BALANCE_SHEET'
      and report_section in('ASSET','CURRENT_ASSET')
      and created_at::date<=p_as_of_date
      and coalesce(transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by
      report_section,
      ledger_id,
      ledger_code,
      ledger_name
    having abs(sum(coalesce(dr_amount,0)-coalesce(cr_amount,0)))>0.005
  ) x;


  -- LIABILITIES
  select
    coalesce(sum(amount),0),
    coalesce(jsonb_agg(to_jsonb(x) order by x.report_section,x.ledger_name),'[]'::jsonb)
  into
    v_liabilities,
    v_liability_rows
  from (
    select
      report_section,
      ledger_id,
      ledger_code,
      ledger_name,
      round(
        sum(coalesce(cr_amount,0)-coalesce(dr_amount,0)),
        2
      ) as amount
    from public.rr_account_reporting_base_v806
    where data_mode=v_mode
      and report_type='BALANCE_SHEET'
      and report_section in('LIABILITY','CURRENT_LIABILITY')
      and created_at::date<=p_as_of_date
      and coalesce(transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by
      report_section,
      ledger_id,
      ledger_code,
      ledger_name
    having abs(sum(coalesce(cr_amount,0)-coalesce(dr_amount,0)))>0.005
  ) x;


  -- EQUITY EXCLUDING CURRENT_YEAR_PROFIT CATEGORY
  select
    coalesce(sum(amount),0),
    coalesce(jsonb_agg(to_jsonb(x) order by x.ledger_name),'[]'::jsonb)
  into
    v_equity,
    v_equity_rows
  from (
    select
      ledger_id,
      ledger_code,
      ledger_name,
      round(
        sum(coalesce(cr_amount,0)-coalesce(dr_amount,0)),
        2
      ) as amount
    from public.rr_account_reporting_base_v806
    where data_mode=v_mode
      and report_type='BALANCE_SHEET'
      and report_section='EQUITY'
      and category_code<>'CURRENT_YEAR_PROFIT'
      and created_at::date<=p_as_of_date
      and coalesce(transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by
      ledger_id,
      ledger_code,
      ledger_name
    having abs(sum(coalesce(cr_amount,0)-coalesce(dr_amount,0)))>0.005
  ) x;

  return jsonb_build_object(
    'ok',true,
    'report','BALANCE_SHEET',
    'data_mode',v_mode,
    'as_of_date',p_as_of_date,

    'assets',round(v_assets,2),
    'liabilities',round(v_liabilities,2),
    'equity_before_current_profit',round(v_equity,2),
    'current_year_profit_loss',round(v_current_profit,2),

    'liabilities_plus_equity',
      round(v_liabilities+v_equity+v_current_profit,2),

    'difference',
      round(
        v_assets
        -(v_liabilities+v_equity+v_current_profit),
        2
      ),

    'balanced',
      abs(
        v_assets
        -(v_liabilities+v_equity+v_current_profit)
      )<=0.01,

    'asset_rows',v_asset_rows,
    'liability_rows',v_liability_rows,

    'equity_rows',
      coalesce(v_equity_rows,'[]'::jsonb)
      ||
      jsonb_build_array(
        jsonb_build_object(
          'ledger_name','Current Year Profit / Loss',
          'amount',round(v_current_profit,2)
        )
      )
  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_balance_sheet_v806(date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_balance_sheet_v806(date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_day_book_v806(p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(entry_date date, voucher_no text, transaction_type text, source_module text, source_record_id text, ledger_name text, debit numeric, credit numeric, transaction_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY select
    b.created_at::date,
    b.voucher_no,
    b.transaction_type,
    b.source_module,
    b.source_record_id,
    b.ledger_name,
    round(coalesce(b.dr_amount,0),2),
    round(coalesce(b.cr_amount,0),2),
    b.transaction_status

  from public.rr_account_reporting_base_v806 b

  where b.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and b.created_at::date between p_from_date and p_to_date

  order by b.created_at,b.voucher_no,b.posting_id;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_day_book_v806(date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_day_book_v806(date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_day_book_v807(p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(entry_date date, voucher_no text, transaction_type text, source_module text, source_record_id text, ledger_name text, debit numeric, credit numeric, transaction_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY select b.created_at::date,b.voucher_no,b.transaction_type,b.source_module,b.source_record_id,b.ledger_name,round(coalesce(b.dr_amount,0),2),round(coalesce(b.cr_amount,0),2),b.transaction_status
 from rr_account_reporting_base_v806 b
 where b.data_mode=upper(coalesce(p_data_mode,'TEST')) and b.created_at::date between p_from_date and p_to_date
 and not exists(select 1 from rr_account_book_hidden_pairs_v1 h where h.original_transaction_id=b.transaction_id or h.reversal_transaction_id=b.transaction_id)
 order by b.created_at,b.voucher_no,b.posting_id;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_day_book_v807(date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_day_book_v807(date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_ledger_statement_v806(p_ledger_id uuid, p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(posting_id uuid, transaction_id uuid, entry_date date, voucher_no text, transaction_type text, source_module text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY select
    b.posting_id,
    b.transaction_id,
    b.created_at::date,
    b.voucher_no,
    b.transaction_type,
    b.source_module,
    round(coalesce(b.dr_amount,0),2),
    round(coalesce(b.cr_amount,0),2),

    round(
      sum(
        coalesce(b.dr_amount,0)-coalesce(b.cr_amount,0)
      )
      over(
        order by b.created_at,b.posting_id
        rows between unbounded preceding and current row
      ),
      2
    ) as running_balance

  from public.rr_account_reporting_base_v806 b

  where b.ledger_id=p_ledger_id
    and b.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and b.created_at::date between p_from_date and p_to_date
    and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')

  order by b.created_at,b.posting_id;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_ledger_statement_v806(uuid,date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_ledger_statement_v806(uuid,date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_ledger_statement_v807(p_ledger_id uuid, p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(posting_id uuid, transaction_id uuid, entry_date date, voucher_no text, transaction_type text, source_module text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY with x as(
 select b.* from rr_account_reporting_base_v806 b where b.ledger_id=p_ledger_id and b.data_mode=upper(coalesce(p_data_mode,'TEST')) and b.created_at::date between p_from_date and p_to_date and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')
 and not exists(select 1 from rr_account_book_hidden_pairs_v1 h where h.original_transaction_id=b.transaction_id or h.reversal_transaction_id=b.transaction_id))
 select x.posting_id,x.transaction_id,x.created_at::date,x.voucher_no,x.transaction_type,x.source_module,round(coalesce(x.dr_amount,0),2),round(coalesce(x.cr_amount,0),2),round(sum(coalesce(x.dr_amount,0)-coalesce(x.cr_amount,0)) over(order by x.created_at,x.posting_id rows between unbounded preceding and current row),2) from x order by x.created_at,x.posting_id;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_ledger_statement_v807(uuid,date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_ledger_statement_v807(uuid,date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_profit_loss_v806(p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));

  v_income numeric:=0;
  v_contra_income numeric:=0;
  v_purchase numeric:=0;
  v_contra_purchase numeric:=0;
  v_expense numeric:=0;
  v_salary numeric:=0;

  v_net_sales numeric:=0;
  v_net_purchase numeric:=0;
  v_net_profit numeric:=0;

  v_sections jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  with section_totals as (
    select
      report_section,
      sum(
        case
          when report_normal_side='DR'
            then coalesce(dr_amount,0)-coalesce(cr_amount,0)
          else coalesce(cr_amount,0)-coalesce(dr_amount,0)
        end
      ) as amount
    from public.rr_account_reporting_base_v806
    where data_mode=v_mode
      and report_type='PROFIT_LOSS'
      and created_at::date between p_from_date and p_to_date
      and coalesce(transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by report_section
  )
  select
    coalesce(sum(amount) filter(where report_section='INCOME'),0),
    coalesce(sum(amount) filter(where report_section='CONTRA_INCOME'),0),
    coalesce(sum(amount) filter(where report_section='PURCHASE'),0),
    coalesce(sum(amount) filter(where report_section='CONTRA_PURCHASE'),0),
    coalesce(sum(amount) filter(where report_section='EXPENSE'),0),
    coalesce(sum(amount) filter(where report_section='SALARY'),0)
  into
    v_income,
    v_contra_income,
    v_purchase,
    v_contra_purchase,
    v_expense,
    v_salary
  from section_totals;

  v_net_sales:=round(v_income-v_contra_income,2);
  v_net_purchase:=round(v_purchase-v_contra_purchase,2);

  v_net_profit:=round(
      v_net_sales
      - v_net_purchase
      - v_expense
      - v_salary,
      2
  );

  select coalesce(
    jsonb_agg(x order by x.report_section,x.category_name),
    '[]'::jsonb
  )
  into v_sections
  from (
    select
      report_section,
      category_code,
      category_name,
      round(
        sum(
          case
            when report_normal_side='DR'
              then coalesce(dr_amount,0)-coalesce(cr_amount,0)
            else coalesce(cr_amount,0)-coalesce(dr_amount,0)
          end
        ),
        2
      ) as amount
    from public.rr_account_reporting_base_v806
    where data_mode=v_mode
      and report_type='PROFIT_LOSS'
      and created_at::date between p_from_date and p_to_date
      and coalesce(transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by
      report_section,
      category_code,
      category_name
  ) x;

  return jsonb_build_object(
    'ok',true,
    'report','INCOME_AND_EXPENDITURE',
    'also_called','PROFIT_AND_LOSS',
    'data_mode',v_mode,
    'from_date',p_from_date,
    'to_date',p_to_date,

    'gross_income',round(v_income,2),
    'sales_return_contra_income',round(v_contra_income,2),
    'net_income',v_net_sales,

    'gross_purchase',round(v_purchase,2),
    'purchase_return',round(v_contra_purchase,2),
    'net_purchase',v_net_purchase,

    'expenses',round(v_expense,2),
    'salary_and_wages',round(v_salary,2),

    'net_profit_loss',v_net_profit,
    'result',
      case
        when v_net_profit>0 then 'PROFIT'
        when v_net_profit<0 then 'LOSS'
        else 'BREAK_EVEN'
      end,

    'sections',v_sections
  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_profit_loss_v806(date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_profit_loss_v806(date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ai_context_v807(p_question text, p_data_mode text DEFAULT 'TEST'::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));

  v_from date:=coalesce(p_from_date,current_date-30);
  v_to date:=coalesce(p_to_date,current_date);
  v_asof date:=coalesce(p_as_of_date,current_date);

  v_intent jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  v_intent:=
    public.rr_report_detect_intent_v807(p_question);


  return jsonb_build_object(

    'ok',true,

    'question',p_question,
    'data_mode',v_mode,

    'intent',v_intent,

    'period',jsonb_build_object(
      'from_date',v_from,
      'to_date',v_to,
      'as_of_date',v_asof
    ),

    'report_health',(
      select to_jsonb(h)
      from public.rr_accounts_reporting_health_v806 h
    ),

    'profit_loss',
      public.rr_profit_loss_v806(
        v_from,
        v_to,
        v_mode
      ),

    'balance_sheet',
      public.rr_balance_sheet_v806(
        v_asof,
        v_mode
      ),

    'available_templates',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'report_code',report_code,
            'report_name',report_name,
            'family',report_family
          )
          order by display_order
        ),
        '[]'::jsonb
      )
      from public.rr_report_template_registry_v807
      where is_active
    ),

    'field_mapping_health',jsonb_build_object(
      'mapping_table','rr_account_flow_field_map_v806',
      'guard_rpc','rr_account_flow_field_assert_v806'
    )

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ai_context_v807(text,text,date,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ai_context_v807(text,text,date,date,date) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ask_bootstrap_v806(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  return jsonb_build_object(

    'ok',true,
    'data_mode',v_mode,

    'title','Ask Reports',

    'placeholder',
      'Ask anything about accounts, profit, expense, supplier, balance or transactions...',

    'templates',jsonb_build_array(

      jsonb_build_object(
        'code','PROFIT_LOSS',
        'label','Profit & Loss'
      ),

      jsonb_build_object(
        'code','BALANCE_SHEET',
        'label','Balance Sheet'
      ),

      jsonb_build_object(
        'code','TRIAL_BALANCE',
        'label','Trial Balance'
      ),

      jsonb_build_object(
        'code','DAY_BOOK',
        'label','Day Book'
      ),

      jsonb_build_object(
        'code','LEDGER_STATEMENT',
        'label','Ledger'
      )

    ),

    'sample_questions',jsonb_build_array(
      'Is month me profit hua ya loss?',
      'Total purchase kitni hui?',
      'Expenses kis category me sabse zyada hain?',
      'Krishna supplier ka account dikhao',
      'Aaj ki entries dikhao',
      'Current assets aur liabilities kitni hain?'
    ),

    'behavior',jsonb_build_object(
      'show_template_suggestions_while_typing',true,
      'allow_free_form_question',true,
      'direct_report_when_confident',true,
      'ai_analysis_for_open_question',true
    )

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ask_bootstrap_v806(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ask_bootstrap_v806(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ask_bootstrap_v807(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN (select public.rr_report_ask_bootstrap_v806(
    upper(coalesce(p_data_mode,'TEST'))
  ));
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ask_bootstrap_v807(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ask_bootstrap_v807(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ask_v807(p_question text, p_data_mode text DEFAULT 'TEST'::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_as_of_date date DEFAULT NULL::date, p_ledger_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));

  v_from date:=coalesce(p_from_date,current_date-30);
  v_to date:=coalesce(p_to_date,current_date);
  v_asof date:=coalesce(p_as_of_date,current_date);

  v_detect jsonb;
  v_intent text;

  v_result jsonb;
  v_log_id uuid;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  if nullif(trim(coalesce(p_question,'')),'') is null then
    raise exception 'Report question required.';
  end if;

  v_detect:=
    public.rr_report_detect_intent_v807(p_question);

  v_intent:=v_detect->>'intent';


  -- ==========================================================
  -- PROFIT / LOSS
  -- ==========================================================
  if v_intent='PROFIT_LOSS' then

    v_result:=
      public.rr_profit_loss_v806(
        v_from,
        v_to,
        v_mode
      );


  -- ==========================================================
  -- BALANCE SHEET
  -- ==========================================================
  elsif v_intent='BALANCE_SHEET' then

    v_result:=
      public.rr_balance_sheet_v806(
        v_asof,
        v_mode
      );


  -- ==========================================================
  -- TRIAL BALANCE
  -- ==========================================================
  elsif v_intent='TRIAL_BALANCE' then

    select jsonb_build_object(
      'ok',true,
      'report','TRIAL_BALANCE',
      'from_date',v_from,
      'to_date',v_to,
      'data_mode',v_mode,

      'rows',
        coalesce(
          jsonb_agg(to_jsonb(x)),
          '[]'::jsonb
        )
    )
    into v_result
    from public.rr_trial_balance_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  -- ==========================================================
  -- DAY BOOK
  -- ==========================================================
  elsif v_intent='DAY_BOOK' then

    select jsonb_build_object(
      'ok',true,
      'report','DAY_BOOK',
      'from_date',v_from,
      'to_date',v_to,
      'data_mode',v_mode,

      'rows',
        coalesce(
          jsonb_agg(to_jsonb(x)),
          '[]'::jsonb
        )
    )
    into v_result
    from public.rr_day_book_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  -- ==========================================================
  -- LEDGER STATEMENT
  -- ==========================================================
  elsif v_intent='LEDGER_STATEMENT' then

    if p_ledger_id is null then

      v_result:=jsonb_build_object(
        'ok',false,
        'needs_input',true,
        'required_input','ledger_id',
        'message','Select Supplier / Customer / Ledger.',
        'intent','LEDGER_STATEMENT'
      );

    else

      select jsonb_build_object(
        'ok',true,
        'report','LEDGER_STATEMENT',
        'ledger_id',p_ledger_id,
        'from_date',v_from,
        'to_date',v_to,
        'data_mode',v_mode,

        'rows',
          coalesce(
            jsonb_agg(to_jsonb(x)),
            '[]'::jsonb
          )
      )
      into v_result
      from public.rr_ledger_statement_v806(
        p_ledger_id,
        v_from,
        v_to,
        v_mode
      ) x;

    end if;


  -- ==========================================================
  -- PURCHASE RETURN
  -- ==========================================================
  elsif v_intent='PURCHASE_RETURN' then

    select jsonb_build_object(
      'ok',true,
      'report','PURCHASE_RETURN',
      'data_mode',v_mode,

      'rows',
        coalesce(
          jsonb_agg(to_jsonb(x) order by x.created_at desc),
          '[]'::jsonb
        )
    )
    into v_result

    from public.rr_purchase_return_status_universal_v806 x

    where x.data_mode=v_mode
      and x.return_date between v_from and v_to;


  -- ==========================================================
  -- OPEN-ENDED QUESTION
  -- ==========================================================
  else

    v_result:=jsonb_build_object(
      'ok',true,
      'report','AI_ANALYSIS_CONTEXT',
      'requires_ai_summary',true,

      'context',
        public.rr_report_ai_context_v807(
          p_question,
          v_mode,
          v_from,
          v_to,
          v_asof
        )
    );

  end if;


  -- ==========================================================
  -- QUESTION AUDIT LOG
  -- ==========================================================
  insert into public.rr_report_question_log_v807(
    question,
    data_mode,
    detected_intent,
    matched_report_code,
    parameters,
    result_type,
    result_snapshot
  )
  values(
    trim(p_question),
    v_mode,
    v_intent,

    case
      when v_intent='ANALYSIS' then null
      else v_intent
    end,

    jsonb_build_object(
      'from_date',v_from,
      'to_date',v_to,
      'as_of_date',v_asof,
      'ledger_id',p_ledger_id
    ),

    case
      when v_intent='ANALYSIS'
        then 'AI_CONTEXT'
      else 'REPORT'
    end,

    v_result
  )
  returning id into v_log_id;


  return v_result
    || jsonb_build_object(
         'question_id',v_log_id,
         'detected_intent',v_intent
       );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ask_v807(text,text,date,date,date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ask_v807(text,text,date,date,date,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_bootstrap_v807(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  return jsonb_build_object(

    'ok',true,
    'data_mode',v_mode,

    'templates',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'report_code',report_code,
            'report_name',report_name,
            'report_family',report_family,
            'description',report_description,
            'requires_from_date',requires_from_date,
            'requires_to_date',requires_to_date,
            'requires_as_of_date',requires_as_of_date,
            'requires_ledger',requires_ledger
          )
          order by display_order
        ),
        '[]'::jsonb
      )
      from public.rr_report_templates_v807
      where is_active
    ),

    'health',(
      select to_jsonb(h)
      from public.rr_accounts_reporting_health_v806 h
    ),

    'search_placeholder',
      'Ask anything about accounts, sales, purchase, expense, supplier, profit or balance...'

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_bootstrap_v807(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_bootstrap_v807(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_hub_bootstrap_v807(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  return jsonb_build_object(

    'ok',true,
    'data_mode',v_mode,

    'templates',(
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.display_order),
        '[]'::jsonb
      )
      from (
        select
          report_code,
          report_name,
          report_family,
          description,
          requires_from_date,
          requires_to_date,
          requires_as_of_date,
          requires_ledger,
          display_order
        from public.rr_report_template_registry_v807
        where is_active
      ) x
    ),

    'search_rpc',
      'rr_report_search_suggest_v807',

    'ask_rpc',
      'rr_report_ask_v807',

    'ui_rules',jsonb_build_object(

      'search_as_you_type',true,

      'suggestion_position','BELOW_SEARCH_BOX',

      'template_click_executes_report',true,

      'question_can_be_free_text',true,

      'analysis_from_verified_accounts_only',true,

      'unmapped_account_field_must_block',true,

      'never_guess_ledger_mapping',true
    )

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_hub_bootstrap_v807(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_hub_bootstrap_v807(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_question_context_v807(p_question_text text, p_data_mode text DEFAULT 'TEST'::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_from date:=coalesce(
    p_from_date,
    date_trunc('month',current_date)::date
  );
  v_to date:=coalesce(p_to_date,current_date);

  v_question_id uuid;
  v_suggestions jsonb;
  v_health jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  if nullif(trim(coalesce(p_question_text,'')),'') is null then
    raise exception 'Question required.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);

  select coalesce(
    jsonb_agg(to_jsonb(s) order by s.score desc),
    '[]'::jsonb
  )
  into v_suggestions
  from public.rr_report_search_v807(
    p_question_text,
    5
  ) s;

  select to_jsonb(h)
  into v_health
  from public.rr_accounts_reporting_health_v806 h;

  insert into public.rr_report_questions_v807(
    data_mode,
    question_text,
    suggested_report_code
  )
  values(
    v_mode,
    trim(p_question_text),
    (
      select s.report_code
      from public.rr_report_search_v807(
        p_question_text,
        1
      ) s
      limit 1
    )
  )
  returning id into v_question_id;

  return jsonb_build_object(
    'ok',true,

    'question_id',v_question_id,
    'question',trim(p_question_text),

    'data_mode',v_mode,
    'from_date',v_from,
    'to_date',v_to,

    'template_suggestions',v_suggestions,

    'reporting_health',v_health,

    'profit_loss',
      public.rr_profit_loss_v806(
        v_from,
        v_to,
        v_mode
      ),

    'balance_sheet',
      public.rr_balance_sheet_v806(
        v_to,
        v_mode
      ),

    'instruction',
      'Use this accounting context to answer the user question. Suggest a template report when relevant, but also provide direct analysis.'
  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_question_context_v807(text,text,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_question_context_v807(text,text,date,date) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_question_route_v806(p_question text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_as_of_date date DEFAULT NULL::date, p_ledger_id uuid DEFAULT NULL::uuid, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_q text:=lower(trim(coalesce(p_question,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));

  v_from date:=coalesce(p_from_date,current_date-30);
  v_to date:=coalesce(p_to_date,current_date);
  v_asof date:=coalesce(p_as_of_date,p_to_date,current_date);

  v_report_code text;
  v_result jsonb;
  v_suggestions jsonb:='[]'::jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  if v_q='' then
    raise exception 'Report question required.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);


  -- ==========================================================
  -- REPORT ROUTING
  -- ==========================================================

  if
       v_q like '%profit%'
    or v_q like '%loss%'
    or v_q like '%income%'
    or v_q like '%expense%'
    or v_q like '%kharcha%'
    or v_q like '%kamai%'
    or v_q like '%munafa%'
    or v_q like '%nuksan%'
  then
    v_report_code:='PROFIT_LOSS';


  elsif
       v_q like '%balance sheet%'
    or v_q like '%asset%'
    or v_q like '%liabilit%'
    or v_q like '%capital%'
    or v_q like '%financial position%'
  then
    v_report_code:='BALANCE_SHEET';


  elsif
       v_q like '%trial balance%'
    or v_q like '%trial%'
    or v_q like '%debit credit balance%'
  then
    v_report_code:='TRIAL_BALANCE';


  elsif
       v_q like '%day book%'
    or v_q like '%voucher%'
    or v_q like '%transaction%'
    or v_q like '%entry%'
    or v_q like '%entries%'
  then
    v_report_code:='DAY_BOOK';


  elsif
       v_q like '%ledger%'
    or v_q like '%supplier%'
    or v_q like '%vendor%'
    or v_q like '%customer account%'
    or v_q like '%party account%'
    or v_q like '%party ledger%'
  then
    v_report_code:='LEDGER_STATEMENT';

  else
    v_report_code:='ANALYZE';
  end if;


  -- ==========================================================
  -- TEMPLATE SUGGESTIONS
  -- ==========================================================

  v_suggestions:=
    jsonb_build_array(

      jsonb_build_object(
        'report_code','PROFIT_LOSS',
        'report_name','Income & Expenditure / Profit & Loss',
        'relevance',
          case when v_report_code='PROFIT_LOSS' then 100 else 20 end
      ),

      jsonb_build_object(
        'report_code','BALANCE_SHEET',
        'report_name','Balance Sheet',
        'relevance',
          case when v_report_code='BALANCE_SHEET' then 100 else 15 end
      ),

      jsonb_build_object(
        'report_code','TRIAL_BALANCE',
        'report_name','Trial Balance',
        'relevance',
          case when v_report_code='TRIAL_BALANCE' then 100 else 10 end
      ),

      jsonb_build_object(
        'report_code','DAY_BOOK',
        'report_name','Day Book',
        'relevance',
          case when v_report_code='DAY_BOOK' then 100 else 10 end
      ),

      jsonb_build_object(
        'report_code','LEDGER_STATEMENT',
        'report_name','Ledger Statement',
        'relevance',
          case when v_report_code='LEDGER_STATEMENT' then 100 else 10 end
      )
    );


  -- ==========================================================
  -- EXECUTE DETERMINISTIC REPORT
  -- ==========================================================

  if v_report_code='PROFIT_LOSS' then

    v_result:=
      public.rr_profit_loss_v806(
        v_from,
        v_to,
        v_mode
      );


  elsif v_report_code='BALANCE_SHEET' then

    v_result:=
      public.rr_balance_sheet_v806(
        v_asof,
        v_mode
      );


  elsif v_report_code='TRIAL_BALANCE' then

    select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    into v_result
    from public.rr_trial_balance_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  elsif v_report_code='DAY_BOOK' then

    select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    into v_result
    from public.rr_day_book_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  elsif v_report_code='LEDGER_STATEMENT' then

    if p_ledger_id is null then

      return jsonb_build_object(
        'ok',true,
        'question',p_question,
        'route','LEDGER_STATEMENT',
        'needs_input',true,
        'required_input','ledger_id',
        'message','Select Supplier / Customer / Ledger.',
        'suggestions',v_suggestions,
        'data_mode',v_mode
      );

    end if;

    select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    into v_result
    from public.rr_ledger_statement_v806(
      p_ledger_id,
      v_from,
      v_to,
      v_mode
    ) x;


  else

    -- ========================================================
    -- OPEN QUESTION CONTEXT
    -- AI/UI layer can synthesize answer from this packet.
    -- ========================================================

    v_result:=jsonb_build_object(

      'profit_loss',
        public.rr_profit_loss_v806(
          v_from,
          v_to,
          v_mode
        ),

      'balance_sheet',
        public.rr_balance_sheet_v806(
          v_asof,
          v_mode
        ),

      'health',
        (
          select to_jsonb(h)
          from public.rr_accounts_reporting_health_v806 h
        ),

      'instruction',
        'Analyze only the supplied accounting context. If the question requires unsupported operational data, request the relevant module context.'

    );

  end if;


  return jsonb_build_object(

    'ok',true,

    'question',p_question,

    'route',v_report_code,

    'data_mode',v_mode,

    'period',jsonb_build_object(
      'from_date',v_from,
      'to_date',v_to,
      'as_of_date',v_asof
    ),

    'needs_input',false,

    'suggestions',v_suggestions,

    'result',coalesce(v_result,'{}'::jsonb),

    'answer_mode',
      case
        when v_report_code='ANALYZE'
          then 'AI_SYNTHESIS'
        else 'DIRECT_REPORT'
      end

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_question_route_v806(text,date,date,date,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_question_route_v806(text,date,date,date,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_question_route_v807(p_question text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_as_of_date date DEFAULT NULL::date, p_ledger_id uuid DEFAULT NULL::uuid, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN (select public.rr_report_question_route_v806(
    p_question,
    p_from_date,
    p_to_date,
    p_as_of_date,
    p_ledger_id,
    upper(coalesce(p_data_mode,'TEST'))
  ));
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_question_route_v807(text,date,date,date,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_question_route_v807(text,date,date,date,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_run_v807(p_report_code text, p_data_mode text DEFAULT 'TEST'::text, p_options jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code text:=upper(trim(coalesce(p_report_code,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));

  v_from date;
  v_to date;
  v_as_of date;
  v_ledger uuid;

  v_result jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  perform public.rr_app_data_mode_assert_v786(v_mode);

  begin
    v_from:=
      coalesce(
        nullif(p_options->>'from_date','')::date,
        date_trunc('month',current_date)::date
      );

    v_to:=
      coalesce(
        nullif(p_options->>'to_date','')::date,
        current_date
      );

    v_as_of:=
      coalesce(
        nullif(p_options->>'as_of_date','')::date,
        current_date
      );

    v_ledger:=
      nullif(p_options->>'ledger_id','')::uuid;

  exception when others then
    raise exception 'Invalid Report Options.';
  end;


  if v_code='PROFIT_LOSS' then

    v_result:=
      public.rr_profit_loss_v806(
        v_from,
        v_to,
        v_mode
      );


  elsif v_code='BALANCE_SHEET' then

    v_result:=
      public.rr_balance_sheet_v806(
        v_as_of,
        v_mode
      );


  elsif v_code='TRIAL_BALANCE' then

    select jsonb_build_object(
      'ok',true,
      'report','TRIAL_BALANCE',
      'data_mode',v_mode,
      'from_date',v_from,
      'to_date',v_to,
      'rows',
      coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    )
    into v_result
    from public.rr_trial_balance_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  elsif v_code='DAY_BOOK' then

    select jsonb_build_object(
      'ok',true,
      'report','DAY_BOOK',
      'data_mode',v_mode,
      'from_date',v_from,
      'to_date',v_to,
      'rows',
      coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    )
    into v_result
    from public.rr_day_book_v806(
      v_from,
      v_to,
      v_mode
    ) x;


  elsif v_code='LEDGER_STATEMENT' then

    if v_ledger is null then
      raise exception 'Ledger required for Ledger Statement.';
    end if;

    select jsonb_build_object(
      'ok',true,
      'report','LEDGER_STATEMENT',
      'data_mode',v_mode,
      'ledger_id',v_ledger,
      'from_date',v_from,
      'to_date',v_to,
      'rows',
      coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    )
    into v_result
    from public.rr_ledger_statement_v806(
      v_ledger,
      v_from,
      v_to,
      v_mode
    ) x;


  else
    raise exception
      'Unsupported Report Code: %',
      v_code;
  end if;


  return v_result;

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_run_v807(text,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_run_v807(text,text,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_search_bridge_v807(p_search_text text, p_limit integer DEFAULT 10)
 RETURNS TABLE(report_code text, report_name text, report_family text, report_description text, requires_from_date boolean, requires_to_date boolean, requires_as_of_date boolean, requires_ledger boolean, score integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY select *
  from public.rr_report_search_v807(
    p_search_text,
    coalesce(p_limit,10)
  );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_search_bridge_v807(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_search_bridge_v807(text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_search_suggest_v807(p_query text, p_limit integer DEFAULT 8)
 RETURNS TABLE(report_code text, report_name text, report_family text, description text, match_score integer, requires_ledger boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY with q as (
    select lower(trim(coalesce(p_query,''))) as s
  ),

  scored as (
    select
      r.report_code,
      r.report_name,
      r.report_family,
      r.description,
      r.requires_ledger,

      case
        when q.s='' then
          greatest(1,100-r.display_order)

        when lower(r.report_name)=q.s
          or lower(r.report_code)=replace(q.s,' ','_')
          then 1000

        when lower(r.report_name) like q.s||'%'
          then 700

        when lower(r.report_name) like '%'||q.s||'%'
          then 500

        when lower(r.report_code) like '%'||replace(q.s,' ','_')||'%'
          then 450

        when lower(array_to_string(r.search_aliases,' '))
             like '%'||q.s||'%'
          then 400

        when lower(array_to_string(r.keywords,' '))
             like '%'||q.s||'%'
          then 300

        else 0
      end as score

    from public.rr_report_template_registry_v807 r
    cross join q

    where r.is_active
  )

  select
    report_code,
    report_name,
    report_family,
    description,
    score,
    requires_ledger
  from scored
  where score>0
  order by score desc,report_name
  limit greatest(1,least(coalesce(p_limit,8),20));
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_search_suggest_v807(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_search_suggest_v807(text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_search_v807(p_search_text text, p_limit integer DEFAULT 10)
 RETURNS TABLE(report_code text, report_name text, report_family text, report_description text, requires_from_date boolean, requires_to_date boolean, requires_as_of_date boolean, requires_ledger boolean, score integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY with q as (
  select lower(trim(coalesce(p_search_text,''))) as s
),

scored as (
  select
    r.report_code,
    r.report_name,
    r.report_family,
    r.description as report_description,
    r.requires_from_date,
    r.requires_to_date,
    r.requires_as_of_date,
    r.requires_ledger,

    case

      -- EMPTY SEARCH:
      -- all active templates visible in configured order
      when q.s='' then
        greatest(1,1000-r.display_order)

      -- EXACT NAME
      when lower(r.report_name)=q.s then
        1000

      -- EXACT CODE
      when lower(r.report_code)=
           replace(replace(q.s,' ','_'),'-','_')
        then 950

      -- NAME PREFIX
      when lower(r.report_name) like q.s||'%'
        then 850

      -- NAME CONTAINS
      when lower(r.report_name) like '%'||q.s||'%'
        then 750

      -- CODE CONTAINS
      when lower(r.report_code)
           like '%'||replace(q.s,' ','_')||'%'
        then 700

      -- ALIAS
      when lower(
             array_to_string(
               coalesce(r.search_aliases,array[]::text[]),
               ' '
             )
           ) like '%'||q.s||'%'
        then 650

      -- KEYWORD
      when lower(
             array_to_string(
               coalesce(r.keywords,array[]::text[]),
               ' '
             )
           ) like '%'||q.s||'%'
        then 550

      -- DESCRIPTION
      when lower(coalesce(r.description,''))
           like '%'||q.s||'%'
        then 400

      else 0
    end as match_score

  from public.rr_report_template_registry_v807 r
  cross join q

  where r.is_active
)

select
  report_code,
  report_name,
  report_family,
  report_description,
  requires_from_date,
  requires_to_date,
  requires_as_of_date,
  requires_ledger,
  match_score::integer as score

from scored

where match_score>0

order by
  match_score desc,
  report_name

limit greatest(
  1,
  least(coalesce(p_limit,10),50)
);
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_search_v807(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_search_v807(text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_bootstrap_v807(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_boot jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();
  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);

  v_boot:=public.rr_report_bootstrap_v807(v_mode);

  return jsonb_build_object(
    'ok',true,
    'data_mode',v_mode,

    'ui',jsonb_build_object(
      'search_placeholder',
        'Report search करें या अपना सवाल लिखें…',

      'question_placeholder',
        'जैसे: इस महीने कितना profit हुआ? Krishna का balance क्या है?',

      'suggestion_limit',8,

      'search_debounce_ms',250,

      'render_same_section',true,

      'auto_open_required_inputs',true
    ),

    'bootstrap',v_boot
  );
end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_bootstrap_v807(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_bootstrap_v807(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_integration_v806(p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_q text:=trim(coalesce(p_query,''));
  v_templates jsonb;
  v_report_objects jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  -- Current registered templates
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'report_code',x.report_code,
        'report_name',x.report_name,
        'report_family',x.report_family,
        'description',x.description,
        'requires_ledger',x.requires_ledger,
        'requires_from_date',x.requires_from_date,
        'requires_to_date',x.requires_to_date,
        'requires_as_of_date',x.requires_as_of_date
      )
      order by x.report_name
    ),
    '[]'::jsonb
  )
  into v_templates
  from (
    select *
    from public.rr_report_template_registry_v806
  ) x;


  v_report_objects:=jsonb_build_object(

    'TRIAL_BALANCE',
      jsonb_build_object(
        'runner','rr_trial_balance_v806',
        'requires_from_date',true,
        'requires_to_date',true,
        'requires_ledger',false
      ),

    'PROFIT_LOSS',
      jsonb_build_object(
        'runner','rr_profit_loss_v806',
        'requires_from_date',true,
        'requires_to_date',true,
        'requires_ledger',false
      ),

    'BALANCE_SHEET',
      jsonb_build_object(
        'runner','rr_balance_sheet_v806',
        'requires_as_of_date',true,
        'requires_ledger',false
      ),

    'LEDGER_STATEMENT',
      jsonb_build_object(
        'runner','rr_ledger_statement_v806',
        'requires_from_date',true,
        'requires_to_date',true,
        'requires_ledger',true
      ),

    'DAY_BOOK',
      jsonb_build_object(
        'runner','rr_day_book_v806',
        'requires_from_date',true,
        'requires_to_date',true,
        'requires_ledger',false
      )
  );


  return jsonb_build_object(

    'ok',true,

    'ui',jsonb_build_object(
      'title','Reports',
      'search_placeholder',
        'Ask anything or search reports…',
      'show_template_suggestions',true,
      'show_question_analysis',true,
      'show_recent_reports',true,
      'default_data_mode','TEST'
    ),

    'templates',v_templates,

    'report_objects',v_report_objects,

    'query',v_q,

    'capabilities',jsonb_build_object(
      'template_reports',true,
      'natural_language_questions',true,
      'live_suggestions',true,
      'intent_detection',true,
      'dynamic_filters',true,
      'universal_report_runner',true,
      'accounts_analysis',true
    )

  );

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_integration_v806(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_integration_v806(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_ledger_search_v807(p_search_text text DEFAULT NULL::text, p_limit integer DEFAULT 30)
 RETURNS TABLE(ledger_id uuid, ledger_code text, ledger_name text, ledger_kind text, category_code text, group_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY select
    l.id,
    l.ledger_code,
    l.ledger_name,
    l.ledger_kind,
    c.category_code,
    g.group_code

  from public.rr_ledgers_v805 l

  join public.rr_account_categories_v805 c
    on c.id=l.category_id

  join public.rr_account_groups_v805 g
    on g.id=c.group_id

  where l.is_active

    and (
      nullif(trim(coalesce(p_search_text,'')),'') is null

      or lower(l.ledger_name)
           like '%'||lower(trim(p_search_text))||'%'

      or lower(coalesce(l.ledger_code,''))
           like '%'||lower(trim(p_search_text))||'%'
    )

  order by l.ledger_name

  limit greatest(
    1,
    least(coalesce(p_limit,30),100)
  );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_ledger_search_v807(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_ledger_search_v807(text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_question_v807(p_question_text text, p_data_mode text DEFAULT 'TEST'::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_question text:=trim(coalesce(p_question_text,''));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_context jsonb;
  v_suggestions jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  if v_question='' then
    raise exception 'Question required.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);

  v_context:=
    public.rr_report_question_context_v807(
      v_question,
      v_mode,
      p_from_date,
      p_to_date
    );

  v_suggestions:=
    public.rr_report_ui_search_v807(
      v_question,
      5
    );

  return jsonb_build_object(
    'ok',true,
    'question',v_question,
    'data_mode',v_mode,

    'context',v_context,

    'suggested_reports',
      coalesce(
        v_suggestions->'suggestions',
        '[]'::jsonb
      ),

    'answer_mode','ANALYZE_CONTEXT',

    'ui_instruction',
      'Show direct analytical answer first, then relevant template report suggestions.'
  );
end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_question_v807(text,text,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_question_v807(text,text,date,date) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_run_v807(p_report_code text, p_data_mode text DEFAULT 'TEST'::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_as_of_date date DEFAULT NULL::date, p_ledger_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code text:=upper(trim(coalesce(p_report_code,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));

  v_from date:=coalesce(
    p_from_date,
    date_trunc('month',current_date)::date
  );

  v_to date:=coalesce(p_to_date,current_date);
  v_asof date:=coalesce(p_as_of_date,current_date);

  v_rows jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  if v_mode not in ('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);


  -- ----------------------------------------------------------
  -- PROFIT & LOSS
  -- ----------------------------------------------------------
  if v_code in(
    'PROFIT_LOSS',
    'PROFIT_AND_LOSS',
    'INCOME_EXPENDITURE',
    'INCOME_AND_EXPENDITURE'
  ) then

    return jsonb_build_object(
      'ok',true,
      'report_code','PROFIT_LOSS',
      'result',
        public.rr_profit_loss_v806(
          v_from,
          v_to,
          v_mode
        )
    );


  -- ----------------------------------------------------------
  -- BALANCE SHEET
  -- ----------------------------------------------------------
  elsif v_code='BALANCE_SHEET' then

    return jsonb_build_object(
      'ok',true,
      'report_code','BALANCE_SHEET',
      'result',
        public.rr_balance_sheet_v806(
          v_asof,
          v_mode
        )
    );


  -- ----------------------------------------------------------
  -- TRIAL BALANCE
  -- ----------------------------------------------------------
  elsif v_code='TRIAL_BALANCE' then

    select coalesce(
      jsonb_agg(to_jsonb(x)),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_trial_balance_v806(
      v_from,
      v_to,
      v_mode
    ) x;

    return jsonb_build_object(
      'ok',true,
      'report_code','TRIAL_BALANCE',
      'from_date',v_from,
      'to_date',v_to,
      'data_mode',v_mode,
      'rows',v_rows
    );


  -- ----------------------------------------------------------
  -- DAY BOOK
  -- ----------------------------------------------------------
  elsif v_code='DAY_BOOK' then

    select coalesce(
      jsonb_agg(to_jsonb(x)),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_day_book_v806(
      v_from,
      v_to,
      v_mode
    ) x;

    return jsonb_build_object(
      'ok',true,
      'report_code','DAY_BOOK',
      'from_date',v_from,
      'to_date',v_to,
      'data_mode',v_mode,
      'rows',v_rows
    );


  -- ----------------------------------------------------------
  -- LEDGER STATEMENT
  -- ----------------------------------------------------------
  elsif v_code='LEDGER_STATEMENT' then

    if p_ledger_id is null then
      raise exception 'Ledger required for Ledger Statement.';
    end if;

    select coalesce(
      jsonb_agg(to_jsonb(x)),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_ledger_statement_v806(
      p_ledger_id,
      v_from,
      v_to,
      v_mode
    ) x;

    return jsonb_build_object(
      'ok',true,
      'report_code','LEDGER_STATEMENT',
      'ledger_id',p_ledger_id,
      'from_date',v_from,
      'to_date',v_to,
      'data_mode',v_mode,
      'rows',v_rows
    );

  else
    raise exception 'Unsupported Report Code: %',v_code;
  end if;

end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_run_v807(text,text,date,date,date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_run_v807(text,text,date,date,date,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_search_v807(p_search_text text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_q text:=trim(coalesce(p_search_text,''));
  v_limit integer:=greatest(1,least(coalesce(p_limit,8),20));
  v_results jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();

  if v_q='' then
    return jsonb_build_object(
      'ok',true,
      'query','',
      'suggestions','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'report_code',x.report_code,
        'report_name',x.report_name,
        'report_family',x.report_family,
        'description',x.description,
        'score',x.match_score,
        'requires_ledger',x.requires_ledger
      )
      order by x.match_score desc,x.report_name
    ),
    '[]'::jsonb
  )
  into v_results
  from public.rr_report_search_suggest_v807(
    v_q,
    v_limit
  ) x;

  return jsonb_build_object(
    'ok',true,
    'query',v_q,
    'suggestions',v_results
  );
end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_search_v807(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_search_v807(text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_report_ui_search_v807(p_search_text text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_q text:=trim(coalesce(p_search_text,''));
  v_templates jsonb;
begin
 PERFORM public.rr_accounts_report_access_assert_test71();
  perform public.rr_app_data_mode_assert_v786(v_mode);

  if v_q='' then
    return jsonb_build_object(
      'ok',true,
      'query','',
      'suggestions','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
  into v_templates
  from public.rr_report_search_v807(v_q,8) x;

  return jsonb_build_object(
    'ok',true,
    'query',v_q,
    'data_mode',v_mode,
    'suggestions',v_templates,

    'show_question_action',true,
    'question_action_label',
      concat('“',v_q,'” का analysis करें')
  );
end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_report_ui_search_v807(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_report_ui_search_v807(text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_trial_balance_v806(p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(ledger_id uuid, ledger_code text, ledger_name text, category_code text, group_code text, total_debit numeric, total_credit numeric, closing_debit numeric, closing_credit numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 RETURN QUERY with x as (
    select
      b.ledger_id,
      b.ledger_code,
      b.ledger_name,
      b.category_code,
      b.group_code,
      sum(coalesce(b.dr_amount,0)) as dr,
      sum(coalesce(b.cr_amount,0)) as cr
    from public.rr_account_reporting_base_v806 b
    where b.data_mode=upper(coalesce(p_data_mode,'TEST'))
      and b.created_at::date between p_from_date and p_to_date
      and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')
    group by
      b.ledger_id,
      b.ledger_code,
      b.ledger_name,
      b.category_code,
      b.group_code
  )
  select
    ledger_id,
    ledger_code,
    ledger_name,
    category_code,
    group_code,
    round(dr,2),
    round(cr,2),
    round(greatest(dr-cr,0),2),
    round(greatest(cr-dr,0),2)
  from x
  where abs(dr-cr)>0.005
  order by group_code,ledger_name;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_trial_balance_v806(date,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_trial_balance_v806(date,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_material_opening_balance_v664(p_material_id uuid, p_qty_consumption numeric, p_total_value numeric, p_as_of date, p_data_mode text DEFAULT 'TEST'::text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record;ref text:=coalesce(nullif(trim(p_reference),''),'OPENING-BALANCE-'||p_material_id::text||'-'||to_char(p_as_of,'YYYYMMDD'));rate numeric;
begin
 if auth.uid() is null or not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.' using errcode='42501'; end if;
 if upper(p_data_mode) not in('TEST','REAL') then raise exception 'Invalid data mode';end if;if coalesce(p_qty_consumption,0)<=0 or coalesce(p_total_value,0)<0 then raise exception 'Opening qty/value required';end if;select * into m from public.rr_material_master_v805 where id=p_material_id and is_active;if not found then raise exception 'Material not found';end if;rate:=p_total_value/p_qty_consumption;
 if exists(select 1 from public.rr_material_purchases_v805 where material_id=p_material_id and upper(data_mode)=upper(p_data_mode) and source_record_id=ref) then return jsonb_build_object('ok',true,'duplicate_blocked',true,'reference',ref);end if;
 insert into public.rr_material_purchases_v805(material_id,purchase_qty,purchase_unit,base_qty,rate_per_purchase_unit,taxable_value,gst_amount,total_value,bill_no,bill_date,payment_status,paid_amount,source_module,source_record_id,data_mode,stock_qty,stock_unit,consumption_equivalent_qty,consumption_equivalent_unit,current_cost_per_consumption_unit,costing_value,running_weighted_avg_cost_per_consumption_unit)
 values(m.id,p_qty_consumption,m.consumption_unit,p_qty_consumption*coalesce(m.consumption_to_base,1),rate,p_total_value,0,p_total_value,ref,p_as_of,'OPENING',0,'MATERIAL_OPENING_BALANCE',ref,upper(p_data_mode),p_qty_consumption*coalesce(m.consumption_to_base,1),m.base_stock_unit,p_qty_consumption,m.consumption_unit,rate,p_total_value,rate);
 return jsonb_build_object('ok',true,'version','V664_MATERIAL_OPENING_BALANCE','material',m.material_name,'opening_qty',p_qty_consumption,'unit',m.consumption_unit,'opening_value',p_total_value,'opening_rate',rate,'reference',ref,'duplicate_blocked',false);
end $function$
;
REVOKE EXECUTE ON FUNCTION public.rr_material_opening_balance_v664(uuid,numeric,numeric,date,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_material_opening_balance_v664(uuid,numeric,numeric,date,text,text) TO authenticated;
COMMIT;

