-- TEST67 only: let an authenticated distributor render each private customer
-- journey from the established REDZED -> customer core view. The share token
-- remains server-side and is never returned to the distributor browser.

create or replace function public.rr_market_partner_sender_core_views_v81(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer public.rr_market_partner_customer_v67%rowtype;
  v_item record;
  v_view jsonb;
  v_views jsonb := '[]'::jsonb;
begin
  v_ctx := public.rr_market_partner_context_v67(
    p_session_token,
    p_device_id
  );
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;

  select c.*
  into v_customer
  from public.rr_market_partner_customer_v67 c
  where c.id = p_partner_customer_id
    and c.owner_customer_id = v_owner
    and c.status = 'ACTIVE';

  if v_customer.id is null then
    raise exception 'Selected distributor customer is unavailable.';
  end if;

  for v_item in
    with ranked_share as (
      select
        coalesce(pc.root_collection_id, pc.id) as root_collection_id,
        pc.collection_no,
        pc.collection_update_no,
        pc.created_at,
        s.token,
        row_number() over (
          partition by coalesce(pc.root_collection_id, pc.id)
          order by pc.collection_update_no desc, pc.created_at desc
        ) as rank_no
      from public.rr_market_partner_collection_v67 pc
      join public.rr_market_share_v9420 s on s.id = pc.share_id
      where pc.owner_customer_id = v_owner
        and pc.partner_customer_id = v_customer.id
        and v_customer.data_mode = 'TEST'
        and pc.status <> 'CANCELLED'
        and not pc.legacy_hidden_v78
        and s.status = 'ACTIVE'
        and s.data_mode = 'TEST'
    )
    select
      root_collection_id,
      collection_no,
      collection_update_no,
      created_at,
      token
    from ranked_share
    where rank_no = 1
    order by collection_no desc, created_at desc
  loop
    -- This is the same source of truth used by the direct REDZED customer
    -- page. It already folds collection updates into one cumulative root,
    -- keeps the latest requirement snapshot, and maps PI / CI visibility.
    v_view := public.rr_market_share_view_v9420(v_item.token);
    v_views := v_views || jsonb_build_array(
      jsonb_build_object(
        'root_collection_id', v_item.root_collection_id,
        'collection_no', v_item.collection_no,
        'latest_update_no', v_item.collection_update_no,
        'created_at', v_item.created_at,
        'view', v_view
      )
    );
  end loop;

  return jsonb_build_object(
    'partner_customer_id', v_customer.id,
    'views', v_views
  );
end;
$$;

revoke all on function public.rr_market_partner_sender_core_views_v81(
  text,
  text,
  uuid
) from public;

grant execute on function public.rr_market_partner_sender_core_views_v81(
  text,
  text,
  uuid
) to anon, authenticated, service_role;

-- `s.html` is also used by the established direct REDZED customer flow.
-- Return only the relation kind so the page can load the partner privacy
-- adapters when required without exposing any owner/customer identifiers.
create or replace function public.rr_market_share_relation_v81(
  p_token text
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1
      from public.rr_market_share_v9420 s
      join public.rr_market_partner_collection_v67 pc on pc.share_id = s.id
      join public.rr_market_partner_customer_v67 c
        on c.id = pc.partner_customer_id
       and c.owner_customer_id = pc.owner_customer_id
      where (s.token = p_token or s.short_code = upper(p_token))
        and s.status = 'ACTIVE'
        and s.data_mode = 'TEST'
        and pc.status <> 'CANCELLED'
        and not pc.legacy_hidden_v78
        and c.status = 'ACTIVE'
        and c.data_mode = 'TEST'
    ) then 'DISTRIBUTOR_CUSTOMER'
    else 'REDZED_CUSTOMER'
  end;
$$;

revoke all on function public.rr_market_share_relation_v81(text) from public;
grant execute on function public.rr_market_share_relation_v81(text)
  to anon, authenticated, service_role;
