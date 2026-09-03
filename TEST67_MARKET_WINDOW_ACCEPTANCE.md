# TEST67 Market Window acceptance checklist

1. Enable a TEST customer as distributor with a unique prefix through `rr_market_configure_distributor_v67`.
2. Open the distributor page from that customer's valid secure collection link.
3. Create Shyam, Ram and Ghanshyam; confirm private IDs are generated.
4. Create orders for different customers and confirm order refs increase owner-wide, not customer-wise.
5. Add the same article to multiple orders with different quantities and rate enhancements.
6. Submit selected orders in one batch; leave one READY order unselected.
7. In staff review, confirm names/mobiles are absent and only private Customer IDs are shown.
8. Confirm customer-wise order detail and article-wise customer/order/quantity totals.
9. Enter adjusted quantities and PI reference; verify distributor receives WAITING confirmation.
10. Confirm one order, change one quantity and cancel one order; verify consolidated confirmed totals.
11. Finalize upstream CI; convert confirmed orders to customer-wise CIs and verify enhanced customer rates.
12. Verify staff cancellation cascades before CI finalization and no TEST67 RPC accepts REAL mode.
