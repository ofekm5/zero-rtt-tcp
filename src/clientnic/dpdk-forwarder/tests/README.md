# ClientNIC DPDK Forwarder Tests

DPDK virtual PMD smoke-test suite targeting the `clientnic-dpdk-forwarder` binary
(no ENA hardware required).

## Usage

```bash
cd clientnic/dpdk-forwarder
meson setup builddir
ninja -C builddir
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk-forwarder
```
