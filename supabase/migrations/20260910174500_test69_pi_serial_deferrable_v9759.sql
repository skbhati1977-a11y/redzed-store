-- V9759: allow an atomic multi-row serial renumber while preserving uniqueness.
begin;
drop index if exists public.rr_fg_pi_lines_v787_pi_serial_uq;
alter table public.rr_fg_pi_lines_v787 drop constraint if exists rr_fg_pi_lines_v787_pi_serial_uq;
alter table public.rr_fg_pi_lines_v787 add constraint rr_fg_pi_lines_v787_pi_serial_uq
 unique(pi_id,serial_no) deferrable initially immediate;
commit;
