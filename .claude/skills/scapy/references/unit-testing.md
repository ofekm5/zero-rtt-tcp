# Unit Testing with Scapy

> Build real Scapy packets in tests — avoid mocking packet internals.

## Real Packets in Tests

Construct real Scapy packets for test inputs. This validates that your code handles actual Scapy objects correctly:

```python
from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP

def test_handle_syn():
    syn = (
        Ether(src="aa:bb:cc:dd:ee:01", dst="aa:bb:cc:dd:ee:02")
        / IP(src="192.168.1.1", dst="10.0.0.1")
        / TCP(sport=12345, dport=80, seq=1000, flags="S")
    )

    result = handler.process(syn)
    assert result[TCP].ack == 1001
```

## What to Mock (and What Not To)

**DO mock**: External I/O — `send()`, `sendp()`, `sniff()`, `get_if_hwaddr()`:
```python
from unittest.mock import patch, MagicMock

@patch('mymodule.send')
def test_forwarding(mock_send):
    handler.forward(packet)
    mock_send.assert_called_once()
    sent_pkt = mock_send.call_args[0][0]
    assert sent_pkt[TCP].ack == expected_ack
```

**DO NOT mock**: Packet construction, field access, `haslayer()`. Use real Scapy objects — they're cheap to create and catch real bugs.

## `pkt.sniffed_on` Is Settable

The ServerNIC forwarder uses `packet.sniffed_on` to determine ingress interface. In tests, set it directly:

```python
def test_forward_from_client():
    pkt = Ether()/IP()/TCP(dport=8080, flags="S")
    pkt.sniffed_on = "eth1"   # simulate sniffed on client-facing interface

    forwarder.handle(pkt)
    # assert packet was forwarded to server interface
```

## `get_if_hwaddr` Patching

`get_if_hwaddr()` queries real network interfaces — fails in CI/test environments. Always patch at the **module where it is imported** (not where it is defined):

```python
# Dispatcher lives in src.pipeline.dispatcher and imports get_if_hwaddr there
with patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff"):
    dispatcher = Dispatcher(syn_handler, syn_ack_handler, translator,
                            flow_table, "eth0", "eth1")
```

Use a `with patch(...)` context manager when constructing the object (the MAC collection happens in `__init__`), not as a decorator on the test method.

## `tx` Module Patching

Pipeline classes import `tx` as a module (`from src.utils import tx`) and call `tx.send_spoofed(...)` etc. Patch the **whole module** on the pipeline module that uses it:

```python
with patch("src.pipeline.syn_handler.tx") as mock_tx:
    stage.process(syn_packet)
    mock_tx.send_spoofed.assert_called_once_with(ANY, "eth0")
    mock_tx.forward.assert_called_once_with(ANY, "eth1")

with patch("src.pipeline.translator.tx") as mock_tx:
    translator.translate_c2s(data_packet)
    mock_tx.forward_rewritten.assert_called_once()
```

This is cleaner than patching individual functions and makes it obvious which send path is being exercised.

## Testing Sequence Number Wraparound

Edge cases around the 32-bit boundary are critical:

```python
def test_seq_wraparound():
    """ACK near max wraps correctly after delta subtraction."""
    pkt = Ether()/IP()/TCP(ack=100, flags="A")
    delta = 200  # subtracting 200 from 100 should wrap

    result_ack = (pkt[TCP].ack - delta) & 0xFFFFFFFF
    assert result_ack == 0xFFFFFF9C  # wrapped around

def test_max_seq():
    pkt = Ether()/IP()/TCP(seq=0xFFFFFFFF, flags="S")
    syn_ack = spoofer.create_syn_ack(pkt, spoofed_isn=100)
    # ack should be 0xFFFFFFFF + 1 (Scapy may not auto-wrap)
```

## Testing Pattern: Assert on Captured Arguments

When testing handlers that call `send()`, capture the sent packet and assert on its fields:

```python
@patch('clientnic.app.src.rewriter.send')
def test_rewrite_adds_delta(mock_send):
    pkt = Ether()/IP()/TCP(seq=1000, flags="A")
    delta = 500

    rewriter.rewrite_server_to_client(pkt, delta, "eth0")

    mock_send.assert_called_once()
    sent = mock_send.call_args[0][0]
    assert sent[TCP].seq == 1500
```

## Test File Locations

This project's test files:
- `clientnic/tests/test_spoofer.py` — SYN-ACK creation, ISN generation
- `clientnic/tests/test_flow_table.py` — flow table CRUD, delta calculation
- `clientnic/tests/test_pipeline.py` — Dispatcher, SynHandler, SynAckHandler, Translator, PacketBuffer
- `servernic/tests/test_dispatcher.py` — stateless forwarding

A `conftest.py` in each `tests/` directory adds the app directory to `sys.path` so tests can do `from src.pipeline.dispatcher import Dispatcher` etc.
