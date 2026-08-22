# Graph Report - zero-rtt-tcp  (2026-08-22)

## Corpus Check
- 433 files · ~325,487 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1665 nodes · 3015 edges · 146 communities (115 shown, 31 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 434 edges (avg confidence: 0.85)
- Token cost: 0 input · 2,339,840 output

## Community Hubs (Navigation)
- Metrics Analyzer Tests
- Live 0-RTT Runtime Assets
- BlueField DPU Offload Spec
- Metrics Analyzer Implementation
- Scapy ClientNIC Pipeline
- T8 Translation OpenSpec Capabilities
- BlueField ReACT DNS App
- SYN-Punt DOCA Flow Handler
- Run-Experiment Skill Docs
- 0-RTT Debugging Incident Log
- Scapy Forwarder Unit Tests
- DPDK Capture and Pcap Writer
- Loadgen Unit Tests
- BlueField Hardware Concepts
- Endpoint.sh Unit Tests
- DPDK ISN Translation Findings
- llm-wiki BlueField Notes
- DPDK eth1 WAN Service
- Experiment Insights Log
- Scapy FlowKey Tests
- ServerNIC Checksum and Flow Table
- BlueField Offload Verification Concepts
- ServerNIC Flow Table Buffered
- ServerNIC Flow Table Tests
- Baseline CI Reports
- 100k Capacity Model Findings
- BlueField SYN-Punt and ReACT Apps
- Scalable Functions and DPDK Modes
- 0-RTT Measurement Concepts
- measure.sh Unit Tests
- ServerNIC Flow Table Design
- Scapy FlowTable Implementation
- Seq-Arith Unit Tests
- Scapy Packet Processor
- Packet Processor Unit Tests
- WAN-Delay Ring Buffer Tests
- DOCA ARGP and Logging
- Scapy Translator Implementation
- CDK PacketTestStack (dpdk)
- DOCA DPL and Flow Programming
- Full-DPDK Endpoint Interfaces Spec
- DPDK Pipeline and Logging
- iperf3 Stress Testing Spec
- BlueField Hugepages and Performance
- Endpoint Mock Harness
- CDK PacketTestStack (scapy)
- ClientNIC and ServerNIC Component Docs
- BlueField eSwitch Offload Spike
- CDK PacketTestStack (baseline)
- run_experiment.sh Orchestrator
- Loadgen Implementation
- SSH Lab Node Discovery
- Scapy FlowEntry Tests
- Packet-Flow Architecture Diagram
- eSwitch Offload Probe Design
- BlueField HW Offload Backend
- SSM Transport Helper
- Virtual-PMD Sender Tests
- BlueField Dev and Sim Docs
- run_experiment.sh Baseline Variant
- run_experiment.sh Load Knobs
- ReACT DNS Pcap Comparison
- Wire-Example DPDK App
- BlueField DPA and HW Gotchas
- DPDK and FlexIO Reference Docs
- ClientNIC Entry Point and Logger
- Hermes Experiment Agent Fleet
- DOCA ARGP, Logging, and EAL Docs
- lab-connect.sh CLI
- BlueField Offload Control Plane
- ServerNIC DPDK Shared Modules
- ClientNIC Forwarder Specs
- run_stress.sh Load Script
- Wire-Example Docker Setup
- OVS Bridge Setup Script
- BlueField Roadmap Track
- DPDK Test Runner Script
- Node-Script Runner Specs
- eBPF TCP Observability Assets
- clientnic.sh Node Script v1
- servernic.sh Node Script v1
- Think-Time Sweep Script
- Wire-Example run.sh
- Wire-Example Verify Script
- Wire-Example Build Script
- BlueField BFB Install Docs
- 100k Connection-Gap Roadmap
- Claude SSH Key Installer
- eSwitch Concept Docs
- clientnic.sh Node Script v2
- servernic.sh Node Script v2
- run_core.sh Orchestrator
- DOCA Image Compress Script
- Hugepages Allocation Script
- Client and Server App Wiki
- Baseline CDK Requirements
- BlueField HW Translation Spec
- DPDK CI Bundle Pointers
- ISN Channel Probe Script
- Offload Probe Verify Script
- client.sh Node Script
- ebpf-trace.sh Node Script
- server.sh Node Script
- OVS Counter Reader
- DNS Query Generator
- DNS Response Generator
- Counter Reader Script
- DNS Test Tmux Runner
- ReACT FP Sweep 20s
- ReACT FP Sweep 60s
- run_trace.sh Cleanup
- 0-RTT Roadmap Backlog
- ovs_config.sh Script
- react.sh Launcher
- DNS Response Delay Script
- Wire-Example build.sh
- SF Setup Script
- VNF Image Build Script
- Baseline Reports Aug 4
- Why-Not-Iperf Rationale
- Scapy ClientNIC Test Config
- Scapy ServerNIC Test Config
- Baseline Report Jun 9b
- Baseline Report Jun 9
- eBPF Observability Change Meta
- T8 Translation Change Meta
- OpenSpec Workflow Config
- BlueField Demo A Concept
- Human-Readable Output Concept
- Server App Doc

## God Nodes (most connected - your core abstractions)
1. `send_unlock Metric` - 46 edges
2. `FlowTable` - 42 edges
3. `FlowKey` - 40 edges
4. `_run_analyzer()` - 33 edges
5. `_write_text()` - 29 edges
6. `server_gap Metric` - 29 edges
7. `main()` - 26 edges
8. `main()` - 23 edges
9. `0-RTT Results Report` - 23 edges
10. `Pcap FCT Metric` - 23 edges

## Surprising Connections (you probably didn't know these)
- `ServerNIC DPDK Translator Binary` --semantically_similar_to--> `TCP Sequence/Ack Number Modification on DPA (doc example)`  [INFERRED] [semantically similar]
  experiments/dpdk/reports/integration-test-report-2026-08-08.md → infra/bluefield/docs/02-programming/dpa-programming.md
- `syn_punt Application` --semantically_similar_to--> `0-RTT ClientNIC Flow Table / Sequence Delta`  [INFERRED] [semantically similar]
  infra/bluefield/examples/syn-punt/TOPOLOGY.md → llm-wiki/raw/2026-03-06-integration-test-report.md
- `Troubleshooting Reference` --semantically_similar_to--> `ISN Delta Sequence Number Translation`  [INFERRED] [semantically similar]
  .claude/skills/run-experiment/references/troubleshooting.md → README.md
- `send_unlock is the metric that actually demonstrates 0-RTT` --conceptually_related_to--> `send_unlock Metric`  [INFERRED]
  experiments/insights.md → docs/index.html
- `TTFB, the metric the project exists to improve, has never been measured` --conceptually_related_to--> `send_unlock Metric`  [INFERRED]
  experiments/insights.md → docs/index.html

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **0-RTT Experiment Run & Analysis Workflow** — claude_skills_offline_analysis_skill_offline_analysis, claude_skills_run_experiment_skill_run_experiment, claude_skills_run_experiment_references_test_scripts_test_scripts, claude_skills_run_experiment_references_troubleshooting_troubleshooting, github_workflows_run_experiment_workflow [EXTRACTED 1.00]
- **2026-08-17 Ten-Run Baseline Reproducibility Series** — experiments_baseline_tcp_reports_baseline_report_2026_08_17_213245_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_213729_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_214206_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_214643_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_215139_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_215619_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_220041_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_220512_report, experiments_baseline_tcp_reports_baseline_report_2026_08_17_220932_report [INFERRED 0.85]
- **Load Generator Configuration Knobs** — concept_load_parallel_knob, concept_load_rate_knob, concept_load_ports_knob, concept_load_bytes_knob, concept_load_concurrency_knob, concept_load_timeout_knob, concept_netem_rtt_ms_knob [EXTRACTED 1.00]
- **CI 100k-connection Baseline vs DPDK Comparison (2026-08-11)** — experiments_ci_results_20260811_080308_baseline_reports_baseline_report_2026_08_11_080243, experiments_ci_results_20260811_082919_dpdk_reports_integration_test_report_2026_08_11, concept_netem_rtt_ms [INFERRED 0.85]
- **CI 2000-conn Baseline vs DPDK Comparison (2026-08-11)** — experiments_ci_results_20260811_085652_baseline_reports_baseline_report_2026_08_11_085628, experiments_ci_results_20260811_090202_dpdk_reports_integration_test_report_2026_08_11, concept_send_unlock_metric [INFERRED 0.85]
- **DPDK 2026-08-17 Sweep Session (capacity100k + run01 + run02)** — experiments_dpdk_reports_integration_test_report_2026_08_17_capacity100k, experiments_dpdk_reports_integration_test_report_2026_08_17_run01, experiments_dpdk_reports_integration_test_report_2026_08_17_run02 [INFERRED 0.75]
- **2026-08-17 10-Run DPDK Sweep** — experiments_dpdk_reports_integration_test_report_2026_08_17_run03, experiments_dpdk_reports_integration_test_report_2026_08_17_run04, experiments_dpdk_reports_integration_test_report_2026_08_17_run05, experiments_dpdk_reports_integration_test_report_2026_08_17_run06, experiments_dpdk_reports_integration_test_report_2026_08_17_run07, experiments_dpdk_reports_integration_test_report_2026_08_17_run08, experiments_dpdk_reports_integration_test_report_2026_08_17_run09, experiments_dpdk_reports_integration_test_report_2026_08_17_run10 [INFERRED 0.85]
- **BlueField-3 Operating Mode Comparison** — bluefield_concept_classic_dpdk_mode, bluefield_concept_smartnic_mode, bluefield_concept_hybrid_mode [EXTRACTED 1.00]
- **0-RTT Latency Metric Tiering (send_unlock / FCT / server_gap)** — concept_send_unlock_metric, concept_pcap_fct_metric, concept_server_gap_metric [EXTRACTED 1.00]
- **Hardware Exception-Path Punting Pattern** — concept_syn_punt_pattern, concept_react_app, concept_hairpin_forwarding [INFERRED 0.80]
- **Local BlueField Testing Without Hardware** — infra_bluefield_docs_04_development_local_simulation_strategies, concept_virtual_pmd, concept_testpmd [EXTRACTED 1.00]
- **BlueField-3 Three-Tier Performance Model (Flow Engine / DPA / ARM)** — concept_nic_flow_engine, concept_dpa_cores, concept_arm_dpdk [EXTRACTED 1.00]
- **BlueField-3 DPU Provisioning Pipeline** — infra_bluefield_setup_bfb_install, infra_bluefield_setup_dpu_mode_setup, infra_bluefield_setup_install_doca_all, infra_bluefield_setup_install_meson_ninja [INFERRED 0.75]
- **0-RTT Integration Test Debugging Saga (2026-03-06 to 2026-03-18)** — llm_wiki_raw_2026_03_06_integration_test_report, llm_wiki_raw_2026_03_07_integration_test_report, llm_wiki_raw_2026_03_12_integration_test_report, llm_wiki_raw_2026_03_18_integration_test_report [INFERRED 0.85]
- **Wire-Example Documentation Set (Basic, Networking, Docker)** — infra_bluefield_examples_wire_example_readme, infra_bluefield_examples_wire_example_networking_setup, infra_bluefield_examples_wire_example_docker [INFERRED 0.85]
- **tc/netem-never-installed finding traced across insights, methodology review, and roadmap** — llm_wiki_wiki_experiment_insights, llm_wiki_wiki_measurement_methodology, llm_wiki_wiki_roadmap [INFERRED 0.85]
- **2026-08-04 baseline/DPDK run pair and its telemetry review** — llm_wiki_raw_2026_08_04_200506_baseline_report, llm_wiki_raw_2026_08_04_integration_test_report_dpdk, llm_wiki_raw_2026_08_08_telemetry_review_artifact [EXTRACTED 1.00]
- **100k-connection run and its capacity-model verification, tracked in roadmap** — llm_wiki_raw_2026_07_25_integration_test_report_dpdk, llm_wiki_wiki_capacity_model, llm_wiki_wiki_roadmap [INFERRED 0.90]
- **BlueField-3 Architecture Layer Trio (Hardware/Pipeline/Ports)** — llm_wiki_wiki_bluefield_architecture_hardware_overview, llm_wiki_wiki_bluefield_architecture_packet_pipeline, llm_wiki_wiki_bluefield_architecture_queues_ports_sfs [EXTRACTED 1.00]
- **SYN Punt Application Documentation Bundle** — llm_wiki_wiki_bluefield_examples_syn_punt_syn_punt_readme, llm_wiki_wiki_bluefield_examples_syn_punt_syn_punt_changes, llm_wiki_wiki_bluefield_examples_syn_punt_syn_punt_option1_fixed, llm_wiki_wiki_bluefield_examples_syn_punt_syn_punt_quickstart, llm_wiki_wiki_bluefield_examples_syn_punt_syn_punt_topology [EXTRACTED 1.00]
- **BF3 Local Development and Testing Workflow** — llm_wiki_wiki_bluefield_development_local_simulation_strategies, llm_wiki_wiki_bluefield_development_testing_strategies, llm_wiki_wiki_bluefield_development_debugging_guide, llm_wiki_wiki_bluefield_development_code_examples, llm_wiki_wiki_bluefield_development_performance_tuning [EXTRACTED 1.00]
- **NIC Flow Engine / DPA / DOCA DPL programming abstraction levels** — llm-wiki_wiki_bluefield_programming_doca_flow_api, llm-wiki_wiki_bluefield_programming_dpa_programming, llm-wiki_wiki_bluefield_programming_doca_dpl_p4 [INFERRED 0.85]
- **ISN ack-num translation split across ClientNIC and ServerNIC (matched pair)** — llm-wiki_wiki_components_clientnic_dpdk_forwarder, llm-wiki_wiki_components_servernic_dpdk, llm-wiki_wiki_bluefield_programming_dpa_programming_tcp_seq_ack_modification [INFERRED 0.85]
- **Client/Server apps as unmodified endpoints driven by loadgen.py** — llm-wiki_wiki_components_client_app, llm-wiki_wiki_components_server_app, llm-wiki_wiki_components_client_app_loadgen [EXTRACTED 1.00]
- **ClientNIC DPDK Port — proposal/design/tasks/spec quartet** — openspec_changes_archive_2026_03_25_clientnic_dpdk_port_proposal_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_design_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_tasks_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_dpdk_data_plane_spec_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_flow_table_c_spec_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_packet_pipeline_c_spec_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_seq_translator_c_spec_doc, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_syn_ack_spoofer_c_spec_doc [INFERRED 0.85]
- **DPDK Tests via SSM — proposal/design/tasks/spec quartet** — openspec_changes_archive_2026_03_28_dpdk_tests_via_ssm_proposal_doc, openspec_changes_archive_2026_03_28_dpdk_tests_via_ssm_design_doc, openspec_changes_archive_2026_03_28_dpdk_tests_via_ssm_tasks_doc, openspec_changes_archive_2026_03_28_dpdk_tests_via_ssm_specs_dpdk_ssm_test_runner_spec_doc [INFERRED 0.85]
- **DPDK infra facts shared by wiki doc, capability, and change design** — llm_wiki_wiki_infra_dpdk_stack_architecture_doc, cap_dpdk_data_plane, openspec_changes_archive_2026_03_25_clientnic_dpdk_port_design_doc [INFERRED 0.75]
- **T8 ISN Ack-Num Translation Shift Change Quartet** — openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_proposal, openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_design, openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_specs_isn_ack_num_channel_spec, concept_isn_ack_num_channel, concept_servernic_dpdk_data_plane [EXTRACTED 1.00]
- **Phase 1A eBPF Observability Change Quartet** — openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_proposal, openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_design, openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_specs_ebpf_tcp_observability_spec, openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_tasks, concept_ebpf_tcp_observability [EXTRACTED 1.00]
- **DPDK Node Script Integration Test Change Group** — openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_proposal, openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_tasks, openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_specs_dpdk_node_script_runner_spec, openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_specs_dpdk_ssm_test_runner_spec, concept_dpdk_node_script_runner [EXTRACTED 1.00]
- **Sequential Phases of the DPDK Data-Plane Effort** — c_t8_change, c_endpoint_pcap_measurement_cap, c_iperf3_stress_testing_cap, c_smartnic_dual_dpdk_io_cap [INFERRED 0.85]
- **Capabilities Co-Modified by full-dpdk-endpoint-interfaces** — c_dpdk_data_plane_cap, c_servernic_dpdk_data_plane_cap, c_smartnic_dual_dpdk_io_cap, c_dpdk_node_script_runner_cap [EXTRACTED 1.00]
- **Endpoint Measurement Pipeline (capture -> analyze -> report)** — c_analyze_metrics_py, c_measure_sh, c_run_core_sh [EXTRACTED 1.00]
- **T8 Shared Modules Reused Across x86 and BlueField ServerNIC Targets** — concept_flow_table_c_shared, concept_syn_handler_c_shared, concept_checksum_c_shared, concept_servernic_bluefield_target [EXTRACTED 1.00]
- **Three-Level Hardware Offload Verification (Accepted/Offloaded/Effective)** — concept_experiments_bluefield_probe, concept_doca_flow_api, concept_rte_flow_api, concept_dpdk_testpmd [EXTRACTED 1.00]
- **BlueField ServerNIC HW Offload Change Blocked on eSwitch Spike Verdict** — openspec_changes_bluefield_servernic_hw_offload_proposal, openspec_changes_bluefield_servernic_hw_offload_design, openspec_changes_verify_eswitch_tcp_seq_offload_proposal [EXTRACTED 1.00]
- **100k-connection scale run and its follow-ups** — roadmap_20_100k_connection_scale_run_done, roadmap_client_side_pcap_analysis_100k, roadmap_100k_connection_burst_gap [INFERRED 0.85]
- **ServerNIC delta computation and seq/ack translation pipeline** — openspec_specs_servernic_flow_table_c_spec_delta_computation, openspec_specs_servernic_syn_handler_c_spec_real_syn_ack_processing, openspec_specs_servernic_seq_translator_c_spec_client_to_server_ack_rewriting [INFERRED 0.85]
- **BlueField e-switch offload dependency chain** — roadmap_verify_eswitch_tcp_seq_offload, roadmap_bluefield_servernic_hw_offload, roadmap_demo_c_bluefield_clientnic_servernic_vm [INFERRED 0.85]
- **Zero-RTT TCP packet-flow pipeline (Client-ClientNIC-ServerNIC-Server)** — architecture_packetflow_client, architecture_packetflow_clientnic, architecture_packetflow_servernic, architecture_packetflow_server [EXTRACTED 1.00]

## Communities (146 total, 31 thin omitted)

### Community 0 - "Metrics Analyzer Tests"
Cohesion: 0.07
Nodes (30): CompletedProcess, _build_client_text(), _build_n_flows(), _build_server_text(), _parse_metric_lines(), _parse_missing_lines(), _parse_summary_lines(), Unit tests for experiments/utils/analyze_metrics.py The analyzer parses… (+22 more)

### Community 1 - "Live 0-RTT Runtime Assets"
Cohesion: 0.06
Nodes (54): clientnic/dpdk-forwarder/, infra/dpdk/cdk/smartnics_stack.py, infra/scapy/cdk/smartnics_stack.py, observability/ebpf/run_trace.sh, observability/ebpf/tcp_retransmit_trace.bt, observability/ebpf/tcp_state_trace.bt, servernic/dpdk/, .claude/skills/zero-rtt-integration-tester/SKILL.md (+46 more)

### Community 2 - "BlueField DPU Offload Spec"
Cohesion: 0.06
Nodes (50): experiments/utils/analyze_metrics.py, Change: bluefield-servernic-hw-offload, src/clientnic/dpdk-forwarder io.c/h (client-facing DPDK port), Requirement: Client MAC learned per-flow from SYN, not configured, Capability: dpdk-data-plane (ClientNIC, modified), Requirement: Dedicated kernel management ENI reserved for SSM, Requirement: Both data-plane interfaces run on DPDK ENA PMD (zero AF_PACKET), Requirement: No SmartNIC-side tcpdump on DPDK-owned interfaces (+42 more)

### Community 3 - "Metrics Analyzer Implementation"
Cohesion: 0.07
Nodes (45): analyze_client(), analyze_server(), _canon(), emit(), format_result(), _is_fin(), _is_syn(), _is_syn_ack() (+37 more)

### Community 4 - "Scapy ClientNIC Pipeline"
Cohesion: 0.08
Nodes (24): Pipeline, FlowTable, Pipeline: Parse → Decide+Modify — routes packets to correct handler., Return (ingress, is_syn, is_syn_ack) or None to drop., Unit tests for Translator and Pipeline., TestPipeline, main(), ServerNIC entry point. (+16 more)

### Community 5 - "T8 Translation OpenSpec Capabilities"
Cohesion: 0.07
Nodes (45): dpdk-data-plane capability, dpdk-ssm-test-runner capability, flow-table-c capability, packet-pipeline-c capability, seq-translator-c capability, syn-ack-spoofer-c capability, Docker-based DPDK test infra (removed), GitHub issue #11 (SSM edge cases) (+37 more)

### Community 6 - "BlueField ReACT DNS App"
Cohesion: 0.09
Nodes (32): bloom_filter_t, bloom_type_t, process_packets(), wait_for_rx_qi_changes(), bloom_get_indices(), bloom_size_callback(), bloom_swap_callback(), bloom_type_callback() (+24 more)

### Community 7 - "SYN-Punt DOCA Flow Handler"
Cohesion: 0.10
Nodes (26): add_syn_punt_entry(), doca_error_t, create_hairpin_pipe(), create_syn_punt_pipe(), doca_flow_cleanup(), doca_flow_init_module(), doca_flow_port_start_module(), doca_error_t (+18 more)

### Community 8 - "Run-Experiment Skill Docs"
Cohesion: 0.13
Nodes (37): CLAUDE.md Project Instructions, Offline Analysis Skill, Test Scripts Reference, Troubleshooting Reference, Run Experiment Skill, RUNS Lab Connect Skill, 0-RTT TCP, CI Results Bundle (+29 more)

### Community 9 - "0-RTT Debugging Incident Log"
Cohesion: 0.08
Nodes (33): 0-RTT ClientNIC Flow Table / Sequence Delta, 0-RTT Timing Validation (Spoofed SYN-ACK Before Real), Plain TCP Baseline Mode (no 0-RTT middleware), NVIDIA DOCA SDK, DPDK 23.11, ENA PMD (AWS DPDK driver), iptables FORWARD DROP Fix (port 8080), Kernel Forwarding Race Condition Bypassing 0-RTT (+25 more)

### Community 10 - "Scapy Forwarder Unit Tests"
Cohesion: 0.14
Nodes (23): build_frame(), checksum(), extract_ack(), extract_dst_mac(), extract_seq(), extract_src_mac(), Forwarder, ForwarderFlowEntry (+15 more)

### Community 11 - "DPDK Capture and Pcap Writer"
Cohesion: 0.13
Nodes (22): pcap_writer_close(), pcap_writer_open(), pcap_writer_write_mbuf(), eth0_init(), eth0_send(), eth0_tx_flush(), eth1_init(), eth1_send() (+14 more)

### Community 12 - "Loadgen Unit Tests"
Cohesion: 0.08
Nodes (17): Tests for experiments/utils/loadgen.py — the asyncio event-driven load…, Every scheduled connection is still opened and counted., The semaphore ceiling holds even when the arrival schedule outruns it., Defaults encode the measurement intent — a wrong default silently produces a…, 1 MB costs ~16 RTTs of transfer, burying the single RTT 0-RTT saves., The CLI default stays unpaced so ad-hoc invocations are unsurprising; the…, port-count=0 (or negative) still yields exactly one port, never an empty list., End-to-end: real sockets over loopback, no mocking. (+9 more)

### Community 13 - "BlueField Hardware Concepts"
Cohesion: 0.12
Nodes (29): ARM Cores (Cortex-A78 control plane), ASAP2 (Accelerated Switching and Packet Processing), Classic DPDK Mode (Separated Host Mode), ConnectX NIC Engine (ASIC), DOCA DPL (P4-based declarative pipeline language), doca_flow API (pipe-based hardware flow programming), DPA (Data Path Accelerator), eSwitch (Embedded Switch) (+21 more)

### Community 14 - "Endpoint.sh Unit Tests"
Cohesion: 0.13
Nodes (15): _cmds_for(), Tests for experiments/utils/endpoint.sh — the shared endpoint setup/capture/…, Both stacks must model the same total RTT or the comparison is void.…, A leftover endpoint qdisc must fail the run, not be assumed absent., A silently-failed tc turns the run into an intra-VPC measurement where one RTT…, iproute-tc is not in the base AMI (F15); without it every netem command fails…, Both stacks must get identical endpoint conditions, or the comparison between…, send_unlock is the primary result; FCT and server_gap are throughput-bound and… (+7 more)

### Community 15 - "DPDK ISN Translation Findings"
Cohesion: 0.30
Nodes (28): TCP SYN Proxy / SYN-ACK Generation on DPA (doc example), Missing first_inbound_payload Anomaly (capacity failures), ISN Ack-Num Translation Shift (0-RTT DPDK Implementation), DPDK ISN Ack-Num Translation Shift, NETEM_RTT_MS Emulated WAN Parameter, NETEM_RTT_MS emulated-WAN-latency parameter, Pcap FCT Metric, server_gap Metric (+20 more)

### Community 16 - "llm-wiki BlueField Notes"
Cohesion: 0.12
Nodes (28): BFB (BlueField Bundle File), BlueField-3 DPU, DOCA Flow Rules Engine, FCT Tail Investigation (deleted wiki note), HANDOFF-fct-tail.md, llm-wiki Vault (four-layer wiki/raw/index/log contract), Load Generation and Think Time (wiki note), Measurement Methodology (wiki note) (+20 more)

### Community 17 - "DPDK eth1 WAN Service"
Cohesion: 0.17
Nodes (22): rte_get_tsc_hz(), rte_rdtsc(), rte_pktmbuf_free(), eth1_init(), eth1_send(), eth1_tx_flush(), eth1_wan_flush_all(), eth1_wan_service() (+14 more)

### Community 18 - "Experiment Insights Log"
Cohesion: 0.09
Nodes (27): Experiment Insights Log, First valid baseline-vs-0-RTT comparison: send_unlock drops a full RTT, FCT does not move, Open: 0-RTT FCT tail reaches 537ms while p99 sits at 201.6ms; cause not established, full-dpdk-endpoint-interfaces 3rd ENI does not fix endpoint scaling, All-metrics-empty run is a harness failure, not a data-plane result, Recurring harness traps: kernel-vs-datapath races and false validator failures, Intra-VPC RTT too small for 0-RTT benefit; demo needs emulated WAN latency, send_unlock is the metric that actually demonstrates 0-RTT (+19 more)

### Community 19 - "Scapy FlowKey Tests"
Cohesion: 0.12
Nodes (9): FlowKey, 4-tuple connection identifier., Unit tests for flow_table.py, Tests for FlowKey dataclass., Tests for buffer_packet / flush_buffer on FlowTable., Tests for FlowTable class., TestFlowKey, TestFlowTable (+1 more)

### Community 20 - "ServerNIC Checksum and Flow Table"
Cohesion: 0.14
Nodes (16): recalc_ip_checksum(), recalc_tcp_checksum(), ft_create(), ft_extract_key(), ft_init(), ft_lookup(), ft_reverse_key(), hash_key() (+8 more)

### Community 21 - "BlueField Offload Verification Concepts"
Cohesion: 0.15
Nodes (25): ARM DPDK software path, CI/CD DPDK Testing (GitLab CI / GitHub Actions), DOCA Test Framework (line-rate benchmarking), DPA (programmable hardware cores), eSwitch-is-not-separate-hardware Misconception, FlexIO (DPA/rte_flow integration), Hardware Hairpin Forwarding (DOCA_FLOW_FWD_PORT bump-in-wire), Hardware Offload Verification (counters/ovs-dpctl) (+17 more)

### Community 22 - "ServerNIC Flow Table Buffered"
Cohesion: 0.17
Nodes (20): recalc_ip_checksum(), recalc_tcp_checksum(), ft_buffer_pkt(), ft_create(), ft_extract_key(), ft_flush_buffer(), ft_init(), ft_lookup() (+12 more)

### Community 23 - "ServerNIC Flow Table Tests"
Cohesion: 0.13
Nodes (20): FlowTable, _hash_key(), ServerNIC flow table unit tests — pure Python (no DPDK required). Models the C…, A single flow can be shed by the global ceiling well before FT_MAX_BUFFER., Two keys that land on the same initial slot are stored separately., Mirrors ft_buffer_pkt(ft, entry, data, len): -1 per-flow cap, -2 global cap., Mirrors ft_flush_buffer(ft, entry, out, count): drains entry, decrements global…, test_buffer_and_flush() (+12 more)

### Community 24 - "Baseline CI Reports"
Cohesion: 0.13
Nodes (14): Baseline TCP Report 2026-08-17-221348, CI Bundle README (baseline 20260811-080308), CI Bundle Report (baseline 20260811-080308), Baseline TCP Report 2026-08-11-080243 (100k), CI Bundle README (baseline 20260811-085652), CI Bundle Report (baseline 20260811-085652), Baseline TCP Report 2026-08-11-085628 (2000conn), latest-baseline.txt Pointer (+6 more)

### Community 25 - "100k Capacity Model Findings"
Cohesion: 0.13
Nodes (16): 100k-connection burst-absorption gap (68.8% established), RX ring depth vs. burst-size ceiling (RX_RING_SIZE=1024 / RX_BURST_SIZE=32), Measurement flaws F2-F16 classification, docs/capacity-model.md (source), discover_nodes(), fail(), log(), pass() (+8 more)

### Community 26 - "BlueField SYN-Punt and ReACT Apps"
Cohesion: 0.24
Nodes (20): Bloom Filter (Classic/Counting/Thread-Safe), DOCA Flow API, Open vSwitch (OVS), ReACT DNS Filtering DOCA Application, syn_punt Application, syn-punt DOCA Flow handler module (doca_flow.c/h -> doca_flow_handler.c/h), SYN-Punt Selective Exception-Path Pattern, ReACT Experiment Procedure (doc) (+12 more)

### Community 27 - "Scalable Functions and DPDK Modes"
Cohesion: 0.14
Nodes (20): Classic DPDK Mode (Separated Host Mode), Hairpin Queues (NIC-to-NIC bypass), mlnx-sf CLI tool, mlxdevm sf CLI tool, NUMA-aware allocation, apps/react-main (stats/memory/timing example), SF Representor vs SF Netdev Distinction, RSS (Receive Side Scaling) (+12 more)

### Community 28 - "0-RTT Measurement Concepts"
Cohesion: 0.19
Nodes (20): Client think time (T) as a workload axis, fct metric (flow completion time), iperf2 as load generator (deprecated/removed from latency path), loadgen.py paced-arrival load generation, netem-emulated WAN RTT placement, send_unlock Metric, T8 ISN ack-num translation shift scheme, Integration Test Report — 2026-06-22 (+12 more)

### Community 29 - "measure.sh Unit Tests"
Cohesion: 0.14
Nodes (13): _extract_inline_python(), Smoke tests for the summarize_metric() Python inline in…, Return the Python code between <<'PY' ... PY in measure.sh., Run the measure.sh inline Python with given inputs, return stdout., Tests for the summarize_metric inline Python in measure.sh., A line in the actual emit() format is parsed and a sample is reported., Multiple emit() lines for the same metric/node are all aggregated., Lines for a different metric name are not counted. (+5 more)

### Community 30 - "ServerNIC Flow Table Design"
Cohesion: 0.10
Nodes (20): Delta computation (seq_delta = V - real_isn), Fixed-size hash table (1024 slots, linear probing), Flow entry state tracking (V, real_isn, delta), Flow key identification (4-tuple), Per-flow packet buffering (cap 64), Ingress-based routing to handlers, Packet parsing and validation, Re-capture loop prevention (own-MAC filter) (+12 more)

### Community 31 - "Scapy FlowTable Implementation"
Cohesion: 0.12
Nodes (12): Packet, FlowEntry, FlowTable, Flow table for tracking TCP connections and sequence number state., Connection state for a single flow., Thread-safe flow table for tracking connections., Create a new flow entry., Get flow entry by key. (+4 more)

### Community 32 - "Seq-Arith Unit Tests"
Cohesion: 0.27
Nodes (17): build_ipv4_tcp(), checksum(), extract_ack(), extract_seq(), ServerNIC sequence-number arithmetic unit tests — no DPDK required. Validates…, Applying delta forward then reverse recovers the original values., Return a minimal 54-byte Ethernet + IPv4 + TCP frame., rewrite_ack() (+9 more)

### Community 33 - "Scapy Packet Processor"
Cohesion: 0.18
Nodes (5): PacketProcessor, FlowTable, PacketProcessor: SYN and SYN-ACK handling + spoofed SYN-ACK generation., TestGenerateRandomIsn, TestProcessSynAck

### Community 34 - "Packet Processor Unit Tests"
Cohesion: 0.27
Nodes (6): _make_processor(), _make_syn(), patch, Unit tests for PacketProcessor (SYN/SYN-ACK handling + spoofed SYN-ACK…, TestCreateSynAck, TestProcessSyn

### Community 35 - "WAN-Delay Ring Buffer Tests"
Cohesion: 0.36
Nodes (13): mb(), test_disabled_is_a_noop(), test_drain_all_ignores_deadlines(), test_max_caps_the_batch(), test_order_is_preserved(), test_packet_is_held_until_its_deadline(), test_ring_full_drops_and_counts(), test_wraparound() (+5 more)

### Community 36 - "DOCA ARGP and Logging"
Cohesion: 0.17
Nodes (15): apps/react-main (BlueField example app), apps/syn-punt (BlueField example app), apps/wire-example (BlueField example app), DOCA ARGP (Argument Parsing Library), doca_argp_init(), doca_argp_set_dpdk_program(), DOCA Logging, doca_log_backend_* (standard/file backends) (+7 more)

### Community 37 - "Scapy Translator Implementation"
Cohesion: 0.19
Nodes (6): FlowTable, Translator: handles seq/ack rewriting for both data directions., Client→server: subtract delta from ACK, or buffer if delta unknown., Server→client: add delta to SEQ., Translator, TestTranslator

### Community 38 - "CDK PacketTestStack (dpdk)"
Cohesion: 0.15
Nodes (9): PacketTestStack, Construct, Stack, _bind_data_enis_to_vfio(), Construct, IVpc, Stack, User-data lines that bind every non-primary ENI to vfio-pci. ENIs are… (+1 more)

### Community 39 - "DOCA DPL and Flow Programming"
Cohesion: 0.21
Nodes (14): DOCA DPL (P4) Programming, DOCA DPL (P4-based declarative packet-processing language), doca-p4c (DPL compiler), DOCA Flow API Programming, doca_flow API (NVIDIA, pipe-based), DOCA Flow pipe/entry model, rte_flow API (DPDK), DPA Programming Guide (+6 more)

### Community 40 - "Full-DPDK Endpoint Interfaces Spec"
Cohesion: 0.16
Nodes (14): Both data-plane interfaces run on DPDK ENA PMD, Dedicated kernel management ENI reserved for SSM, DPDK port roles resolved by ENI identity, not port ID, Next-hop MAC supplied via CLI where unlearnable, smartnic-dual-dpdk-io spec, #18 — full-DPDK endpoint interfaces (done), ClientNIC dual-DPDK data plane, Full-owner design diff (removed clientnic/dpdk/ vs dpdk-forwarder) (+6 more)

### Community 41 - "DPDK Pipeline and Logging"
Cohesion: 0.20
Nodes (5): log_init(), pipeline_feed_eth1(), pipeline_feed_eth2(), pipeline_init(), port_in_app_range()

### Community 42 - "iperf3 Stress Testing Spec"
Cohesion: 0.21
Nodes (13): Requirement: iperf3 client node script, iperf3-client.sh node script, Requirement: iperf3 installed on Client and Server VMs, Requirement: iperf3 experiment orchestrator, Requirement: iperf3 server node script, iperf3-server.sh node script, Capability: iperf3-stress-testing, run_iperf3_experiment.sh orchestrator (+5 more)

### Community 43 - "BlueField Hugepages and Performance"
Cohesion: 0.27
Nodes (13): ARM Cores (BlueField-3 CPU Complex), ASAP2 (Accelerated Switching and Packet Processing), DPA (Data Path Accelerator), eSwitch (Embedded Switch), DPDK Hugepages, SmartNIC Mode (Embedded Switch Mode), Hugepages Setup (doc), Performance Optimization (doc) (+5 more)

### Community 44 - "Endpoint Mock Harness"
Cohesion: 0.19
Nodes (6): NETEM_RTT_MS, remote_bg(), remote_run(), remote_stdout(), endpoint_mock_harness.sh script, _trace()

### Community 45 - "CDK PacketTestStack (scapy)"
Cohesion: 0.15
Nodes (8): PacketTestStack, Construct, Stack, Construct, IVpc, Stack, Baseline 4-VM chain: plain kernel IP forwarding, no DPDK, no Scapy middleware.…, SmartNicsStack

### Community 46 - "ClientNIC and ServerNIC Component Docs"
Cohesion: 0.19
Nodes (13): ClientNIC (component overview), ClientNIC DPDK Forwarder, Dual-DPDK data plane (both endpoint ports on ENA PMD), ISN ack-num channel (V stamping), packet_processor.c/h: proc_handle_syn (spoof SYN-ACK + stamp V), ClientNIC DPDK Forwarder Tests, scapy/src/utils/translator.py (seq/ack rewrite + checksum recalc, deprecated), validate_0rtt_capture.py (pcap analysis tool) (+5 more)

### Community 47 - "BlueField eSwitch Offload Spike"
Cohesion: 0.24
Nodes (12): bluefield-runs3-dpu (10.13.36.16), dpdk-testpmd, ens16f0np0 (x86 host VM NIC), oob_net0 (DPU management port), p0 (dark port, no carrier), pf0hpf (sole data path port), BlueField ServerNIC HW Offload Design, Verify eSwitch TCP Seq Offload Design (+4 more)

### Community 48 - "CDK PacketTestStack (baseline)"
Cohesion: 0.17
Nodes (7): PacketTestStack, Construct, Stack, Construct, IVpc, Stack, SmartNicsStack

### Community 49 - "run_experiment.sh Orchestrator"
Cohesion: 0.25
Nodes (7): fail(), log(), pass(), PYTHONIOENCODING, PYTHONUTF8, run_experiment.sh script, warn()

### Community 50 - "Loadgen Implementation"
Cohesion: 0.29
Nodes (9): _build_parser(), _client_conn(), main(), _parse_ports(), Bind and start accepting on every port. Accepting begins immediately on return…, Open `parallel` connections, paced at `rate` connections/sec (0 = burst).…, run_client(), run_server() (+1 more)

### Community 51 - "SSH Lab Node Discovery"
Cohesion: 0.27
Nodes (8): get_lab_mac(), json_idx(), _lab_ssh(), _lab_ssh_bg(), remote_bg(), remote_run(), remote_stdout(), ssh_lab.sh script

### Community 52 - "Scapy FlowEntry Tests"
Cohesion: 0.22
Nodes (3): Tests for FlowEntry dataclass., TestFlowEntry, FlowEntry

### Community 53 - "Packet-Flow Architecture Diagram"
Cohesion: 0.31
Nodes (10): Client, ClientNIC, ServerNIC delta calculation (real SYN-ACK Seq:3000 vs spoofed Seq:300), Annotation: from this point translation could theoretically be performed by either side, Client-to-server rewrite: subtract delta from seq/ack, Server-to-client rewrite: adding delta to ack, Server, ServerNIC (+2 more)

### Community 54 - "eSwitch Offload Probe Design"
Cohesion: 0.28
Nodes (9): eswitch-offload-probe capability, experiments/bluefield/probe/ harness, Scalable Function (SF) egress fallback, Verify eSwitch TCP Seq Offload Proposal, Verify eSwitch Offload Tasks, D1 — Test in the e-switch domain, not the NIC domain, D2 — Three-level verification: accepted/offloaded/effective, D4 — PARTIAL is a defined outcome with a defined consequence (+1 more)

### Community 55 - "BlueField HW Offload Backend"
Cohesion: 0.36
Nodes (9): io.c (BlueField mlx5 representor I/O), offload.c backend interface, pipeline.c (BlueField handshake dispatch), translator.c (x86 ServerNIC, not reused), BlueField ServerNIC HW Offload Proposal, BlueField ServerNIC HW Offload Tasks, D4 — Sibling target, shared modules by reference, D5 — Exception path must be observable (SC3 measurability) (+1 more)

### Community 56 - "SSM Transport Helper"
Cohesion: 0.28
Nodes (4): json_idx(), ssm.sh script, ssm_run(), ssm_stdout()

### Community 57 - "Virtual-PMD Sender Tests"
Cohesion: 0.33
Nodes (8): main(), Send TCP SYN-ACK packets (should be fast-forwarded), Send TCP data packets (should be fast-forwarded), Send UDP packets (should be fast-forwarded), send_data_packets(), send_syn_ack_packets(), send_syn_packets(), send_udp_packets()

### Community 58 - "BlueField Dev and Sim Docs"
Cohesion: 0.36
Nodes (8): DPDK Virtual PMDs (null/pcap/tap/ring/memif), ovs-vsctl / ovs-dpctl CLI tools, dpdk-testpmd tool, CLI Commands Reference (doc), Code Examples Repository, Debugging Guide, Local Simulation Strategies for DOCA/DPDK Development, Testing Strategies for BF3 DPU Applications

### Community 59 - "run_experiment.sh Baseline Variant"
Cohesion: 0.29
Nodes (4): log(), PYTHONIOENCODING, PYTHONUTF8, run_experiment.sh script

### Community 60 - "run_experiment.sh Load Knobs"
Cohesion: 0.36
Nodes (6): fail(), LOAD_PARALLEL, LOAD_PORTS, log(), pass(), run_experiment.sh script

### Community 61 - "ReACT DNS Pcap Comparison"
Cohesion: 0.39
Nodes (7): extract_dns_key(), load_dns_keys(), main(), Extract (dport, dns.id) tuple from DNS response packet, Load DNS keys from the server-side PCAP, Stream client-side PCAP and compare with server, stream_dns()

### Community 62 - "Wire-Example DPDK App"
Cohesion: 0.36
Nodes (5): list_ports(), main(), port_init(), wire_lcore(), wire_ports()

### Community 63 - "BlueField DPA and HW Gotchas"
Cohesion: 0.29
Nodes (8): Hardware parser programming (custom protocols), DPA use case: TCP seq/ack number modification, ovs-vsctl (OVS management), Common Gotchas and Pitfalls, Gotcha #4: hardware parser needs DOCA DPL, not rte_flow, Gotcha #3: SF representor vs SF netdev usage, Gotcha #7: TCP seq/ack modification requires DPA or ARM, translator.c/h: trans_c2s (ACK -= delta) / trans_s2c (SEQ += delta)

### Community 64 - "DPDK and FlexIO Reference Docs"
Cohesion: 0.29
Nodes (8): DPDK Integration, FlexIO integration with rte_flow, rte_eth_rx_burst / rte_eth_tx_burst, API Cheatsheet, FlexIO function signatures, rte_flow function signatures, CLI Commands Reference, mlnx-sf (Scalable Function management)

### Community 65 - "ClientNIC Entry Point and Logger"
Cohesion: 0.25
Nodes (6): main(), ClientNIC entry point., Logger, Logging setup for ClientNIC., Configure and return the ClientNIC logger., setup_logging()

### Community 66 - "Hermes Experiment Agent Fleet"
Cohesion: 0.48
Nodes (7): GitHub Actions aws-ops / run-experiment workflow, experiments/ci-results/ bundles, experiment-analyst (Hermes agent), experiment-runner (Hermes agent), experiment-warden (Hermes agent), Paperclip orchestration layer, 0-RTT Experiment Agent Fleet (Wiki)

### Community 67 - "DOCA ARGP, Logging, and EAL Docs"
Cohesion: 0.40
Nodes (6): doca_argp (DOCA argument parsing library), DOCA Logging (doca_log backends and levels), DPDK EAL (rte_eal_init/remote_launch core functions), DOCA Argument Parsing Library (doca_argp), DOCA Logging, DPDK Core Functions (rte_eal_*)

### Community 68 - "lab-connect.sh CLI"
Cohesion: 0.60
Nodes (5): cmd_bind(), cmd_help(), cmd_ssh(), cmd_status(), lab-connect.sh script

### Community 69 - "BlueField Offload Control Plane"
Cohesion: 0.33
Nodes (6): bluefield-offload-control-plane capability, V / spoofed ISN ack-num channel (T8), BlueField Offload Control Plane Spec, ISN Ack-Num Channel Spec, D1 — Rule installed only after delta known (SYN-ACK), D3 — Teardown driven by FIN/RST punt

### Community 70 - "ServerNIC DPDK Shared Modules"
Cohesion: 0.47
Nodes (6): checksum.c (shared T8 module), flow_table.c (shared T8 module), src/servernic/bluefield/ meson target, src/servernic/dpdk (live ServerNIC impl), syn_handler.c (shared T8 module), ServerNIC DPDK Data Plane Spec

### Community 71 - "ClientNIC Forwarder Specs"
Cohesion: 0.53
Nodes (6): src/clientnic/dpdk-forwarder (live ClientNIC impl), ClientNIC Forwarder Flow Table Spec, ClientNIC Forwarder Pipeline Spec, ClientNIC Forwarder SYN Spoof Spec, ClientNIC Forwarder Transparent Forwarding Spec, DPDK Data Plane Spec (ClientNIC)

### Community 72 - "run_stress.sh Load Script"
Cohesion: 0.33
Nodes (5): LOAD_BYTES, LOAD_CONCURRENCY, LOAD_PARALLEL, LOAD_RATE, run_stress.sh script

### Community 73 - "Wire-Example Docker Setup"
Cohesion: 0.60
Nodes (5): print_error(), print_header(), print_info(), print_success(), docker_setup.sh script

### Community 74 - "OVS Bridge Setup Script"
Cohesion: 0.60
Nodes (5): print_error(), print_header(), print_info(), print_success(), ovs_setup.sh script

### Community 75 - "BlueField Roadmap Track"
Cohesion: 0.40
Nodes (6): Gap: BlueField lab deployment change (not yet proposed), bluefield-servernic-hw-offload — blocked on the spike, BlueField-3 track, Demo B — all-VM 4-chain on Proxmox, Demo C — BlueField as ClientNIC, ServerNIC stays a VM, verify-eswitch-tcp-seq-offload — in progress, DPU left mutated

### Community 76 - "DPDK Test Runner Script"
Cohesion: 0.53
Nodes (4): log_fail(), log_pass(), log_skip(), run_dpdk_tests.sh script

### Community 77 - "Node-Script Runner Specs"
Cohesion: 0.40
Nodes (5): analyze_metrics.py, experiments/utils/measure.sh, DPDK Node Script Runner Spec, eBPF TCP Observability Spec, Endpoint Pcap Measurement Spec

### Community 78 - "eBPF TCP Observability Assets"
Cohesion: 0.70
Nodes (5): run_trace.sh (eBPF orchestrator), tcp_retransmit_trace.bt, tcp_state_trace.bt, eBPF TCP Observability (Wiki), eBPF TCP Observability (README)

### Community 79 - "clientnic.sh Node Script v1"
Cohesion: 0.60
Nodes (3): cleanup(), log(), clientnic.sh script

### Community 80 - "servernic.sh Node Script v1"
Cohesion: 0.60
Nodes (3): cleanup(), log(), servernic.sh script

### Community 81 - "Think-Time Sweep Script"
Cohesion: 0.70
Nodes (4): fail(), log(), pass(), run_think_sweep.sh script

### Community 82 - "Wire-Example run.sh"
Cohesion: 0.70
Nodes (4): print_error(), print_info(), print_success(), run.sh script

### Community 83 - "Wire-Example Verify Script"
Cohesion: 0.70
Nodes (4): print_error(), print_info(), print_success(), test_verify.sh script

### Community 84 - "Wire-Example Build Script"
Cohesion: 0.60
Nodes (3): fail(), log(), build_wire_image.sh script

### Community 85 - "BlueField BFB Install Docs"
Cohesion: 0.40
Nodes (5): BlueField BFB Installation Guide, BFB (BlueField Bundle File), rshim service, DPU Mode Setup, SoC mode configuration (mlxconfig INTERNAL_CPU_*)

### Community 86 - "100k Connection-Gap Roadmap"
Cohesion: 0.40
Nodes (5): Idea: close the 100k connection-burst gap, #20 — 100k-connection scale run (done), Client-side pcap analysis doesn't scale to 100k, DDoS resistance, Infra hand-tailoring — closed

### Community 87 - "Claude SSH Key Installer"
Cohesion: 0.83
Nodes (3): add_config_block(), install_on_host(), install_claude_ssh_key.sh script

### Community 88 - "eSwitch Concept Docs"
Cohesion: 0.67
Nodes (4): DOCA Flow API, eSwitch is not separate hardware, only flow-table entries, eSwitch and NIC Flow Engine, BlueField-3 DPU Documentation

### Community 89 - "clientnic.sh Node Script v2"
Cohesion: 0.83
Nodes (3): cleanup(), log(), clientnic.sh script

### Community 90 - "servernic.sh Node Script v2"
Cohesion: 0.83
Nodes (3): cleanup(), log(), servernic.sh script

### Community 91 - "run_core.sh Orchestrator"
Cohesion: 0.67
Nodes (3): run_experiment(), run_core.sh script, warn_if_truncated()

### Community 92 - "DOCA Image Compress Script"
Cohesion: 0.83
Nodes (3): fail(), log(), compress_doca_image.sh script

### Community 93 - "Hugepages Allocation Script"
Cohesion: 0.83
Nodes (3): error(), log(), allocate_hugepages.sh script

### Community 94 - "Client and Server App Wiki"
Cohesion: 0.83
Nodes (4): Client App (wiki entry), iperf2 removal rationale (thread-per-connection, no arrival pacing), experiments/utils/loadgen.py (asyncio load generator), Server App (wiki entry)

### Community 95 - "Baseline CDK Requirements"
Cohesion: 0.67
Nodes (3): aws-cdk-lib (AWS CDK Python library), constructs (CDK constructs library), Baseline CDK Python Requirements

### Community 96 - "BlueField HW Translation Spec"
Cohesion: 0.67
Nodes (3): bluefield-hw-translation capability, BlueField HW Translation Spec, D2 — Two directional hardware rules per flow

### Community 97 - "DPDK CI Bundle Pointers"
Cohesion: 1.00
Nodes (3): CI Bundle README (dpdk 20260811-090202), latest.txt Pointer, latest-dpdk.txt Pointer

### Community 111 - "0-RTT Roadmap Backlog"
Cohesion: 0.67
Nodes (3): #21 Run experiment on both DPDK and baseline stacks, Multi-round send in the load generator, Client App (loadgen-driven, unmodified TCP client)

## Ambiguous Edges - Review These
- `Run Experiment Skill` → `RUNS Lab Connect Skill`  [AMBIGUOUS]
  .claude/skills/runs-lab-connect/SKILL.md · relation: conceptually_related_to
- `Option 1 Implementation - FIXED for Hardware Fast-Path` → `SYN Punt Application`  [AMBIGUOUS]
  llm-wiki/wiki/bluefield/examples/syn-punt/Syn-Punt Option1 Fixed.md · relation: conceptually_related_to

## Knowledge Gaps
- **197 isolated node(s):** `PYTHONUTF8`, `PYTHONIOENCODING`, `PYTHONUTF8`, `PYTHONIOENCODING`, `run_stress.sh script` (+192 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **31 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Run Experiment Skill` and `RUNS Lab Connect Skill`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Option 1 Implementation - FIXED for Hardware Fast-Path` and `SYN Punt Application`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `roadmap.md (source)` connect `100k Capacity Model Findings` to `llm-wiki BlueField Notes`, `eSwitch Concept Docs`, `0-RTT Measurement Concepts`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Why does `Load Generation and Think Time` connect `0-RTT Measurement Concepts` to `Baseline CI Reports`, `100k Capacity Model Findings`, `Loadgen Implementation`, `Metrics Analyzer Implementation`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **Why does `Measurement Methodology Review` connect `0-RTT Measurement Concepts` to `run_stress.sh Load Script`, `run_experiment.sh Orchestrator`, `Experiment Insights Log`, `Loadgen Implementation`, `Baseline CI Reports`, `100k Capacity Model Findings`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `send_unlock Metric` (e.g. with `send_unlock is the metric that actually demonstrates 0-RTT` and `TTFB, the metric the project exists to improve, has never been measured`) actually correct?**
  _`send_unlock Metric` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `FlowTable` (e.g. with `.test_create_flow()` and `.test_get_flow_exists()`) actually correct?**
  _`FlowTable` has 23 INFERRED edges - model-reasoned connections that need verification._