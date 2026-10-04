# TEST71 outside-share Collection routing fix

The public portal opened correctly, but outside shares created by rr_market_create_share_v9420 had neither origin route nor Collection cycle. The direct submission wrapper rejected them before the existing generic adoption path could run.

The direct wrapper now adopts only unrouted TEST shares into the existing customer/chat/cycle model, under a share row lock. It uses existing customer registration and direct chat identity checks, rejects mismatched customers/chats and distributor-linked shares, then retains the original submission and canonical single-card consolidation. Already-routed links retain their strict routing guard. No price, stock or costing rules changed.

Applied to Supabase. Live outside-share fixture tested under anon role inside a rolled-back transaction: first submission succeeded; repeat reused the same requirement; exactly one active requirement card; share bound to the same direct chat. Existing customer login and function grants unchanged. Phone UI submit still needs customer retry.
