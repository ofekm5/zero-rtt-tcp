project('servernic-dpdk', 'c',
    version: '0.1.0',
    default_options: ['c_std=c11', 'warning_level=2'])

add_project_arguments('-D_GNU_SOURCE', language: 'c')

dpdk_dep = dependency('libdpdk', required: true)

sources = files(
    'main.c',
    'flow_table.c',
    'checksum.c',
    'io.c',
    'log.c',
    'syn_handler.c',
    'translator.c',
    'pipeline.c',
)

executable('servernic-dpdk', sources,
    dependencies: [dpdk_dep],
    install: false)
