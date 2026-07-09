"""
ServerNIC flow table unit tests — pure Python (no DPDK required).

Models the C flow_table.c logic: open-addressing hash table (1024 slots, linear
probe), ft_create/ft_lookup, ft_set_delta (idempotent), ft_buffer_pkt/ft_flush_buffer.
"""

import struct
import ctypes
import pytest

FT_SIZE = 1024
FT_MAX_BUFFER = 64
FLOW_STATE_PENDING = 0
FLOW_STATE_ACTIVE = 1


def _hash_key(src_ip, src_port, dst_ip, dst_port):
    h = src_ip ^ dst_ip
    h ^= ((src_port & 0xFFFF) << 16) | (dst_port & 0xFFFF)
    h ^= (h >> 16) & 0xFFFFFFFF
    h = (h * 0x45d9f3b) & 0xFFFFFFFF
    h ^= (h >> 16) & 0xFFFFFFFF
    return h & (FT_SIZE - 1)


class FlowEntry:
    def __init__(self):
        self.occupied = False
        self.key = None
        self.spoofed_server_isn = 0
        self.real_server_isn = 0
        self.seq_delta = 0
        self.delta_valid = False
        self.state = FLOW_STATE_PENDING
        self.server_mac = bytes(6)
        self.buffer = []

    def set_delta(self, real_server_isn):
        if self.delta_valid:
            return 0  # idempotent
        self.real_server_isn = real_server_isn
        self.seq_delta = (self.spoofed_server_isn - real_server_isn) & 0xFFFFFFFF
        self.delta_valid = True
        self.state = FLOW_STATE_ACTIVE
        return 1

    def buffer_pkt(self, data):
        if len(self.buffer) >= FT_MAX_BUFFER:
            return -1
        self.buffer.append(bytes(data))
        return 0

    def flush_buffer(self):
        out = list(self.buffer)
        self.buffer = []
        return out


class FlowTable:
    def __init__(self):
        self.entries = [FlowEntry() for _ in range(FT_SIZE)]

    def create(self, key, spoofed_isn, server_mac):
        idx = _hash_key(*key)
        for i in range(FT_SIZE):
            slot = (idx + i) & (FT_SIZE - 1)
            e = self.entries[slot]
            if not e.occupied:
                e.occupied = True
                e.key = key
                e.spoofed_server_isn = spoofed_isn
                e.server_mac = server_mac
                return e
            if e.key == key:
                return e  # idempotent for retransmitted SYN
        return None  # table full

    def lookup(self, key):
        idx = _hash_key(*key)
        for i in range(FT_SIZE):
            slot = (idx + i) & (FT_SIZE - 1)
            e = self.entries[slot]
            if not e.occupied:
                return None
            if e.key == key:
                return e
        return None


MAC = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
KEY_A = (0x0A000001, 1234, 0x0A000002, 8080)
KEY_B = (0x0A000003, 5678, 0x0A000004, 8080)


# ─── create / lookup ─────────────────────────────────────────────────────────

def test_create_and_lookup():
    ft = FlowTable()
    e = ft.create(KEY_A, 0xDEADBEEF, MAC)
    assert e is not None
    assert e.spoofed_server_isn == 0xDEADBEEF
    assert e.state == FLOW_STATE_PENDING
    assert not e.delta_valid

    found = ft.lookup(KEY_A)
    assert found is e


def test_lookup_miss():
    ft = FlowTable()
    ft.create(KEY_A, 0x11111111, MAC)
    assert ft.lookup(KEY_B) is None


def test_create_idempotent_on_retransmit():
    ft = FlowTable()
    e1 = ft.create(KEY_A, 0xDEADBEEF, MAC)
    e2 = ft.create(KEY_A, 0xDEADBEEF, MAC)
    assert e1 is e2  # same entry returned


# ─── delta computation ────────────────────────────────────────────────────────

def test_set_delta_basic():
    ft = FlowTable()
    e = ft.create(KEY_A, 1000, MAC)
    result = e.set_delta(700)
    assert result == 1
    assert e.delta_valid
    assert e.seq_delta == (1000 - 700) & 0xFFFFFFFF
    assert e.state == FLOW_STATE_ACTIVE


def test_set_delta_wraparound():
    ft = FlowTable()
    # V < real_isn: delta wraps around 2^32
    V = 100
    real = 0xFFFFFF00
    e = ft.create(KEY_A, V, MAC)
    e.set_delta(real)
    expected = (V - real) & 0xFFFFFFFF
    assert e.seq_delta == expected


def test_set_delta_idempotent():
    ft = FlowTable()
    e = ft.create(KEY_A, 1000, MAC)
    r1 = e.set_delta(700)
    r2 = e.set_delta(999)  # second call with different value — ignored
    assert r1 == 1
    assert r2 == 0
    assert e.seq_delta == (1000 - 700) & 0xFFFFFFFF  # first value preserved


# ─── buffering ────────────────────────────────────────────────────────────────

def test_buffer_and_flush():
    ft = FlowTable()
    e = ft.create(KEY_A, 1000, MAC)
    pkt1 = b"\x01" * 60
    pkt2 = b"\x02" * 60
    assert e.buffer_pkt(pkt1) == 0
    assert e.buffer_pkt(pkt2) == 0
    out = e.flush_buffer()
    assert len(out) == 2
    assert out[0] == pkt1
    assert out[1] == pkt2
    assert e.flush_buffer() == []  # cleared after flush


def test_buffer_overflow_at_cap():
    ft = FlowTable()
    e = ft.create(KEY_A, 1000, MAC)
    pkt = b"\xAB" * 60
    for _ in range(FT_MAX_BUFFER):
        assert e.buffer_pkt(pkt) == 0
    assert e.buffer_pkt(pkt) == -1  # 65th packet rejected


# ─── hash collision / linear probe ───────────────────────────────────────────

def test_collision_linear_probe():
    """Two keys that land on the same initial slot are stored separately."""
    ft = FlowTable()
    # Craft two distinct keys that hash to the same slot
    KEY_C = KEY_A
    slot_a = _hash_key(*KEY_A)

    # Find KEY_D that also hashes to slot_a with different values
    for port in range(1, 65535):
        k = (KEY_A[0], port, KEY_A[2], KEY_A[3])
        if k != KEY_A and _hash_key(*k) == slot_a:
            KEY_D = k
            break
    else:
        pytest.skip("could not find colliding key in range")

    e1 = ft.create(KEY_A, 0xAAAAAAAA, MAC)
    e2 = ft.create(KEY_D, 0xBBBBBBBB, MAC)
    assert e1 is not e2
    assert ft.lookup(KEY_A) is e1
    assert ft.lookup(KEY_D) is e2
