begin;

-- Keep the newest editable PI and retain older duplicates as auditable cancelled records.
with ranked as (
  select id,row_number() over(partition by market_requirement_id order by created_at desc,id desc) rn
  from public.rr_fg_pi_v787
  where market_requirement_id is not null and status='DRAFT'
)
update public.rr_fg_pi_v787 p set status='CANCELLED',updated_at=now()
from ranked r where p.id=r.id and r.rn>1;

create unique index if not exists rr_fg_pi_one_draft_per_requirement_v9747
on public.rr_fg_pi_v787(market_requirement_id)
where market_requirement_id is not null and status='DRAFT';

commit;
