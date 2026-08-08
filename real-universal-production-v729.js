<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>REDZED REAL — Cutting Master & Production Board</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        body { background-color: #121212; color: #ffffff; padding: 20px; }
        .header-panel { display: flex; justify-content: space-between; align-items: center; background: #1e1e24; padding: 15px 20px; border-radius: 8px; margin-bottom: 20px; border: 1px solid #333; }
        .header-title { font-size: 20px; font-weight: bold; color: #ffffff; }
        .dept-filter-box { display: flex; align-items: center; gap: 10px; }
        .dept-select { background: #2a2a35; color: #00ffcc; border: 1px solid #444; padding: 10px 15px; border-radius: 6px; font-size: 14px; font-weight: bold; outline: none; cursor: pointer; }
        .board-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 15px; margin-top: 10px; }
        
        /* Modal & Message Styling */
        .status-box-green { display: none; background: #2ecc71; color: #ffffff; padding: 12px; border-radius: 6px; font-weight: bold; margin-top: 15px; text-align: center; font-size: 14px; }
        .status-box-red { display: none; background: #e74c3c; color: #ffffff; padding: 12px; border-radius: 6px; font-weight: bold; margin-top: 15px; text-align: center; font-size: 14px; }
    </style>
    <!-- Supabase JS Client -->
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
</head>
<body>

    <!-- Top Navigation & Department Selector -->
    <div class="header-panel">
        <div class="header-title">
            REDZED REAL <span style="color: #e74c3c;">— Production Board</span>
        </div>
        <div class="dept-filter-box">
            <label for="dept-select-filter" style="font-size: 14px; color: #bbb;">Select Department / Queue:</label>
            <select id="dept-select-filter" class="dept-select">
                <option value="OPEN_RANDOM_QUEUE" selected>OPEN RANDOM QUEUE</option>
                <option value="ALL">ALL DEPARTMENTS (Read-Only)</option>
                <option value="PRINTING">PRINTING</option>
                <option value="KAAJ">KAAJ</option>
                <option value="PRESS">PRESS</option>
                <option value="PACKING">PACKING</option>
            </select>
        </div>
    </div>

    <!-- Status Message Notification Box -->
    <div id="status-message-green" class="status-box-green"></div>
    <div id="status-message-red" class="status-box-red"></div>

    <!-- Main Production Board Cards Container -->
    <div id="board-container" class="board-grid">
        <!-- Dynamic Cards Loaded from real-universal-production-v729.js -->
    </div>

    <!-- Supabase Setup & Automatic Release Handler -->
    <script>
        // Universal Supabase Client Check
        if (typeof supabase === 'undefined' && typeof supabaseClient !== 'undefined') {
            window.supabase = supabaseClient;
        }

        // Direct Release & Open Random Queue Mapping Function
        async function releaseLotToOpenQueue(lotId, lotNo) {
            const greenBox = document.getElementById('status-message-green');
            const redBox = document.getElementById('status-message-red');
            
            if (redBox) redBox.style.display = 'none';

            try {
                // Update status in rr_cutting_lots_v3
                const { error } = await supabase
                    .from('rr_cutting_lots_v3')
                    .update({ status: 'released', updated_at: new Date().toISOString() })
                    .eq('id', lotId);

                if (error) {
                    if (redBox) {
                        redBox.innerText = "Error releasing lot: " + error.message;
                        redBox.style.display = 'block';
                    }
                    return;
                }

                // Show Green Success Banner
                if (greenBox) {
                    greenBox.innerText = `Lot ${lotNo} Successfully Released — Open Random Queue Mapped!`;
                    greenBox.style.display = 'block';
                    
                    setTimeout(() => {
                        greenBox.style.display = 'none';
                    }, 3000);
                }

                // Refresh Board automatically
                if (typeof loadOpenRandomQueue === 'function') {
                    loadOpenRandomQueue();
                }

            } catch (err) {
                console.error("Release Handler Exception:", err);
            }
        }
    </script>

    <!-- Main JS Engine -->
    <script src="real-universal-production-v729.js"></script>

</body>
</html>
