REAL FACTORY PACKING V808_2 FRONTEND FINAL

BACKEND REQUIRED:
PACKING_AI_MEDIA_V808_2 = PASS

REPLACE TOGETHER:
- real-finished-goods-v787.html
- real-finished-goods-v787.js

ADDITIVE ONLY:
- Existing Packing/Box Material/Submit Packing unchanged
- 1–4 Packing Final Images upload to existing product-images bucket
- rr_media_ai_add_source_v808
- 5 AI image generation through real-factory-ai
- generated images stored in product-images
- rr_media_ai_register_variants_v808
- Admin Accept / Regenerate / Compare / Print A4 / Publish
- rr_media_ai_admin_decide_v808
- rr_media_ai_publish_v808
- Lot state from rr_media_ai_lot_state_v808
- Same Lot No locked through every RPC
- TEST only

AI generation uses the uploaded source set round-robin across outputs without changing the existing Edge Function.
Original Final Images are never overwritten.

OPEN:
real-finished-goods-v787.html?view=packing&v=8082F1
