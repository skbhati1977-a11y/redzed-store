REDZED V720.37.5 — INDIVIDUAL MULTI LOT CARDS

PURPOSE
Multi release के बाद 2NSKB1 और 2NSKB2 अब combined display नहीं रहेंगे.
हर Lot अलग card में दिखेगा:
- अपना Lot No
- अपना D1A / D1B code
- अपनी Pcs
- अपना Cost
- अपना independent downstream note

HOW TO APPLY
1. इस ZIP को GitHub repository folder में extract करें.
2. सुनिश्चित करें कि latest file का नाम है:
   real-cutting-master-pm.V719.3.js
3. Windows CMD / Terminal में चलाएँ:
   node patch-individual-multi-lot-cards.js real-cutting-master-pm.V719.3.js
4. Output PATCHED_OK आना चाहिए.
5. Updated JS GitHub पर upload/commit करें.
6. real-cutting-master.html में JS cache version ?v=720375 करें.
7. Page खोलकर Ctrl+F5 करें.

BACKUP
Patcher अपने-आप backup बनाएगा:
real-cutting-master-pm.V719.3.js.backup-v720375

IMPORTANT
Database में Multi Lots पहले से rr_production_lots में individual records हैं.
यह patch combined frontend display को individual production cards में बदलता है.
