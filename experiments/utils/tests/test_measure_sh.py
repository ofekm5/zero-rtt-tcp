"""
Smoke tests for the summarize_metric() Python inline in experiments/utils/measure.sh.

Feeds lines in the actual analyzer emit() format:
  metric=<name> value_ms=<v> node=<n> flow=<f>
and asserts that the inline parser extracts the value_ms sample correctly.

No DPDK, no live infrastructure, no bash required.
"""

import os
import subprocess
import sys
from pathlib import Path

# The inline Python from measure.sh, extracted verbatim so we test the real logic.
# We run it via subprocess with METRIC_DATA set, mimicking how measure.sh calls it.

_UTILS_DIR = Path(__file__).parent.parent
_MEASURE_SH = str(_UTILS_DIR / "measure.sh")

# Extract the Python inline from the shell script at test time so any future
# edits to measure.sh are automatically reflected here.
def _extract_inline_python() -> str:
    """Return the Python code between <<'PY' ... PY in measure.sh."""
    src = Path(_MEASURE_SH).read_text(encoding="utf-8")
    start_marker = "<<'PY'\n"
    end_marker = "\nPY"
    start = src.index(start_marker) + len(start_marker)
    end = src.index(end_marker, start)
    return src[start:end]


def _run_inline(metric: str, node: str, label: str, metric_data: str) -> str:
    """Run the measure.sh inline Python with given inputs, return stdout."""
    code = _extract_inline_python()
    env = os.environ.copy()
    env["METRIC_DATA"] = metric_data
    result = subprocess.run(
        [sys.executable, "-c", code, metric, node, label],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, f"inline python exited {result.returncode}: {result.stderr}"
    return result.stdout


class TestSummarizeMetricInline:
    """Tests for the summarize_metric inline Python in measure.sh."""

    def test_real_emit_format_is_parsed(self):
        """A line in the actual emit() format is parsed and a sample is reported."""
        # Actual format from analyze_metrics.py emit():
        #   metric=<name> value_ms=<v> node=<n> flow=<f>
        line = "metric=ttfb value_ms=12.345 node=clientnic flow=10.0.0.1:1234-10.0.0.2:5001"
        out = _run_inline("ttfb", "clientnic", "ClientNIC TTFB", line)
        assert "no samples found" not in out, (
            f"parser failed to find sample in emit() formatted line.\noutput: {out}"
        )
        assert "n=1" in out, f"expected n=1 in output:\n{out}"
        assert "12.345" in out, f"expected value 12.345 in output:\n{out}"

    def test_multiple_emit_lines_aggregated(self):
        """Multiple emit() lines for the same metric/node are all aggregated."""
        lines = "\n".join([
            "metric=ttfb value_ms=10.000 node=servernic flow=10.0.0.1:1111-10.0.0.2:5001",
            "metric=ttfb value_ms=20.000 node=servernic flow=10.0.0.1:1112-10.0.0.2:5001",
            "metric=ttfb value_ms=30.000 node=servernic flow=10.0.0.1:1113-10.0.0.2:5001",
        ])
        out = _run_inline("ttfb", "servernic", "ServerNIC TTFB", lines)
        assert "no samples found" not in out
        assert "n=3" in out, f"expected n=3 in output:\n{out}"
        # mean should be 20.000
        assert "20.000" in out, f"expected mean=20.000 in output:\n{out}"

    def test_wrong_metric_not_matched(self):
        """Lines for a different metric name are not counted."""
        line = "metric=fct value_ms=99.999 node=clientnic flow=10.0.0.1:1234-10.0.0.2:5001"
        out = _run_inline("ttfb", "clientnic", "ClientNIC TTFB", line)
        assert "no samples found" in out, (
            f"should not match a different metric name:\n{out}"
        )

    def test_wrong_node_not_matched(self):
        """Lines for a different node are not counted."""
        line = "metric=ttfb value_ms=12.345 node=servernic flow=10.0.0.1:1234-10.0.0.2:5001"
        out = _run_inline("ttfb", "clientnic", "ClientNIC TTFB", line)
        assert "no samples found" in out, (
            f"should not match a different node:\n{out}"
        )

    def test_empty_input_no_samples(self):
        """Empty METRIC_DATA produces 'no samples found'."""
        out = _run_inline("ttfb", "clientnic", "ClientNIC TTFB", "")
        assert "no samples found" in out

    def test_field_order_independence(self):
        """Parser works regardless of field order within the line."""
        # node= before metric= before value_ms= (unusual but should still work)
        line = "node=clientnic metric=ttfb value_ms=55.500 flow=10.0.0.1:1234-10.0.0.2:5001"
        out = _run_inline("ttfb", "clientnic", "ClientNIC TTFB", line)
        assert "no samples found" not in out, (
            f"parser should be order-independent:\n{out}"
        )
        assert "55.500" in out
