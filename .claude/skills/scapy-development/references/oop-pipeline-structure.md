# OOP Pipeline Structure

> How to organise a Scapy middlebox as composable OOP classes that follow the Parse → Decide → Modify pattern and remain portable to DPDK/eBPF.

---

## Module Layout

Split source into two top-level packages inside `src/`:

```
src/
├── utils/          # shared infrastructure — imported by >1 module
│   ├── flow_table.py   # FlowKey, FlowEntry, FlowTable
│   ├── buffer.py       # PacketBuffer (thread-safe)
│   ├── tx.py           # send_spoofed / forward / forward_rewritten
│   └── logger.py       # setup_logging()
└── pipeline/       # processing logic — one class per packet type / role
    ├── dispatcher.py       # Dispatcher — single entry point
    ├── syn_handler.py      # SynHandler
    ├── syn_ack_handler.py  # SynAckHandler
    ├── translator.py       # Translator (data path, both directions)
    └── spoofer.py          # SynAckSpoofer
```

**Rule:** if a module is imported by more than one pipeline file, it belongs in `utils/`. Pipeline files import from `utils/` but never from each other.

---

## Dispatcher Pattern

One `Dispatcher` class is the **single sniff callback**. It owns Parse + Decide; it delegates Modify to specialised handlers.

```python
class Dispatcher:
    def dispatch(self, packet) -> None:
        # ── PARSE ──────────────────────────────────────────────
        if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
            return
        if packet[Ether].src.lower() in self._our_macs:   # self-sent guard
            return

        ingress = packet.sniffed_on          # set by Scapy multi-iface sniff
        flags   = packet[TCP].flags
        is_syn     = flags.S and not flags.A
        is_syn_ack = flags.S and flags.A

        # ── DECIDE ─────────────────────────────────────────────
        if ingress == self._server_iface:
            if self._flow_table.get_flow(FlowTable.extract_key(packet)) is not None:
                return   # re-captured outgoing frame — skip

        # ── ROUTE (= Modify entry point) ────────────────────────
        if ingress == self._client_iface:
            if is_syn: self._syn.process(packet)
            else:      self._translator.translate_c2s(packet)
        elif ingress == self._server_iface:
            if is_syn_ack: self._syn_ack.process(packet)
            else:          self._translator.translate_s2c(packet)
```

Key properties:
- **No packet mutation in Dispatcher** — it only reads and routes.
- `packet.sniffed_on` is set automatically by Scapy when using a multi-interface `sniff()` call.

---

## Handler-per-Packet-Type (not "stage")

Name classes after the **packet type that triggers them**, with the suffix `Handler`. The handler owns the **complete workflow** for that packet type — it does not pass the packet to a next stage.

```
SynHandler      → fires on SYN from client
                  creates flow, sends spoofed SYN-ACK (sendp), forwards SYN (send)

SynAckHandler   → fires on real SYN-ACK from server
                  computes delta, flushes buffer, drops the SYN-ACK

Translator      → fires on all data packets (both directions)
                  translates_c2s: subtract delta from ACK, or buffer
                  translate_s2c: add delta to SEQ
```

Avoid the suffix `Stage` — it implies the packet flows through and continues to a next stage, which is wrong here.

---

## Single Multi-Interface Sniff

Replace two threaded sniffers with one `sniff()` call and use `pkt.sniffed_on` to distinguish interfaces:

```python
# main.py
sniff(
    iface=[args.client_iface, args.server_iface],
    prn=dispatcher.dispatch,
    filter=f"tcp port {args.port} and not host 169.254.169.254",
    store=False,
)
```

- No `threading.Thread` needed.
- `packet.sniffed_on` is a string (e.g. `"eth0"`) — compare directly.
- The BPF filter is applied per-interface before any Python code runs.

---

## tx.py — Thin Send Wrapper

Centralise `send` / `sendp` decisions in one file. Each function name expresses **intent**, not Scapy API details:

```python
# src/utils/tx.py
from scapy.sendrecv import send, sendp
from scapy.layers.inet import IP

def send_spoofed(packet, iface: str) -> None:
    """Crafted packet with custom Ether layer → L2 (sendp), preserves spoofed MACs."""
    sendp(packet, iface=iface, verbose=False)

def forward(packet, iface: str) -> None:
    """Transparent forwarding → L3 (send), kernel fills in L2 via ARP."""
    send(packet[IP], iface=iface, verbose=False)

def forward_rewritten(packet, iface: str) -> None:
    """Already-mutated IP packet (checksums deleted) → L3 (send)."""
    send(packet, iface=iface, verbose=False)
```

In pipeline classes, import and call as `tx.send_spoofed(...)` — never call `send`/`sendp` directly. This makes the send layer mockable in one place:

```python
# in tests
with patch("src.pipeline.syn_handler.tx") as mock_tx:
    stage.process(syn_packet)
    mock_tx.send_spoofed.assert_called_once_with(ANY, "eth0")
    mock_tx.forward.assert_called_once_with(ANY, "eth1")
```

---

## Self-Sent MAC Guard

AF_PACKET sniffers see **both incoming and outgoing** frames. Filter self-sent frames at startup:

```python
# Dispatcher.__init__
self._our_macs = set()
for iface in (client_iface, server_iface):
    try:
        self._our_macs.add(get_if_hwaddr(iface).lower())
    except Exception:
        pass

# Dispatcher.dispatch
if packet[Ether].src.lower() in self._our_macs:
    return
```

Collect MACs once at startup. Use `.lower()` on both sides — MACs can be mixed-case.

---

## Re-Captured Outgoing Frame Guard (server-side)

On `eth1`, the sniffer also captures packets that **ClientNIC itself forwarded out** (e.g. the original SYN, client ACKs). These are outgoing frames, not server→client traffic. Identify them by checking if the packet's forward-direction key exists in the flow table:

```python
if ingress == self._server_iface:
    if self._flow_table.get_flow(FlowTable.extract_key(packet)) is not None:
        return  # outgoing frame re-captured — ignore
```

**Why this works:** the flow table is keyed `(client_src, client_sport, server_dst, server_dport)`. A re-captured outgoing packet (client→server direction) will match this key. A genuine server→client packet has `src=server, dst=client`, so `extract_key` returns the reverse key, which is not in the table.

---

## wiring in main.py

```python
flow_table    = FlowTable()
buffer        = PacketBuffer()
spoofer       = SynAckSpoofer()

syn_handler     = SynHandler(flow_table, spoofer, args.client_iface, args.server_iface)
syn_ack_handler = SynAckHandler(flow_table, buffer, args.server_iface)
translator      = Translator(flow_table, buffer, args.client_iface, args.server_iface)
dispatcher      = Dispatcher(syn_handler, syn_ack_handler, translator,
                              flow_table, args.client_iface, args.server_iface)

sniff(iface=[args.client_iface, args.server_iface],
      prn=dispatcher.dispatch, filter=bpf, store=False)
```
