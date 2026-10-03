#!/bin/bash
# ensure_quic_python.sh — print the path of a Python with aioquic==1.3.0,
# creating it on first use.
#
# The endpoint VMs run Amazon Linux 2, whose python3 is 3.7, and aioquic 1.3.0
# needs Python >= 3.10. Rather than change the AMI — which would also change the
# kernel TCP stack under the TCP baseline and 0-RTT arms — the QUIC generator
# gets its own interpreter: uv fetches a standalone CPython 3.11 into /opt.
# loadgen.py (the TCP arms) keeps using the system python3.
#
# Progress goes to stderr; stdout is only the interpreter path.
set -euo pipefail

VENV=/opt/loadgen-quic
UV_VERSION=0.12.22
export UV_INSTALL_DIR=/opt/uv/bin UV_NO_MODIFY_PATH=1 \
       UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_CACHE_DIR=/opt/uv/cache

if ! "$VENV/bin/python" -c 'import aioquic, sys; sys.exit(aioquic.__version__ != "1.3.0")' 2>/dev/null; then
    if [ ! -x "$UV_INSTALL_DIR/uv" ]; then
        echo "Installing uv $UV_VERSION..." >&2
        curl -LsSf "https://astral.sh/uv/$UV_VERSION/install.sh" | sh >&2
    fi
    echo "Creating $VENV (CPython 3.11, aioquic 1.3.0)..." >&2
    "$UV_INSTALL_DIR/uv" venv --quiet --python 3.11 "$VENV" >&2
    "$UV_INSTALL_DIR/uv" pip install --quiet --python "$VENV/bin/python" 'aioquic==1.3.0' >&2
fi
echo "$VENV/bin/python"
