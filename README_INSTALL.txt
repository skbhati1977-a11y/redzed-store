REDZED UPM SMART PACKING V1

1. Take Supabase backup.
2. Run REDZED_UPM_SMART_PACKING_V1.sql.
3. Upload redzed-upm-smart-packing-v1.js.
4. Replace/open real-universal-production-v72041.html.
5. Keep existing real-universal-production-v72040.js unchanged.

Locked rule:
- Carton capacity 18 PCS.
- Fresh boxes first: all colours × all sizes.
- Remaining standard boxes: SIZE-FIRST, 18 PCS exact, maximum colours first, then duplicates from highest balance.
- Remainder 1–9 merges with the final 18-PCS base box and becomes MIX (e.g. 26 PCS).
- Worker sees only the generated table and submits that exact plan.
- Submit is blocked unless packed cell total equals source total.

Test matrix for the 620 PCS example:
[
 {"colour_code":"C1","size_code":"Size 1","qty":34},{"colour_code":"C1","size_code":"Size 2","qty":28},{"colour_code":"C1","size_code":"Size 3","qty":39},
 {"colour_code":"C2","size_code":"Size 1","qty":36},{"colour_code":"C2","size_code":"Size 2","qty":26},{"colour_code":"C2","size_code":"Size 3","qty":28},
 {"colour_code":"C3","size_code":"Size 1","qty":33},{"colour_code":"C3","size_code":"Size 2","qty":42},{"colour_code":"C3","size_code":"Size 3","qty":39},
 {"colour_code":"C4","size_code":"Size 1","qty":24},{"colour_code":"C4","size_code":"Size 2","qty":36},{"colour_code":"C4","size_code":"Size 3","qty":33},
 {"colour_code":"C5","size_code":"Size 1","qty":36},{"colour_code":"C5","size_code":"Size 2","qty":36},{"colour_code":"C5","size_code":"Size 3","qty":36},
 {"colour_code":"C6","size_code":"Size 1","qty":38},{"colour_code":"C6","size_code":"Size 2","qty":38},{"colour_code":"C6","size_code":"Size 3","qty":38}
]
