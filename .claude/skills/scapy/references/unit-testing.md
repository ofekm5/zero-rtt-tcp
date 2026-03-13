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

`get_if_hwaddr()` queries real network interfaces — fails in CI/test environments. Patch it:

```python
@patch('clientnic.app.main.get_if_hwaddr')
def test_startup(mock_hwaddr):
    mock_hwaddr.return_value = "aa:bb:cc:dd:ee:ff"
    # ... test initialization code
```

Or patch at the module where it's imported:
```python
@patch('mymodule.get_if_hwaddr', return_value="00:11:22:33:44:55")
def test_mac_collection(mock_hwaddr):
    handler = PacketHandler()
    assert "00:11:22:33:44:55" in handler._our_macs
```

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
- `clientnic/tests/test_handlers.py` — packet handler logic
- `servernic/tests/test_forwarder.py` — stateless forwarding
