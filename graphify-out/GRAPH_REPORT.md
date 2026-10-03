# Graph Report - zero-rtt-tcp  (2026-10-03)

## Corpus Check
- 245 files · ~349,683 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2103 nodes · 3330 edges · 214 communities (148 shown, 66 thin omitted)
- Extraction: 84% EXTRACTED · 16% INFERRED · 0% AMBIGUOUS · INFERRED: 529 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Analyzer Unit Tests
- BlueField-3 Docs
- Metrics and Methodology
- Pcap Analysis and Tracing
- DPDK Port Specs
- BlueField eSwitch Concepts
- Scapy Pipeline Tests
- Experiments Harness Plan
- run.sh Tests
- DOCA React Example
- DOCA Flow Handler
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 106
- Community 107
- Community 108
- Community 109
- Community 110
- Community 111
- Community 112
- Community 113
- Community 114
- Community 115
- Community 116
- Community 117
- Community 118
- Community 119
- Community 121
- Community 122
- Community 123
- Community 124
- Community 125
- Community 126
- Community 127
- Community 128
- Community 129
- Community 130
- Community 131
- Community 132
- Community 133
- Community 134
- Community 135
- Community 136
- Community 137
- Community 138
- Community 139
- Community 140
- Community 141
- Community 142
- Community 143
- Community 144
- Community 145
- Community 146
- Community 147
- Community 148
- Community 149
- Community 150
- Community 151
- Community 152
- Community 153
- Community 154
- Community 155
- Community 156
- Community 157
- Community 158
- Community 159
- Community 160
- Community 161
- Community 162
- Community 163
- Community 164
- Community 165
- Community 166
- Community 167
- Community 168
- Community 169
- Community 170
- Community 171
- Community 172
- Community 173
- Community 174
- Community 175
- Community 176
- Community 177
- Community 178
- Community 179
- Community 180
- Community 181
- Community 182
- Community 183
- Community 184
- Community 185
- Community 186
- Community 187
- Community 188
- Community 189
- Community 190
- Community 191
- Community 192
- Community 193
- Community 194
- Community 205
- Community 206
- Community 210

## God Nodes (most connected - your core abstractions)
1. `FlowTable` - 42 edges
2. `FlowKey` - 40 edges
3. `_run_analyzer()` - 33 edges
4. `_write_text()` - 29 edges
5. `main()` - 26 edges
6. `main()` - 23 edges
7. `Pcap FCT Metric` - 23 edges
8. `_build_client_text()` - 22 edges
9. `_calls()` - 22 edges
10. `FlowTable` - 20 edges

## Surprising Connections (you probably didn't know these)
- `ServerNIC DPDK Translator Binary` --semantically_similar_to--> `TCP Sequence/Ack Number Modification on DPA (doc example)`  [INFERRED] [semantically similar]
  experiments/dpdk/reports/integration-test-report-2026-08-08.md → infra/bluefield/docs/02-programming/dpa-programming.md
- `Condition: each NIC beside its own endpoint, delay on NIC-NIC leg` --semantically_similar_to--> `Emulated delay placement (NIC-NIC leg only)`  [INFERRED] [semantically similar]
  README.md → docs/index.html
- `Emulated RTT on Server egress (NETEM_RTT_MS)` --semantically_similar_to--> `Emulated delay placement (NIC-NIC leg only)`  [INFERRED] [semantically similar]
  .claude/skills/run-experiment/references/test-scripts.md → docs/index.html
- `send_unlock demonstrates 0-RTT` --semantically_similar_to--> `send_unlock metric`  [INFERRED] [semantically similar]
  experiments/insights.md → docs/superpowers/plans/2026-09-19-quic-comparison.md
- `ClientNIC DPDK Forwarder Binary` --semantically_similar_to--> `TCP SYN Proxy / SYN-ACK Generation on DPA (doc example)`  [INFERRED] [semantically similar]
  experiments/dpdk/reports/integration-test-report-2026-08-08.md → infra/bluefield/docs/02-programming/dpa-programming.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **CI experiment pipeline: workflow, run.sh, results bundle, offline analysis** — _github_workflows_run_experiment_run_experiment_workflow, experiments_run, _claude_skills_offline_analysis_skill_ci_results_bundle, _claude_skills_offline_analysis_skill_offline_analysis [EXTRACTED 1.00]
- **Endpoint-pcap metrics: send_unlock, FCT, server_gap** — docs_index_send_unlock, docs_index_flow_completion_time, docs_index_server_gap, experiments_nodes_analyze_metrics [EXTRACTED 1.00]
- **Scapy-era bug chain found during integration tests (Mar 2026)** — _claude_skills_run_experiment_references_troubleshooting_kernel_forwarding_races_scapy, _claude_skills_run_experiment_references_troubleshooting_packet_recapture_loop, _claude_skills_run_experiment_references_troubleshooting_swapped_seq_ack, _claude_skills_run_experiment_references_troubleshooting_scapy_iface_ignored [INFERRED 0.85]
- **Pcap-derived metric triad (send_unlock, fct, server_gap)** — docs_kb_wiki_measurement_methodology_send_unlock, docs_kb_wiki_measurement_methodology_fct, docs_kb_wiki_measurement_methodology_server_gap [EXTRACTED 1.00]
- **100k-run ceiling: burst SYNs, RX ring depth, single lcore** — docs_kb_wiki_capacity_model_live_100k_run, docs_kb_wiki_capacity_model_rx_ring_burst_absorption, docs_kb_wiki_capacity_model_cpu_budget, docs_kb_raw_2026_07_25_integration_test_report_dpdk_68779_of_100000 [EXTRACTED 1.00]
- **BlueField-3 packet processing paths (hardware, DPA hybrid, ARM, hairpin)** — docs_kb_wiki_bluefield_architecture_packet_pipeline_hw_fast_path, docs_kb_wiki_bluefield_architecture_packet_pipeline_dpa_hybrid_path, docs_kb_wiki_bluefield_architecture_packet_pipeline_arm_software_path, docs_kb_wiki_bluefield_architecture_packet_pipeline_hairpin_path [EXTRACTED 1.00]
- **SYN Punt documentation suite (README, Quickstart, Topology, Changes, Option1 Fixed)** — docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_readme, docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_quickstart, docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_topology, docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_changes, docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_option1_fixed [EXTRACTED 0.95]
- **BF3 testing flow: local simulation, staged hardware testing, debugging, perf tuning** — docs_kb_wiki_bluefield_development_local_simulation_strategies, docs_kb_wiki_bluefield_development_testing_strategies, docs_kb_wiki_bluefield_development_debugging_guide, docs_kb_wiki_bluefield_development_performance_tuning [INFERRED 0.85]
- **Bump-in-the-wire forwarding patterns on BF3 (wire app, syn_punt hairpin, SF-based wire)** — docs_kb_wiki_bluefield_examples_wire_example_wire_example_readme_wire_app, docs_kb_wiki_bluefield_examples_syn_punt_syn_punt_option1_fixed_two_port_architecture, docs_kb_wiki_bluefield_examples_wire_example_wire_example_docker_sf_based_wire, docs_kb_wiki_bluefield_examples_wire_example_wire_example_networking_setup_classic_dpdk_mode [INFERRED 0.75]
- **0-RTT translation split (ClientNIC spoof+stamp, ServerNIC translate)** — docs_kb_wiki_components_clientnic_dpdk_forwarder_proc_handle_syn, docs_kb_wiki_components_clientnic_dpdk_forwarder_isn_ack_num_channel, docs_kb_wiki_components_servernic_dpdk_syn_handler, docs_kb_wiki_components_servernic_dpdk_translator [EXTRACTED 0.95]
- **BlueField-3 packet processing tiers (Flow Engine, DPA, ARM)** — docs_kb_wiki_bluefield_programming_dpa_programming_nic_flow_engine, docs_kb_wiki_bluefield_programming_packet_modification_capability_matrix, docs_kb_wiki_bluefield_reference_gotchas_performance_tiers [INFERRED 0.85]
- **Hermes experiment agent fleet** — docs_kb_wiki_hermes_hermes_agents_overview_experiment_runner, docs_kb_wiki_hermes_hermes_agents_overview_experiment_analyst, docs_kb_wiki_hermes_hermes_agents_overview_experiment_warden [EXTRACTED 0.95]
- **ClientNIC DPDK port capability specs** — docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_dpdk_data_plane_spec, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_flow_table_c_spec, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_packet_pipeline_c_spec, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_seq_translator_c_spec, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_syn_ack_spoofer_c_spec [EXTRACTED 1.00]
- **ClientNIC parse-classify-dispatch flow** — docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_packet_pipeline_c_spec_ingress_routing, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_syn_ack_spoofer_c_spec_syn_interception, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_syn_ack_spoofer_c_spec_real_syn_ack, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_seq_translator_c_spec_c2s_ack_rewrite, docs_openspec_changes_archive_2026_03_25_clientnic_dpdk_port_specs_seq_translator_c_spec_s2c_seq_rewrite [EXTRACTED 1.00]
- **Node-script orchestration design decisions** — docs_openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_design_setsid_wrap, docs_openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_design_client_py_direct, docs_openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_design_gw_mac_orchestrator, docs_openspec_changes_archive_2026_04_08_dpdk_node_script_integration_test_design_git_safe_directory [EXTRACTED 1.00]
- **T8 translation-shift data plane (V channel, ClientNIC forwarder, ServerNIC translator)** — docs_openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_design_syn_ack_num_channel, docs_openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_design_clientnic_dpdk_forwarder_variant, docs_openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_design_servernic_sole_translator, docs_openspec_changes_archive_2026_05_31_t8_isn_ack_num_translation_shift_design_real_syn_ack_dropped_at_servernic [EXTRACTED 1.00]
- **Endpoint pcap measurement pipeline (captures, analyzer, three metrics)** — docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_design_two_captures_one_analyzer, docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_design_analyze_metrics_py, docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_design_metric_fct, docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_design_metric_send_unlock, docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_design_metric_server_gap [EXTRACTED 1.00]
- **Phase 1a eBPF trace toolchain (scripts, runner, node wrapper)** — docs_openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_design_tcp_state_trace_bt, docs_openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_design_tcp_retransmit_trace_bt, docs_openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_design_run_trace_sh, docs_openspec_changes_archive_2026_05_23_phase_1a_ebpf_observability_design_node_script_ebpf_trace_sh [EXTRACTED 1.00]
- **Endpoint-observed metrics measured from two captures** — docs_openspec_changes_archive_2026_07_08_endpoint_pcap_measurement_specs_endpoint_pcap_measurement_spec_fct, docs_superpowers_plans_2026_09_19_quic_comparison_send_unlock, docs_kb_wiki_measurement_methodology_server_gap [EXTRACTED 1.00]
- **Dual-DPDK MAC handling (port identity, server peer MAC, learned client MAC)** — docs_openspec_changes_archive_2026_07_14_full_dpdk_endpoint_interfaces_design_d3_server_mac_cli, docs_openspec_changes_archive_2026_07_14_full_dpdk_endpoint_interfaces_design_d3b_port_role_by_mac, docs_openspec_changes_archive_2026_07_14_full_dpdk_endpoint_interfaces_proposal_client_mac_learned_per_flow [EXTRACTED 1.00]
- **BlueField per-flow lifecycle: pre-delta buffering, rule install, hardware steady state, FIN/RST teardown** — docs_openspec_changes_bluefield_servernic_hw_offload_specs_bluefield_offload_control_plane_spec_pre_delta_buffering, docs_openspec_changes_bluefield_servernic_hw_offload_specs_bluefield_offload_control_plane_spec_rule_lifecycle, docs_openspec_changes_bluefield_servernic_hw_offload_specs_bluefield_hw_translation_spec_hw_no_cpu_path, docs_openspec_changes_bluefield_servernic_hw_offload_design_d3_fin_rst_teardown [EXTRACTED 1.00]
- **E-switch probe: composed rule, hardware-execution check, on-wire rewrite check** — docs_openspec_changes_verify_eswitch_tcp_seq_offload_specs_eswitch_offload_probe_spec_composed_eswitch_rule, docs_openspec_changes_verify_eswitch_tcp_seq_offload_specs_eswitch_offload_probe_spec_hardware_execution_verification, docs_openspec_changes_verify_eswitch_tcp_seq_offload_specs_eswitch_offload_probe_spec_onwire_rewrite_verification [EXTRACTED 1.00]
- **ServerNIC translation flow: SYN ingest, delta on real SYN-ACK, c2s/s2c rewrite** — docs_openspec_specs_servernic_syn_handler_c_spec_forwarded_syn_ingestion, docs_openspec_specs_servernic_syn_handler_c_spec_real_synack_processing, docs_openspec_specs_servernic_flow_table_c_spec_delta_computation, docs_openspec_specs_servernic_seq_translator_c_spec_c2s_ack_rewriting, docs_openspec_specs_servernic_seq_translator_c_spec_s2c_seq_rewriting [INFERRED 0.95]
- **ClientNIC forwarder: spoof SYN-ACK, stamp V, transparent forward** — docs_openspec_specs_clientnic_forwarder_syn_spoof_spec_syn_interception_v_stamping, docs_openspec_specs_clientnic_forwarder_transparent_fwd_spec_c2s_transparent_forwarding, docs_openspec_specs_clientnic_forwarder_transparent_fwd_spec_s2c_transparent_forwarding, docs_openspec_specs_clientnic_forwarder_flow_table_spec_slim_flow_entry [INFERRED 0.95]
- **Run 1 sprint 1 build/grade repair rounds producing report_header/report_section** — docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_run1_sprint_1_round_1_build_notes, docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_run1_sprint_1_round_2_build_notes, docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_run1_sprint_1_round_3_build_notes, experiments_lib_report_sh [EXTRACTED 0.95]
- **run.sh dispatch architecture (run.sh, core.sh, transport shims, nodes)** — experiments_run_sh, experiments_lib_core_sh, experiments_lib_transport, experiments_nodes_dir [EXTRACTED 0.95]
- **Streamline harness sprints 1 to 4 consolidation** — docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_sprint_1_round_1_build_notes, docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_sprint_2_contract, docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_sprint_3_contract, docs_superpowers_plans_2026_09_08_streamline_experiments_harness__harness_sprint_4_contract [EXTRACTED 0.95]
- **QUIC four-arm send_unlock comparison** — docs_superpowers_specs_2026_09_19_quic_comparison_design_four_arms, docs_superpowers_plans_2026_09_19_quic_comparison_loadgen_quic, docs_superpowers_plans_2026_09_19_quic_comparison_send_unlock, docs_superpowers_plans_2026_09_19_quic_comparison_run_sh_quic_arm [EXTRACTED 0.95]
- **Dual-sink experiment output flow** — docs_superpowers_plans_2026_09_19_human_readable_experiment_output_output_sh, docs_superpowers_plans_2026_09_19_human_readable_experiment_output_output_init, docs_superpowers_plans_2026_09_19_human_readable_experiment_output_print_scorecard, docs_superpowers_plans_2026_09_19_human_readable_experiment_output_run_log, docs_superpowers_plans_2026_09_19_human_readable_experiment_output_experiment_full_log [EXTRACTED 0.95]
- **BlueField-3 Operating Mode Comparison** — bluefield_concept_hybrid_mode [EXTRACTED 1.00]
- **BlueField-3 Three-Tier Performance Model (Flow Engine / DPA / ARM)** — concept_nic_flow_engine, concept_dpa_cores, concept_arm_dpdk [EXTRACTED 1.00]
- **Local BlueField Testing Without Hardware** — infra_bluefield_docs_04_development_local_simulation_strategies, concept_virtual_pmd, concept_testpmd [EXTRACTED 1.00]
- **Zero-RTT TCP packet-flow pipeline (Client-ClientNIC-ServerNIC-Server)** — architecture_packetflow_client, architecture_packetflow_clientnic, architecture_packetflow_servernic, architecture_packetflow_server [EXTRACTED 1.00]
- **0-RTT Latency Metric Tiering (send_unlock / FCT / server_gap)** — concept_pcap_fct_metric [EXTRACTED 1.00]
- **BlueField-3 DPU Provisioning Pipeline** — infra_bluefield_setup_bfb_install, infra_bluefield_setup_dpu_mode_setup, infra_bluefield_setup_install_doca_all, infra_bluefield_setup_install_meson_ninja [INFERRED 0.75]
- **DPDK 2026-08-17 Sweep Session (capacity100k + run01 + run02)** — experiments_dpdk_reports_integration_test_report_2026_08_17_capacity100k, experiments_dpdk_reports_integration_test_report_2026_08_17_run01, experiments_dpdk_reports_integration_test_report_2026_08_17_run02 [INFERRED 0.75]
- **Hardware Exception-Path Punting Pattern** — concept_syn_punt_pattern, concept_react_app, concept_hairpin_forwarding [INFERRED 0.80]
- **CI 100k-connection Baseline vs DPDK Comparison (2026-08-11)** — experiments_ci_results_20260811_080308_baseline_reports_baseline_report_2026_08_11_080243, experiments_ci_results_20260811_082919_dpdk_reports_integration_test_report_2026_08_11, concept_netem_rtt_ms [INFERRED 0.85]
- **CI 2000-conn Baseline vs DPDK Comparison (2026-08-11)** — experiments_ci_results_20260811_085652_baseline_reports_baseline_report_2026_08_11_085628, experiments_ci_results_20260811_090202_dpdk_reports_integration_test_report_2026_08_11 [INFERRED 0.85]
- **2026-08-17 10-Run DPDK Sweep** — experiments_dpdk_reports_integration_test_report_2026_08_17_run03, experiments_dpdk_reports_integration_test_report_2026_08_17_run04, experiments_dpdk_reports_integration_test_report_2026_08_17_run05, experiments_dpdk_reports_integration_test_report_2026_08_17_run06, experiments_dpdk_reports_integration_test_report_2026_08_17_run07, experiments_dpdk_reports_integration_test_report_2026_08_17_run08, experiments_dpdk_reports_integration_test_report_2026_08_17_run09, experiments_dpdk_reports_integration_test_report_2026_08_17_run10 [INFERRED 0.85]
- **Wire-Example Documentation Set (Basic, Networking, Docker)** — infra_bluefield_examples_wire_example_readme, infra_bluefield_examples_wire_example_networking_setup, infra_bluefield_examples_wire_example_docker [INFERRED 0.85]

## Communities (214 total, 66 thin omitted)

### Community 0 - "Analyzer Unit Tests"
Cohesion: 0.07
Nodes (30): CompletedProcess, _build_client_text(), _build_n_flows(), _build_server_text(), _parse_metric_lines(), _parse_missing_lines(), _parse_summary_lines(), Unit tests for experiments/nodes/analyze_metrics.py The analyzer parses… (+22 more)

### Community 1 - "BlueField-3 Docs"
Cohesion: 0.07
Nodes (57): ARM DPDK software path, Bloom Filter (Classic/Counting/Thread-Safe), CI/CD DPDK Testing (GitLab CI / GitHub Actions), DOCA Test Framework (line-rate benchmarking), DPA (programmable hardware cores), ENA PMD (AWS DPDK driver), eSwitch-is-not-separate-hardware Misconception, FlexIO (DPA/rte_flow integration) (+49 more)

### Community 2 - "Metrics and Methodology"
Cohesion: 0.10
Nodes (55): TCP SYN Proxy / SYN-ACK Generation on DPA (doc example), Missing first_inbound_payload Anomaly (capacity failures), ISN Ack-Num Translation Shift (0-RTT DPDK Implementation), DPDK ISN Ack-Num Translation Shift, NETEM_RTT_MS Emulated WAN Parameter, NETEM_RTT_MS emulated-WAN-latency parameter, Pcap FCT Metric, Baseline TCP Report 2026-08-17-221348 (+47 more)

### Community 3 - "Pcap Analysis and Tracing"
Cohesion: 0.04
Nodes (49): Tracing scope: Client and Server VMs only, tracepoint:sock:inet_sock_set_state, JSON-line trace output format, ebpf-trace.sh node script (always traces state + retransmits), bpftrace port filter as positional arg $1, run_trace.sh (SSM-deployable trace runner), Runtime bpftrace fallback install, tracepoint:tcp:tcp_retransmit_skb (+41 more)

### Community 4 - "DPDK Port Specs"
Cohesion: 0.06
Nodes (48): Design: ClientNIC DPDK port, Single-threaded busy-poll loop, L2 sends on eth0 with cached client MAC, Gateway MAC passed via --gw-mac CLI argument, Hybrid I/O: AF_PACKET eth0 + DPDK ENA PMD eth1, C module structure mirrors Scapy layout 1:1, Open-addressing 1024-slot flow hash table (linear probing, XOR-fold), DPDK 23.11 ENA PMD on eth1 (vfio-pci) (+40 more)

### Community 5 - "BlueField eSwitch Concepts"
Cohesion: 0.07
Nodes (46): ARM Cores (Cortex-A78 control plane), ConnectX NIC Engine (ASIC), DOCA DPL (P4-based declarative pipeline language), doca_flow API (pipe-based hardware flow programming), Hairpin Queue (NIC-to-NIC, bypass CPU), Hardware Parser (fixed-function ASIC), Hybrid Mode (SmartNIC + DPA), mbuf (rte_mbuf packet buffer) (+38 more)

### Community 6 - "Scapy Pipeline Tests"
Cohesion: 0.08
Nodes (24): Pipeline, FlowTable, Pipeline: Parse → Decide+Modify — routes packets to correct handler., Return (ingress, is_syn, is_syn_ack) or None to drop., Unit tests for Translator and Pipeline., TestPipeline, main(), ServerNIC entry point. (+16 more)

### Community 7 - "Experiments Harness Plan"
Cohesion: 0.06
Nodes (43): Streamline experiments harness plan, Run 2 harness plan (4 sprints), Run 1 harness plan, Sprint 2 re-plan after scope-violation, Run 1 run report (scope-violation), Scope-violation outcome (touches[] too narrow), Run 1 sprint 1 contract, Run 1 sprint 1 round 0 contract-lens findings (+35 more)

### Community 8 - "run.sh Tests"
Cohesion: 0.09
Nodes (41): _calls(), _parse(), fixture, parametrize, _client_load(), parametrize, _quic(), Pins the QUIC arm of experiments/run.sh (STACK=baseline PROTO=quic) against the… (+33 more)

### Community 9 - "DOCA React Example"
Cohesion: 0.09
Nodes (32): bloom_filter_t, bloom_type_t, process_packets(), wait_for_rx_qi_changes(), bloom_get_indices(), bloom_size_callback(), bloom_swap_callback(), bloom_type_callback() (+24 more)

### Community 10 - "DOCA Flow Handler"
Cohesion: 0.10
Nodes (26): add_syn_punt_entry(), doca_error_t, create_hairpin_pipe(), create_syn_punt_pipe(), doca_flow_cleanup(), doca_flow_init_module(), doca_flow_port_start_module(), doca_error_t (+18 more)

### Community 11 - "Community 11"
Cohesion: 0.12
Nodes (25): recalc_ip_checksum(), recalc_tcp_checksum(), ft_buffer_pkt(), ft_create(), ft_extract_key(), ft_flush_buffer(), ft_init(), ft_lookup() (+17 more)

### Community 12 - "Community 12"
Cohesion: 0.14
Nodes (23): build_frame(), checksum(), extract_ack(), extract_dst_mac(), extract_seq(), extract_src_mac(), Forwarder, ForwarderFlowEntry (+15 more)

### Community 13 - "Community 13"
Cohesion: 0.13
Nodes (22): pcap_writer_close(), pcap_writer_open(), pcap_writer_write_mbuf(), eth0_init(), eth0_send(), eth0_tx_flush(), eth1_init(), eth1_send() (+14 more)

### Community 14 - "Community 14"
Cohesion: 0.08
Nodes (17): Tests for experiments/nodes/loadgen.py — the asyncio event-driven load…, Every scheduled connection is still opened and counted., The semaphore ceiling holds even when the arrival schedule outruns it., Defaults encode the measurement intent — a wrong default silently produces a…, 1 MB costs ~16 RTTs of transfer, burying the single RTT 0-RTT saves., The CLI default stays unpaced so ad-hoc invocations are unsurprising; the…, port-count=0 (or negative) still yields exactly one port, never an empty list., End-to-end: real sockets over loopback, no mocking. (+9 more)

### Community 15 - "Community 15"
Cohesion: 0.13
Nodes (15): _cmds_for(), Tests for experiments/lib/endpoint.sh — the shared endpoint setup/capture/…, Both stacks must model the same total RTT or the comparison is void.…, A leftover endpoint qdisc must fail the run, not be assumed absent., A silently-failed tc turns the run into an intra-VPC measurement where one RTT…, iproute-tc is not in the base AMI (F15); without it every netem command fails…, Both stacks must get identical endpoint conditions, or the comparison between…, send_unlock is the primary result; FCT and server_gap are throughput-bound and… (+7 more)

### Community 16 - "Community 16"
Cohesion: 0.17
Nodes (22): rte_get_tsc_hz(), rte_rdtsc(), rte_pktmbuf_free(), eth1_init(), eth1_send(), eth1_tx_flush(), eth1_wan_flush_all(), eth1_wan_service() (+14 more)

### Community 17 - "Community 17"
Cohesion: 0.12
Nodes (9): FlowKey, 4-tuple connection identifier., Unit tests for flow_table.py, Tests for FlowKey dataclass., Tests for buffer_packet / flush_buffer on FlowTable., Tests for FlowTable class., TestFlowKey, TestFlowTable (+1 more)

### Community 18 - "Community 18"
Cohesion: 0.14
Nodes (16): recalc_ip_checksum(), recalc_tcp_checksum(), ft_create(), ft_extract_key(), ft_init(), ft_lookup(), ft_reverse_key(), hash_key() (+8 more)

### Community 19 - "Community 19"
Cohesion: 0.13
Nodes (20): FlowTable, _hash_key(), ServerNIC flow table unit tests — pure Python (no DPDK required). Models the C…, A single flow can be shed by the global ceiling well before FT_MAX_BUFFER., Two keys that land on the same initial slot are stored separately., Mirrors ft_buffer_pkt(ft, entry, data, len): -1 per-flow cap, -2 global cap., Mirrors ft_flush_buffer(ft, entry, out, count): drains entry, decrements global…, test_buffer_and_flush() (+12 more)

### Community 20 - "Community 20"
Cohesion: 0.09
Nodes (24): Accuracy knobs (offload off, tc netem delay), analyze_metrics.py (pcap analyzer), Relabel rdtsc [METRIC] to [DIAG], Endpoint tcpdump capture with nanosecond timestamps, measure.sh, Portable measurement across AWS and Proxmox, Unmodified iperf2 load generator, Validation guardrails for incomplete captures (+16 more)

### Community 21 - "Community 21"
Cohesion: 0.09
Nodes (23): EAL init with two DPDK ports (ClientNIC forwarder), ServerNIC EAL init with two DPDK ports, Alternative C: timer-based rule expiry (on the shelf), D2 Two rules per flow, one per direction, D3 Teardown driven by FIN/RST punt, D4 Sibling target, shared modules by reference, D5 Observable exception path (non_handshake_rx counter), D6 Offload API behind a four-operation backend interface (+15 more)

### Community 22 - "Community 22"
Cohesion: 0.15
Nodes (22): _build_parser(), _client_config(), _client_conn(), _exchange(), _lag_probe(), main(), _pct(), _prime() (+14 more)

### Community 23 - "Community 23"
Cohesion: 0.13
Nodes (22): Debugging Guide, Debugging tools (tcpdump, ethtool, mlxdump, perf), rte_flow COUNT action for debugging rule hits, Hardware offload verification via ovs-appctl dump-flows type=offloaded, Issue: packets not forwarded (no flow rule / not offloaded), Local Simulation Strategies for DOCA/DPDK Development, CI/CD integration (GitLab CI, GitHub Actions) for DPDK tests, Container-based DPDK testing (Dockerfile, docker-compose, memif) (+14 more)

### Community 24 - "Community 24"
Cohesion: 0.15
Nodes (21): analyze_client(), analyze_server(), _canon(), _is_fin(), _is_syn(), _is_syn_ack(), main(), _make_source() (+13 more)

### Community 25 - "Community 25"
Cohesion: 0.13
Nodes (20): Baseline Report 2026-08-04-194023 (failed, server.sh missing), Baseline Report 2026-08-04-194902 (failed, server.sh missing), Baseline Report 2026-08-04-200506 (send_unlock 100.8 ms), Baseline Report 2026-08-04-201326 (all passed), 0-RTT Telemetry Review artifact, What would make the claim airtight (blocking/high/design/scale), Cost of iperf to loadgen.py migration, NIC logs truncated at 24 KB SSM cap (+12 more)

### Community 26 - "Community 26"
Cohesion: 0.14
Nodes (13): _extract_inline_python(), Smoke tests for the summarize_metric() Python inline in…, Return the Python code between <<'PY' ... PY in measure.sh., Run the measure.sh inline Python with given inputs, return stdout., Tests for the summarize_metric inline Python in measure.sh., A line in the actual emit() format is parsed and a sample is reported., Multiple emit() lines for the same metric/node are all aggregated., Lines for a different metric name are not counted. (+5 more)

### Community 27 - "Community 27"
Cohesion: 0.24
Nodes (10): _ensures(), _loadgen_calls(), _pip_installs(), Tests for the PROTO switch in experiments/nodes/client.sh and server.sh. The…, System python3 is 3.7 on the VMs; aioquic 1.3.0 needs >= 3.10., loadgen_quic.py has no --think-ms; argparse would reject an unknown flag on the…, Run a copy of a node script with stubbed commands; return recorded calls., _run() (+2 more)

### Community 28 - "Community 28"
Cohesion: 0.12
Nodes (12): Packet, FlowEntry, FlowTable, Flow table for tracking TCP connections and sequence number state., Connection state for a single flow., Thread-safe flow table for tracking connections., Create a new flow entry., Get flow entry by key. (+4 more)

### Community 29 - "Community 29"
Cohesion: 0.15
Nodes (19): eSwitch and NIC Flow Engine, eSwitch is flow-table entries, not separate hardware, Flow table capacity, priority and offload-failure causes, eSwitch programming methods (rte_flow, OVS-DPDK, DOCA Flow), BlueField-3 Hardware Architecture, ARM cores (16x Cortex-A78), ASAP2 offload architecture, Hardware parser (+11 more)

### Community 30 - "Community 30"
Cohesion: 0.13
Nodes (19): ReACT DOCA Application Analysis, Bloom filter variants (classic, counting, thread-safe), DNS amplification attack prevention (response filtering), ReACT DOCA Flow pipes (requests, responses, copy-to-meta, egress), process_packets() worker (react_arm.c), ReACT DNS filtering application, Sliding window 3-phase Bloom filter rotation, React Experiment (+11 more)

### Community 31 - "Community 31"
Cohesion: 0.13
Nodes (19): DOCA Logging, DOCA_LOG_REGISTER macro, Avoid logging in hot paths, DOCA log backends (standard/file/syslog), DOCA log levels and per-source env control, DPDK Core Functions (rte_eal_*), One queue per core (lock-free), rte_eal_init (+11 more)

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (19): bluefield-runs3-dpu environment (DOCA 3.0, switchdev, no DNS, p0 dark), D4 PARTIAL verdict with defined consequence, D5 restore is a success criterion, not cleanup, D6 DOCA Flow first; a NO triggers rte_flow cross-check, DOCA devel container built elsewhere and transported as saved image, pf0hpf <-> ens16f0np0 single-port data path, Scalable Function egress topology (Alternative C fallback), Pre-mutation baseline capture (+11 more)

### Community 33 - "Community 33"
Cohesion: 0.27
Nodes (17): build_ipv4_tcp(), checksum(), extract_ack(), extract_seq(), ServerNIC sequence-number arithmetic unit tests — no DPDK required. Validates…, Applying delta forward then reverse recovers the original values., Return a minimal 54-byte Ethernet + IPv4 + TCP frame., rewrite_ack() (+9 more)

### Community 34 - "Community 34"
Cohesion: 0.11
Nodes (18): clientnic/dpdk-forwarder variant (parallel folder), clientnic/dpdk full-owner implementation (preserved), ClientNIC minimal flow table {client_mac, V, state}, servernic/dpdk module decomposition (mirrors ClientNIC), ServerNIC interface roles (eth0 AF_PACKET client-facing, eth1 DPDK server-facing), ServerNIC RST suppression and FORWARD drop rules, 1024-slot open-addressing flow hash table (ClientNIC forwarder), clientnic-forwarder slim flow entry {V, state, client_mac} (+10 more)

### Community 35 - "Community 35"
Cohesion: 0.18
Nodes (5): PacketProcessor, FlowTable, PacketProcessor: SYN and SYN-ACK handling + spoofed SYN-ACK generation., TestGenerateRandomIsn, TestProcessSynAck

### Community 36 - "Community 36"
Cohesion: 0.27
Nodes (6): _make_processor(), _make_syn(), patch, Unit tests for PacketProcessor (SYN/SYN-ACK handling + spoofed SYN-ACK…, TestCreateSynAck, TestProcessSyn

### Community 37 - "Community 37"
Cohesion: 0.16
Nodes (17): Per-flow packet buffering until delta known, ClientNIC Scapy implementation (deprecated), seq_delta = spoofed ISN - real ISN, ServerNIC, ServerNIC DPDK Implementation, ServerNIC flow table {V, real_isn, delta, buffer}, servernic-dpdk binary, ServerNIC as sole stateful translator (+9 more)

### Community 38 - "Community 38"
Cohesion: 0.36
Nodes (13): mb(), test_disabled_is_a_noop(), test_drain_all_ignores_deadlines(), test_max_caps_the_batch(), test_order_is_preserved(), test_packet_is_held_until_its_deadline(), test_ring_full_drops_and_counts(), test_wraparound() (+5 more)

### Community 39 - "Community 39"
Cohesion: 0.17
Nodes (16): VPC route-table overrides through NIC ENIs, ClientNIC (spoof SYN-ACK, stamp V), DPDK data plane (live implementation), 4-VM chain Client-ClientNIC-ServerNIC-Server, ISN V stamped in forwarded SYN ack-num, Scapy data plane (deprecated PoC), ServerNIC (sole stateful translator), 0-RTT TCP technique (+8 more)

### Community 40 - "Community 40"
Cohesion: 0.19
Nodes (6): FlowTable, Translator: handles seq/ack rewriting for both data directions., Client→server: subtract delta from ACK, or buffer if delta unknown., Server→client: add delta to SEQ., Translator, TestTranslator

### Community 41 - "Community 41"
Cohesion: 0.17
Nodes (15): Client App, experiments/nodes/loadgen.py, Unmodified endpoint transparency principle, Why iperf was removed (thread-per-connection, no pacing), Server App, 0-RTT Experiment Agent Fleet (Hermes), GitHub Actions workflow_dispatch (aws-ops / run-experiment), Claude OAuth billing caveat (unofficial, extra-usage risk) (+7 more)

### Community 42 - "Community 42"
Cohesion: 0.16
Nodes (15): Real SYN-ACK dropped at ServerNIC, clientnic-forwarder ingress-based routing, Spoofed SYN-ACK 54-byte frame construction, clientnic-forwarder SYN spoof and V stamping, clientnic-forwarder transparent bidirectional forwarding, V carried in forwarded SYN ack-num, ft_set_delta: delta = (V - real_isn) & 0xFFFFFFFF, ServerNIC ingress and flags routing (+7 more)

### Community 43 - "Community 43"
Cohesion: 0.19
Nodes (14): CI results bundle (experiments/ci-results), offline-analysis skill, Baseline/dpdk pair knob-equality check, Experiment scripts reference, Experiment modes (DPDK, Proxmox, Baseline), run-experiment skill, infra=both serialized baseline+dpdk matrix, OIDC AWS authentication (+6 more)

### Community 44 - "Community 44"
Cohesion: 0.16
Nodes (14): DPDK Integration, Hardware checksum offload (mbuf ol_flags), Flow Director queue steering via rte_flow, RSS multi-queue distribution, rte_eth_rx_burst / rte_eth_tx_burst, API Cheatsheet, API selection guide, rte_ipv4_cksum / rte_ipv4_udptcp_cksum helpers (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.18
Nodes (11): arms(), fixture, parametrize, Loopback test for experiments/nodes/loadgen_quic.py — pins the cold-vs-resumed…, Run a cold and a resumed client against one loopback server., Fewer than n resumed means resumption silently fell back to 1-RTT., _summary(), test_early_data_accepted_on_every_resumed_flow_and_no_cold_flow() (+3 more)

### Community 46 - "Community 46"
Cohesion: 0.15
Nodes (9): PacketTestStack, Construct, Stack, _bind_data_enis_to_vfio(), Construct, IVpc, Stack, User-data lines that bind every non-primary ENI to vfio-pci. ENIs are… (+1 more)

### Community 47 - "Community 47"
Cohesion: 0.19
Nodes (13): Endpoint pcap measurement model, Spoofed SYN-ACK, Reported arrival rate measures scheduling, not establishment, Metric: flow completion time (FCT), Limitations and open questions (emulated WAN, options off, 100k failure), Twelve-run reproduction per stack (24,000 flows), Zero-RTT TCP experiment results report, 100k attempts: plain 99,728 / 0-RTT 87,073 completed (+5 more)

### Community 48 - "Community 48"
Cohesion: 0.22
Nodes (13): DPA Programming Guide, DPA examples use placeholder function names, NIC Flow Engine, DPA SYN-ACK proxy kernel (build_synack), DPA TCP seq/ack modifier kernel, Packet Modification and Generation, Packet modification capability matrix (Flow Engine vs DPA vs ARM), Where-to-modify decision tree (+5 more)

### Community 49 - "Community 49"
Cohesion: 0.18
Nodes (13): bluefield-servernic-hw-offload companion change (gated on verdict), E-switch hardware TCP seq/ack rewrite capability (unverified), No real SYN-ACK processing on ClientNIC, Offload disable and tc netem 50ms on each endpoint, ServerNIC reads V at SYN time and zeroes ack-num, ft_set_delta: seq_delta = V - real_isn (32-bit wrap), ServerNIC flow entry {V, real_isn, seq_delta, delta_valid, state}, ServerNIC ingress-based routing (SYN, non-SYN, SYN-ACK, data) (+5 more)

### Community 50 - "Community 50"
Cohesion: 0.17
Nodes (13): ClientNIC --gw-mac next-hop argument, --client-port-mac / --server-port-mac port identity, Orchestrator discovers and passes next-hop and port-identity MACs, Orchestrator launches node scripts via SSM (Server, ServerNIC, ClientNIC order), ServerNIC --gw-mac next-hop argument, Sending toward the Server via DPDK with --server-mac, Dedicated kernel management ENI reserved for SSM, Next-hop MAC via CLI only where it cannot be learned (+5 more)

### Community 51 - "Community 51"
Cohesion: 0.19
Nodes (6): NETEM_RTT_MS, remote_bg(), remote_run(), remote_stdout(), endpoint_mock_harness.sh script, _trace()

### Community 52 - "Community 52"
Cohesion: 0.15
Nodes (8): PacketTestStack, Construct, Stack, Construct, IVpc, Stack, Baseline 4-VM chain: plain kernel IP forwarding, no DPDK, no Scapy middleware.…, SmartNicsStack

### Community 53 - "Community 53"
Cohesion: 0.17
Nodes (12): Kernel forwarding races Scapy (iptables FORWARD DROP fix), Packet re-capture loop on ServerNIC (MAC filter fix), Scapy send(iface=) ignored on L3, Scapy sendp() vs send() L2/L3 forwarding bug, Spoofed SYN-ACK arrives late (metadata sniff filter), Swapped SEQ/ACK rewrite fields bug, Sequence number translation (delta = spoofed - real ISN), Bug: sniff filter matched AWS metadata traffic (+4 more)

### Community 54 - "Community 54"
Cohesion: 0.21
Nodes (12): Integration Test Report 2026-06-27 (10k DPDK run, iperf2), 10k run symptom: FCT 30-64s and server_gap 47-74s, Integration Test Report 2026-06-28 (all metrics empty, 5 failures), SKIP_BUILD=1 with git hard-reset (stale binary), Experiment Insights, All-empty metrics means harness failure, not data-plane result, 10k run bottleneck is t3.micro endpoints, not SmartNIC, Open: 0-RTT FCT tail 537 ms, RTO hypothesis unconfirmed (+4 more)

### Community 55 - "Community 55"
Cohesion: 0.21
Nodes (12): ClientNIC, ClientNIC DPDK Forwarder, clientnic-dpdk-forwarder binary, forward_c2s / forward_s2c, ISN ack-num channel (V stamped in SYN ack field), proc_handle_syn, Slim flow table {V, client_mac, state}, ClientNIC DPDK Forwarder Tests (+4 more)

### Community 56 - "Community 56"
Cohesion: 0.17
Nodes (7): PacketTestStack, Construct, Stack, Construct, IVpc, Stack, SmartNicsStack

### Community 57 - "Community 57"
Cohesion: 0.22
Nodes (11): AWS CDK stacks (infra/scapy, infra/dpdk, infra/baseline), NVIDIA BlueField-3 DPU platform target, CLAUDE.md project guidance, OpenSpec change tracking workflow, Protocol limitations (TCP only, no options, no reordering), Four-layer vault contract (wiki/raw/index/log), Vault out-of-scope paths (skills, openspec, SOUL.md, CLAUDE.md), zero-rtt-tcp Wiki Index (+3 more)

### Community 58 - "Community 58"
Cohesion: 0.18
Nodes (11): Alternative A1: keep AF_PACKET, deepen buffers (rejected), Alternative A2: PACKET_MMAP TPACKET_V3 (rejected), Alternative A3: dual ENA PMD + management ENI (chosen), D2 Second ENA PMD port, not bonded, D5 mbuf pool sizing (4,660 needed vs 8,191), AF_PACKET endpoint ports as backpressure/tail-drop source, smartnic-dual-dpdk-io capability, Deploy-gated acceptance criteria (SSM reachable, drop counters, 100k run) (+3 more)

### Community 59 - "Community 59"
Cohesion: 0.20
Nodes (11): clientnic-forwarder-flow-table spec, ClientNIC flow_key 4-tuple, ClientNIC slim flow entry {V, state, client_mac}, clientnic-forwarder-syn-spoof spec, Spoofed SYN-ACK construction (54-byte frame), SYN interception, spoofing and V stamping (proc_handle_syn), Sending toward the client with learned client MAC, isn-ack-num-channel spec (T8) (+3 more)

### Community 60 - "Community 60"
Cohesion: 0.18
Nodes (11): No tcpdump on DPDK-owned SmartNIC interfaces, analyze_metrics.py key=value output consumed by measure.sh, tcpdump nanosecond timestamp capture on endpoints, Same measurement portable across AWS EC2 and Proxmox LAN, Three endpoint metrics: fct, send_unlock, server_gap, Analyzer rejects incomplete captures, Per-flow 64-packet buffer for PENDING flows, Zero-RTT TCP Results Review (11-slide deck) (+3 more)

### Community 61 - "Community 61"
Cohesion: 0.24
Nodes (11): Sprint 2 contract: single entrypoint and mock test, test_run_sh.py mock-transport test, Sprint 3 contract: delete old runners and fix report paths, STACK=baseline skips data-plane steps, Four near-duplicate runners problem, Mock-transport pytest verification, Per-stack report directories reports/0rtt and reports/baseline, experiments/run.sh single entrypoint (+3 more)

### Community 62 - "Community 62"
Cohesion: 0.20
Nodes (11): experiment-full.log bundle artifact, Four run_experiment.sh runners, output_init, lib/output.sh dual-sink module, print_scorecard, RUN_LOG full log file, test_output.py sink test, run-experiment.yml workflow (+3 more)

### Community 64 - "Community 64"
Cohesion: 0.27
Nodes (8): get_lab_mac(), json_idx(), _lab_ssh(), _lab_ssh_bg(), remote_bg(), remote_run(), remote_stdout(), ssh_lab.sh script

### Community 65 - "Community 65"
Cohesion: 0.29
Nodes (9): _build_parser(), _client_conn(), main(), _parse_ports(), Bind and start accepting on every port. Accepting begins immediately on return…, Open `parallel` connections, paced at `rate` connections/sec (0 = burst).…, run_client(), run_server() (+1 more)

### Community 66 - "Community 66"
Cohesion: 0.22
Nodes (3): Tests for FlowEntry dataclass., TestFlowEntry, FlowEntry

### Community 67 - "Community 67"
Cohesion: 0.20
Nodes (10): Emulated RTT on Server egress (NETEM_RTT_MS), DPDK --wan-delay-us in-forwarder delay queue, Emulated delay placement (NIC-NIC leg only), tc netem qdisc delay (50 ms per side), ServerNIC per-connection buffering until offset known, Finding: packets dropped instead of buffered, Integration Test Report 2026-03-06 (Scapy), Baseline TCP Report 2026-05-31 (0/20 failed) (+2 more)

### Community 68 - "Community 68"
Cohesion: 0.31
Nodes (10): Client, ClientNIC, ServerNIC delta calculation (real SYN-ACK Seq:3000 vs spoofed Seq:300), Annotation: from this point translation could theoretically be performed by either side, Client-to-server rewrite: subtract delta from seq/ack, Server-to-client rewrite: adding delta to ack, Server, ServerNIC (+2 more)

### Community 69 - "Community 69"
Cohesion: 0.36
Nodes (10): OVS Bridge br-syn-punt, Changes Made to SYN Punt Application, ovs_setup.sh (OVS bridge pf0hpf <-> p0), Topology correction: Host VM -> pf0hpf -> DPU -> p0 -> Tofino with OVS bridge, Quick Start Guide - SYN Punt Application, Lab topology: Host VM -> pf0hpf -> OVS br-syn-punt -> p0 -> Tofino, SYN Punt Application, Network Topology for SYN Punt Application (+2 more)

### Community 70 - "Community 70"
Cohesion: 0.27
Nodes (10): Hugepage configuration commands, Dual-DPDK data plane (ClientNIC), Port-role matching by own-ENI MAC, Dual-DPDK data plane (ServerNIC), Infrastructure Architecture - DPDK Variant, NIC VM DPDK setup (hugepages, DPDK 23.11, devbind), ENI binding model (kernel primary for SSM, vfio-pci secondary for DPDK), PacketTestStack (VPC + subnets) (+2 more)

### Community 71 - "Community 71"
Cohesion: 0.27
Nodes (10): Capacity Model, Buffered-packet cap (FT_MAX_BUFFERED_BYTES 1 GiB), CPU budget (single lcore, cycles per packet), AWS ENA allowances (conntrack_allowance_exceeded etc.), Endpoint limits (t3.micro to m5.xlarge, kernel sysctls), Flow tables (FT_SIZE 262144; ServerNIC ~1096 B/entry), 2048-byte frame ceiling and MTU 1500 pin, mbuf pool sizing (MBUF_POOL_SIZE 8191, NUM_MBUFS formula) (+2 more)

### Community 72 - "Community 72"
Cohesion: 0.27
Nodes (10): Known Limitations, Spoofing amplifier exposure, Roadmap, Human-readable experiment output, Unscoped ideas (QUIC, DDoS purge, cross-region, packet loss, BlueField scale, CDN), Multi-round send in the load generator, Phase 1 - BlueField as ServerNIC, Phase 2 - BlueField as ClientNIC and ServerNIC (+2 more)

### Community 73 - "Community 73"
Cohesion: 0.24
Nodes (10): D1 test in the e-switch domain, not the NIC domain, Composed e-switch rule (5-tuple match + TCP seq modify + egress + counter), experiments/bluefield/probe/docaprobe/probe.c (DOCA Flow probe), clientnic-forwarder-pipeline spec, ClientNIC ingress-based routing (eth0 SYN / eth0 other / eth1), forward_c2s transparent client-to-server forwarding, forward_s2c transparent server-to-client forwarding, trans_c2s: client-to-server ACK -= delta (+2 more)

### Community 74 - "Community 74"
Cohesion: 0.49
Nodes (9): _report_0rtt_body(), _report_0rtt_ssh(), _report_0rtt_ssm(), _report_baseline(), report_header(), _report_quic(), report_section(), report.sh script (+1 more)

### Community 75 - "Community 75"
Cohesion: 0.27
Nodes (6): discover_nodes(), prologue_0rtt(), PYTHONIOENCODING, PYTHONUTF8, remote_run(), run.sh script

### Community 76 - "Community 76"
Cohesion: 0.22
Nodes (9): Offline failure diagnosis procedure, GW MAC EC2 API fails from VM (pass MAC as arg), LOAD_TIMEOUT / LOAD_PARALLEL / LOAD_RATE balance, SSM daemon detachment (use setsid), Troubleshooting reference, Load knobs are mandatory (2000 @ 500/s), Export only explicitly-given knobs (REPO_REF, LOAD_*), Integration Test Report 2026-03-18 (Scapy) (+1 more)

### Community 77 - "Community 77"
Cohesion: 0.25
Nodes (9): iperf3 (TCP throughput testing), pktgen automated test script, PCAP PMD replay with Scapy-generated pcaps, Testing Strategies for BF3 DPU Applications, pktgen kernel packet generator, Staged testing workflow (validation, functional, load, benchmark, stress), tcpdump + scapy functional testing, Testing pyramid (functional, load, performance) (+1 more)

### Community 78 - "Community 78"
Cohesion: 0.31
Nodes (9): Integration Test Report 2026-07-25 (100k run, 68,779 ok), 68,779/100,000 connections established, Live 100k-connection run 2026-07-25, loadgen arrival rate reported from coroutine-spawn timing, Scale beyond measured load (100k runs never completed), Arrival-rate pacing (--rate, absolute timeline), 10k run bottleneck is t3.micro endpoints, Why iperf was replaced (+1 more)

### Community 79 - "Community 79"
Cohesion: 0.22
Nodes (9): DPDK throughput benchmark example, Performance targets per component (NIC flow engine, DPA, ARM DPDK), DOCA Test Framework (line-rate benchmarking, latency measurement), Docker Deployment Guide for Wire-Example, Wire container requirements (--privileged, --network host, hugepages), SF-based wire setup (SF representors wired in container), Classic DPDK Mode (ARM-core forwarding), Wire Example README (+1 more)

### Community 80 - "Community 80"
Cohesion: 0.25
Nodes (9): OVS steering of DNS requests/responses to ReACT, SF0 management/SSH scalable function (reserved), Networking Setup for Wire-Example, Wire setup options (minimal, subfunctions, hybrid with OVS), Subfunctions preferred over VFs, OVS Management, OVS port naming (pf0hpf, SF representor, p0), Using mlnx-sf to Manage Scalable Functions (+1 more)

### Community 81 - "Community 81"
Cohesion: 0.22
Nodes (8): D3 Next-hop MAC via CLI only where it cannot be learned (--server-mac), D3b Port role resolved by ENI MAC, never by port ID, Client MAC learned per-flow from SYN (no --client-mac), --client-port-mac / --server-port-mac port identity flags, Orchestrator discovers next-hop and port-identity MACs, ServerNIC --server-mac peer MAC argument, Boot-time vfio-pci bind by IMDS device-number and MAC, _bind_data_enis_to_vfio() CDK user-data helper

### Community 82 - "Community 82"
Cohesion: 0.28
Nodes (6): run_experiment(), core.sh script, warn_if_truncated(), report_nic_ttfb(), measure.sh script, summarize_metric()

### Community 83 - "Community 83"
Cohesion: 0.28
Nodes (4): json_idx(), ssm.sh script, ssm_run(), ssm_stdout()

### Community 84 - "Community 84"
Cohesion: 0.33
Nodes (8): main(), Send TCP SYN-ACK packets (should be fast-forwarded), Send TCP data packets (should be fast-forwarded), Send UDP packets (should be fast-forwarded), send_data_packets(), send_syn_ack_packets(), send_syn_packets(), send_udp_packets()

### Community 85 - "Community 85"
Cohesion: 0.32
Nodes (8): Queues, Ports, and Scalable Functions, DMA is point-to-point; queues live in owner memory, DPDK RX/TX queues (descriptor rings), Hairpin queues (NIC-internal buffers), RSS and one-queue-per-core, Scalable Functions (netdev vs representor faces), RX ring burst absorption (RX_RING_SIZE 1024, imissed), Porting guidelines (vanilla executable, no containers, no SFs)

### Community 86 - "Community 86"
Cohesion: 0.32
Nodes (8): Code Examples Repository, DPA compilation with dpacc (separate from gcc DPDK build), DOCA DPL (P4) Programming, DPL compilation pipeline (doca-p4c to parser, flow rules, DPA), Hardware parser programming (DPL only for custom protocols), Stateful per-flow processing with P4 registers, DOCA Flow API Programming, DOCA Flow pipe types (BASIC, CONTROL, LPM, ACL, ORDERED_LIST, HASH)

### Community 87 - "Community 87"
Cohesion: 0.32
Nodes (8): MST / mlxconfig / mlxfwreset, eSwitch is flow engine logic, not separate hardware, BlueField BFB Installation Guide, bfb-install command, rshim service, DPU Mode Setup, FLEX_PARSER_PROFILE_ENABLE=3 (needs HCA reset), SoC mode mlxconfig parameters

### Community 88 - "Community 88"
Cohesion: 0.29
Nodes (8): 4-tuple / port-space budget (LOAD_PORTS), Capacity runs separate entry point (stress.sh), zero-rtt-tcp Overview, AWS CDK stacks (Scapy and DPDK, VPC 10.1.0.0/16), 4-VM chain topology (Client, ClientNIC, ServerNIC, Server), Load knobs (LOAD_PARALLEL, LOAD_RATE, LOAD_BYTES, NETEM_RTT_MS...), Scapy (deprecated) vs DPDK (live) implementations, Two experiments, not one (latency vs capacity)

### Community 89 - "Community 89"
Cohesion: 0.32
Nodes (8): Sprint 1 round 0 contract-lens findings, Structural presence checks valid for location claims, Sprint 1 round 1 spec-decision-lens findings, Byte-identity move constraint, Plan: human-readable experiment output, Streamline experiments harness design spec, Design: human-readable experiment output, Roadmap: human-readable experiment output

### Community 90 - "Community 90"
Cohesion: 0.32
Nodes (8): loadgen.py (kept byte-identical), loadgen_quic.py, PROTO=quic selection in client.sh/server.sh, rate-spike mode, QUIC arm in run.sh on STACK=baseline, Separate loadgen_quic.py rather than --proto flag, loadgen.py as client and server app, Roadmap: multi-round send in load generator

### Community 91 - "Community 91"
Cohesion: 0.39
Nodes (7): extract_dns_key(), load_dns_keys(), main(), Extract (dport, dns.id) tuple from DNS response packet, Load DNS keys from the server-side PCAP, Stream client-side PCAP and compare with server, stream_dns()

### Community 92 - "Community 92"
Cohesion: 0.36
Nodes (5): list_ports(), main(), port_init(), wire_lcore(), wire_ports()

### Community 93 - "Community 93"
Cohesion: 0.25
Nodes (6): main(), ClientNIC entry point., Logger, Logging setup for ClientNIC., Configure and return the ClientNIC logger., setup_logging()

### Community 94 - "Community 94"
Cohesion: 0.33
Nodes (7): Capacity run vs latency run (LOAD_RATE=0 burst), Failure: missing=SYN-ACK flow=unknown, DPDK Integration Test Report 2026-06-22 (1 failure), Finding: 100-conn burst FCT mean 13.5 s (queueing, iperf2 ~1 MB/flow), DPDK Integration Test Report 2026-06-23 (100 conns, all passed), ClientNIC V-stamp / ServerNIC delta logs (T8 translation shift), Latency run vs capacity run (stress.sh)

### Community 95 - "Community 95"
Cohesion: 0.38
Nodes (6): Option 1 Implementation - FIXED for Hardware Fast-Path, create_hairpin_pipe(), DOCA_FLOW_FWD_PORT hardware hairpin for non-SYN packets, Option 1 architecture: no OVS, eSwitch hairpin between pf0hpf and p0, When OVS is needed vs optional for DOCA apps, eSwitch VM-to-VM forwarding rule example

### Community 96 - "Community 96"
Cohesion: 0.29
Nodes (7): server_gap metric, FCT (flow completion time), Three endpoint-observed metrics (fct, send_unlock, server_gap), A2 wire cross-check escalation, send_unlock metric, App-side send_unlock (A1), Wire cross-check from QUIC header bits (A2, deferred)

### Community 97 - "Community 97"
Cohesion: 0.33
Nodes (7): verify-eswitch-tcp-seq-offload .openspec.yaml (spec-driven, created 2026-07-25), verify-eswitch-tcp-seq-offload design, verify-eswitch-tcp-seq-offload proposal, Spike success criteria SC1-SC5, eswitch-offload-probe spec, verify-eswitch-tcp-seq-offload tasks (13 tasks), OpenSpec config.yaml (schema: spec-driven)

### Community 98 - "Community 98"
Cohesion: 0.29
Nodes (7): Sprint 1 round 1 build notes, git mv of utils into lib and nodes, Callers outside experiments still name old paths, Sprint 1 round 1 integrity-lens findings, Oracle independence for renamed-but-unmodified tests, Sprint 4 contract: update callers and roadmap, lib / nodes / sweeps / reports / tests layout

### Community 99 - "Community 99"
Cohesion: 0.29
Nodes (6): LOAD_BYTES, LOAD_CONCURRENCY, LOAD_PARALLEL, LOAD_RATE, stress.sh script, STACK

### Community 100 - "Community 100"
Cohesion: 0.40
Nodes (6): doca_argp (DOCA argument parsing library), DOCA Logging (doca_log backends and levels), DPDK EAL (rte_eal_init/remote_launch core functions), DOCA Argument Parsing Library (doca_argp), DOCA Logging, DPDK Core Functions (rte_eal_*)

### Community 101 - "Community 101"
Cohesion: 0.60
Nodes (5): cmd_bind(), cmd_help(), cmd_ssh(), cmd_status(), lab-connect.sh script

### Community 102 - "Community 102"
Cohesion: 0.33
Nodes (6): CLI Commands Reference, dpdk-testpmd, mlnx-sf (Scalable Function management), ovs-vsctl / ovs-dpctl, SF netdev for DPDK, representor for OVS, Verify hardware offload explicitly

### Community 103 - "Community 103"
Cohesion: 0.33
Nodes (6): Plan: QUIC comparison, Design: QUIC comparison, Four arms: TCP baseline, 0-RTT TCP, QUIC cold, QUIC resumed, Lower arrival rate from loopback spike, One session ticket reused for all resumed flows, Plaintext TCP versus always-encrypted QUIC asymmetry

### Community 104 - "Community 104"
Cohesion: 0.33
Nodes (6): Open: 0-RTT FCT tail 537 ms, RTO hypothesis, NIC log truncated by SSM 24 KB cap, 0-RTT relocates the RTT wait to ServerNIC, FCT unchanged, send_unlock demonstrates 0-RTT, TTFB never measured; only pcap metrics produced, Idea: packet-loss handling

### Community 106 - "Community 106"
Cohesion: 0.33
Nodes (5): ensure_quic_python.sh script, UV_CACHE_DIR, UV_INSTALL_DIR, UV_NO_MODIFY_PATH, UV_PYTHON_INSTALL_DIR

### Community 108 - "Community 108"
Cohesion: 0.60
Nodes (5): print_error(), print_header(), print_info(), print_success(), docker_setup.sh script

### Community 109 - "Community 109"
Cohesion: 0.60
Nodes (5): print_error(), print_header(), print_info(), print_success(), ovs_setup.sh script

### Community 110 - "Community 110"
Cohesion: 0.40
Nodes (6): Roadmap, Roadmap: Phase 1 BlueField as ServerNIC, Roadmap: Phase 2 BlueField as ClientNIC and ServerNIC, Port model: bind DPU physical ports p0/p1 directly, Porting guidelines: vanilla executable, no containers, no SFs, Roadmap: QUIC comparison

### Community 111 - "Community 111"
Cohesion: 0.53
Nodes (4): log_fail(), log_pass(), log_skip(), run_dpdk_tests.sh script

### Community 112 - "Community 112"
Cohesion: 0.40
Nodes (5): Baseline TCP Report 2026-06-09-184846 (iperf3), Baseline TCP Report 2026-06-09-185025 (iperf3), Finding: Client TTFB/FCT 'no samples found' with iperf, Baseline TCP Report 2026-06-09 (iperf3), iperf2 replaced by asyncio loadgen

### Community 113 - "Community 113"
Cohesion: 0.40
Nodes (5): dpdk-data-plane spec (ClientNIC), ClientNIC busy-poll main loop, 100k-flow failure: single lcore RX ring overrun (imissed), Not demonstrated: real WAN, TCP options, throughput, high concurrency, Open decisions for a paper (TFO/QUIC 0-RTT positioning, WAN, options, 12.9% loss)

### Community 114 - "Community 114"
Cohesion: 0.60
Nodes (3): cleanup(), log(), clientnic.sh script

### Community 115 - "Community 115"
Cohesion: 0.60
Nodes (3): cleanup(), log(), servernic.sh script

### Community 116 - "Community 116"
Cohesion: 0.70
Nodes (4): fail(), log(), pass(), think.sh script

### Community 117 - "Community 117"
Cohesion: 0.70
Nodes (4): print_error(), print_info(), print_success(), run.sh script

### Community 118 - "Community 118"
Cohesion: 0.70
Nodes (4): print_error(), print_info(), print_success(), test_verify.sh script

### Community 119 - "Community 119"
Cohesion: 0.60
Nodes (3): fail(), log(), build_wire_image.sh script

### Community 121 - "Community 121"
Cohesion: 0.83
Nodes (3): add_config_block(), install_on_host(), install_claude_ssh_key.sh script

### Community 122 - "Community 122"
Cohesion: 0.83
Nodes (4): RTT relocated to ServerNIC, not removed (FCT unchanged), Delay must sit on ClientNIC-ServerNIC leg for FCT win (E2/E3), --wan-delay-us timestamped FIFO on eth1 TX, F2 resolved: emulated WAN moved to middle leg (-101.85 ms FCT)

### Community 123 - "Community 123"
Cohesion: 0.50
Nodes (4): Alternative A: rule at SYN-ACK, FIN/RST teardown (recommended), Alternative B: wildcard rule at SYN (rejected), D1 Delta known only at SYN-ACK, rule installed then, Pre-delta packet buffering and flush

### Community 124 - "Community 124"
Cohesion: 0.50
Nodes (4): D2 three-level verification (accepted, offloaded, effective), D3 generate and capture from the x86 VM, Hardware-execution verification (counter vs software-queue receives), On-wire rewrite verification at the sender

### Community 125 - "Community 125"
Cohesion: 0.50
Nodes (4): percentile(), Linear-interpolated percentile over an already-sorted list. Hand-rolled rather…, Collapse per-flow results into a constant number of aggregate lines. Emits one…, summarize()

### Community 126 - "Community 126"
Cohesion: 0.50
Nodes (3): parametrize, Pins where run.sh's report writer (write_run_report in…, test_report_lands_under_reports_stack()

### Community 127 - "Community 127"
Cohesion: 0.83
Nodes (3): fail(), log(), compress_doca_image.sh script

### Community 128 - "Community 128"
Cohesion: 0.83
Nodes (3): error(), log(), allocate_hugepages.sh script

### Community 129 - "Community 129"
Cohesion: 0.67
Nodes (3): aws-cdk-lib (AWS CDK Python library), constructs (CDK constructs library), Baseline CDK Python Requirements

### Community 130 - "Community 130"
Cohesion: 0.67
Nodes (3): ClientNIC packet parsing and validation, ClientNIC re-capture loop prevention, ServerNIC packet parsing and re-capture loop prevention

### Community 131 - "Community 131"
Cohesion: 1.00
Nodes (3): ClientNIC DPDK EAL init and two-port ENA config, ServerNIC DPDK EAL init and two-port ENA config, Both SmartNIC data ports on DPDK ENA PMD (no AF_PACKET)

### Community 132 - "Community 132"
Cohesion: 0.67
Nodes (3): dpdk-node-script-runner spec, Non-interactive client test via client.py, Per-VM log capture and Markdown report

### Community 135 - "Community 135"
Cohesion: 0.67
Nodes (3): emit(), format_result(), Render one per-flow result as its key=value line (no trailing newline).

### Community 145 - "Community 145"
Cohesion: 0.67
Nodes (3): ClientNIC dpdk-forwarder source files table, ClientNIC dpdk-forwarder smoke tests (virtual PMD), DPDK header stubs (rte_* stand-ins for wan_delay.c tests)

## Ambiguous Edges - Review These
- `RUNS Lab Connect Skill` → `run-experiment skill`  [AMBIGUOUS]
  .claude/skills/runs-lab-connect/SKILL.md · relation: conceptually_related_to
- `SYN interception, spoofing and V stamping (proc_handle_syn)` → `One 0-RTT connection end to end (10 steps)`  [AMBIGUOUS]
  docs/results-review.html · relation: conceptually_related_to
- `Unmodified iperf2 load generator requirement` → `Python asyncio load generator replaces iperf`  [AMBIGUOUS]
  docs/results-review.html · relation: conceptually_related_to
- `Offload disable and tc netem 50ms on each endpoint` → `Emulated WAN: 50 ms netem egress on each NIC's middle leg`  [AMBIGUOUS]
  docs/results-review.html · relation: conceptually_related_to

## Knowledge Gaps
- **290 isolated node(s):** `read_ovs_counters.sh script`, `read_counters.sh script`, `run_dns_test_tmux.sh script`, `SUDO_ASKPASS`, `run_react_fp_sweep_20s.sh script` (+285 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **66 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `RUNS Lab Connect Skill` and `run-experiment skill`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `SYN interception, spoofing and V stamping (proc_handle_syn)` and `One 0-RTT connection end to end (10 steps)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Unmodified iperf2 load generator requirement` and `Python asyncio load generator replaces iperf`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Offload disable and tc netem 50ms on each endpoint` and `Emulated WAN: 50 ms netem egress on each NIC's middle leg`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `experiments/insights.md` connect `Community 43` to `Metrics and Methodology`, `Community 110`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Why does `Measurement Methodology Review` connect `Metrics and Methodology` to `Community 43`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Why does `TCP SYN Proxy / SYN-ACK Generation on DPA (doc example)` connect `Metrics and Methodology` to `BlueField eSwitch Concepts`?**
  _High betweenness centrality (0.039) - this node is a cross-community bridge._