BEGIN;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
INSERT INTO public.rr_regular_attendance_sessions_v778_2(worker_id,business_date,checkin_at,checkout_at,checkin_latitude,checkin_longitude,checkin_inside_geofence,source_checkin_id,data_mode,forgot_checkout)
VALUES('3cb8f1b4-74ab-4230-b2fb-4ebed6826249',(now() AT TIME ZONE 'Asia/Kolkata')::date-1,now()-interval '1 day',now()-interval '1 day',28.662889,77.259056,true,gen_random_uuid()::text,'TEST',true);
DO $$DECLARE q jsonb; BEGIN q:=public.rr_chat_attendance_queue_test71(null,'3cb8f1b4-74ab-4230-b2fb-4ebed6826249');ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(q->'cards')c WHERE c->>'status'='REVIEW_REQUIRED' AND c->>'chat_status'='OPEN'),'Forgotten checkout must stay in review OPEN';END $$;
SELECT true forgotten_review_open;ROLLBACK;