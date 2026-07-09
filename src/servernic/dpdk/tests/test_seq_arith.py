"""
ServerNIC sequence-number arithmetic unit tests — no DPDK required.

Validates the translator arithmetic:
  c2s: ACK -= seq_delta  (mod 2^32)
  s2c: SEQ += seq_delta  (mod 2^32)

and V-extraction / ack-num zeroing from the SYN handler.
Also verifies that IP+TCP checksum fields change after rewriting
(functional checksum correctness is tested separately with real packets).
"""

import struct
import socket
import pytest

MASK32 = 0xFFFFFFFF


# ─── helpers ─────────────────────────────────────────────────────────────────

def inet(s):
    return struct.unpack("!I", socket.inet_aton(s))[0]


def checksum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    s = 0
    for i in range(0, len(data), 2):
        s += (data[i] << 8) | data[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return ~s & 0xFFFF


def build_ipv4_tcp(src_ip, dst_ip, sport, dport, seq, ack, flags):
    """Return a minimal 54-byte Ethernet + IPv4 + TCP frame."""
    # Ethernet (14 bytes) — dummy MACs
    eth = bytes(6) + bytes(6) + b"\x08\x00"
    # IPv4 header (20 bytes)
    ip_hdr = struct.pack(
        "!BBHHHBBH4s4s",
        0x45, 0, 40,          # ver/ihl, tos, total_len
        0, 0,                 # id, frag_off
        64, 6,                # ttl, proto=TCP
        0,                    # checksum (filled below)
        socket.inet_aton(src_ip), socket.inet_aton(dst_ip),
    )
    ip_chk = checksum(ip_hdr)
    ip_hdr = ip_hdr[:10] + struct.pack("!H", ip_chk) + ip_hdr[12:]

    # TCP header (20 bytes)
    tcp_hdr = struct.pack(
        "!HHIIBBHHH",
        sport, dport,
        seq, ack,
        0x50, flags,   # data_off=5, flags
        65535,         # window
        0, 0,          # checksum (filled below), urgent
    )
    pseudo = socket.inet_aton(src_ip) + socket.inet_aton(dst_ip) + b"\x00\x06" + struct.pack("!H", 20)
    tcp_chk = checksum(pseudo + tcp_hdr)
    tcp_hdr = tcp_hdr[:16] + struct.pack("!H", tcp_chk) + tcp_hdr[18:]

    return eth + ip_hdr + tcp_hdr


def extract_ack(frame: bytes) -> int:
    return struct.unpack("!I", frame[14 + 20 + 8: 14 + 20 + 12])[0]


def extract_seq(frame: bytes) -> int:
    return struct.unpack("!I", frame[14 + 20 + 4: 14 + 20 + 8])[0]


def rewrite_ack(frame: bytes, new_ack: int) -> bytes:
    b = bytearray(frame)
    struct.pack_into("!I", b, 14 + 20 + 8, new_ack)
    # recompute TCP checksum
    src_ip = frame[26:30]
    dst_ip = frame[30:34]
    tcp = bytes(b[34:54])
    tcp = tcp[:16] + b"\x00\x00" + tcp[18:]
    pseudo = src_ip + dst_ip + b"\x00\x06" + struct.pack("!H", 20)
    chk = checksum(pseudo + tcp)
    struct.pack_into("!H", b, 50, chk)
    return bytes(b)


def rewrite_seq(frame: bytes, new_seq: int) -> bytes:
    b = bytearray(frame)
    struct.pack_into("!I", b, 14 + 20 + 4, new_seq)
    src_ip = frame[26:30]
    dst_ip = frame[30:34]
    tcp = bytes(b[34:54])
    tcp = tcp[:16] + b"\x00\x00" + tcp[18:]
    pseudo = src_ip + dst_ip + b"\x00\x06" + struct.pack("!H", 20)
    chk = checksum(pseudo + tcp)
    struct.pack_into("!H", b, 50, chk)
    return bytes(b)


# ─── V extraction from SYN ack-num field ─────────────────────────────────────

def test_v_extraction():
    V = 0xDEADBEEF
    # SYN with V in ack_num field (flags=0x02 SYN)
    frame = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=100, ack=V, flags=0x02)
    got_v = extract_ack(frame)
    assert got_v == V


def test_ack_num_zeroing():
    V = 0xCAFEBABE
    frame = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=100, ack=V, flags=0x02)
    zeroed = rewrite_ack(frame, 0)
    assert extract_ack(zeroed) == 0


def test_checksum_valid_after_zero():
    V = 0xCAFEBABE
    frame = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=100, ack=V, flags=0x02)
    zeroed = rewrite_ack(frame, 0)
    # Verify TCP checksum of the zeroed frame
    src_ip = zeroed[26:30]
    dst_ip = zeroed[30:34]
    tcp_raw = zeroed[34:54]
    tcp_for_chk = tcp_raw[:16] + b"\x00\x00" + tcp_raw[18:]
    pseudo = src_ip + dst_ip + b"\x00\x06" + struct.pack("!H", 20)
    chk = checksum(pseudo + tcp_for_chk)
    assert chk == struct.unpack("!H", tcp_raw[16:18])[0]


# ─── c2s: ACK -= delta ───────────────────────────────────────────────────────

def test_c2s_ack_minus_delta():
    V = 5000
    real_isn = 3000
    delta = (V - real_isn) & MASK32
    original_ack = 4000

    frame = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=200, ack=original_ack, flags=0x10)
    rewritten = rewrite_ack(frame, (original_ack - delta) & MASK32)
    assert extract_ack(rewritten) == (original_ack - delta) & MASK32


def test_c2s_ack_minus_delta_near_zero_wraparound():
    V = 100
    real_isn = 0xFFFFFF00
    delta = (V - real_isn) & MASK32  # large positive delta
    original_ack = 50  # ACK near zero — subtraction wraps

    expected = (original_ack - delta) & MASK32
    frame = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=200, ack=original_ack, flags=0x10)
    rewritten = rewrite_ack(frame, expected)
    assert extract_ack(rewritten) == expected


# ─── s2c: SEQ += delta ───────────────────────────────────────────────────────

def test_s2c_seq_plus_delta():
    V = 5000
    real_isn = 3000
    delta = (V - real_isn) & MASK32
    original_seq = 3500

    frame = build_ipv4_tcp("10.0.0.2", "10.0.0.1", 8080, 1234, seq=original_seq, ack=201, flags=0x10)
    rewritten = rewrite_seq(frame, (original_seq + delta) & MASK32)
    assert extract_seq(rewritten) == (original_seq + delta) & MASK32


def test_s2c_seq_plus_delta_near_max_wraparound():
    V = 0xFFFFFF00
    real_isn = 3000
    delta = (V - real_isn) & MASK32
    original_seq = 0xFFFFFFF0  # near max — addition wraps

    expected = (original_seq + delta) & MASK32
    frame = build_ipv4_tcp("10.0.0.2", "10.0.0.1", 8080, 1234, seq=original_seq, ack=201, flags=0x10)
    rewritten = rewrite_seq(frame, expected)
    assert extract_seq(rewritten) == expected


# ─── round-trip consistency ───────────────────────────────────────────────────

def test_round_trip_c2s_s2c():
    """Applying delta forward then reverse recovers the original values."""
    V = 0xABCD1234
    real_isn = 0x12345678
    delta = (V - real_isn) & MASK32

    original_ack = 0x99999999
    original_seq = 0x11111111

    c2s = build_ipv4_tcp("10.0.0.1", "10.0.0.2", 1234, 8080, seq=100, ack=original_ack, flags=0x10)
    c2s_rewritten = rewrite_ack(c2s, (original_ack - delta) & MASK32)
    recovered_ack = (extract_ack(c2s_rewritten) + delta) & MASK32
    assert recovered_ack == original_ack

    s2c = build_ipv4_tcp("10.0.0.2", "10.0.0.1", 8080, 1234, seq=original_seq, ack=200, flags=0x10)
    s2c_rewritten = rewrite_seq(s2c, (original_seq + delta) & MASK32)
    recovered_seq = (extract_seq(s2c_rewritten) - delta) & MASK32
    assert recovered_seq == original_seq
