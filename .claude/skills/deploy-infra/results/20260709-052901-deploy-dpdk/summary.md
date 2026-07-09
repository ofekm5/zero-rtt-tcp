# aws-ops: deploy (dpdk)

- Run: https://github.com/ofekm5/zero-rtt-demo/actions/runs/28996139123
- Trigger: push on `feat/mobile-ops`
- Time (UTC): 20260709-052901
- Job status so far: success

## Stack outputs
```
------------------------------------------------
|                DescribeStacks                |
+----------------------+-----------------------+
|  ServerNicPublicIp   |  18.199.141.123       |
|  ClientPublicIp      |  3.68.218.215         |
|  ServerNicInstanceId |  i-0500d7475ce659f50  |
|  ClientInstanceId    |  i-08e2620dbae83540a  |
|  ServerInstanceId    |  i-0822007a010da97a2  |
|  ServerPublicIp      |  18.193.88.150        |
|  ClientNicPublicIp   |  18.193.82.219        |
|  ClientNicInstanceId |  i-0a426faceb6ac1c3c  |
+----------------------+-----------------------+
```

Note: on the dpdk variant, the ClientNIC builds DPDK 23.11 from source in
user data — wait ~15-20 min after deploy before running an experiment.
