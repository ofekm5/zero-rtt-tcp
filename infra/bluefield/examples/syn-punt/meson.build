#
# Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
#

project('syn_punt', 'C',
    version: '1.0.0',
    license: 'Proprietary',
    default_options: ['buildtype=debug', 'warning_level=2'],
    meson_version: '>= 0.61.2'
)

APP_NAME = 'syn_punt'

# Allow experimental DOCA APIs
add_project_arguments('-D DOCA_ALLOW_EXPERIMENTAL_API', language: 'c')

# ARM-specific optimization flags
add_project_arguments([
    '-mcpu=cortex-a72+crc',
    '-Wno-missing-braces',
], language: 'c')

# Dependencies
dependencies = []
dependencies += dependency('doca')
dependencies += dependency('libdpdk')

# Source files
sources = [
    'src/main.c',
    'src/utils.c',
    'src/dpdk_init.c',
    'src/doca_flow_handler.c',
    'src/packet_parser.c',
    'src/packet_processor.c',
]

# Include directories
inc_dirs = include_directories('src')

# Build executable
executable(APP_NAME,
    sources,
    dependencies: dependencies,
    include_directories: inc_dirs,
    install: false
)
