---
type: Log
title: "zero-rtt-tcp Wiki Log"
description: "Append-only record of mutations made to the zero-rtt-tcp llm-wiki vault."
tags: [log]
timestamp: 2026-08-08T00:00:00+03:00
---

# Log

- 2026-08-08T00:00:00+03:00 — refactor — bootstrapped the vault from scattered repo docs: 52 living docs copied into `wiki/` (project docs, 8 component READMEs, 2 infra architecture docs, hermes overview, 37 BlueField-3 docs/examples/setup), 19 dated experiment reports moved into `raw/` (`experiments/archive/`, `experiments/baseline-tcp/reports/`, `experiments/dpdk/reports/`), `capacity-model.md` (pre-existing in the vault root from a manual move) relocated to `wiki/Capacity Model.md` and given frontmatter; `index/index.md` and this log created. Excluded by design: `.claude/skills/**`, `openspec/**`, `hermes/*/SOUL.md`, `CLAUDE.md` — each is read by exact path by other tooling. Updated `CLAUDE.md`'s `docs/capacity-model.md` reference to point at the new location.
- 2026-08-08T18:55:15+03:00 — ingest — [[raw/2026-08-08-telemetry-review-artifact]] → created [[wiki/Load Generation and Think Time]] and [[wiki/FCT Tail Investigation]]; re-synced [[wiki/Measurement Methodology]] (new §E: emulated WAN, netem/qdisc mechanics, four-placement proof that only the ClientNIC↔ServerNIC leg can show an FCT win) and [[wiki/Roadmap]] (new F2–F16 measurement-flaw classification; F1/FCT-tail removed from the roadmap and carried to `HANDOFF-fct-tail.md`); index updated. Vault was not registered with the obsidian CLI (find_vault.sh exit 3), so notes were written directly — no moves were involved, so no wikilink rewriting was at risk.
