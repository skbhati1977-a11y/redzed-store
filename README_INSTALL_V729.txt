REDZED UPM V729 — LOCKED ALTER / REMAKE RESPONSIBILITY
======================================================

FILES
1. REDZED_UPM_V729_LOCKED.sql
2. real-universal-production-v729.html
3. real-universal-production-v729.js
4. REDZED_IDENTITY_MAPPING_SOURCE_EXPORT.sql

INSTALL ORDER
1. Take Supabase backup.
2. Run REDZED_UPM_V729_LOCKED.sql in Supabase SQL Editor.
3. Upload HTML and JS to the same site folder as config.js and real-common.js.
4. Open real-universal-production-v729.html and hard refresh.

LOCKED FLOW
- Alter Fill: mapped Department Line Man only; 1–3 live camera images and physical evidence mandatory.
- Alter debit: mapped Cutting Master.
- Remake Issue: mapped Cutting Master only; responsibility moves to mapped Line Man.
- Remake Delivered: mapped Line Man only; responsibility moves to current mapped Worker/Karigar.
- Remake Submit: mapped Worker/Karigar only; quantity returns to Good through existing REMAKE_COMPLETE action and responsibility becomes NONE.
- Missing Worker, Line Man or Cutting Master mapping blocks the action with exact create-and-assign message.
- No manual person name, sample UUID or fallback person is accepted.

IMPORTANT IDENTITY NOTE
The supplied backend export does not contain the exact Product Master / Art Master / Print Master / Cutting identity source table definitions. Therefore this package adds ART NO, PRINT NO and FRAME NO display fields but intentionally does not invent joins or columns. Missing values show MAPPING REQUIRED instead of a guessed value.

Run REDZED_IDENTITY_MAPPING_SOURCE_EXPORT.sql and provide its single JSON result. The final identity RPC can then be written against the exact live Art → Print → Product → Cutting mapping without guessed table or field names.

VALIDATION PERFORMED
- JavaScript passed node --check.
- HTML parsed successfully.
- SQL is additive and keeps existing V726/V727 action accounting functions.
- Live Supabase execution was not available here; test on backup/test project first.
