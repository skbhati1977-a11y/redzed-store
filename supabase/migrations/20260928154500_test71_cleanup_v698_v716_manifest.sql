-- TEST71 canonical cleanup continuation V698-V716
-- Backend-applied authority manifest; substantive definitions are live in TEST71 Supabase and guarded here for branch parity.
-- Materials: Kandhi ALL/BOM_AUTO 0.3 MTR; raw BOM aggregate V701; Thread fixed FOC policy.
-- FOC V705: Electricity 1.50, Thread 1.50, Water .50, Repairs 1.00, Lapse Salary 1.00 = 5.50/pc.
-- Product cost V709 includes FOC exactly once; actual overhead/lapse analytics do not double count.
-- Monthly FOC V710/V713; cron V711 runs 02:30 UTC on day 2 (=08:00 IST); canonical worker identity V712.
-- Targeted web push V708; Real Chat route V713; Final Rate push V714.
-- Lifecycle compatibility: V327/V328 -> V690; finalize V327 -> V689.
select 1;
