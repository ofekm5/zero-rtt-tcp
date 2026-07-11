#!/usr/bin/env bash
#
# install_claude_ssh_key.sh — bind Claude Code to any university/lab VM over SSH.
#
# What it does:
#   1. Generates (once) a dedicated ed25519 keypair for Claude Code, stored in a
#      DURABLE location (~/.ssh, not a scratchpad) so it survives across sessions.
#   2. Installs the PUBLIC key into ~/.ssh/authorized_keys on each target VM.
#   3. (Optional) Adds a matching ~/.ssh/config block so plain `ssh <host>` — and
#      every Claude Code tool call — uses the key automatically, no password.
#   4. Verifies non-interactive key auth actually works.
#
# All lab hosts are Ubuntu, so ~/.ssh/authorized_keys is the right target.
#
# IMPORTANT — run this in a REAL terminal (Git Bash on Windows, or any
# Linux/macOS shell). It prompts for each host's password ONCE. The Claude Code
# `!` prefix and Windows PowerShell cannot present an interactive password prompt
# (and PowerShell's native OpenSSH also can't do ControlMaster), so they won't work.
#
# Usage:
#   ./install_claude_ssh_key.sh [user@]host [[user@]host ...]
#
# Examples:
#   ./install_claude_ssh_key.sh bluefieldadmin@10.13.37.10
#   ./install_claude_ssh_key.sh 10.13.36.16 10.13.36.46          # uses DEFAULT_USER
#   DEFAULT_USER=root ./install_claude_ssh_key.sh 10.13.36.233
#
# Env overrides:
#   KEY_PATH      private key path              (default: ~/.ssh/claude_code_ed25519)
#   DEFAULT_USER  user when host has no user@   (default: ubuntu)
#   WRITE_CONFIG  add ~/.ssh/config entries     (default: 1; set 0 to skip)

set -euo pipefail

KEY_PATH="${KEY_PATH:-$HOME/.ssh/claude_code_ed25519}"
DEFAULT_USER="${DEFAULT_USER:-ubuntu}"
WRITE_CONFIG="${WRITE_CONFIG:-1}"
SSH_CONFIG="$HOME/.ssh/config"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [user@]host [[user@]host ...]" >&2
  echo "  e.g. $0 bluefieldadmin@10.13.37.10 10.13.36.16" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Ensure the dedicated Claude Code keypair exists (generate once, durably).
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ ! -f "$KEY_PATH" ]; then
  echo "[*] Generating dedicated Claude Code key at $KEY_PATH"
  ssh-keygen -t ed25519 -N "" -C "claude-code@$(hostname)" -f "$KEY_PATH" >/dev/null
  echo "[✓] Key generated"
else
  echo "[*] Reusing existing key at $KEY_PATH"
fi
PUBKEY_FILE="${KEY_PATH}.pub"
echo "[*] Public key:"
echo "    $(cat "$PUBKEY_FILE")"
echo

# ---------------------------------------------------------------------------
# 2. + 3. Install on each host, then optionally record an ssh config block.
# ---------------------------------------------------------------------------
add_config_block() {
  local host="$1" user="$2"
  [ "$WRITE_CONFIG" = "1" ] || return 0
  touch "$SSH_CONFIG"; chmod 600 "$SSH_CONFIG"
  local marker="# >>> claude-code ${host} >>>"
  if grep -qF "$marker" "$SSH_CONFIG"; then
    echo "[*] ssh config entry for $host already present — leaving as is"
    return 0
  fi
  {
    echo ""
    echo "$marker"
    echo "Host $host"
    echo "    HostName $host"
    echo "    User $user"
    echo "    IdentityFile $KEY_PATH"
    echo "    IdentitiesOnly yes"
    echo "    StrictHostKeyChecking accept-new"
    echo "# <<< claude-code ${host} <<<"
  } >> "$SSH_CONFIG"
  echo "[✓] Added ~/.ssh/config entry for $host"
}

install_on_host() {
  local target="$1" user host
  if [[ "$target" == *"@"* ]]; then
    user="${target%%@*}"; host="${target#*@}"
  else
    user="$DEFAULT_USER"; host="$target"
  fi

  echo "=============================================================="
  echo "[*] Installing key on ${user}@${host}  (you'll be asked for its password)"

  # Prefer ssh-copy-id; fall back to a manual, idempotent append.
  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$PUBKEY_FILE" "${user}@${host}"
  else
    ssh -o StrictHostKeyChecking=accept-new "${user}@${host}" \
      'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' \
      < "$PUBKEY_FILE"
  fi

  # Verify non-interactive key auth (no password should be needed now).
  echo "[*] Verifying key auth to ${user}@${host} ..."
  if ssh -i "$KEY_PATH" -o IdentitiesOnly=yes -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        "${user}@${host}" 'echo OK $(hostname)'; then
    echo "[✓] Key auth works for ${user}@${host}"
    add_config_block "$host" "$user"
  else
    echo "[!] Key auth verification FAILED for ${user}@${host}" >&2
    echo "    Check the password you entered and that the account allows key auth." >&2
    return 1
  fi
  echo
}

rc=0
for target in "$@"; do
  install_on_host "$target" || rc=1
done

echo "=============================================================="
if [ "$rc" -eq 0 ]; then
  echo "[✓] Done. Claude Code can now reach the host(s) with:"
  echo "      ssh -i $KEY_PATH <user>@<host>"
  [ "$WRITE_CONFIG" = "1" ] && echo "    or simply:  ssh <host>   (via ~/.ssh/config)"
else
  echo "[!] Finished with errors — see messages above." >&2
fi
exit "$rc"
