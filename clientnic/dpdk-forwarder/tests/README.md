# ClientNIC DPDK Forwarder Tests

Same DPDK virtual PMD smoke-test suite as `clientnic/dpdk/tests/` but targeting
the `clientnic-dpdk-forwarder` binary.

## Usage

```bash
cd clientnic/dpdk-forwarder
meson setup builddir
ninja -C builddir
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk-forwarder
```
