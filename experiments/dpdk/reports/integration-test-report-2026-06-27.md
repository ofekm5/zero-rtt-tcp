# Integration Test Report — 2026-06-27

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 2 FAILURE(S)

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : n=165  min=31302.661  mean=45020.406  median=44154.318  max=64023.380 ms
  Send unlock   : no samples found
  Server gap    : n=34  min=47797.258  mean=62600.993  median=67771.855  max=74458.035 ms
```

## Client Output

```

```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x69b85bde in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x91f1eb53 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x12aeacc1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x87767ffa in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xafc420ec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3102a70a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x285b2ff5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcddceca0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x36fea608 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x08f3b1f5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3c42f0a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb825029c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0a55eb63 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe238d9de in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3ece72bb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0cb6c9ce in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfa3e71bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd0080a34 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe0764c23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x33c51e12 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1578da8c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc64cc852 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4cb90fdc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa0ed30f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbc4a4e97 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x10718617 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x03236f9f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf1cc74a4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x22fa977e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa5f47a8b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9261a650 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x977b56c7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x07b51bdf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd1e19859 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcc07800b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x731813d8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb9592ee5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x91a7efcd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4178db72 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd893ceb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2de543a9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbfc1a9f9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9fd56b7f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7ead1aaf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4bd16630 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x77964670 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3514146b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x339cb7cd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x556196b6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN f--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN: new flow, V=0x7f4901ff
SERVERNIC: SYN: new flow, V=0x5df7f8ba
SERVERNIC: SYN: new flow, V=0x95ef8852
SERVERNIC: SYN: new flow, V=0xb2bf4c4f
SERVERNIC: SYN-ACK: delta=0xa2d2b185, V=0x6436eaae, real_isn=0xc1643929
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x57722017
SERVERNIC: SYN: new flow, V=0x8df06882
SERVERNIC: SYN-ACK: delta=0x890c9007, V=0x5df7f8ba, real_isn=0xd4eb68b3
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x18f5904b, V=0x95ef8852, real_isn=0x7cf9f807
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xa5b5827e, V=0x7f4901ff, real_isn=0xd9937f81
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x0081848b, V=0xb2bf4c4f, real_isn=0xb23dc7c4
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xc362b014, V=0x57722017, real_isn=0x940f7003
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x8895693a, V=0x8df06882, real_isn=0x055aff48
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7ef4b807
SERVERNIC: SYN: new flow, V=0xc27096ec
SERVERNIC: SYN-ACK: delta=0x32ca6d00, V=0x7ef4b807, real_isn=0x4c2a4b07
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xe2a1a6b5, V=0xc27096ec, real_isn=0xdfcef037
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xed488d7f
SERVERNIC: SYN: new flow, V=0xfeae5987
SERVERNIC: SYN: new flow, V=0xbae95522
SERV--output truncated--
```

## Server Log

```
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abort failed: Success
recvn abo--output truncated--
```

## Packet Analysis

```
missing=first_outbound_payload flow=10.1.0.41:2910-10.1.2.103:8080
metric=fct value_ms=40820.807 node=client flow=10.1.0.41:2910-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2918-10.1.2.103:8080
metric=fct value_ms=40877.164 node=client flow=10.1.0.41:2918-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2924-10.1.2.103:8080
metric=fct value_ms=40877.097 node=client flow=10.1.0.41:2924-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2938-10.1.2.103:8080
metric=fct value_ms=40819.602 node=client flow=10.1.0.41:2938-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2948-10.1.2.103:8080
metric=fct value_ms=39618.772 node=client flow=10.1.0.41:2948-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2962-10.1.2.103:8080
metric=fct value_ms=40958.639 node=client flow=10.1.0.41:2962-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2974-10.1.2.103:8080
metric=fct value_ms=40818.150 node=client flow=10.1.0.41:2974-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2978-10.1.2.103:8080
metric=fct value_ms=40817.249 node=client flow=10.1.0.41:2978-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2988-10.1.2.103:8080
metric=fct value_ms=40874.348 node=client flow=10.1.0.41:2988-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:2998-10.1.2.103:8080
metric=fct value_ms=40873.717 node=client flow=10.1.0.41:2998-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3012-10.1.2.103:8080
metric=fct value_ms=40203.292 node=client flow=10.1.0.41:3012-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3014-10.1.2.103:8080
metric=fct value_ms=40202.647 node=client flow=10.1.0.41:3014-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3020-10.1.2.103:8080
metric=fct value_ms=40872.480 node=client flow=10.1.0.41:3020-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3030-10.1.2.103:8080
metric=fct value_ms=40872.417 node=client flow=10.1.0.41:3030-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3034-10.1.2.103:8080
metric=fct value_ms=40582.648 node=client flow=10.1.0.41:3034-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3046-10.1.2.103:8080
metric=fct value_ms=40408.939 node=client flow=10.1.0.41:3046-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3054-10.1.2.103:8080
metric=fct value_ms=40201.604 node=client flow=10.1.0.41:3054-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3060-10.1.2.103:8080
metric=fct value_ms=41417.403 node=client flow=10.1.0.41:3060-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3072-10.1.2.103:8080
metric=fct value_ms=40588.752 node=client flow=10.1.0.41:3072-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3084-10.1.2.103:8080
metric=fct value_ms=40869.774 node=client flow=10.1.0.41:3084-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3096-10.1.2.103:8080
metric=fct value_ms=40580.547 node=client flow=10.1.0.41:3096-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3108-10.1.2.103:8080
metric=fct value_ms=40207.913 node=client flow=10.1.0.41:3108-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3114-10.1.2.103:8080
metric=fct value_ms=41039.899 node=client flow=10.1.0.41:3114-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3116-10.1.2.103:8080
metric=fct value_ms=41591.290 node=client flow=10.1.0.41:3116-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3126-10.1.2.103:8080
metric=fct value_ms=40586.698 node=client flow=10.1.0.41:3126-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3132-10.1.2.103:8080
metric=fct value_ms=41606.640 node=client flow=10.1.0.41:3132-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3144-10.1.2.103:8080
metric=fct value_ms=41622.504 node=client flow=10.1.0.41:3144-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3148-10.1.2.103:8080
metric=fct value_ms=41550.447 node=client flow=10.1.0.41:3148-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3160-10.1.2.103:8080
metric=fct value_ms=41625.878 node=client flow=10.1.0.41:3160-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3170-10.1.2.103:8080
metric=fct value_ms=41585.802 node=client flow=10.1.0.41:3170-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3178-10.1.2.103:8080
metric=fct value_ms=42193.673 node=client flow=10.1.0.41:3178-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3184-10.1.2.103:8080
metric=fct value_ms=42193.515 node=client flow=10.1.0.41:3184-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3200-10.1.2.103:8080
metric=fct value_ms=41640.835 node=client flow=10.1.0.41:3200-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3208-10.1.2.103:8080
metric=fct value_ms=40936.131 node=client flow=10.1.0.41:3208-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3218-10.1.2.103:8080
metric=fct value_ms=41839.435 node=client flow=10.1.0.41:3218-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3224-10.1.2.103:8080
metric=fct value_ms=42454.848 node=client flow=10.1.0.41:3224-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3240-10.1.2.103:8080
metric=fct value_ms=42191.425 node=client flow=10.1.0.41:3240-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3248-10.1.2.103:8080
metric=fct value_ms=42758.657 node=client flow=10.1.0.41:3248-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3260-10.1.2.103:8080
metric=fct value_ms=42425.502 node=client flow=10.1.0.41:3260-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3266-10.1.2.103:8080
metric=fct value_ms=42757.174 node=client flow=10.1.0.41:3266-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3270-10.1.2.103:8080
metric=fct value_ms=41880.694 node=client flow=10.1.0.41:3270-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3274-10.1.2.103:8080
metric=fct value_ms=42792.648 node=client flow=10.1.0.41:3274-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3278-10.1.2.103:8080
metric=fct value_ms=42475.965 node=client flow=10.1.0.41:3278-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3294-10.1.2.103:8080
metric=fct value_ms=42443.205 node=client flow=10.1.0.41:3294-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3310-10.1.2.103:8080
metric=fct value_ms=42755.599 node=client flow=10.1.0.41:3310-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:8924-10.1.2.103:8082
metric=fct value_ms=31306.333 node=client flow=10.1.0.41:8924-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8940-10.1.2.103:8082
metric=fct value_ms=44327.904 node=client flow=10.1.0.41:8940-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8946-10.1.2.103:8082
metric=fct value_ms=44361.444 node=client flow=10.1.0.41:8946-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8948-10.1.2.103:8082
metric=fct value_ms=44360.274 node=client flow=10.1.0.41:8948-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8954-10.1.2.103:8082
metric=fct value_ms=44208.030 node=client flow=10.1.0.41:8954-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8960-10.1.2.103:8082
metric=fct value_ms=44360.600 node=client flow=10.1.0.41:8960-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8966-10.1.2.103:8082
metric=fct value_ms=44371.968 node=client flow=10.1.0.41:8966-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8982-10.1.2.103:8082
metric=fct value_ms=44206.303 node=client flow=10.1.0.41:8982-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8992-10.1.2.103:8082
metric=fct value_ms=44325.249 node=client flow=10.1.0.41:8992-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8996-10.1.2.103:8082
metric=fct value_ms=44168.496 node=client flow=10.1.0.41:8996-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:8998-10.1.2.103:8082
metric=fct value_ms=31402.480 node=client flow=10.1.0.41:8998-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9014-10.1.2.103:8082
metric=fct value_ms=31302.661 node=client flow=10.1.0.41:9014-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9020-10.1.2.103:8082
metric=fct value_ms=44357.109 node=client flow=10.1.0.41:9020-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9026-10.1.2.103:8082
metric=fct value_ms=31481.276 node=client flow=10.1.0.41:9026-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9034-10.1.2.103:8082
metric=fct value_ms=44205.021 node=client flow=10.1.0.41:9034-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9038-10.1.2.103:8082
metric=fct value_ms=44317.188 node=client flow=10.1.0.41:9038-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9042-10.1.2.103:8082
metric=fct value_ms=44182.002 node=client flow=10.1.0.41:9042-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9056-10.1.2.103:8082
metric=fct value_ms=44316.794 node=client flow=10.1.0.41:9056-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9058-10.1.2.103:8082
metric=fct value_ms=44170.181 node=client flow=10.1.0.41:9058-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9060-10.1.2.103:8082
metric=fct value_ms=44202.660 node=client flow=10.1.0.41:9060-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9072-10.1.2.103:8082
metric=fct value_ms=44322.766 node=client flow=10.1.0.41:9072-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9086-10.1.2.103:8082
metric=fct value_ms=44321.150 node=client flow=10.1.0.41:9086-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9100-10.1.2.103:8082
metric=fct value_ms=44172.601 node=client flow=10.1.0.41:9100-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9114-10.1.2.103:8082
metric=fct value_ms=44320.532 node=client flow=10.1.0.41:9114-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9120-10.1.2.103:8082
metric=fct value_ms=44324.487 node=client flow=10.1.0.41:9120-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9128-10.1.2.103:8082
metric=fct value_ms=44285.433 node=client flow=10.1.0.41:9128-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9134-10.1.2.103:8082
metric=fct value_ms=44179.338 node=client flow=10.1.0.41:9134-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9142-10.1.2.103:8082
metric=fct value_ms=44318.970 node=client flow=10.1.0.41:9142-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9154-10.1.2.103:8082
metric=fct value_ms=44318.571 node=client flow=10.1.0.41:9154-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9164-10.1.2.103:8082
metric=fct value_ms=64023.380 node=client flow=10.1.0.41:9164-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9166-10.1.2.103:8082
metric=fct value_ms=44317.900 node=client flow=10.1.0.41:9166-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9176-10.1.2.103:8082
metric=fct value_ms=44299.276 node=client flow=10.1.0.41:9176-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9180-10.1.2.103:8082
metric=fct value_ms=44298.594 node=client flow=10.1.0.41:9180-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9188-10.1.2.103:8082
metric=fct value_ms=44350.796 node=client flow=10.1.0.41:9188-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9198-10.1.2.103:8082
metric=fct value_ms=44316.583 node=client flow=10.1.0.41:9198-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9204-10.1.2.103:8082
metric=fct value_ms=44172.183 node=client flow=10.1.0.41:9204-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9218-10.1.2.103:8082
metric=fct value_ms=44170.656 node=client flow=10.1.0.41:9218-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9234-10.1.2.103:8082
metric=fct value_ms=44320.304 node=client flow=10.1.0.41:9234-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9246-10.1.2.103:8082
metric=fct value_ms=44348.378 node=client flow=10.1.0.41:9246-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9254-10.1.2.103:8082
metric=fct value_ms=44314.251 node=client flow=10.1.0.41:9254-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9270-10.1.2.103:8082
metric=fct value_ms=44313.022 node=client flow=10.1.0.41:9270-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9272-10.1.2.103:8082
metric=fct value_ms=44311.021 node=client flow=10.1.0.41:9272-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9276-10.1.2.103:8082
metric=fct value_ms=44304.073 node=client flow=10.1.0.41:9276-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9284-10.1.2.103:8082
metric=fct value_ms=44158.276 node=client flow=10.1.0.41:9284-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9288-10.1.2.103:8082
metric=fct value_ms=44152.637 node=client flow=10.1.0.41:9288-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9290-10.1.2.103:8082
metric=fct value_ms=44290.467 node=client flow=10.1.0.41:9290-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9296-10.1.2.103:8082
metric=fct value_ms=44308.968 node=client flow=10.1.0.41:9296-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9310-10.1.2.103:8082
metric=fct value_ms=44308.593 node=client flow=10.1.0.41:9310-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9326-10.1.2.103:8082
metric=fct value_ms=44313.175 node=client flow=10.1.0.41:9326-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9336-10.1.2.103:8082
metric=fct value_ms=44151.241 node=client flow=10.1.0.41:9336-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9350-10.1.2.103:8082
metric=fct value_ms=44159.358 node=client flow=10.1.0.41:9350-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9362-10.1.2.103:8082
metric=fct value_ms=44311.683 node=client flow=10.1.0.41:9362-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9368-10.1.2.103:8082
metric=fct value_ms=44306.490 node=client flow=10.1.0.41:9368-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9384-10.1.2.103:8082
metric=fct value_ms=44149.507 node=client flow=10.1.0.41:9384-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9388-10.1.2.103:8082
metric=fct value_ms=64010.722 node=client flow=10.1.0.41:9388-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9394-10.1.2.103:8082
metric=fct value_ms=44305.634 node=client flow=10.1.0.41:9394-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9406-10.1.2.103:8082
metric=fct value_ms=44310.665 node=client flow=10.1.0.41:9406-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9418-10.1.2.103:8082
metric=fct value_ms=44305.142 node=client flow=10.1.0.41:9418-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9430-10.1.2.103:8082
metric=fct value_ms=44306.145 node=client flow=10.1.0.41:9430-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9438-10.1.2.103:8082
metric=fct value_ms=44294.175 node=client flow=10.1.0.41:9438-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9440-10.1.2.103:8082
metric=fct value_ms=64008.813 node=client flow=10.1.0.41:9440-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9448-10.1.2.103:8082
metric=fct value_ms=44304.180 node=client flow=10.1.0.41:9448-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9452-10.1.2.103:8082
metric=fct value_ms=44316.464 node=client flow=10.1.0.41:9452-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9454-10.1.2.103:8082
metric=fct value_ms=44154.318 node=client flow=10.1.0.41:9454-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9468-10.1.2.103:8082
metric=fct value_ms=44178.724 node=client flow=10.1.0.41:9468-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9484-10.1.2.103:8082
metric=fct value_ms=44299.644 node=client flow=10.1.0.41:9484-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9494-10.1.2.103:8082
metric=fct value_ms=44151.121 node=client flow=10.1.0.41:9494-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9510-10.1.2.103:8082
metric=fct value_ms=44310.622 node=client flow=10.1.0.41:9510-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9520-10.1.2.103:8082
metric=fct value_ms=44331.290 node=client flow=10.1.0.41:9520-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9528-10.1.2.103:8082
metric=fct value_ms=44330.379 node=client flow=10.1.0.41:9528-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9530-10.1.2.103:8082
metric=fct value_ms=44148.768 node=client flow=10.1.0.41:9530-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9534-10.1.2.103:8082
metric=fct value_ms=44300.310 node=client flow=10.1.0.41:9534-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:3326-10.1.2.103:8080
metric=fct value_ms=42153.939 node=client flow=10.1.0.41:3326-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:9546-10.1.2.103:8082
metric=fct value_ms=31996.556 node=client flow=10.1.0.41:9546-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9560-10.1.2.103:8082
metric=fct value_ms=63999.075 node=client flow=10.1.0.41:9560-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:9566-10.1.2.103:8082
metric=fct value_ms=44293.864 node=client flow=10.1.0.41:9566-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:3342-10.1.2.103:8080
metric=fct value_ms=42721.678 node=client flow=10.1.0.41:3342-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3354-10.1.2.103:8080
metric=fct value_ms=42397.528 node=client flow=10.1.0.41:3354-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3356-10.1.2.103:8080
metric=fct value_ms=62793.599 node=client flow=10.1.0.41:3356-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3362-10.1.2.103:8080
metric=fct value_ms=42717.509 node=client flow=10.1.0.41:3362-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3366-10.1.2.103:8080
metric=fct value_ms=41956.861 node=client flow=10.1.0.41:3366-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3380-10.1.2.103:8080
metric=fct value_ms=42680.703 node=client flow=10.1.0.41:3380-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3394-10.1.2.103:8080
metric=fct value_ms=42716.705 node=client flow=10.1.0.41:3394-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3404-10.1.2.103:8080
metric=fct value_ms=42425.457 node=client flow=10.1.0.41:3404-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3416-10.1.2.103:8080
metric=fct value_ms=42716.406 node=client flow=10.1.0.41:3416-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53210-10.1.2.103:8081
metric=fct value_ms=63089.720 node=client flow=10.1.0.41:53210-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3426-10.1.2.103:8080
metric=fct value_ms=42031.974 node=client flow=10.1.0.41:3426-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3428-10.1.2.103:8080
metric=fct value_ms=42716.357 node=client flow=10.1.0.41:3428-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3434-10.1.2.103:8080
metric=fct value_ms=41151.810 node=client flow=10.1.0.41:3434-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53226-10.1.2.103:8081
metric=fct value_ms=63047.378 node=client flow=10.1.0.41:53226-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3436-10.1.2.103:8080
metric=fct value_ms=42715.602 node=client flow=10.1.0.41:3436-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3448-10.1.2.103:8080
metric=fct value_ms=42394.893 node=client flow=10.1.0.41:3448-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53236-10.1.2.103:8081
metric=fct value_ms=63102.770 node=client flow=10.1.0.41:53236-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3462-10.1.2.103:8080
metric=fct value_ms=42422.415 node=client flow=10.1.0.41:3462-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3468-10.1.2.103:8080
metric=fct value_ms=42098.376 node=client flow=10.1.0.41:3468-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3482-10.1.2.103:8080
metric=fct value_ms=42714.701 node=client flow=10.1.0.41:3482-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3486-10.1.2.103:8080
metric=fct value_ms=42423.024 node=client flow=10.1.0.41:3486-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3502-10.1.2.103:8080
metric=fct value_ms=42714.569 node=client flow=10.1.0.41:3502-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53242-10.1.2.103:8081
metric=fct value_ms=63110.201 node=client flow=10.1.0.41:53242-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:53250-10.1.2.103:8081
metric=fct value_ms=63072.394 node=client flow=10.1.0.41:53250-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3508-10.1.2.103:8080
metric=fct value_ms=63055.486 node=client flow=10.1.0.41:3508-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53262-10.1.2.103:8081
metric=fct value_ms=63068.970 node=client flow=10.1.0.41:53262-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:9570-10.1.2.103:8082
metric=fct value_ms=44180.417 node=client flow=10.1.0.41:9570-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:53276-10.1.2.103:8081
metric=fct value_ms=62735.552 node=client flow=10.1.0.41:53276-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:9578-10.1.2.103:8082
metric=fct value_ms=31312.518 node=client flow=10.1.0.41:9578-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:53290-10.1.2.103:8081
metric=fct value_ms=63067.851 node=client flow=10.1.0.41:53290-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:53296-10.1.2.103:8081
metric=fct value_ms=63067.195 node=client flow=10.1.0.41:53296-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:9594-10.1.2.103:8082
metric=fct value_ms=44284.383 node=client flow=10.1.0.41:9594-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:3510-10.1.2.103:8080
metric=fct value_ms=42710.489 node=client flow=10.1.0.41:3510-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3522-10.1.2.103:8080
metric=fct value_ms=42146.071 node=client flow=10.1.0.41:3522-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3524-10.1.2.103:8080
metric=fct value_ms=42710.497 node=client flow=10.1.0.41:3524-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:3534-10.1.2.103:8080
metric=fct value_ms=42710.443 node=client flow=10.1.0.41:3534-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53298-10.1.2.103:8081
metric=fct value_ms=63094.356 node=client flow=10.1.0.41:53298-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:53308-10.1.2.103:8081
metric=fct value_ms=62712.385 node=client flow=10.1.0.41:53308-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3548-10.1.2.103:8080
metric=fct value_ms=42709.313 node=client flow=10.1.0.41:3548-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53312-10.1.2.103:8081
metric=fct value_ms=63124.595 node=client flow=10.1.0.41:53312-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:9606-10.1.2.103:8082
metric=fct value_ms=44126.094 node=client flow=10.1.0.41:9606-10.1.2.103:8082
missing=first_outbound_payload flow=10.1.0.41:53316-10.1.2.103:8081
metric=fct value_ms=63107.767 node=client flow=10.1.0.41:53316-10.1.2.103:8081
missing=first_outbound_payload flow=10.1.0.41:3550-10.1.2.103:8080
metric=fct value_ms=42707.918 node=client flow=10.1.0.41:3550-10.1.2.103:8080
missing=first_outbound_payload flow=10.1.0.41:53324-10.1.2.103:8081
metric=fct value_ms=62710.413 node=client flow=10.1.0.41:53324-10.1.2.103:8081
missing=first_outbound_payl--output truncated--
missing=first_inbound_payload flow=10.1.0.41:2910-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2918-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2924-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2938-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2948-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2962-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2974-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2978-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2988-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:2998-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3012-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3014-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3020-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3030-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3034-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3046-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3054-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3060-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3072-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3084-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3096-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3108-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3114-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3116-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3126-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3132-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3144-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3148-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3160-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3170-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3178-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3184-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3200-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3208-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3218-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3224-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3240-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3248-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3260-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3266-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3270-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3274-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3278-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3294-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3310-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:8924-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8940-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8946-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8948-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8954-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8960-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8966-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8982-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8992-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8996-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:8998-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9014-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9020-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9026-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9034-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9038-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9042-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9056-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9058-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9060-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9072-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9086-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9100-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9114-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9120-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9128-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9134-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9142-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9154-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9164-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9166-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9176-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9180-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9188-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9198-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9204-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9218-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9234-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9246-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9254-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9270-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9272-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9276-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9284-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9288-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9290-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9296-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9310-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9326-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9336-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9350-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9362-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9368-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9384-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9388-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9394-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9406-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9418-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9430-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9438-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9440-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9448-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9452-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9454-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9468-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9484-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9494-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9510-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9520-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9528-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9530-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9534-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:3326-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:9546-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9560-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9566-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:3342-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3354-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3356-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3362-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3366-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3380-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3394-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3404-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3416-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3426-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53210-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3428-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3434-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53226-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3436-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3448-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53236-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3462-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3468-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3482-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3486-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3502-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53242-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53250-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3508-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53262-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9570-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53276-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9578-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53290-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53296-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9594-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:3510-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3522-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3524-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3534-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53298-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53308-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3548-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53312-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9606-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53316-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3550-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53324-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9610-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53328-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9622-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53330-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53334-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53340-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53352-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3554-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3558-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3562-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3578-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3588-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53366-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3598-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53376-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3608-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53386-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3612-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3618-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53388-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3634-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53400-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3650-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53412-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3656-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53416-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9626-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:3666-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53422-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3680-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53426-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3684-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53442-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3688-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53458-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3702-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53472-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3724-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3708-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53486-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53492-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3740-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53502-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3744-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3756-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53508-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53516-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53518-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3772-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3778-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3792-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3802-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3810-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3824-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3826-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3820-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3838-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53528-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3844-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53546-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53532-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:3852-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3860-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3880-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3876-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3882-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3894-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3914-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3920-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3928-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3902-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3916-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3940-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3944-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3950-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3962-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3958-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3970-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3980-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3982-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3988-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:3994-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4004-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4000-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4020-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4038-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4034-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4040-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4054-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4066-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4100-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4086-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4070-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53550-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4106-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4112-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53564-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53566-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4126-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4114-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53574-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53604-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53588-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4134-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4142-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4146-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4148-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53608-10.1.2.103:8081
metric=server_gap value_ms=47827.778 node=server flow=10.1.0.41:40572-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:4158-10.1.2.103:8080
metric=server_gap value_ms=74458.035 node=server flow=10.1.0.41:40582-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53624-10.1.2.103:8081
metric=server_gap value_ms=47907.149 node=server flow=10.1.0.41:40594-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:4174-10.1.2.103:8080
metric=server_gap value_ms=62677.798 node=server flow=10.1.0.41:40600-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53628-10.1.2.103:8081
metric=server_gap value_ms=74429.572 node=server flow=10.1.0.41:40614-10.1.2.103:8083
metric=server_gap value_ms=47878.174 node=server flow=10.1.0.41:40630-10.1.2.103:8083
metric=server_gap value_ms=74432.117 node=server flow=10.1.0.41:40632-10.1.2.103:8083
metric=server_gap value_ms=47798.357 node=server flow=10.1.0.41:40638-10.1.2.103:8083
metric=server_gap value_ms=72122.433 node=server flow=10.1.0.41:40654-10.1.2.103:8083
metric=server_gap value_ms=74428.804 node=server flow=10.1.0.41:40666-10.1.2.103:8083
metric=server_gap value_ms=74428.710 node=server flow=10.1.0.41:40692-10.1.2.103:8083
metric=server_gap value_ms=47798.472 node=server flow=10.1.0.41:40672-10.1.2.103:8083
metric=server_gap value_ms=47879.323 node=server flow=10.1.0.41:40686-10.1.2.103:8083
metric=server_gap value_ms=74428.718 node=server flow=10.1.0.41:40698-10.1.2.103:8083
metric=server_gap value_ms=74428.683 node=server flow=10.1.0.41:40730-10.1.2.103:8083
metric=server_gap value_ms=68282.358 node=server flow=10.1.0.41:40706-10.1.2.103:8083
metric=server_gap value_ms=47878.195 node=server flow=10.1.0.41:40714-10.1.2.103:8083
metric=server_gap value_ms=67770.565 node=server flow=10.1.0.41:40718-10.1.2.103:8083
metric=server_gap value_ms=67003.455 node=server flow=10.1.0.41:40732-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:4178-10.1.2.103:8080
metric=server_gap value_ms=47875.900 node=server flow=10.1.0.41:40740-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53636-10.1.2.103:8081
metric=server_gap value_ms=65722.251 node=server flow=10.1.0.41:40742-10.1.2.103:8083
metric=server_gap value_ms=74428.519 node=server flow=10.1.0.41:40762-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:4190-10.1.2.103:8080
metric=server_gap value_ms=67773.144 node=server flow=10.1.0.41:40756-10.1.2.103:8083
metric=server_gap value_ms=74429.184 node=server flow=10.1.0.41:40774-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53648-10.1.2.103:8081
metric=server_gap value_ms=68794.250 node=server flow=10.1.0.41:40786-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53650-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4192-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4208-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53660-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4212-10.1.2.103:8080
metric=server_gap value_ms=47876.698 node=server flow=10.1.0.41:40796-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53676-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4220-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4234-10.1.2.103:8080
metric=server_gap value_ms=68537.495 node=server flow=10.1.0.41:40804-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53684-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53678-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4248-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4246-10.1.2.103:8080
metric=server_gap value_ms=47797.258 node=server flow=10.1.0.41:40828-10.1.2.103:8083
metric=server_gap value_ms=66805.669 node=server flow=10.1.0.41:40818-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:53688-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53696-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:53708-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4256-10.1.2.103:8080
metric=server_gap value_ms=68537.395 node=server flow=10.1.0.41:40838-10.1.2.103:8083
metric=server_gap value_ms=71865.162 node=server flow=10.1.0.41:40844-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:9630-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53724-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9640-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9646-10.1.2.103:8082
metric=server_gap value_ms=47797.287 node=server flow=10.1.0.41:40860-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:4264-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:9648-10.1.2.103:8082
metric=server_gap value_ms=47797.676 node=server flow=10.1.0.41:40862-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:9650-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53740-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:4276-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:9664-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9676-10.1.2.103:8082
metric=server_gap value_ms=68537.163 node=server flow=10.1.0.41:40874-10.1.2.103:8083
missing=first_inbound_payload flow=10.1.0.41:9692-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:9704-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:53742-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9706-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:4280-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:4292-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:9716-10.1.2.103:8082
missing=first_inbound_payload flow=10.1.0.41:4298-10.1.2.103:8080
missing=first_inbound_payload flow=10.1.0.41:53748-10.1.2.103:8081
missing=first_inbound_payload flow=10.1.0.41:9720-10.1.2.103:8082
missi--output truncated--
```
