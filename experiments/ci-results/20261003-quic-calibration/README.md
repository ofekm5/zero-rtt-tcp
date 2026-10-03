# QUIC rate calibration and hardware evidence (2026-10-03)

`experiment.log`, `setup.log`, and `run-meta.json` record the initial loopback
spike on the baseline client. `instance-types.json` confirms that this initial
client and server were **t3.micro**, despite an attempted sizing change in the
generated CDK template. The asset manifest still referenced the original
template, so that attempt did not change the deployed endpoints.

The 500/s delayed-path cold run achieved only 228/s. Subsequent 100/s baseline
bundles at 14:38, 14:44, and 14:50 UTC also used t3.micro endpoints and are
superseded for the final four-arm comparison. `cold100-*-cpu.log` belongs to
that initial t3.micro cold run; these samples must not be attributed to m5.xlarge.

The baseline was then synthesized with endpoint overrides before `app.synth()`
and redeployed through `infra/baseline/deploy.ps1`. CDK's change set contained
only the two endpoint instance types. `matched-instance-types.json` confirms
all four compared endpoints now use **m5.xlarge**; baseline NIC VMs remain
t3.micro and DPDK NIC VMs remain c5n.large. The committed infrastructure source
was not changed.

`matched-experiment.log` and `matched-run-meta.json` record the repeated spike
on m5.xlarge: all tested rates through 3,200/s passed the 20 ms lag gate; this
is the highest tested rate, not a measured capacity ceiling. The final rate
remains a conservative 100/s, identical across all four arms.

`matched-client-cpu.log` and `matched-server-cpu.log` came from successful SSM
command `f9204eaf-8861-4635-91fd-6f9c39ca6156`, sampling every 250 ms between
14:58:41 and 15:06:13 UTC. CPU is the delta of `/proc/<pid>/stat` user/system
ticks divided by `SC_CLK_TCK` and elapsed monotonic time, as a percentage of
one core. Only nonzero samples are emitted.

The cold client (PID 2901) has 82 active samples: mean 32.156%, max 55.6%.
The cold server (PID 2887) has 84: mean 22.730%, max 43.7%.
Client-host PIDs 2739 and 2741 are the preceding loopback calibration, not the
delayed-path cold run, and are excluded. The sampler ended before resumed
measurement started; it provides no resumed CPU measurement. Preserve all raw
samples rather than attributing calibration CPU to the experiment.
