Hi @channel, quick update before today's meeting.

The 0-RTT pipeline is working end-to-end at validation scale and the 0-RTT latency saving is confirmed (~1 RTT saved per connection). There's still one open issue: high flow-completion time (likely retransmissions in the translated data path) that I need to fix before the results are meaningful at scale.

Since I won't have that fixed in time, I'd suggest we cancel today's meeting. I'll focus on the repair, then come back with results at a much larger connection scale plus a comparison across the infra types. That'll make for a much more useful discussion. I'll share an updated brief and propose a new time once I have those numbers. Full detail below for reference. Thanks for understanding!

---

Quick status on the 0-RTT experiment:

*Run config (validation scale)*
This was a *small validation run, not the target scale* — goal was to confirm the pipeline works end-to-end before scaling up.
• Connections: *100* total, *100 in parallel* (1 round, ~25 across each of 4 ports), 1 MB each
• Target for the real benchmark: *100,000* connections (not yet run)
• Emulated network: 50 ms each way (~100 ms RTT); TCP timestamps/WS/SACK and NIC offloads off

*Results (n=100)*
• *Client delta* (SYN → first byte sent): mean *12.6 ms* (min 0.27, max 30)
• *Server delta* (server's SYN-ACK → first client data in): mean *165 ms* (bimodal: ~5–25 ms or ~210–238 ms)
• *FCT* (full 1 MB transfer): mean *13.5 s* (min 5.3 s, max 38.5 s)

*Working*
• 0-RTT confirmed: client unblocked in ~12 ms vs ~100 ms baseline → *~1 RTT (~90 ms) saved per connection*
• DPDK data plane stable; seq/ack translation correct enough to complete all 100 connections and move full payloads
• Automated end-to-end test passing

*Needs repair — high FCT*
• 1 MB takes 5–38 s (should be ~0.5–2 s); throughput only 0.26–1.17 Mbit/s
• Looks like packet loss in the translated path → TCP retransmission stalls (the bimodal server delta is the tell-tale)
• Distinct from the 0-RTT mechanism, which works. Next step: isolate the cause (single-flow / no-netem runs, audit ServerNIC translation + checksums), fix, then scale toward 100k