FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    dpdk-dev \
    libdpdk-dev \
    meson \
    ninja-build \
    pkg-config \
    build-essential \
    python3 \
    file \
    binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY .. .

RUN meson setup builddir --wipe -Db_lto=false \
    && ninja -C builddir

CMD ["bash", "tests/run_dpdk_tests.sh", "builddir/clientnic-dpdk"]
