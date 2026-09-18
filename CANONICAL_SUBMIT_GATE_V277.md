# V277 Canonical Submit Gate
Backend migration canonical_submit_gate_v277 applied.
Single submit path:
Submit -> V760 Actual Rate Gate -> V276 consolidated alert when missing -> receiver list -> V204 canonical handover.
RPCs:
- rr_upm_submit_gate_v277: returns FULFIL_RATE_ALERT or SELECT_RECEIVER with canonical Line Man/Packer candidates.
- rr_upm_ready_submit_canonical_v277: rechecks the same gate, canonicalizes selected receiver through V264, then calls V204 submit handover.
Frontend/App/Real Chat must call these same V277 RPCs; no separate rate/receiver rule is allowed.
Rate authority remains V760. Alert projection remains V276. Worker identity remains V264.
