# aws-ops: status (dpdk)

- Run: https://github.com/ofekm5/zero-rtt-tcp/actions/runs/28997630458
- Trigger: push on `feat/mobile-ops`
- Time (UTC): 20260709-060206
- Job status so far: success
## CloudFormation stacks
- PacketTestStack: CREATE_COMPLETE
- SmartNicsStack: CREATE_COMPLETE

## smartnics instances
```
-------------------------------------------------------------------------------------------------------------------
|                                                DescribeInstances                                                |
+---------------------+----------------------+----------+------------+-------------+------------------------------+
|  smartnics-server   |  i-0822007a010da97a2 |  running |  t3.micro  |  10.1.2.149 |  2026-07-09T05:28:30+00:00   |
|  smartnics-servernic|  i-0500d7475ce659f50 |  running |  c5n.large |  10.1.1.213 |  2026-07-09T05:28:30+00:00   |
|  smartnics-clientnic|  i-0a426faceb6ac1c3c |  running |  c5n.large |  10.1.0.193 |  2026-07-09T05:28:31+00:00   |
|  smartnics-client   |  i-08e2620dbae83540a |  running |  t3.micro  |  10.1.0.95  |  2026-07-09T05:28:30+00:00   |
+---------------------+----------------------+----------+------------+-------------+------------------------------+
```
