# Plan: Refactor clientnic to SmartNIC Standards

## Context
`clientnic/app-with-translate` works but violates SmartNIC standards from the Scapy skill and ServerNIC reference. Fixes: Parse→Decide→Modify pattern, MAC collection in `__init__`, argparse, metadata BPF filter, `sendp()` for spoofed SYN-ACK (latent bug), ACK wraparound, dead code removal, `_tcp_flags()` helper, and single-sniff dispatcher.

---

## `src/spoofer.py` — Fix ACK wraparound

```diff
-            ack=syn_packet[TCP].seq + 1,
+            ack=(syn_packet[TCP].seq + 1) & 0xFFFFFFFF,
```

---

## `src/rewriter.py` — Add `send_spoofed()`, remove dead method

```diff
+from scapy.sendrecv import send, sendp
-from scapy.sendrecv import send

+    def send_spoofed(self, packet: Packet, iface: str) -> None:
+        """Send a crafted packet with Ether layer (L2) — preserves spoofed src/dst MACs."""
+        sendp(packet, iface=iface, verbose=False)

-    def _recalc_checksums(self, packet: Packet) -> None:
-        """Delete checksums to force Scapy recalculation on send."""
-        del packet[IP].chksum
-        del packet[TCP].chksum
```

---

## `src/handlers.py` — Full restructure

### New module-level helper (after imports):
```python
def _tcp_flags(tcp) -> str:
    parts = []
    if tcp.flags.S: parts.append("SYN")
    if tcp.flags.A: parts.append("ACK")
    if tcp.flags.P: parts.append("PSH")
    if tcp.flags.F: parts.append("FIN")
    if tcp.flags.R: parts.append("RST")
    return "-".join(parts) if parts else "NONE"
```

### `ClientPacketHandler.__init__` — Collect MACs internally:
```diff
-    def __init__(self, ..., our_macs: Set[str] = None):
-        ...
-        self._our_macs = our_macs or set()
+    def __init__(self, ...):   # remove our_macs param
+        ...
+        self._our_macs = set()
+        for iface in (client_iface, server_iface):
+            try:
+                self._our_macs.add(get_if_hwaddr(iface).lower())
+            except Exception:
+                pass
```

### `ClientPacketHandler.handle()` — Explicit Parse → Decide → Modify:
```python
def handle(self, packet: Packet) -> None:
    # --- Parse ---
    if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
        return
    src_mac = packet[Ether].src.lower()
    src_ip  = packet[IP].src
    dst_ip  = packet[IP].dst
    sport   = packet[TCP].sport
    dport   = packet[TCP].dport
    flags   = packet[TCP].flags
    seq     = packet[TCP].seq

    # --- Decide ---
    if src_mac in self._our_macs:
        return
    key = FlowKey(src_ip=src_ip, src_port=sport, dst_ip=dst_ip, dst_port=dport)
    is_syn = flags.S and not flags.A

    if is_syn:
        if self._flow_table.get_flow(key) is not None:
            logger.debug("SYN retransmit ignored for flow: %s", key)
            return
        spoofed_isn = self._spoofer.generate_random_isn()
    else:
        entry = self._flow_table.get_flow(key)

    # --- Modify ---
    if is_syn:
        self._flow_table.create_flow(key, seq, spoofed_isn)
        logger.info("SYN received, flow created: %s [%s]", key, _tcp_flags(packet[TCP]))
        syn_ack = self._spoofer.create_syn_ack(packet, spoofed_isn)
        self._rewriter.send_spoofed(syn_ack, self._client_iface)   # sendp — L2
        self._rewriter.forward_packet(packet, self._server_iface)  # send  — L3
    else:
        if entry is not None and entry.seq_delta is not None:
            self._rewriter.rewrite_client_to_server(packet, entry.seq_delta, self._server_iface)
            logger.debug("Packet forwarded with seq rewrite for flow: %s", key)
        else:
            self._buffer.add(key, packet)
            logger.debug("Packet buffered for flow: %s", key)
```

Remove `_is_syn()`, `_handle_syn()`, `_handle_data()` (inlined above).

### `ServerPacketHandler` — Same pattern:
Remove `our_macs` param, collect MACs in `__init__`, restructure `handle()` into explicit P→D→M sections, inline `_is_syn_ack()`, `_handle_syn_ack()`, `_handle_data()`.

---

## `main.py` — argparse + single sniff + updated filter

```diff
-import threading
+import argparse
+import logging

+def _make_dispatcher(client_handler, server_handler, client_iface, server_iface):
+    def dispatch(packet):
+        ingress = packet.sniffed_on
+        if ingress == client_iface:
+            client_handler.handle(packet)
+        elif ingress == server_iface:
+            server_handler.handle(packet)
+    return dispatch

 def main():
+    parser = argparse.ArgumentParser(description="ClientNIC - 0-RTT TCP middleware")
+    parser.add_argument("--client-iface", default="eth0")
+    parser.add_argument("--server-iface", default="eth1")
+    parser.add_argument("--port", type=int, default=8080)
+    parser.add_argument("--verbose", action="store_true")
+    args = parser.parse_args()
+
-    logger = setup_logging()
+    logger = setup_logging(logging.DEBUG if args.verbose else logging.INFO)

-    our_macs = set()
-    for iface in (CLIENT_IFACE, SERVER_IFACE): ...

     client_handler = ClientPacketHandler(
-        ..., client_iface=CLIENT_IFACE, server_iface=SERVER_IFACE, our_macs=our_macs,
+        ..., client_iface=args.client_iface, server_iface=args.server_iface,
     )
     server_handler = ServerPacketHandler(
-        ..., our_macs=our_macs,
+        ..., client_iface=args.client_iface, server_iface=args.server_iface,
     )

-    eth1_thread = threading.Thread(target=sniff, ..., daemon=True)
-    eth1_thread.start()
-    sniff(iface=CLIENT_IFACE, prn=client_handler.handle, filter="tcp port 8080", store=False)
+    bpf = f"tcp port {args.port} and not host 169.254.169.254"
+    sniff(
+        iface=[args.client_iface, args.server_iface],
+        prn=_make_dispatcher(client_handler, server_handler, args.client_iface, args.server_iface),
+        filter=bpf,
+        store=False,
+    )
```

---

## `tests/test_handlers.py` — Fix constructor calls + test bugs

1. All handler constructor calls: remove `our_macs=...`, add `@patch("...get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")`.

2. `test_handle_syn_sends_spoofed_syn_ack` — SYN-ACK now via `send_spoofed`, not `forward_packet`:
   ```diff
   -    calls = rewriter.forward_packet.call_args_list
   -    assert len(calls) == 2
   -    assert calls[0][0][1] == "eth0"
   +    rewriter.send_spoofed.assert_called_once()
   +    assert rewriter.send_spoofed.call_args[0][1] == "eth0"
   +    assert len(rewriter.forward_packet.call_args_list) == 1
   +    assert rewriter.forward_packet.call_args_list[0][0][1] == "eth1"
   ```

3. `test_handle_multiple_syns_same_flow` — **test bug** (handler ignores retransmit, second ISN never used):
   ```diff
   -    assert entry.spoofed_server_isn == 2000  # Second ISN
   +    assert entry.spoofed_server_isn == 1000  # Retransmit ignored, first ISN kept
   ```

4. Remove tests for private helpers `_is_syn()` / `_is_syn_ack()` — inlined, covered by `handle()` tests.

---

## Verification
1. `python -m pytest clientnic/tests/ -v` — all pass
2. `./expermients/zero-rtt-clientnic-translate/run_experiment.sh` — integration test passes
3. `validate_0rtt_capture.py` on ClientNIC VM confirms spoofed SYN-ACK, ISN delta, checksums
