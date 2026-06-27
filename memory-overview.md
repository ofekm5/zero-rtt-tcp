# Memory Overview — zero-rtt-demo

Snapshot of the persistent project memory (stored under
`~/.claude/projects/C--Users-shir-Documents-GitHub-zero-rtt-demo/memory/`).
Generated 2026-06-28.

| Memory | Type | Summary |
|--------|------|---------|
| `dpdk-100k-scale-blocker` | project | GRO loss bug **fixed**; t3.micro (1 GB) Client/Server endpoints OOM below 10k connections — upsize instances to reach 10k/100k. |
| `ultracode-vs-goal-token-efficiency` | feedback | Workflow/ultracode is cheap for breadth (~1.2M tok / 32 agents / 5 min) but confirm its findings with direct evidence before shipping. |

---

## dpdk-100k-scale-blocker (project)

**Loss bug — FIXED (2026-06): GRO on the AF_PACKET ingress NICs.**
ClientNIC `eth0` / ServerNIC `eth2` had GRO enabled, coalescing the client's TCP
segments into >2048-byte super-frames that every data-plane copy site
(`uint8_t buf[2048]; if (len > sizeof(buf)) return;`) silently dropped → ~200 ms
RTO retransmits (bimodal `server_gap`). Fix: disable gro/lro on those interfaces
+ advertise MSS 1460 in the spoofed SYN-ACK. 100-conn run is clean
(`server_gap` ~18 ms, FCT ~0.7 s).

**Scale blocker (ongoing): Client + Server are t3.micro (1 GB RAM).**
iperf2 is thread-per-connection; at 10k the client stalls (~275 opened) and the
Server OOMs into an `impaired` state (needs reboot). Data-plane scale fixes are
done (flow table 1024→262144, sysctls, retry cap).

**How to proceed:** upsize Client+Server endpoints (`infra/dpdk/cdk/smartnics_stack.py`,
t3.micro → ~m5.2xlarge) for 10k; for true 100k also upsize the c5n.large NICs
(single DPDK lcore + AF_PACKET syscall-per-packet is the next ceiling) and/or move
to PACKET_MMAP / multi-queue. Always `git push` before a run — VMs `reset --hard
origin/main`.

---

## ultracode-vs-goal-token-efficiency (feedback)

The audit workflow (`dpdk-loss-rootcause`) cost **32 agents / ~1.21M subagent
tokens / 186 tool uses / ~5 min** for a 6-dimension parallel audit + adversarial
verify — cheap for the breadth it buys, because a bounded fan-out has a
predictable one-shot cost. The iterative /goal main-loop work spread tokens
across many read→run→inspect turns (and full-context re-reads after long sleeps),
so it *felt* heavier.

**Caveat:** the workflow's top "confirmed" findings (egress EAGAIN drops, poll
starvation) were plausible-but-wrong; the real cause (GRO coalescing) was found
afterward via **pcap inspection**. Pattern to apply: use ultracode for the wide
hypothesis sweep, then **confirm with direct evidence (pcaps/logs) before
committing fixes**. Mind prompt-cache windows — ScheduleWakeup sleeps >300 s force
full-context re-reads.

---

### Related artifacts (not in memory)
- Session handoff: `%TEMP%\handoff-dpdk-100k-scale-2026-06-28.md`
- Code fixes: commits `751c307`..`32ce593` on `origin/main`
- Run evidence: `experiments/dpdk/reports/`
