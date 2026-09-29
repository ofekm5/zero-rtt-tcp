# Sprint 1: core.sh honours STACK

## Tasks
- Task 5.1: Make the shared flow in `lib/core.sh` honour `STACK`

## Acceptance criteria
- C1: `run_experiment` in `lib/core.sh` reads `STACK`; with `STACK=baseline` it skips the data-plane build/start/log-collection steps and still runs the plain-TCP flow (NIC preflight, netem, server start, load, captures), while an unset `STACK` produces the full 0-RTT remote-call sequence — verify: `( f=$(mktemp); remote_run() { printf '%s\n' "$2" >> "$f"; echo '["Success","",""]'; }; remote_bg() { printf '%s\n' "$2" >> "$f"; }; remote_stdout() { printf '%s\n' "$2" >> "$f"; }; ssm_run() { remote_run "$@"; }; json_idx() { :; }; sleep() { :; }; log() { :; }; pass() { :; }; fail() { :; }; warn() { :; }; source experiments/lib/measure.sh; source experiments/lib/core.sh; SERVER_PORT=8080 CONNECTIONS=1 REPO_PATH=/r LOAD_PARALLEL=100 FAILURES=0 SERVER_ID=s SERVERNIC_ID=sn CLIENTNIC_ID=cn CLIENT_ID=c SERVER_IP=10.1.2.10; STACK=baseline run_experiment "" "" "" "" "" > /dev/null 2>&1; b=$(cat "$f"); : > "$f"; unset STACK; run_experiment m1 m2 m3 m4 m5 > /dev/null 2>&1; z=$(cat "$f"); rm -f "$f"; ! grep -qE 'meson setup|nodes/(client|server)nic\.sh|/tmp/(client|server)nic\.log' <<< "$b" && grep -qF 'nodes/server.sh' <<< "$b" && grep -qF 'ip route show 10.1.2.0/24' <<< "$b" && grep -qF 'netem delay' <<< "$b" && grep -qF 'meson setup' <<< "$z" && grep -qF 'nodes/servernic.sh' <<< "$z" && grep -qF 'nodes/clientnic.sh' <<< "$z" )`

## Out of scope
- Creating `experiments/run.sh` (sprint 2)
- Adding the mock-transport pytest suite (sprint 3)
- Report path changes and `reports/<stack>/` directories (sprint 4)
- Deleting the four runners and scapy/ (sprint 5)
- Updating callers in `.github/workflows/`, `.claude/skills/`, and `CLAUDE.md` (sprint 6)
